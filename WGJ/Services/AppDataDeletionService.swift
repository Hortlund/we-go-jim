import Foundation
import SwiftData

nonisolated final class AppDataDeletionService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let clearWeeklyGoalWidgetSnapshot: @Sendable () -> Void
    private let clearActiveWorkoutSnapshot: @Sendable () async throws -> Void

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        clearWeeklyGoalWidgetSnapshot: @escaping @Sendable () -> Void = {
            WeeklyGoalWidgetPublisher()?.clear()
        },
        clearActiveWorkoutSnapshot: @escaping @Sendable () async throws -> Void = {
            try ActiveWorkoutSnapshotStore.shared.delete()
        }
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        self.clearWeeklyGoalWidgetSnapshot = clearWeeklyGoalWidgetSnapshot
        self.clearActiveWorkoutSnapshot = clearActiveWorkoutSnapshot
    }

    func deleteAllUserData() async throws {
        try deleteLocalData()
        try await clearLocalArtifacts()
    }

    private func deleteLocalData() throws {
        try clearExerciseImageCache()
        try recordCloudMirrorDeletionTombstones()
        try deleteCustomExercises()
        try deleteAll(ProfileWidgetConfig.self)
        try deleteAll(CachedCoachFollowUpNarrative.self)
        try deleteAll(CachedCoachNarrative.self)
        try deleteAll(ActiveWorkoutDraftSession.self)
        try deleteAll(WorkoutSession.self)
        try deleteAll(CompletedSetFact.self)
        try deleteAll(TemplateCardioBlock.self)
        try deleteAll(TemplateExercise.self)
        try deleteAll(WorkoutTemplate.self)
        try deleteAll(TemplateFolder.self)
        try deleteAll(UserProfile.self)
        try modelContext.save()
    }

    private func clearLocalArtifacts() async throws {
        clearWeeklyGoalWidgetSnapshot()
        try await clearActiveWorkoutSnapshot()
    }

    private func clearExerciseImageCache() throws {
        let cacheDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ExerciseImages", isDirectory: true)

        if let cacheDirectory, fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
        }

        let assets = try modelContext.fetch(FetchDescriptor<ExerciseImageAsset>())
        for asset in assets {
            asset.localPath = nil
            asset.fileSizeBytes = 0
        }
    }

    private func deleteCustomExercises() throws {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
        for exercise in exercises where exercise.sourceName == "custom" {
            modelContext.delete(exercise)
        }
    }

    private func recordCloudMirrorDeletionTombstones() throws {
        var existingKeys = Set(
            try modelContext.fetch(FetchDescriptor<UserDataDeletionTombstone>())
                .map(cloudMirrorTombstoneKey)
        )

        for profile in try modelContext.fetch(FetchDescriptor<UserProfile>()) {
            insertTombstoneIfNeeded(
                entityName: "UserProfile",
                entityID: profile.id,
                existingKeys: &existingKeys
            )
        }

        for config in try modelContext.fetch(FetchDescriptor<ProfileWidgetConfig>()) {
            insertTombstoneIfNeeded(
                entityName: "ProfileWidgetConfig",
                entityID: config.id,
                existingKeys: &existingKeys
            )
        }

        for folder in try modelContext.fetch(FetchDescriptor<TemplateFolder>()) {
            insertTombstoneIfNeeded(
                entityName: "TemplateFolder",
                entityID: folder.id,
                existingKeys: &existingKeys
            )
        }

        for template in try modelContext.fetch(FetchDescriptor<WorkoutTemplate>()) {
            insertTombstoneIfNeeded(
                entityName: "WorkoutTemplate",
                entityID: template.id,
                existingKeys: &existingKeys
            )
        }

        for session in try modelContext.fetch(FetchDescriptor<WorkoutSession>()) {
            insertTombstoneIfNeeded(
                entityName: "WorkoutSession",
                entityID: session.id,
                existingKeys: &existingKeys
            )
        }

        for exercise in try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
        where exercise.sourceName == "custom" {
            insertTombstoneIfNeeded(
                entityName: "ExerciseCatalogItem",
                entityID: UUID(),
                entityKey: exercise.remoteUUID,
                existingKeys: &existingKeys
            )
        }
    }

    private func insertTombstoneIfNeeded(
        entityName: String,
        entityID: UUID,
        entityKey: String? = nil,
        existingKeys: inout Set<String>
    ) {
        let tombstone = UserDataDeletionTombstone(
            entityName: entityName,
            entityID: entityID,
            entityKey: entityKey
        )
        let key = cloudMirrorTombstoneKey(tombstone)
        guard existingKeys.insert(key).inserted else { return }
        modelContext.insert(tombstone)
    }

    private func cloudMirrorTombstoneKey(_ tombstone: UserDataDeletionTombstone) -> String {
        if let entityKey = tombstone.entityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityKey.isEmpty {
            return "\(tombstone.entityName):\(entityKey)"
        }
        return "\(tombstone.entityName):\(tombstone.entityID.uuidString.lowercased())"
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}
