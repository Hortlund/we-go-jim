import CloudKit
import Foundation
import SwiftData
import UIKit

nonisolated struct UserDataCloudBackupRemoteRecord: Equatable, Sendable {
    var updatedAt: Date
    var payloadData: Data
    var contentSummary: UserDataCloudBackupContentSummary? = nil
    var generation: String? = nil
}

nonisolated struct UserDataCloudBackupRemoteMetadata: Codable, Equatable, Sendable {
    var updatedAt: Date
    var contentSummary: UserDataCloudBackupContentSummary? = nil
    var generation: String? = nil
}

nonisolated struct UserDataCloudBackupRemoteSnapshot: Equatable, Sendable {
    var updatedAt: Date
    var contentSummary: UserDataCloudBackupContentSummary
}

nonisolated struct UserDataCloudBackupRestoreResult: Equatable, Sendable {
    var restoredAt: Date
    var cleanupWarnings: [AppDataArtifactCleanupWarning]
}

nonisolated struct UserDataCloudBackupContentSummary: Codable, Equatable, Sendable {
    var profileCount: Int
    var profileWidgetCount: Int
    var customExerciseCount: Int
    var templateFolderCount: Int
    var workoutTemplateCount: Int
    var templateCardioBlockCount: Int
    var templateExerciseCount: Int
    var templateComponentCount: Int
    var templateSetCount: Int
    var templateDropStageCount: Int
    var completedWorkoutCount: Int
    var workoutCardioBlockCount: Int
    var workoutExerciseCount: Int
    var workoutSetCount: Int
    var workoutDropStageCount: Int
}

extension UserDataCloudBackupContentSummary {
    nonisolated var hasTrainingContent: Bool {
        completedWorkoutCount > 0 || workoutTemplateCount > 0 || customExerciseCount > 0
    }

    nonisolated func wouldEraseRemoteContent(_ remote: Self?) -> Bool {
        guard !hasTrainingContent else { return false }
        // Unknown counts include backups written by older app versions.
        guard let remote else { return true }
        return remote.hasTrainingContent
            || (profileCount == 0 && profileWidgetCount == 0 && templateFolderCount == 0)
    }

    nonisolated static func loadLocal(context: ModelContext) throws -> UserDataCloudBackupContentSummary {
        let customSourceName = "custom"
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        let customExerciseDescriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                exercise.sourceName == customSourceName
            }
        )
        let completedWorkoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus
            }
        )

        return UserDataCloudBackupContentSummary(
            profileCount: try context.fetchCount(FetchDescriptor<UserProfile>()),
            profileWidgetCount: try context.fetchCount(FetchDescriptor<ProfileWidgetConfig>()),
            customExerciseCount: try context.fetchCount(customExerciseDescriptor),
            templateFolderCount: try context.fetchCount(FetchDescriptor<TemplateFolder>()),
            workoutTemplateCount: try context.fetchCount(FetchDescriptor<WorkoutTemplate>()),
            templateCardioBlockCount: try context.fetchCount(FetchDescriptor<TemplateCardioBlock>()),
            templateExerciseCount: try context.fetchCount(FetchDescriptor<TemplateExercise>()),
            templateComponentCount: try context.fetchCount(FetchDescriptor<TemplateExerciseComponent>()),
            templateSetCount: try context.fetchCount(FetchDescriptor<TemplateExerciseSet>()),
            templateDropStageCount: try context.fetchCount(FetchDescriptor<TemplateExerciseDropStage>()),
            completedWorkoutCount: try context.fetchCount(completedWorkoutDescriptor),
            workoutCardioBlockCount: try context.fetchCount(FetchDescriptor<WorkoutSessionCardioBlock>()),
            workoutExerciseCount: try context.fetchCount(FetchDescriptor<WorkoutSessionExercise>()),
            workoutSetCount: try context.fetchCount(FetchDescriptor<WorkoutSessionSet>()),
            workoutDropStageCount: try context.fetchCount(FetchDescriptor<WorkoutSessionDropStage>())
        )
    }
}

nonisolated protocol UserDataCloudBackupStoring: Sendable {
    func reportingProgress(_ progress: CloudBackupProgressReporter) -> any UserDataCloudBackupStoring
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws
    func deleteBackup() async throws
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord?
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata?
    func accountIdentifier() async throws -> String
    func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord?
}

extension UserDataCloudBackupStoring {
    nonisolated func reportingProgress(_ progress: CloudBackupProgressReporter) -> any UserDataCloudBackupStoring { self }
    nonisolated func accountIdentifier() async throws -> String { "local-test-store" }
    nonisolated func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord? { nil }
}

nonisolated enum UserDataCloudBackupDescriptor {
    static let recordType = "WGJUserDataBackup"
    static let recordName = "current-user-data-backup-v2"

    enum Field {
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let contentSummary = "contentSummary"
        static let payloadAsset = "payloadAsset"
        static let payloadData = "payloadData"
        static let payloadCompression = "payloadCompression"
    }

    static let metadataFieldKeys: [CKRecord.FieldKey] = [Field.updatedAt, Field.contentSummary]

    static func encodeSummary(_ summary: UserDataCloudBackupContentSummary?, updatedAt: Date) throws -> Data? {
        guard let summary else { return nil }
        return try JSONEncoder().encode(UserDataCloudBackupRemoteMetadata(updatedAt: updatedAt, contentSummary: summary))
    }

    static func decodeSummary(_ data: Data?, updatedAt: Date) -> UserDataCloudBackupContentSummary? {
        guard let data,
              let metadata = try? JSONDecoder().decode(UserDataCloudBackupRemoteMetadata.self, from: data),
              abs(metadata.updatedAt.timeIntervalSince(updatedAt)) < 0.001
        else { return nil }
        // Older app versions can preserve an unknown summary field while replacing the payload.
        // Only use counts stamped for this upload (allowing sub-millisecond date rounding).
        return metadata.contentSummary
    }
}

nonisolated enum BoundaryCloudBackupReason: String, Sendable {
    case manual
    case retry
    case workoutCompleted
    case workoutCompletionTemplateSaved
    case workoutDeleted
    case workoutEdited
    case profileWidgetsSaved
    case templateSaved
    case customExerciseSaved
    case profileSaved
    case settingsSaved

    var failureDescription: String {
        switch self {
        case .manual:
            return "manual backup"
        case .retry:
            return "backup retry"
        case .workoutCompleted:
            return "workout completion"
        case .workoutCompletionTemplateSaved:
            return "workout completion template update"
        case .workoutEdited:
            return "workout edit"
        case .profileWidgetsSaved:
            return "profile widget save"
        case .workoutDeleted:
            return "workout delete"
        case .templateSaved:
            return "template save"
        case .customExerciseSaved:
            return "custom exercise save"
        case .profileSaved:
            return "profile save"
        case .settingsSaved:
            return "settings save"
        }
    }
}

nonisolated struct UserDataBackupBoundaryEffects: Sendable {
    let scheduleBackup: @Sendable (ModelContainer, BoundaryCloudBackupReason) -> Void

    static let live = Self(scheduleBackup: BoundaryCloudBackupScheduler.exportBestEffort)
}

nonisolated enum BoundaryCloudBackupScheduler {
    static func exportBestEffort(container: ModelContainer, reason: BoundaryCloudBackupReason) {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }

        do { try BackupLocalJournal.markPending(for: container) }
        catch {
            reportJournalFailure(error)
            return
        }
        Task.detached(priority: .utility) {
            let sessionRevision = await AppRuntimeState.shared.cloudBackupSessionRevision
            await BoundaryCloudBackupExportQueue.shared.enqueue(container: container, reason: reason, sessionRevision: sessionRevision)
        }
    }

    static func exportManually(container: ModelContainer) async {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }
        do { try BackupLocalJournal.markPending(for: container) }
        catch {
            reportJournalFailure(error)
            return
        }
        let sessionRevision = await AppRuntimeState.shared.cloudBackupSessionRevision
        await BoundaryCloudBackupExportQueue.shared.enqueueAndWait(container: container, sessionRevision: sessionRevision)
    }
    static func resumePending(container: ModelContainer) {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }
        do {
            guard let pending = try BackupLocalJournal.pending(for: container),
                  pending.retryAfter != .distantFuture else { return }
            Task.detached(priority: .utility) {
                let revision = await AppRuntimeState.shared.cloudBackupSessionRevision
                let delay = max(0, pending.retryAfter.timeIntervalSinceNow)
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled,
                      let current = try? BackupLocalJournal.pending(for: container),
                      current.ticket == pending.ticket, current.retryAfter <= .now else { return }
                await BoundaryCloudBackupExportQueue.shared.enqueue(container: container, reason: .retry, sessionRevision: revision)
            }
        } catch { reportJournalFailure(error) }
    }

    static func resumeOperations(container: ModelContainer) {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }
        Task.detached(priority: .utility) {
            do {
                try await UserDataCloudBackupService(localContainer: container,
                    backupStore: CloudKitUserDataCloudBackupStore()).resumePendingRestore()
            } catch {
                await MainActor.run { AppRuntimeState.shared.updateUserDataSyncStatus(.degraded("Cloud restore paused: \(error.localizedDescription)")) }
            }
            resumePending(container: container)
        }
    }

    private static func reportJournalFailure(_ error: Error) {
        let message = "Your data is saved locally, but the backup request could not be saved: \(error.localizedDescription)"
        Task { @MainActor in AppRuntimeState.shared.updateUserDataSyncStatus(.degraded(message)) }
    }

}

nonisolated enum CloudBackupStatusCheckScheduler {
    @discardableResult
    static func checkMetadataBestEffort(container: ModelContainer, isStartup: Bool = true) -> Task<Void, Never>? {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return nil }

        return Task.detached(priority: .utility) {
            await checkMetadata(isStartup: isStartup, state: AppRuntimeState.shared) {
                try await UserDataCloudBackupService(
                    localContainer: container,
                    backupStore: CloudKitUserDataCloudBackupStore()
                ).latestBackupMetadata()
            }
        }
    }

    @MainActor
    static func checkMetadata(
        isStartup: Bool,
        state: AppRuntimeState,
        fetchMetadata: @Sendable () async throws -> UserDataCloudBackupRemoteMetadata?
    ) async {
        guard !Task.isCancelled else { return }
        let previousStatus = state.userDataSyncStatus
        guard let revision = state.beginCloudBackupMetadataCheck(isStartup: isStartup) else { return }
        do {
            let metadata = try await fetchMetadata()
            guard !Task.isCancelled else {
                state.finishUserDataSyncStatusCheck(previousStatus, matching: revision)
                return
            }
            state.finishCloudBackupMetadataCheck(metadata, matching: revision)
        } catch {
            state.finishUserDataSyncStatusCheck(
                CloudBackupOperationErrorPolicy.isCancellation(error, taskWasCancelled: Task.isCancelled)
                    ? previousStatus : .checkFailed(error.localizedDescription),
                matching: revision
            )
        }
    }
}

nonisolated enum CloudBackupOperationErrorPolicy {
    static func isCancellation(_ error: Error, taskWasCancelled: Bool) -> Bool {
        if taskWasCancelled || error is CancellationError {
            return true
        }
        if let cloudError = error as? CKError {
            return cloudError.code == .operationCancelled
        }

        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.operationCancelled.rawValue
    }
}

private struct BoundaryCloudBackupRequest {
    let container: ModelContainer
    let reason: BoundaryCloudBackupReason
    let sessionRevision: Int
    var completions: [CheckedContinuation<Void, Never>]
}

actor BoundaryCloudBackupExportQueue {
    static let shared = BoundaryCloudBackupExportQueue()

    private var isProcessing = false
    private var pendingRequest: BoundaryCloudBackupRequest?
    private let exportOperation: @Sendable (ModelContainer, BoundaryCloudBackupReason, Int) async -> Void

    init(exportOperation: @escaping @Sendable (ModelContainer, BoundaryCloudBackupReason, Int) async -> Void = BoundaryCloudBackupExportQueue.export) {
        self.exportOperation = exportOperation
    }

    func enqueue(
        container: ModelContainer,
        reason: BoundaryCloudBackupReason,
        sessionRevision: Int,
        completion: CheckedContinuation<Void, Never>? = nil
    ) {
        var completions = pendingRequest?.completions ?? []
        if let completion { completions.append(completion) }
        pendingRequest = BoundaryCloudBackupRequest(
            container: container, reason: completions.isEmpty ? reason : .manual, sessionRevision: sessionRevision, completions: completions
        )
        guard !isProcessing else { return }

        isProcessing = true
        Task(priority: .utility) {
            await processPendingRequests()
        }
    }

    func enqueueAndWait(container: ModelContainer, sessionRevision: Int) async {
        await withCheckedContinuation { completion in
            enqueue(container: container, reason: .manual, sessionRevision: sessionRevision, completion: completion)
        }
    }

    private func processPendingRequests() async {
        while let request = pendingRequest {
            pendingRequest = nil
            await exportOperation(request.container, request.reason, request.sessionRevision)
            for completion in request.completions { completion.resume() }
        }
        isProcessing = false
    }

    @concurrent
    private static func export(container: ModelContainer, reason: BoundaryCloudBackupReason, sessionRevision: Int) async {
        guard (try? BackupLocalJournal.pending(for: container)) != nil else { return }
        let canExport = await MainActor.run {
            guard AppRuntimeState.shared.cloudBackupSessionRevision == sessionRevision else { return false }
            AppRuntimeState.shared.updateUserDataSyncStatus(.pending())
            return true
        }
        guard canExport else { return }
        do {
            let exportedSnapshot = try await UserDataCloudBackupService(
                localContainer: container,
                backupStore: CloudKitUserDataCloudBackupStore()
            ).exportCurrentBackup(expectedSessionRevision: sessionRevision, showsProgress: reason == .manual)
            await MainActor.run {
                AppRuntimeState.shared.recordSuccessfulCloudBackup(exportedSnapshot, sessionRevision: sessionRevision)
            }
        } catch {
            if let pending = try? BackupLocalJournal.pending(for: container) {
                let isConflict = error is UserDataCloudBackupSafetyError || error is PersistentRestoreRecovery.RecoveryRequired
                let delay = max((error as? CKError)?.retryAfterSeconds ?? 0, min(3600, 30 * pow(2, Double(min(pending.attempt, 7)))))
                try? BackupLocalJournal.finish(pending, for: container, retryAfter: isConflict ? .distantFuture : Date().addingTimeInterval(delay))
                if !isConflict {
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(for: .seconds(delay))
                        BoundaryCloudBackupScheduler.resumePending(container: container)
                    }
                }
            }
            await MainActor.run {
                guard AppRuntimeState.shared.cloudBackupSessionRevision == sessionRevision else { return }
                AppRuntimeState.shared.updateUserDataSyncStatus(.degraded("Cloud backup failed after \(reason.failureDescription): \(error.localizedDescription)"))
            }
        }
    }
}

nonisolated enum UserDataCloudBackupSafetyError: LocalizedError {
    case emptyDevice
    case remoteChanged
    case unrelatedDevice
    case accountChanged
    case deletionPending

    var errorDescription: String? {
        switch self {
        case .emptyDevice:
            "Backup stopped to protect your iCloud saves. This device has no saved workouts, templates, or custom exercises. Restore your cloud backup before backing up this device."
        case .unrelatedDevice:
            "This device has not restored the current cloud backup. Restore it before making a new backup, or choose Use This Device’s Data in Settings → Storage to keep your local data and create a new backup."
        case .deletionPending:
            "Cloud backup deletion has not finished. Retry Delete My Data before creating another backup."
        case .accountChanged:
            "The iCloud account changed. Backup is paused to keep account data separate. Restore the backup for this account before continuing."
        case .remoteChanged:
            "The cloud backup changed while preparing this upload. Nothing was uploaded. Check your cloud backup before trying again."
        }
    }
}

nonisolated enum UserDataCloudRestorePause: LocalizedError {
    case accountNotConfirmed
    case localSaveFailed

    var errorDescription: String? {
        switch self {
        case .accountNotConfirmed:
            "Restore paused because the iCloud account could not be confirmed. Choose Restore Cloud Backup again in Settings → Storage to restore from the currently signed-in account."
        case .localSaveFailed:
            "Automatic restore paused after a local save failed. Choose Restore Cloud Backup again in Settings → Storage when you are ready to retry."
        }
    }
}

nonisolated final class UserDataCloudBackupService {
    private let localContainer: ModelContainer
    private let backupStore: any UserDataCloudBackupStoring
    private let restoreTransaction: UserDataCloudRestoreTransaction
    private let artifactCleanupQueue: AppDataArtifactCleanupQueue
    private let progressCenter: CloudBackupProgressCenter?

    init(
        localContainer: ModelContainer,
        backupStore: any UserDataCloudBackupStoring,
        restoreTransaction: UserDataCloudRestoreTransaction? = nil,
        artifactCleanupQueue: AppDataArtifactCleanupQueue = .shared,
        progressCenter: CloudBackupProgressCenter? = nil
    ) {
        self.localContainer = localContainer
        self.backupStore = backupStore
        self.restoreTransaction = restoreTransaction
            ?? UserDataCloudRestoreTransaction(container: localContainer)
        self.artifactCleanupQueue = artifactCleanupQueue
        self.progressCenter = progressCenter
    }

    @discardableResult
    func exportCurrentBackup(replacingRemote: Bool = false, expectedSessionRevision: Int? = nil, showsProgress: Bool = false) async throws -> UserDataCloudBackupRemoteSnapshot {
        let center = await MainActor.run { [progressCenter] in progressCenter ?? CloudBackupProgressCenter.shared }
        let operation = await center.begin(kind: .backup, foreground: showsProgress || replacingRemote)
        let progress = await operation.reporter
        do {
            let result = try await exportBackup(replacingRemote: replacingRemote, expectedSessionRevision: expectedSessionRevision, progress: progress)
            await center.finish(operation, outcome: .success("Your saved data is backed up to iCloud."))
            return result
        } catch {
            await center.finish(operation, outcome: .failure("Your data is still saved on this device. \(error.localizedDescription)"))
            throw error
        }
    }

    private func exportBackup(replacingRemote: Bool, expectedSessionRevision: Int?, progress: CloudBackupProgressReporter) async throws -> UserDataCloudBackupRemoteSnapshot {
        let backupStore = backupStore.reportingProgress(progress)
        let trace = WGJPerformance.begin("backup.export")
        defer { WGJPerformance.end(trace) }
        if replacingRemote {
            // Persist the explicit choice before waiting behind a stalled download.
            // Its stale ticket can no longer enter the restore transaction.
            try LocalStoreWriteBarrier.exclusively {
                try PersistentRestoreRecovery.requireHealthyStore(localContainer)
                try BackupLocalJournal.reconcileRestore(for: localContainer)
                try BackupLocalJournal.saveRestore(nil, for: localContainer)
            }
        }
        await BackupOperationGate.shared.acquire()
        // Keep the operation gate held through cleanup, but return as soon as the
        // cloud commit and its local acknowledgment are durable.
        var acknowledgedCleanup: BackupLocalJournal.State?
        defer {
            let cleanup = acknowledgedCleanup
            Task { [localContainer, backupStore] in
                if let cleanup {
                    await Self.finishRetentionCleanup(cleanup, localContainer: localContainer, backupStore: backupStore)
                }
                await BackupOperationGate.shared.release()
            }
        }
        if let expectedSessionRevision {
            guard await AppRuntimeState.shared.cloudBackupSessionRevision == expectedSessionRevision else { throw CancellationError() }
        }
        try PersistentRestoreRecovery.requireHealthyStore(localContainer)
        try LocalStoreWriteBarrier.exclusively {
            try PersistentRestoreRecovery.requireHealthyStore(localContainer)
            try BackupLocalJournal.reconcileRestore(for: localContainer)
            guard try BackupLocalJournal.restoreRequest(for: localContainer) == nil else { throw LocalStoreWriteBarrier.RestoreInProgress() }
        }
        let lease = await CloudBackupBackgroundLease.begin()
        defer { Task { @MainActor in lease.end() } }
        progress(.checking)
        let account = try await backupStore.accountIdentifier()
        var state = try BackupLocalJournal.state(for: localContainer)
        let pending = try BackupLocalJournal.pending(for: localContainer)
        guard state.account == nil || state.account == account,
              pending?.account == nil || pending?.account == account else {
            throw UserDataCloudBackupSafetyError.accountChanged
        }
        let remote = try await backupStore.fetchBackupMetadata()
        if let remote {
            let localSummary = try UserDataCloudBackupContentSummary.loadLocal(context: ModelContext(localContainer))
            if localSummary.wouldEraseRemoteContent(remote.contentSummary) { throw UserDataCloudBackupSafetyError.emptyDevice }
            if replacingRemote {
                // Only the explicit recovery action opts into replacement. Automatic saves never do.
                state.generation = remote.generation
                state.legacyUpdatedAt = remote.generation == nil ? remote.updatedAt : nil
            }
            if let generation = remote.generation {
                if state.attemptedManifest?.generation == generation {
                    // Publication succeeded but the process exited before local acknowledgment.
                    state.generation = generation
                    state.manifest = state.attemptedManifest
                    state.attemptedManifest = nil
                    state.account = account
                    try BackupLocalJournal.save(state, for: localContainer)
                }
                guard state.generation == generation else { throw UserDataCloudBackupSafetyError.unrelatedDevice }
            } else if state.legacyUpdatedAt != remote.updatedAt {
                // Safe adoption of an unchanged legacy installation; never infer lineage from counts.
                guard let old = try await backupStore.fetchBackup() else { throw UserDataCloudBackupSafetyError.remoteChanged }
                let (local, _) = try makeExportRecord()
                guard let oldData = try? UserDataBackupPayloadCodec.canonicalData(old.payloadData),
                      oldData == (try UserDataBackupPayloadCodec.canonicalData(local.payloadData)) else {
                    throw UserDataCloudBackupSafetyError.unrelatedDevice
                }
                state.legacyUpdatedAt = remote.updatedAt
            }
        } else if state.generation != nil || state.legacyUpdatedAt != nil {
            guard replacingRemote else { throw UserDataCloudBackupSafetyError.remoteChanged }
            // Explicitly recreate a deleted lineage. Old chunks may have been deleted
            // too, so neither the cached manifest nor an attempted upload is reusable.
            state.garbageRecords = try BackupLocalJournal.knownRecordNames(for: localContainer)
            state.generation = nil
            state.legacyUpdatedAt = nil
            state.manifest = nil
            state.attemptedManifest = nil
        }

        progress(.preparing)
        let snapshot: UserDataCloudBackupRemoteSnapshot
        if let archive = backupStore as? any IncrementalBackupStoring {
            let previous = state.manifest?.generation == remote?.generation ? state.manifest : try await archive.fetchManifest()
            guard previous?.generation == remote?.generation else { throw UserDataCloudBackupSafetyError.remoteChanged }
            let plan = try BackupExportPlan.build(container: localContainer, previous: previous, attempted: state.attemptedManifest, progress: progress)
            defer { plan.cleanUp() }
            if let previous, previous.chunks == plan.manifest.chunks, state.attemptedManifest == nil {
                // Avoid advancing retention or uploading manifests for a no-op save.
                state.account = account
                state.generation = previous.generation
                state.manifest = previous
                try BackupLocalJournal.save(state, for: localContainer)
                if let pending { try BackupLocalJournal.finish(pending, for: localContainer) }
                acknowledgedCleanup = state
                return UserDataCloudBackupRemoteSnapshot(updatedAt: previous.updatedAt, contentSummary: previous.summary)
            }
            if let abandoned = state.attemptedManifest, abandoned.generation != previous?.generation {
                var garbage = state.garbageRecords ?? []
                let reused = Set(plan.manifest.chunks.map(\.recordName))
                garbage.formUnion(Set(abandoned.chunks.map(\.recordName)).subtracting(reused))
                garbage.insert("backup-generation-v3-\(abandoned.generation)")
                state.garbageRecords = garbage
            }
            let retired = Set(previous?.previousGenerations ?? []).subtracting(plan.manifest.previousGenerations)
            state.garbageRecords = (state.garbageRecords ?? []).union(retired.map { "backup-generation-v3-\($0)" })
            state.account = account
            state.attemptedManifest = plan.manifest
            try BackupLocalJournal.save(state, for: localContainer)
            progress(.uploading)
            try await WGJPerformance.measureAsync("backup.upload") {
                try await archive.saveArchive(plan.manifest, chunkFiles: plan.chunkFiles, expectedGeneration: previous?.generation, expectedAccount: account)
            }
            state.generation = plan.manifest.generation
            state.manifest = plan.manifest
            state.attemptedManifest = nil
            snapshot = UserDataCloudBackupRemoteSnapshot(updatedAt: plan.manifest.updatedAt, contentSummary: plan.manifest.summary)
        } else {
            let (record, exported) = try makeExportRecord()
            progress(.uploading)
            try await backupStore.saveBackup(record, expectedUpdatedAt: remote?.updatedAt)
            state.legacyUpdatedAt = record.updatedAt
            state.account = account
            snapshot = exported
        }
        progress(.finishing)
        try BackupLocalJournal.save(state, for: localContainer)
        if let pending { try BackupLocalJournal.finish(pending, for: localContainer) }
        acknowledgedCleanup = state
        return snapshot
    }

    /// Called only while the exporting operation still owns BackupOperationGate.
    /// Cleanup failure (or app termination) leaves the journal intact for retry.
    private static func finishRetentionCleanup(
        _ acknowledged: BackupLocalJournal.State,
        localContainer: ModelContainer,
        backupStore: any UserDataCloudBackupStoring
    ) async {
        guard let archive = backupStore as? any IncrementalBackupStoring,
              let manifest = acknowledged.manifest,
              let garbage = acknowledged.garbageRecords, !garbage.isEmpty else { return }
        do {
            guard try await backupStore.accountIdentifier() == acknowledged.account else { return }
            try await archive.removeOrphanedRecords(garbage, retaining: manifest)
            try BackupLocalJournal.finishCleanup(
                garbage, account: acknowledged.account, generation: manifest.generation, for: localContainer
            )
        } catch { /* Retry at the next successful backup boundary. */ }
    }

    private func makeExportRecord() throws -> (UserDataCloudBackupRemoteRecord, UserDataCloudBackupRemoteSnapshot) {
        let context = ModelContext(localContainer)
        context.autosaveEnabled = false
        try TemplateRepository(modelContext: context, autoSaveChanges: false).pruneOrphanedTemplateGraphs()
        let payload = try UserDataCloudBackupPayload(context: context)
        let summary = payload.contentSummary
        return (
            UserDataCloudBackupRemoteRecord(
                updatedAt: payload.generatedAt,
                payloadData: try Self.makeEncoder().encode(payload),
                contentSummary: summary
            ),
            UserDataCloudBackupRemoteSnapshot(updatedAt: payload.generatedAt, contentSummary: summary)
        )
    }

    func latestBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        try await backupStore.fetchBackupMetadata()
    }

    func deleteRemoteBackup() async throws {
        if let cloud = backupStore as? CloudKitUserDataCloudBackupStore {
            try await cloud.deleteBackup(additionalRecordNames: BackupLocalJournal.knownRecordNames(for: localContainer))
        } else { try await backupStore.deleteBackup() }
        try AppDataDeletionService(modelContext: ModelContext(localContainer)).resetLocalBackupState()
        await MainActor.run { AppRuntimeState.shared.recordCloudBackupDeletion() }
    }

    func latestBackupSnapshot() async throws -> UserDataCloudBackupRemoteSnapshot? {
        guard let record = try await backupStore.fetchBackup() else {
            return nil
        }

        let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        return UserDataCloudBackupRemoteSnapshot(
            updatedAt: record.updatedAt,
            contentSummary: payload.contentSummary
        )
    }

    func restoreLatestBackup(replacingLocalData: Bool = false, previousGeneration: Bool = false) async throws -> UserDataCloudBackupRestoreResult? {
        // This intent must survive even the first account lookup failing or the
        // process exiting while offline. Only this explicit call may bind an
        // unknown account. A deferred unbound request needs a fresh user choice;
        // the account may have changed while the app was closed.
        let bindingSessionRevision = await AppRuntimeState.shared.cloudBackupSessionRevision
        let request = try LocalStoreWriteBarrier.exclusively {
            try PersistentRestoreRecovery.requireHealthyStore(localContainer)
            try BackupLocalJournal.reconcileRestore(for: localContainer)
            let request = BackupLocalJournal.RestoreRequest(account: nil,
                replacingLocalData: replacingLocalData, previousGeneration: previousGeneration)
            // Explicit recovery choices supersede paused or downloading attempts.
            // The write barrier and transaction ticket prevent a stale commit.
            try BackupLocalJournal.saveRestore(request, for: localContainer)
            return request
        }
        return try await resumeRestore(request, bindingSessionRevision: bindingSessionRevision)
    }

    @discardableResult
    func resumePendingRestore() async throws -> UserDataCloudBackupRestoreResult? {
        try LocalStoreWriteBarrier.exclusively { try BackupLocalJournal.reconcileRestore(for: localContainer) }
        _ = try await finishRestoreCleanup()
        guard let request = try BackupLocalJournal.restoreRequest(for: localContainer) else { return nil }
        return try await resumeRestore(request)
    }

    private func resumeRestore(_ original: BackupLocalJournal.RestoreRequest, bindingSessionRevision: Int? = nil) async throws -> UserDataCloudBackupRestoreResult? {
        guard try BackupLocalJournal.restoreRequest(for: localContainer)?.ticket == original.ticket else { return nil }
        // An automatic observer must not reserve an unbound request ahead of
        // the explicit call that is allowed to bind its iCloud account. Keep the
        // checks inside the gate too, since the durable request can change.
        guard original.requiresExplicitRetry != true else { throw UserDataCloudRestorePause.localSaveFailed }
        guard original.account != nil || bindingSessionRevision != nil else { throw UserDataCloudRestorePause.accountNotConfirmed }
        let center = await MainActor.run { [progressCenter] in progressCenter ?? CloudBackupProgressCenter.shared }
        // Foreground/launch hooks can observe the same durable request while its
        // first download is still running. Keep one operation and one result UI.
        guard let operation = await center.beginRestore(requestID: original.ticket, foreground: true) else { return nil }
        let progress = await operation.reporter
        do {
            let result = try await performRestore(original, bindingSessionRevision: bindingSessionRevision, progress: progress)
            let message = result.map { result in
                result.cleanupWarnings.isEmpty
                    ? "Your backup has been restored on this device."
                    : "Your backup has been restored. Some old local files will be cleaned up automatically on the next launch."
            } ?? "No backup was restored. Check your cloud backup and try again."
            await center.finish(operation, outcome: result == nil ? .failure(message) : .success(message))
            return result
        } catch {
            await center.finish(operation, outcome: .failure(error.localizedDescription))
            throw error
        }
    }

    private func performRestore(_ original: BackupLocalJournal.RestoreRequest, bindingSessionRevision: Int?, progress: CloudBackupProgressReporter) async throws -> UserDataCloudBackupRestoreResult? {
        let backupStore = backupStore.reportingProgress(progress)
        await BackupOperationGate.shared.acquire()
        defer { Task { await BackupOperationGate.shared.release() } }
        let lease = await CloudBackupBackgroundLease.begin()
        defer { Task { @MainActor in lease.end() } }
        try LocalStoreWriteBarrier.exclusively { try BackupLocalJournal.reconcileRestore(for: localContainer) }
        guard var request = try BackupLocalJournal.restoreRequest(for: localContainer),
              request.ticket == original.ticket else { return nil }
        let sessionRevision = await MainActor.run { AppRuntimeState.shared.cloudBackupSessionRevision }
        do {
            guard request.requiresExplicitRetry != true else { throw UserDataCloudRestorePause.localSaveFailed }
            guard request.account != nil || bindingSessionRevision != nil else { throw UserDataCloudRestorePause.accountNotConfirmed }
            if let bindingSessionRevision, bindingSessionRevision != sessionRevision {
                throw UserDataCloudBackupSafetyError.accountChanged
            }
            progress(.checking)
            let account = try await backupStore.accountIdentifier()
            guard await AppRuntimeState.shared.cloudBackupSessionRevision == sessionRevision else {
                throw UserDataCloudBackupSafetyError.accountChanged
            }
            guard request.account == nil || request.account == account else { throw UserDataCloudBackupSafetyError.accountChanged }
            request.account = account
            try updateRestore(request)
            let headMetadata = try await backupStore.fetchBackupMetadata()
            if request.pinned, request.head != headMetadata { throw UserDataCloudBackupSafetyError.remoteChanged }
            request.head = headMetadata
            request.pinned = true
            try updateRestore(request)
            progress(.downloading)
            guard let record = try await (request.previousGeneration ? backupStore.fetchPreviousBackup() : backupStore.fetchBackup()) else {
                try clearRestore(request.ticket)
                return nil
            }
            progress(.validating)
            let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
            try payload.validate()
            if !request.replacingLocalData {
                guard try Self.isLocalUserDataEmpty(context: ModelContext(localContainer)) else {
                    try clearRestore(request.ticket)
                    return nil
                }
            }
            guard try await backupStore.accountIdentifier() == request.account else { throw UserDataCloudBackupSafetyError.accountChanged }
            guard try await backupStore.fetchBackupMetadata() == headMetadata else { throw UserDataCloudBackupSafetyError.remoteChanged }
            let oldState = try BackupLocalJournal.state(for: localContainer)
            let cleanup = oldState.account == request.account
                ? try BackupLocalJournal.knownRecordNames(for: localContainer) : []
            request.stateAfterCommit = .init(account: request.account, generation: headMetadata?.generation,
                legacyUpdatedAt: headMetadata?.generation == nil ? headMetadata?.updatedAt : nil,
                garbageRecords: cleanup.isEmpty ? nil : cleanup)
            request.pendingBeforeCommit = try BackupLocalJournal.pending(for: localContainer)
            try updateRestore(request)
            progress(.restoring)
            try restoreTransaction.commit(replacingLocalData: request.replacingLocalData, restoreTicket: request.ticket, replacementPayload: payload, progress: progress,
                mergeDatabaseGraph: { try payload.mergeDatabaseGraph(into: $0) },
                relinkRelationships: { try payload.relinkRelationships(in: $0) })
            try LocalStoreWriteBarrier.exclusively {
                if BackupLocalJournal.directory(for: localContainer) == nil {
                    // Memory-only test/preview stores have no crash recovery receipt.
                    if let state = request.stateAfterCommit { try BackupLocalJournal.save(state, for: localContainer) }
                    if let pending = request.pendingBeforeCommit { try BackupLocalJournal.finish(pending, for: localContainer) }
                    try BackupLocalJournal.saveRestoreCleanup(request.cleanupBefore, for: localContainer)
                    try BackupLocalJournal.saveRestore(nil, for: localContainer)
                } else { try BackupLocalJournal.reconcileRestore(for: localContainer) }
            }
            HistoryAnalyticsCache.shared.clear()
            // Emit once for this commit, before any asynchronous cleanup. Cleanup
            // retries (including crash recovery) must never reset a newer workout.
            await MainActor.run {
                NotificationCenter.default.post(name: .wgjUserDataRestoreDidComplete, object: nil,
                    userInfo: ["cleanupBefore": request.cleanupBefore])
            }
            progress(.finishing)
            let cleanupWarnings = try await finishRestoreCleanup()
            await MainActor.run {
                AppRuntimeState.shared.recordSuccessfulCloudBackup(.init(updatedAt: record.updatedAt,
                    contentSummary: payload.contentSummary), sessionRevision: sessionRevision)
            }
            return .init(restoredAt: record.updatedAt, cleanupWarnings: cleanupWarnings)
        } catch let error as PersistentRestoreRecovery.RecoveryRequired {
            // A known failed local transaction needs a deliberate retry after
            // rollback. A process interruption still retains its resumable intent.
            let pause = Result {
                try LocalStoreWriteBarrier.exclusively {
                    try BackupLocalJournal.pauseRestore(request.ticket, for: localContainer)
                }
            }
            await MainActor.run { AppRuntimeState.shared.requiresStorageRecovery = true }
            try pause.get()
            throw error
        } catch {
            // Transport/cancellation errors keep the request for the next foreground
            // or launch. Invalid data and changed accounts/heads require a new choice.
            if error is UserDataCloudBackupSafetyError || error is UserDataCloudRestoreValidationError || error is BackupArchiveError || error is DecodingError {
                try clearRestore(request.ticket)
            }
            throw error
        }
    }

    func finishRestoreCleanup() async throws -> [AppDataArtifactCleanupWarning] {
        guard let cutoff = try BackupLocalJournal.restoreCleanup(for: localContainer) else { return [] }
        HistoryAnalyticsCache.shared.clear()
        let warnings = await artifactCleanupQueue.enqueue(Set(AppDataArtifact.allCases), before: cutoff)
        try LocalStoreWriteBarrier.exclusively {
            if try BackupLocalJournal.restoreCleanup(for: localContainer) == cutoff {
                try BackupLocalJournal.saveRestoreCleanup(nil, for: localContainer)
            }
        }
        return warnings
    }

    private func updateRestore(_ request: BackupLocalJournal.RestoreRequest) throws {
        try LocalStoreWriteBarrier.exclusively {
            guard try BackupLocalJournal.restoreRequest(for: localContainer)?.ticket == request.ticket else { throw CancellationError() }
            try BackupLocalJournal.saveRestore(request, for: localContainer)
        }
    }

    private func clearRestore(_ ticket: UUID) throws {
        try LocalStoreWriteBarrier.exclusively {
            guard try BackupLocalJournal.restoreRequest(for: localContainer)?.ticket == ticket else { return }
            try BackupLocalJournal.saveRestore(nil, for: localContainer)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func isLocalUserDataEmpty(context: ModelContext) throws -> Bool {
        let customSourceName = "custom"
        let customExerciseDescriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                exercise.sourceName == customSourceName
            }
        )
        return try context.fetchCount(FetchDescriptor<UserProfile>()) == 0
            && context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 0
            && context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0
            && context.fetchCount(customExerciseDescriptor) == 0
    }
}

nonisolated struct CloudKitUserDataCloudBackupStore: IncrementalBackupStoring {
    private static let inlinePayloadFallbackLimitBytes = 900_000
    private static let lzfsePayloadCompression = "lzfse"

    let database: CKDatabase?
    let cloudContainer: CKContainer?
    var progress = CloudBackupProgressReporter()

    func reportingProgress(_ progress: CloudBackupProgressReporter) -> any UserDataCloudBackupStoring {
        var store = self
        store.progress = progress
        return store
    }

    init(container: CKContainer? = nil) {
        self.cloudContainer = container ?? AppRuntimeConfig.makeCloudKitContainer()
        self.database = cloudContainer?.privateCloudDatabase
    }

    static func removeExpiredTemporaryPayloads(olderThan age: TimeInterval = 24 * 60 * 60) {
        BackupTemporaryFiles.removeExpired(olderThan: age)
    }

    @concurrent
    func saveBackup(_ backup: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        let existing = try await existingRecord(
            recordID: recordID,
            desiredKeys: [UserDataCloudBackupDescriptor.Field.updatedAt]
        )
        let actualUpdatedAt = existing.map { $0[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast }
        guard actualUpdatedAt == expectedUpdatedAt else { throw UserDataCloudBackupSafetyError.remoteChanged }
        let record = existing ?? CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: recordID)
        let payloadURL = try writeTemporaryPayload(backup.payloadData)
        defer {
            BackupTemporaryFiles.remove(payloadURL)
        }

        record[UserDataCloudBackupDescriptor.Field.updatedAt] = backup.updatedAt as CKRecordValue
        record[UserDataCloudBackupDescriptor.Field.contentSummary] = try UserDataCloudBackupDescriptor.encodeSummary(
            backup.contentSummary, updatedAt: backup.updatedAt
        ) as CKRecordValue?
        record[UserDataCloudBackupDescriptor.Field.schemaVersion] = NSNumber(value: UserDataCloudBackupPayload.schemaVersion)
        record[UserDataCloudBackupDescriptor.Field.payloadAsset] = CKAsset(fileURL: payloadURL)
        if let inlinePayload = Self.inlinePayloadFallback(for: backup.payloadData) {
            record[UserDataCloudBackupDescriptor.Field.payloadData] = inlinePayload.data as CKRecordValue
            record[UserDataCloudBackupDescriptor.Field.payloadCompression] = inlinePayload.compression as CKRecordValue?
        } else {
            record[UserDataCloudBackupDescriptor.Field.payloadData] = nil
            record[UserDataCloudBackupDescriptor.Field.payloadCompression] = nil
        }

        let results = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let result = results.saveResults[recordID] else {
            throw UserDataCloudBackupSafetyError.remoteChanged
        }
        _ = try result.get()
    }

    func deleteLegacyBackup() async throws {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard try await existingRecord(recordID: recordID, desiredKeys: []) != nil else {
            return
        }

        _ = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .allKeys,
            atomically: true
        )
    }

    func fetchLegacyBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard let record = try await existingRecord(recordID: recordID) else {
            return nil
        }

        let updatedAt = record[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast
        if let asset = record[UserDataCloudBackupDescriptor.Field.payloadAsset] as? CKAsset,
           let fileURL = asset.fileURL,
           let payloadData = try? Data(contentsOf: fileURL) {
            return UserDataCloudBackupRemoteRecord(updatedAt: updatedAt, payloadData: payloadData)
        }
        if let payloadData = record[UserDataCloudBackupDescriptor.Field.payloadData] as? Data {
            let compression = record[UserDataCloudBackupDescriptor.Field.payloadCompression] as? String
            guard let decodedPayloadData = Self.decodedInlinePayload(payloadData, compression: compression) else {
                return nil
            }
            return UserDataCloudBackupRemoteRecord(updatedAt: updatedAt, payloadData: decodedPayloadData)
        }
        return nil
    }

    func fetchLegacyBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard let record = try await existingRecord(
            recordID: recordID,
            desiredKeys: UserDataCloudBackupDescriptor.metadataFieldKeys
        ) else {
            return nil
        }

        let updatedAt = record[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast
        let summary = UserDataCloudBackupDescriptor.decodeSummary(
            record[UserDataCloudBackupDescriptor.Field.contentSummary] as? Data, updatedAt: updatedAt
        )
        return UserDataCloudBackupRemoteMetadata(updatedAt: updatedAt, contentSummary: summary)
    }

    private static func inlinePayloadFallback(for payloadData: Data) -> (data: Data, compression: String?)? {
        if payloadData.count <= inlinePayloadFallbackLimitBytes {
            return (payloadData, nil)
        }

        guard let compressedPayload = try? (payloadData as NSData).compressed(using: .lzfse) as Data,
              compressedPayload.count <= inlinePayloadFallbackLimitBytes
        else {
            return nil
        }
        return (compressedPayload, lzfsePayloadCompression)
    }

    private static func decodedInlinePayload(_ payloadData: Data, compression: String?) -> Data? {
        guard let compression else {
            return payloadData
        }

        guard compression == lzfsePayloadCompression else {
            return nil
        }
        return try? (payloadData as NSData).decompressed(using: .lzfse) as Data
    }

    func existingRecord(
        recordID: CKRecord.ID,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> CKRecord? {
        try await existingRecords(recordIDs: [recordID], desiredKeys: desiredKeys)[recordID]
    }

    func existingRecords(
        recordIDs: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord.ID: CKRecord] {
        let database = try requireDatabase()
        var records: [CKRecord.ID: CKRecord] = [:]
        for offset in stride(from: 0, to: recordIDs.count, by: 50) {
            try Task.checkCancellation()
            let batch = Array(recordIDs[offset..<min(offset + 50, recordIDs.count)])
            let results: [CKRecord.ID: Result<CKRecord, Error>]
            do {
                results = try await WGJPerformance.measureAsync("backup.cloud.read") {
                    try await database.records(for: batch, desiredKeys: desiredKeys)
                }
            } catch let error as CKError where error.code == .unknownItem && batch.count == 1 {
                // A single-record fetch may report absence at the operation level.
                continue
            }
            records.merge(try Self.resolveRecords(results, requestedIDs: batch)) { _, new in new }
        }
        return records
    }

    /// Only an explicit unknownItem means absent. Missing results or transport
    /// failures must never be mistaken for permission to create or delete data.
    static func resolveRecords(
        _ results: [CKRecord.ID: Result<CKRecord, Error>],
        requestedIDs: [CKRecord.ID]
    ) throws -> [CKRecord.ID: CKRecord] {
        var records: [CKRecord.ID: CKRecord] = [:]
        for recordID in requestedIDs {
            guard let result = results[recordID] else {
                throw BackupArchiveError.missingChunk
            }
            switch result {
            case .success(let record):
                records[recordID] = record
            case .failure(let error as CKError) where error.code == .unknownItem:
                continue
            case .failure(let error):
                throw error
            }
        }
        return records
    }

    private func writeTemporaryPayload(_ data: Data) throws -> URL {
        try BackupTemporaryFiles.write(data, prefix: "",
            in: FileManager.default.temporaryDirectory.appendingPathComponent(BackupTemporaryFiles.legacyDirectoryName, isDirectory: true),
            fileExtension: "json")
    }

    func requireDatabase() throws -> CKDatabase {
        guard let database else {
            throw CloudKitContainerAvailabilityError.unavailable
        }
        return database
    }
}

/// A best-effort execution window, never a substitute for durable operation state.
@MainActor
private final class CloudBackupBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    static func begin() -> CloudBackupBackgroundLease {
        let lease = CloudBackupBackgroundLease()
        lease.identifier = UIApplication.shared.beginBackgroundTask(withName: "WGJ cloud backup") { [weak lease] in
            lease?.end()
        }
        return lease
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
