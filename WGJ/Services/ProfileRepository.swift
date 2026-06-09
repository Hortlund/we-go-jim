import Foundation
import SwiftData

nonisolated final class ProfileRepository {
    private static var localDefaultDisplayName: String {
        ReviewModerationService.sanitizedForSharing("Athlete", kind: .displayName)
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func currentProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func currentProfileSnapshot() throws -> ProfileIdentitySnapshot? {
        try currentProfile().map(ProfileIdentitySnapshot.init(profile:))
    }

    @discardableResult
    func loadOrCreateProfile() throws -> UserProfile {
        if let existing = try currentProfile() {
            return existing
        }

        let profile = UserProfile(displayName: Self.localDefaultDisplayName)
        modelContext.insert(profile)
        try saveUserDataChanges()
        return profile
    }

    @discardableResult
    func bootstrapProfileIdentity(
        cloudSyncEnabled: Bool,
        defaultDisplayNameProvider: (any ProfileDefaultDisplayNameProviding)? = nil
    ) async throws -> UserProfile {
        if let existing = try currentProfile() {
            guard shouldAttemptCloudDisplayNameUpgrade(for: existing, cloudSyncEnabled: cloudSyncEnabled) else {
                return existing
            }

            let defaultDisplayNameProvider = defaultDisplayNameProvider ?? ICloudProfileDefaultDisplayNameProvider()
            let preferredDisplayName = await resolvedDefaultDisplayName(
                cloudSyncEnabled: cloudSyncEnabled,
                defaultDisplayNameProvider: defaultDisplayNameProvider
            )

            guard shouldReplaceDefaultDisplayName(for: existing, with: preferredDisplayName) else {
                return existing
            }

            existing.displayName = preferredDisplayName
            existing.updatedAt = .now
            try saveUserDataChanges()
            return existing
        }

        let defaultDisplayNameProvider = defaultDisplayNameProvider ?? ICloudProfileDefaultDisplayNameProvider()
        let preferredDisplayName = await resolvedDefaultDisplayName(
            cloudSyncEnabled: cloudSyncEnabled,
            defaultDisplayNameProvider: defaultDisplayNameProvider
        )
        let profile = UserProfile(displayName: preferredDisplayName)
        modelContext.insert(profile)
        try saveUserDataChanges()
        return profile
    }

    func bootstrapProfileIdentitySnapshot(
        cloudSyncEnabled: Bool,
        defaultDisplayNameProvider: (any ProfileDefaultDisplayNameProviding)? = nil
    ) async throws -> ProfileIdentitySnapshot {
        ProfileIdentitySnapshot(
            profile: try await bootstrapProfileIdentity(
                cloudSyncEnabled: cloudSyncEnabled,
                defaultDisplayNameProvider: defaultDisplayNameProvider
            )
        )
    }

    func updateIdentity(name: String, athleteType: ProfileAthleteType?) throws {
        let profile = try loadOrCreateProfile()
        try saveProfile(
            name: name,
            athleteType: athleteType,
            avatarImageData: profile.avatarImageData
        )
    }

    func updateDisplayName(_ displayName: String) throws {
        let athleteType = try currentProfile()?.athleteType
        try updateIdentity(name: displayName, athleteType: athleteType)
    }

    func updateAvatar(imageData: Data?) throws {
        let profile = try loadOrCreateProfile()
        try saveProfile(
            name: profile.displayName,
            athleteType: profile.athleteType,
            avatarImageData: imageData
        )
    }

    func saveProfile(
        name: String,
        athleteType: ProfileAthleteType?,
        avatarImageData: Data?
    ) throws {
        let profile = try loadOrCreateProfile()
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .displayName)

        profile.displayName = cleaned
        profile.athleteType = athleteType
        profile.avatarImageData = avatarImageData
        profile.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateWeeklyWorkoutGoal(_ goal: Int) throws {
        let profile = try loadOrCreateProfile()
        profile.weeklyWorkoutGoal = max(1, min(14, goal))
        profile.updatedAt = .now
        try saveUserDataChanges()
        WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: modelContext)
    }

    func updateTrainingGuidanceEnabled(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        profile.isTrainingGuidanceEnabled = isEnabled
        profile.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateKeepsScreenAwake(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        profile.keepsScreenAwake = isEnabled
        profile.updatedAt = .now
        try saveUserDataChanges()
    }

    func updatePreferredWeightUnit(_ unit: PreferredWeightUnit) throws {
        let profile = try loadOrCreateProfile()
        profile.preferredWeightUnit = unit
        profile.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateWorkoutNotificationStyle(_ style: WorkoutNotificationStyle) throws {
        let profile = try loadOrCreateProfile()
        profile.workoutNotificationStyle = style
        profile.updatedAt = .now
        try saveUserDataChanges()
    }

    private func resolvedDefaultDisplayName(
        cloudSyncEnabled: Bool,
        defaultDisplayNameProvider: any ProfileDefaultDisplayNameProviding
    ) async -> String {
        guard cloudSyncEnabled,
              let preferredName = await defaultDisplayNameProvider.defaultDisplayName(),
              !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return Self.localDefaultDisplayName
        }

        return ReviewModerationService.sanitizedForSharing(preferredName, kind: .displayName)
    }

    private func shouldReplaceDefaultDisplayName(
        for profile: UserProfile,
        with preferredDisplayName: String
    ) -> Bool {
        let currentName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentName.isEmpty || currentName == Self.localDefaultDisplayName else {
            return false
        }

        return currentName != preferredDisplayName
    }

    private func shouldAttemptCloudDisplayNameUpgrade(
        for profile: UserProfile,
        cloudSyncEnabled: Bool
    ) -> Bool {
        guard cloudSyncEnabled else {
            return false
        }

        let currentName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentName.isEmpty || currentName == Self.localDefaultDisplayName
    }

    private func saveUserDataChanges() throws {
        try modelContext.save()
    }
}
