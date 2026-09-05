import Foundation
import SwiftData

nonisolated final class ProfileRepository {
    private static var localDefaultDisplayName: String {
        ReviewModerationService.sanitizedForSharing("Athlete", kind: .displayName)
    }

    private let modelContext: ModelContext
    private let boundaryEffects: UserDataBackupBoundaryEffects
    private let scheduleCalorieBackfill: @Sendable (ModelContainer) -> Void

    init(
        modelContext: ModelContext,
        boundaryEffects: UserDataBackupBoundaryEffects = .live,
        backgroundStore: AppBackgroundStore? = nil,
        scheduleCalorieBackfill: (@Sendable (ModelContainer) -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.boundaryEffects = boundaryEffects
        self.scheduleCalorieBackfill = scheduleCalorieBackfill ?? { container in
            HistoryAnalyticsCache.shared.invalidate(container: container)
            WorkoutHistoryChangeBroadcaster.post()
            WorkoutCalorieBackfillScheduler.schedule(
                backgroundStore: backgroundStore ?? AppBackgroundStore(container: container),
                container: container,
                reason: .profileSaved
            )
        }
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

    /// Applies an already-resolved Cloud display name without holding a
    /// `ModelContext` across an async suspension point.
    func bootstrapProfileIdentitySnapshot(
        preferredDisplayName: String?
    ) throws -> ProfileIdentitySnapshot {
        let sanitizedPreferredName = preferredDisplayName
            .map { ReviewModerationService.sanitizedForSharing($0, kind: .displayName) }
            .flatMap { value in
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }

        if let existing = try currentProfile() {
            if let sanitizedPreferredName,
               shouldReplaceDefaultDisplayName(for: existing, with: sanitizedPreferredName) {
                existing.displayName = sanitizedPreferredName
                existing.updatedAt = .now
                try saveUserDataChanges()
            }
            return ProfileIdentitySnapshot(profile: existing)
        }

        let profile = UserProfile(displayName: sanitizedPreferredName ?? Self.localDefaultDisplayName)
        modelContext.insert(profile)
        try saveUserDataChanges()
        return ProfileIdentitySnapshot(profile: profile)
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

        guard profile.displayName != cleaned || profile.athleteType != athleteType
                || profile.avatarImageData != avatarImageData || modelContext.hasChanges else { return }
        profile.displayName = cleaned
        profile.athleteType = athleteType
        profile.avatarImageData = avatarImageData
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .profileSaved)
    }

    func saveProfile(
        name: String,
        athleteType: ProfileAthleteType?,
        avatarImageData: Data?,
        calorieProfile: WorkoutCalorieProfileSnapshot
    ) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .displayName)
        let profile: UserProfile
        if let existing = try currentProfile() {
            profile = existing
        } else {
            profile = UserProfile(displayName: Self.localDefaultDisplayName)
            modelContext.insert(profile)
        }

        let calorieDetailsChanged = profile.calorieEstimateSex != calorieProfile.sex
            || profile.dateOfBirth != calorieProfile.dateOfBirth
            || profile.heightCentimeters != calorieProfile.heightCentimeters
            || profile.bodyWeightKilograms != calorieProfile.bodyWeightKilograms
        guard calorieDetailsChanged || profile.displayName != cleaned || profile.athleteType != athleteType
                || profile.avatarImageData != avatarImageData || modelContext.hasChanges else { return }
        profile.displayName = cleaned
        profile.athleteType = athleteType
        profile.avatarImageData = avatarImageData
        profile.calorieEstimateSex = calorieProfile.sex
        profile.dateOfBirth = calorieProfile.dateOfBirth
        profile.heightCentimeters = calorieProfile.heightCentimeters
        profile.bodyWeightKilograms = calorieProfile.bodyWeightKilograms
        profile.updatedAt = .now
        try saveUserDataChanges()
        if calorieDetailsChanged {
            scheduleCalorieBackfill(modelContext.container)
        } else {
            boundaryEffects.scheduleBackup(modelContext.container, .profileSaved)
        }
    }

    func updateWeeklyWorkoutGoal(_ goal: Int) throws {
        let profile = try loadOrCreateProfile()
        guard profile.weeklyWorkoutGoal != max(1, min(14, goal)) else { return }
        profile.weeklyWorkoutGoal = max(1, min(14, goal))
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .settingsSaved)
        WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: modelContext)
    }

    func updateTrainingGuidanceEnabled(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        guard profile.isTrainingGuidanceEnabled != isEnabled else { return }
        profile.isTrainingGuidanceEnabled = isEnabled
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .settingsSaved)
    }

    func updateKeepsScreenAwake(_ isEnabled: Bool) throws {
        let profile = try loadOrCreateProfile()
        guard profile.keepsScreenAwake != isEnabled else { return }
        profile.keepsScreenAwake = isEnabled
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .settingsSaved)
    }

    func updatePreferredWeightUnit(_ unit: PreferredWeightUnit) throws {
        let profile = try loadOrCreateProfile()
        guard profile.preferredWeightUnit != unit else { return }
        profile.preferredWeightUnit = unit
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .settingsSaved)
    }

    func updateWorkoutNotificationStyle(_ style: WorkoutNotificationStyle) throws {
        let profile = try loadOrCreateProfile()
        guard profile.workoutNotificationStyle != style else { return }
        profile.workoutNotificationStyle = style
        profile.updatedAt = .now
        try saveUserDataChanges()
        boundaryEffects.scheduleBackup(modelContext.container, .settingsSaved)
    }

    func applySettingsPatch(_ patch: UserSettingsPatch) throws -> UserSettingsDraft {
        let profile = try loadOrCreateProfile()
        var changed = false

        if let value = patch.weeklyWorkoutGoal, max(1, min(14, value)) != profile.weeklyWorkoutGoal {
            profile.weeklyWorkoutGoal = max(1, min(14, value))
            changed = true
        }
        if let value = patch.isTrainingGuidanceEnabled, value != profile.isTrainingGuidanceEnabled {
            profile.isTrainingGuidanceEnabled = value
            changed = true
        }
        if let value = patch.keepsScreenAwake, value != profile.keepsScreenAwake {
            profile.keepsScreenAwake = value
            changed = true
        }
        if let value = patch.preferredWeightUnit, value != profile.preferredWeightUnit {
            profile.preferredWeightUnit = value
            changed = true
        }
        if let value = patch.preferredDistanceUnit, value != profile.preferredDistanceUnit {
            profile.preferredDistanceUnit = value
            changed = true
        }
        if let value = patch.workoutNotificationStyle, value != profile.workoutNotificationStyle {
            profile.workoutNotificationStyle = value
            changed = true
        }
        if let value = patch.automaticallyClosesCompletedExercises, value != profile.automaticallyClosesCompletedExercises {
            profile.automaticallyClosesCompletedExercises = value
            changed = true
        }
        if let value = patch.showsCalorieEstimates,
           value != profile.showsCalorieEstimates {
            profile.showsCalorieEstimates = value
            changed = true
        }

        if changed {
            profile.updatedAt = .now
            try saveUserDataChanges()
            if patch.weeklyWorkoutGoal != nil {
                WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: modelContext)
            }
        }
        return UserSettingsDraft(profile: profile)
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
