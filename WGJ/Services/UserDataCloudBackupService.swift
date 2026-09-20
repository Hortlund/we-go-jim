import CloudKit
import Foundation
import SwiftData

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
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws
    func deleteBackup() async throws
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord?
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata?
    func accountIdentifier() async throws -> String
    func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord?
}

extension UserDataCloudBackupStoring {
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
                await BoundaryCloudBackupExportQueue.shared.enqueue(container: container, reason: .manual, sessionRevision: revision)
            }
        } catch { reportJournalFailure(error) }
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
            container: container, reason: reason, sessionRevision: sessionRevision, completions: completions
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
            ).exportCurrentBackup(expectedSessionRevision: sessionRevision)
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

nonisolated final class UserDataCloudBackupService {
    private let localContainer: ModelContainer
    private let backupStore: any UserDataCloudBackupStoring
    private let restoreTransaction: UserDataCloudRestoreTransaction
    private let artifactCleanupQueue: AppDataArtifactCleanupQueue

    init(
        localContainer: ModelContainer,
        backupStore: any UserDataCloudBackupStoring,
        restoreTransaction: UserDataCloudRestoreTransaction? = nil,
        artifactCleanupQueue: AppDataArtifactCleanupQueue = .shared
    ) {
        self.localContainer = localContainer
        self.backupStore = backupStore
        self.restoreTransaction = restoreTransaction
            ?? UserDataCloudRestoreTransaction(container: localContainer)
        self.artifactCleanupQueue = artifactCleanupQueue
    }

    @discardableResult
    func exportCurrentBackup(replacingRemote: Bool = false, expectedSessionRevision: Int? = nil) async throws -> UserDataCloudBackupRemoteSnapshot {
        await BackupOperationGate.shared.acquire()
        defer { Task { await BackupOperationGate.shared.release() } }
        if let expectedSessionRevision {
            guard await AppRuntimeState.shared.cloudBackupSessionRevision == expectedSessionRevision else { throw CancellationError() }
        }
        try PersistentRestoreRecovery.requireHealthyStore(localContainer)
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

        let snapshot: UserDataCloudBackupRemoteSnapshot
        if let archive = backupStore as? any IncrementalBackupStoring {
            let previous = state.manifest?.generation == remote?.generation ? state.manifest : try await archive.fetchManifest()
            guard previous?.generation == remote?.generation else { throw UserDataCloudBackupSafetyError.remoteChanged }
            let plan = try BackupExportPlan.build(container: localContainer, previous: previous, attempted: state.attemptedManifest)
            defer { plan.cleanUp() }
            if let previous, previous.chunks == plan.manifest.chunks, state.attemptedManifest == nil {
                // Avoid advancing retention or uploading manifests for a no-op save.
                state.account = account
                state.generation = previous.generation
                state.manifest = previous
                if let garbage = state.garbageRecords, !garbage.isEmpty {
                    do {
                        try await archive.removeOrphanedRecords(garbage, retaining: previous)
                        state.garbageRecords = nil
                    } catch { /* Keep cleanup work durable until another boundary. */ }
                }
                try BackupLocalJournal.save(state, for: localContainer)
                if let pending { try BackupLocalJournal.finish(pending, for: localContainer) }
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
            try await WGJPerformance.measureAsync("backup.upload") {
                try await archive.saveArchive(plan.manifest, chunkFiles: plan.chunkFiles, expectedGeneration: previous?.generation, expectedAccount: account)
            }
            if let garbage = state.garbageRecords, !garbage.isEmpty {
                do {
                    try await archive.removeOrphanedRecords(garbage, retaining: plan.manifest)
                    state.garbageRecords = nil
                } catch { /* Retry cleanup after the next successful publication. */ }
            }
            state.generation = plan.manifest.generation
            state.manifest = plan.manifest
            state.attemptedManifest = nil
            snapshot = UserDataCloudBackupRemoteSnapshot(updatedAt: plan.manifest.updatedAt, contentSummary: plan.manifest.summary)
        } else {
            let (record, exported) = try makeExportRecord()
            try await backupStore.saveBackup(record, expectedUpdatedAt: remote?.updatedAt)
            state.legacyUpdatedAt = record.updatedAt
            state.account = account
            snapshot = exported
        }
        try BackupLocalJournal.save(state, for: localContainer)
        if let pending { try BackupLocalJournal.finish(pending, for: localContainer) }
        return snapshot
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
        await BackupOperationGate.shared.acquire()
        defer { Task { await BackupOperationGate.shared.release() } }
        let sessionRevision = await MainActor.run { AppRuntimeState.shared.cloudBackupSessionRevision }
        let restoreAccount = try await backupStore.accountIdentifier()
        let headMetadata = try await backupStore.fetchBackupMetadata()
        guard let record = try await (previousGeneration ? backupStore.fetchPreviousBackup() : backupStore.fetchBackup()) else {
            return nil
        }

        let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        try payload.validate()

        if !replacingLocalData {
            let checkContext = ModelContext(localContainer)
            guard try Self.isLocalUserDataEmpty(context: checkContext) else {
                return nil
            }
        }

        guard try await backupStore.accountIdentifier() == restoreAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
        let latestMetadata = try await backupStore.fetchBackupMetadata()
        guard latestMetadata == headMetadata else { throw UserDataCloudBackupSafetyError.remoteChanged }
        let pendingBeforeRestore = try BackupLocalJournal.pending(for: localContainer)
        do {
            try restoreTransaction.commit(
                replacingLocalData: replacingLocalData,
                mergeDatabaseGraph: { context in
                    try payload.mergeDatabaseGraph(into: context)
                },
                relinkRelationships: { context in
                    try payload.relinkRelationships(in: context)
                }
            )
        } catch let error as PersistentRestoreRecovery.RecoveryRequired {
            await MainActor.run { AppRuntimeState.shared.requiresStorageRecovery = true }
            throw error
        }
        let oldState = try BackupLocalJournal.state(for: localContainer)
        // Failed uploads are not discoverable through the remote head. Keep their
        // record identities until cleanup succeeds, but never cross account scopes.
        let cleanup = oldState.account == restoreAccount
            ? try BackupLocalJournal.knownRecordNames(for: localContainer) : []
        try BackupLocalJournal.save(.init(
            account: restoreAccount, generation: headMetadata?.generation,
            legacyUpdatedAt: headMetadata?.generation == nil ? headMetadata?.updatedAt : nil,
            garbageRecords: cleanup.isEmpty ? nil : cleanup
        ), for: localContainer)
        if let pending = pendingBeforeRestore {
            try BackupLocalJournal.finish(pending, for: localContainer)
        }
        HistoryAnalyticsCache.shared.clear()
        let cleanupWarnings = await artifactCleanupQueue.enqueue(Set(AppDataArtifact.allCases))
        await MainActor.run {
            AppRuntimeState.shared.recordSuccessfulCloudBackup(UserDataCloudBackupRemoteSnapshot(
                updatedAt: record.updatedAt,
                contentSummary: payload.contentSummary
            ), sessionRevision: sessionRevision)
        }
        NotificationCenter.default.post(name: .wgjUserDataRestoreDidComplete, object: nil)
        return UserDataCloudBackupRestoreResult(
            restoredAt: record.updatedAt,
            cleanupWarnings: cleanupWarnings
        )
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
        let database = try requireDatabase()
        do {
            let results = try await database.records(for: [recordID], desiredKeys: desiredKeys)
            guard let result = results[recordID] else {
                return nil
            }

            switch result {
            case .success(let record):
                return record
            case .failure(let error as CKError) where error.code == .unknownItem:
                return nil
            case .failure(let error):
                throw error
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
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
