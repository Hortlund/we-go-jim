import Foundation
import SwiftData

@MainActor
final class ProfileRepository {
    private static var localDefaultDisplayName: String {
        ReviewModerationService.sanitizedForSharing("Athlete", kind: .displayName)
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func currentProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func loadOrCreateProfile() throws -> UserProfile {
        if let existing = try currentProfile() {
            return existing
        }

        let profile = UserProfile(displayName: Self.localDefaultDisplayName)
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    @discardableResult
    func bootstrapProfileIdentity(
        cloudSyncEnabled: Bool,
        defaultDisplayNameProvider: (any ProfileDefaultDisplayNameProviding)? = nil
    ) async throws -> UserProfile {
        let defaultDisplayNameProvider = defaultDisplayNameProvider ?? ICloudProfileDefaultDisplayNameProvider()
        let preferredDisplayName = await resolvedDefaultDisplayName(
            cloudSyncEnabled: cloudSyncEnabled,
            defaultDisplayNameProvider: defaultDisplayNameProvider
        )

        if let existing = try currentProfile() {
            guard shouldReplaceDefaultDisplayName(for: existing, with: preferredDisplayName) else {
                return existing
            }

            existing.displayName = preferredDisplayName
            existing.updatedAt = .now
            try modelContext.save()
            try? CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)?.queueCurrentProfileSync()
            return existing
        }

        let profile = UserProfile(displayName: preferredDisplayName)
        modelContext.insert(profile)
        try modelContext.save()
        return profile
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
        try modelContext.save()
        try? CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)?.queueCurrentProfileSync()
    }

    func updateWeeklyWorkoutGoal(_ goal: Int) throws {
        let profile = try loadOrCreateProfile()
        profile.weeklyWorkoutGoal = max(1, min(14, goal))
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updateTrainingGuidanceEnabled(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        profile.isTrainingGuidanceEnabled = isEnabled
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updateKeepsScreenAwake(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        profile.keepsScreenAwake = isEnabled
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updatePreferredWeightUnit(_ unit: PreferredWeightUnit) throws {
        let profile = try loadOrCreateProfile()
        profile.preferredWeightUnit = unit
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updateWorkoutNotificationStyle(_ style: WorkoutNotificationStyle) throws {
        let profile = try loadOrCreateProfile()
        profile.workoutNotificationStyle = style
        profile.updatedAt = .now
        try modelContext.save()
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
}
