import Foundation
import SwiftData

nonisolated final class AppDataDeletionService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let deleteCloudBackup: @Sendable () async throws -> Void
    private let clearWeeklyGoalWidgetSnapshot: @Sendable () -> Void
    private let clearActiveWorkoutSnapshot: @Sendable () async throws -> Void
    private let resetAppleHealthState: @Sendable () async throws -> Void

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        deleteCloudBackup: (@Sendable () async throws -> Void)? = nil,
        clearWeeklyGoalWidgetSnapshot: @escaping @Sendable () -> Void = {
            WeeklyGoalWidgetPublisher()?.clear()
        },
        clearActiveWorkoutSnapshot: @escaping @Sendable () async throws -> Void = {
            try await AppDataDeletionService.clearDefaultActiveWorkoutSnapshot()
        },
        resetAppleHealthState: @escaping @Sendable () async throws -> Void = {
            try AppleHealthExportService.shared.resetLocalState()
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
        self.resetAppleHealthState = resetAppleHealthState
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

    func stageLocalDataDeletion(preservingHistory payload: UserDataCloudBackupPayload? = nil) throws {
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

        var duplicateHistory = false
        if let payload {
            duplicateHistory = try deleteMissing(WorkoutSessionDropStage.self, keeping: Set(payload.workoutDropStages.map(\.id)), id: \.id) || duplicateHistory
            duplicateHistory = try deleteMissing(WorkoutSessionSet.self, keeping: Set(payload.workoutSets.map(\.id)), id: \.id) || duplicateHistory
            duplicateHistory = try deleteMissing(WorkoutSessionCardioBlock.self, keeping: Set(payload.workoutCardioBlocks.map(\.id)), id: \.id) || duplicateHistory
            duplicateHistory = try deleteMissing(WorkoutSessionSupersetGroup.self, keeping: Set((payload.workoutSupersetGroups ?? []).map(\.id)), id: \.id) || duplicateHistory
            duplicateHistory = try deleteMissing(WorkoutSessionExercise.self, keeping: Set(payload.workoutExercises.map(\.id)), id: \.id) || duplicateHistory
            duplicateHistory = try deleteMissing(WorkoutSession.self, keeping: Set(payload.workoutSessions.map(\.id)), id: \.id) || duplicateHistory
            // The bulk projection rebuild reconciles derived records by identity.
        }
        if payload == nil || duplicateHistory {
            // Corrupt local identities cannot be reused safely: cascading deletes
            // may remove children belonging to either duplicate. Rebuild the whole
            // history graph from the validated payload inside the restore transaction.
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
        }
        try deleteAll(CachedCoachFollowUpNarrative.self)
        try deleteAll(CachedCoachNarrative.self)
        try deleteAll(ProfileWidgetConfig.self)
        try deleteAll(UserDataDeletionTombstone.self)
        try deleteAll(UserProfile.self)
    }

    func resetLocalBackupState() throws {
        try LocalStoreWriteBarrier.exclusively {
            try BackupLocalJournal.reconcileRestore(for: modelContext.container)
            try BackupLocalJournal.saveRestore(nil, for: modelContext.container)
            try BackupLocalJournal.save(.init(), for: modelContext.container)
            if let pending = try BackupLocalJournal.pending(for: modelContext.container) {
                try BackupLocalJournal.finish(pending, for: modelContext.container)
            }
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

    /// Once local deletion commits, cleanup failures are warnings and must not keep the old UI alive.
    @MainActor
    static func performUserDataDeletion(
        deleteCloudBackup: () async throws -> Void,
        commitLocalDeletion: () async throws -> Void,
        didCommitLocalDeletion: () -> Void,
        resetBackupState: () async throws -> Void,
        clearArtifacts: () async throws -> Void
    ) async -> UserDataDeletionOutcome {
        do {
            try await deleteCloudBackup()
            try await commitLocalDeletion()
        } catch {
            return UserDataDeletionOutcome(didDeleteLocalData: false, message: error.localizedDescription)
        }
        didCommitLocalDeletion()
        var warnings: [String] = []
        do { try await resetBackupState() }
        catch { warnings.append(error.localizedDescription) }
        do { try await clearArtifacts() }
        catch { warnings.append(error.localizedDescription) }
        var message = "Your CloudKit backup and local WGJ data were deleted. WGJ will return to setup after you tap OK."
        if !warnings.isEmpty { message += "\n\nCleanup needs attention: " + warnings.joined(separator: "; ") }
        return UserDataDeletionOutcome(didDeleteLocalData: true, message: message)
    }

    static func clearDefaultActiveWorkoutSnapshot(
        sessionID: UUID? = nil,
        queue: AppDataArtifactCleanupQueue = .shared,
        snapshotStore: ActiveWorkoutSnapshotStore = .shared
    ) async throws {
        var targets = Set(sessionID.map { [$0] } ?? [])
        do {
            if let storedID = try await snapshotStore.loadStoredSnapshot()?.session.id { targets.insert(storedID) }
        } catch {
            // An in-memory identity still lets us fence a temporarily unreadable file.
            guard !targets.isEmpty else { throw error }
        }
        guard !targets.isEmpty else { return }
        // Retrying this identity cannot erase a newer workout, even after clock changes.
        let warnings = await queue.enqueueSnapshotDeletion(sessionIDs: targets)
        if !warnings.isEmpty {
            throw LocalArtifactCleanupError(failures: warnings.map(\.description))
        }
    }

    static func clearDefaultLocalArtifacts(
        resetAppleHealthState: @Sendable () async throws -> Void = {
            try AppleHealthExportService.shared.resetLocalState()
        },
        clearExerciseImages: () -> Void = { removeExerciseImageCacheDirectory() },
        clearWeeklyGoalWidgetSnapshot: () -> Void = { WeeklyGoalWidgetPublisher()?.clear() },
        clearActiveWorkoutSnapshot: @Sendable () async throws -> Void = {
            try await AppDataDeletionService.clearDefaultActiveWorkoutSnapshot()
        }
    ) async throws {
        var failures: [String] = []
        do { try await CardioRouteRecorder.shared.reset() }
        catch { failures.append("Outdoor routes: \(error.localizedDescription)") }
        do { try await resetAppleHealthState() }
        catch { failures.append("Apple Health: \(error.localizedDescription)") }
        clearExerciseImages()
        clearWeeklyGoalWidgetSnapshot()
        do { try await clearActiveWorkoutSnapshot() }
        catch { failures.append("Active workout: \(error.localizedDescription)") }
        if !failures.isEmpty { throw LocalArtifactCleanupError(failures: failures) }
    }

    func clearLocalArtifacts() async throws {
        let fileManager = fileManager
        try await Self.clearDefaultLocalArtifacts(
            resetAppleHealthState: resetAppleHealthState,
            clearExerciseImages: { Self.removeExerciseImageCacheDirectory(fileManager: fileManager) },
            clearWeeklyGoalWidgetSnapshot: clearWeeklyGoalWidgetSnapshot,
            clearActiveWorkoutSnapshot: clearActiveWorkoutSnapshot
        )
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

    private func deleteMissing<T: PersistentModel>(_ type: T.Type, keeping ids: Set<UUID>, id: KeyPath<T, UUID>) throws -> Bool {
        var seen = Set<UUID>()
        var hasDuplicates = false
        for item in try modelContext.fetch(FetchDescriptor<T>()) {
            let identifier = item[keyPath: id]
            if !seen.insert(identifier).inserted { hasDuplicates = true }
            if !ids.contains(identifier) { modelContext.delete(item) }
        }
        return hasDuplicates
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}

nonisolated struct LocalArtifactCleanupError: LocalizedError {
    let failures: [String]

    var errorDescription: String? {
        "Some local files could not be cleared. " + failures.joined(separator: "; ")
    }
}

nonisolated struct UserDataDeletionOutcome {
    let didDeleteLocalData: Bool
    let message: String
    var title: String { didDeleteLocalData ? "Data Deleted" : "Delete Failed" }
}
