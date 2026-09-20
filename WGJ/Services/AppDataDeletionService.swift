import Foundation
import SwiftData

nonisolated final class AppDataDeletionService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let deleteCloudBackup: @Sendable () async throws -> Void
    private let clearWeeklyGoalWidgetSnapshot: @Sendable () -> Void
    private let clearActiveWorkoutSnapshot: @Sendable () async throws -> Void

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        deleteCloudBackup: (@Sendable () async throws -> Void)? = nil,
        clearWeeklyGoalWidgetSnapshot: @escaping @Sendable () -> Void = {
            WeeklyGoalWidgetPublisher()?.clear()
        },
        clearActiveWorkoutSnapshot: @escaping @Sendable () async throws -> Void = {
            try ActiveWorkoutSnapshotStore.shared.delete()
        }
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        let container = modelContext.container
        self.deleteCloudBackup = deleteCloudBackup ?? {
            guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }
            try await CloudKitUserDataCloudBackupStore().deleteBackup(
                additionalRecordNames: BackupLocalJournal.knownRecordNames(for: container))
        }
        self.clearWeeklyGoalWidgetSnapshot = clearWeeklyGoalWidgetSnapshot
        self.clearActiveWorkoutSnapshot = clearActiveWorkoutSnapshot
    }

    func deleteAllUserData() async throws {
        try await deleteCloudBackup()
        await MainActor.run { AppRuntimeState.shared.recordCloudBackupDeletion() }
        try await deleteLocalDeviceData()
    }

    func deleteLocalDeviceData() async throws {
        try stageLocalDataDeletion()
        if modelContext.hasChanges {
            try modelContext.saveWithRecoveryProtection()
        }
        try resetLocalBackupState()
        invalidateCommittedCaches()
        try await clearLocalArtifacts()
    }

    func stageLocalDataDeletion() throws {
        try stageExerciseImageMetadataReset()
        try deleteCustomExercises()

        try deleteAll(TemplateExerciseDropStage.self)
        try deleteAll(TemplateExerciseSet.self)
        try deleteAll(TemplateExerciseComponent.self)
        try deleteAll(TemplateCardioBlock.self)
        try deleteAll(TemplateSupersetGroup.self)
        try deleteAll(TemplateExercise.self)
        try deleteAll(WorkoutTemplate.self)
        try deleteAll(TemplateFolder.self)

        try deleteAll(ActiveWorkoutDraftDropStage.self)
        try deleteAll(ActiveWorkoutDraftSet.self)
        try deleteAll(ActiveWorkoutDraftExerciseComponent.self)
        try deleteAll(ActiveWorkoutDraftCardioBlock.self)
        try deleteAll(ActiveWorkoutDraftSupersetGroup.self)
        try deleteAll(ActiveWorkoutDraftExercise.self)
        try deleteAll(ActiveWorkoutDraftSession.self)

        try deleteAll(WorkoutSessionDropStage.self)
        try deleteAll(WorkoutSessionSet.self)
        try deleteAll(WorkoutSessionCardioBlock.self)
        try deleteAll(WorkoutSessionSupersetGroup.self)
        try deleteAll(WorkoutSessionExercise.self)
        try deleteAll(WorkoutSession.self)

        try deleteAll(ExerciseSessionSummary.self)
        try deleteAll(CompletedCardioFact.self)
        try deleteAll(HistoryProjectionCheckpoint.self)
        try deleteAll(CompletedSetFact.self)
        try deleteAll(CachedCoachFollowUpNarrative.self)
        try deleteAll(CachedCoachNarrative.self)
        try deleteAll(ProfileWidgetConfig.self)
        try deleteAll(UserDataDeletionTombstone.self)
        try deleteAll(UserProfile.self)
    }

    func resetLocalBackupState() throws {
        try BackupLocalJournal.save(.init(), for: modelContext.container)
        if let pending = try BackupLocalJournal.pending(for: modelContext.container) {
            try BackupLocalJournal.finish(pending, for: modelContext.container)
        }
    }

    func invalidateCommittedCaches() {
        HistoryAnalyticsCache.shared.clear()
    }

    static func deleteConfiguredCloudBackup(container: ModelContainer? = nil) async throws {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }
        let names = try container.map { try BackupLocalJournal.knownRecordNames(for: $0) } ?? []
        try await CloudKitUserDataCloudBackupStore().deleteBackup(additionalRecordNames: names)
        await MainActor.run { AppRuntimeState.shared.recordCloudBackupDeletion() }
    }

    static func clearDefaultLocalArtifacts() async throws {
        removeExerciseImageCacheDirectory()
        WeeklyGoalWidgetPublisher()?.clear()
        try await ActiveWorkoutSnapshotStore.shared.delete()
    }

    func clearLocalArtifacts() async throws {
        Self.removeExerciseImageCacheDirectory(fileManager: fileManager)
        clearWeeklyGoalWidgetSnapshot()
        try await clearActiveWorkoutSnapshot()
    }

    static func removeExerciseImageCacheDirectory(fileManager: FileManager = .default) {
        let cacheDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ExerciseImages", isDirectory: true)

        if let cacheDirectory, fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
        }
    }

    private func stageExerciseImageMetadataReset() throws {
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

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}
