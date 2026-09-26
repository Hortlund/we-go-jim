import CloudKit
import SwiftData
import XCTest
import os
@testable import WGJ

@MainActor
final class IncrementalBackupTests: XCTestCase {
    func testUnboundAutomaticRestoreRejectsBeforeReservingProgressOrWaitingForGate() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let center = CloudBackupProgressCenter()
        let request = BackupLocalJournal.RestoreRequest(account: nil, replacingLocalData: true, previousGeneration: false)
        try BackupLocalJournal.saveRestore(request, for: target)
        let lookupsBefore = await store.accountLookupCount
        await BackupOperationGate.shared.acquire()
        let rejected = expectation(description: "Unbound observer rejects while the operation gate is held")
        let automatic = Task {
            defer { rejected.fulfill() }
            do {
                _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
                    .resumePendingRestore()
                XCTFail("Automatic restore must require an explicitly bound account")
            } catch UserDataCloudRestorePause.accountNotConfirmed { }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await fulfillment(of: [rejected], timeout: 2)
        XCTAssertTrue(center.operations.isEmpty)
        XCTAssertNil(center.presentedOperation)
        await BackupOperationGate.shared.release()
        await automatic.value
        let lookupsAfter = await store.accountLookupCount
        XCTAssertEqual(lookupsAfter, lookupsBefore)
        XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: target)?.ticket, request.ticket)
        let result = try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
            .restoreLatestBackup(replacingLocalData: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        await waitForCleanup()
    }

    func testAutomaticRestoreRetryReusesVisibleErrorUntilSuccessfulCommit() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let center = CloudBackupProgressCenter()
        await store.failNextDownload()
        do {
            _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
                .restoreLatestBackup(replacingLocalData: true)
            XCTFail("Expected download failure")
        } catch ArchiveTestError.publication { }
        let original = try XCTUnwrap(center.presentedOperation)
        XCTAssertFalse(original.isRunning)
        let downloadStarted = expectation(description: "Automatic retry is downloading")
        await store.pauseDownload(started: downloadStarted)
        let retry = Task {
            try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
                .resumePendingRestore()
        }
        await fulfillment(of: [downloadStarted], timeout: 5)
        XCTAssertTrue(center.presentedOperation === original)
        XCTAssertTrue(original.isRunning)
        XCTAssertEqual(original.progress.stage, .downloading)
        XCTAssertEqual(center.operations.count, 1)
        await store.resumeDownload()
        let result = try await retry.value
        XCTAssertNotNil(result)
        guard case .success = original.outcome else { return XCTFail("Retry did not report success") }
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        await waitForCleanup()
    }

    func testExportPreparationReportsActualArchivePartCounts() throws {
        let container = try makeContainer(workouts: 80)
        let updates = OSAllocatedUnfairLock(initialState: [CloudBackupProgressUpdate]())
        let reporter = CloudBackupProgressReporter { update in updates.withLock { $0.append(update) } }
        let plan = try BackupExportPlan.build(container: container, previous: nil, progress: reporter)
        defer { plan.cleanUp() }
        let observed = updates.withLock { $0 }
        XCTAssertEqual(observed.first?.completed, 0)
        XCTAssertEqual(observed.last?.completed, plan.manifest.chunks.count)
        XCTAssertEqual(observed.last?.total, plan.manifest.chunks.count)
        XCTAssertEqual(observed.map(\.completed), (0...plan.manifest.chunks.count).map(Optional.some))
        XCTAssertTrue(observed.allSatisfy { $0.stage == .preparing })
    }

    func testRestoreProgressStaysActiveThroughDownloadAndFinishesAfterCommit() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let center = CloudBackupProgressCenter()
        let downloadStarted = expectation(description: "Download began")
        await store.pauseDownload(started: downloadStarted)
        let restore = Task {
            try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
                .restoreLatestBackup(replacingLocalData: true)
        }
        await fulfillment(of: [downloadStarted], timeout: 5)
        let operation = try XCTUnwrap(center.presentedOperation)
        XCTAssertTrue(operation.isRunning)
        XCTAssertEqual(operation.progress.stage, .downloading)
        XCTAssertTrue(center.hasForegroundOperation)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        let duplicate = try await UserDataCloudBackupService(localContainer: target, backupStore: store, progressCenter: center)
            .resumePendingRestore()
        XCTAssertNil(duplicate)
        XCTAssertEqual(center.operations.count, 1)
        await store.resumeDownload()
        _ = try await restore.value
        XCTAssertFalse(operation.isRunning)
        XCTAssertFalse(center.hasForegroundOperation)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        guard case .success = operation.outcome else { return XCTFail("Restore did not report success") }
        XCTAssertEqual(center.presentedOperation?.id, operation.id)
        await waitForCleanup()
    }

    func testBackupFailureEndsProgressWithoutClaimingSuccess() async throws {
        let center = CloudBackupProgressCenter()
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        await store.failNextPublication()
        do {
            _ = try await UserDataCloudBackupService(localContainer: container, backupStore: store, progressCenter: center)
                .exportCurrentBackup(showsProgress: true)
            XCTFail("Expected publication failure")
        } catch { }
        let operation = try XCTUnwrap(center.presentedOperation)
        XCTAssertFalse(operation.isRunning)
        XCTAssertNil(center.activeOperation)
        guard case .failure = operation.outcome else { return XCTFail("Failure was not presented") }
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        await waitForCleanup()
    }

    func testHistoryAndCatalogMaintenanceDeferDuringPendingRestore() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 1)
        let request = BackupLocalJournal.RestoreRequest(account: "account-a", replacingLocalData: true, previousGeneration: false)
        try BackupLocalJournal.saveRestore(request, for: target)
        let maintenance: [(ModelContext) throws -> Void] = [
            { _ = try ProfileRepository(modelContext: $0).bootstrapProfileIdentitySnapshot(preferredDisplayName: nil) },
            { _ = try ProfileWidgetRepository(modelContext: $0).enabledConfigurationSnapshots() },
            { _ = try HistoryProjectionRepository(modelContext: $0).backfillIfNeeded() },
            { _ = try WorkoutSessionRepository(modelContext: $0).backfillCompletedSessionSummariesIfNeeded() },
            { try ExerciseCatalogRepository(modelContext: $0).ensureSeedImportedIfNeeded() }
        ]
        for operation in maintenance {
            let context = ModelContext(target)
            context.autosaveEnabled = false
            XCTAssertThrowsError(try operation(context)) { XCTAssertTrue($0 is LocalStoreWriteBarrier.RestoreInProgress) }
            context.rollback()
            XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: target)?.ticket, request.ticket)
            XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        }
        _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store).resumePendingRestore()
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
    }

    func testMaintenanceSaveDefersMixedUserEditsUntilExplicitSave() throws {
        let container = try makeContainer(workouts: 0)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let request = BackupLocalJournal.RestoreRequest(account: "account-a", replacingLocalData: true, previousGeneration: false)
        try BackupLocalJournal.saveRestore(request, for: container)
        context.insert(UserProfile(displayName: "Unsaved edit"))
        context.insert(HistoryProjectionCheckpoint(version: 1))
        XCTAssertThrowsError(try context.saveWithRecoveryProtection(purpose: .maintenance))
        XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: container)?.ticket, request.ticket)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<UserProfile>()), 0)
        try context.saveWithRecoveryProtection()
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: container))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Unsaved edit")
    }

    func testNewRestoreSupersedesPausedFileAndClearingCannotResurrectIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("paused.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        let old = BackupLocalJournal.RestoreRequest(account: "account-a", replacingLocalData: true, previousGeneration: false)
        try BackupLocalJournal.saveRestore(old, for: container)
        try LocalStoreWriteBarrier.exclusively { try BackupLocalJournal.pauseRestore(old.ticket, for: container) }
        let pausedURL = try XCTUnwrap(BackupLocalJournal.directory(for: container)).appendingPathComponent("restore-paused.json")
        let pausedBytes = try Data(contentsOf: pausedURL)
        let next = BackupLocalJournal.RestoreRequest(account: "account-a", replacingLocalData: true, previousGeneration: true)
        try BackupLocalJournal.saveRestore(next, for: container)
        // Simulate termination after persisting a new choice but before removing
        // its predecessor. The new explicit choice must always take precedence.
        try pausedBytes.write(to: pausedURL)
        XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: container)?.ticket, next.ticket)
        XCTAssertNotEqual(try BackupLocalJournal.restoreRequest(for: container)?.requiresExplicitRetry, true)
        try LocalStoreWriteBarrier.exclusively { try BackupLocalJournal.pauseRestore(old.ticket, for: container) }
        XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: container)?.ticket, next.ticket)
        try BackupLocalJournal.saveRestore(nil, for: container)
        let reopened = try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: reopened))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pausedURL.path))
    }

    func testCacheMaintenancePreservesPendingRestoreAndItStillResumes() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let context = ModelContext(target)
        let expired = Date.now.addingTimeInterval(-100 * 24 * 60 * 60)
        context.insert(CachedCoachNarrative(weekStart: expired, revisionKey: "old", headline: "Old", body: "Old", updatedAt: expired))
        context.insert(CachedCoachFollowUpNarrative(weekStart: expired, revisionKey: "old", headline: "Old",
            followUpKind: .whatImproved, body: "Old", updatedAt: expired))
        try context.saveWithRecoveryProtection()
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected transport failure") }
        catch ArchiveTestError.publication { }
        let ticket = try XCTUnwrap(BackupLocalJournal.restoreRequest(for: target)).ticket

        try await AppBackgroundStore(container: target).pruneCoachCache()
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<CachedCoachNarrative>()), 0)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<CachedCoachFollowUpNarrative>()), 0)
        let cache = CoachNarrativeCacheRepository(modelContext: ModelContext(target))
        for headline in ["Inserted", "Updated"] {
            try cache.saveRecap(.init(headline: headline, body: "Cache", availabilityMode: .generated),
                weekStart: .distantPast, revisionKey: "current")
            XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: target)?.ticket, ticket)
        }
        _ = try await service.resumePendingRestore()
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
    }

    func testCacheSavesStillCancelRestoreForMixedUserInsertUpdateAndDelete() throws {
        for operation in ["insert", "update", "delete"] {
            let target = try makeContainer(workouts: 0)
            let context = ModelContext(target)
            context.autosaveEnabled = false
            let profile = UserProfile(displayName: "Original")
            context.insert(profile)
            try context.saveWithRecoveryProtection()
            try BackupLocalJournal.saveRestore(.init(account: "account-a", replacingLocalData: true, previousGeneration: false), for: target)
            switch operation {
            case "insert": context.insert(UserProfile(displayName: "New"))
            case "update": profile.displayName = "Edited"
            default: context.delete(profile)
            }
            try CoachNarrativeCacheRepository(modelContext: context).saveRecap(
                .init(headline: "Cache", body: "Cache", availabilityMode: .generated), weekStart: .now, revisionKey: "new")
            XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target), operation)
        }
    }

    func testCloudChunkNetworkFailureKeepsRestoreIntentForRetry() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextCloudChunkRead(.networkFailure)
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected network failure") }
        catch let error as CKError { XCTAssertEqual(error.code, .networkFailure) }
        XCTAssertNotNil(try BackupLocalJournal.restoreRequest(for: target))
        _ = try await service.resumePendingRestore()
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
    }

    func testRestoreEmitsOneCompletionEventEvenWhenCleanupNeedsRetry() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let suite = "RestoreEvent.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let cleanup = AppDataArtifactCleanupQueue(defaultsSuiteName: suite) { _ in throw CancellationError() }
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store, artifactCleanupQueue: cleanup)
        let event = expectation(description: "One reset for the actual commit")
        event.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(forName: .wgjUserDataRestoreDidComplete,
            object: nil, queue: nil) { notification in
                XCTAssertNotNil(notification.userInfo?["cleanupBefore"] as? Date)
                event.fulfill()
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        let result = try await service.restoreLatestBackup(replacingLocalData: true)
        XCTAssertFalse(try XCTUnwrap(result).cleanupWarnings.isEmpty)
        _ = await cleanup.retryPending()
        try BackupLocalJournal.saveRestoreCleanup(.now, for: target)
        _ = try await service.resumePendingRestore()
        await fulfillment(of: [event], timeout: 1)
    }

    func testUnboundRestoreSurvivesReopenButRequiresExplicitAccountChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("intent.store"), cloudKitDatabase: .none)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        }
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        await waitForCleanup()
        do {
            let target = try open()
            await store.failNextAccountLookup()
            do {
                _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store).restoreLatestBackup(replacingLocalData: true)
                XCTFail("Expected account lookup failure")
            } catch ArchiveTestError.publication { }
            let request = try XCTUnwrap(BackupLocalJournal.restoreRequest(for: target))
            XCTAssertNil(request.account)
            XCTAssertFalse(request.pinned)
        }
        let reopened = try open()
        await store.changeAccount()
        let service = UserDataCloudBackupService(localContainer: reopened, backupStore: store)
        let callsBeforeRetry = await store.accountLookupCount
        do { _ = try await service.resumePendingRestore(); XCTFail("Unbound intent must not adopt another account automatically") }
        catch UserDataCloudRestorePause.accountNotConfirmed { }
        let callsAfterRetry = await store.accountLookupCount
        XCTAssertEqual(callsBeforeRetry, callsAfterRetry)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertNotNil(try BackupLocalJournal.restoreRequest(for: reopened))
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        XCTAssertEqual(try BackupLocalJournal.state(for: reopened).account, "account-b")
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: reopened))
    }

    func testAccountChangeWhileExplicitRestoreWaitsForGateCancelsBinding() async throws {
        let target = try makeContainer(workouts: 0)
        let store = MemoryArchiveStore()
        await BackupOperationGate.shared.acquire()
        let task = Task { try await UserDataCloudBackupService(localContainer: target, backupStore: store)
            .restoreLatestBackup(replacingLocalData: true) }
        await assertEventually { (try? BackupLocalJournal.restoreRequest(for: target)) != nil }
        AppRuntimeState.shared.resetCloudBackupSession()
        await store.changeAccount()
        await BackupOperationGate.shared.release()
        do { _ = try await task.value; XCTFail("The account changed after the explicit choice") }
        catch UserDataCloudBackupSafetyError.accountChanged { }
        let calls = await store.accountLookupCount
        XCTAssertEqual(calls, 0)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
    }

    func testUncommittedInterruptedRestoreStillResumesAfterRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("interrupted.store"), cloudKitDatabase: .none)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        }
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        do {
            let target = try open()
            let context = ModelContext(target)
            context.insert(UserProfile(displayName: "Before interruption"))
            try context.saveWithRecoveryProtection()
            let request = BackupLocalJournal.RestoreRequest(account: "account-a", replacingLocalData: true, previousGeneration: false)
            try BackupLocalJournal.saveRestore(request, for: target)
            // Leave the rollback marker just as termination during the transaction
            // would, without running the service's handled-save-failure branch.
            _ = try PersistentRestoreRecovery.prepare(container: target, ticket: request.ticket)
        }
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: [configuration])
        let reopened = try open()
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Before interruption")
        _ = try await UserDataCloudBackupService(localContainer: reopened, backupStore: store).resumePendingRestore()
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: reopened))
    }

    func testPermanentRestoreFormatErrorsClearIntentAndLeaveLocalDataUsable() async throws {
        for failure in RestoreFixtureFailure.allCases {
            let store = MemoryArchiveStore()
            let source = try makeContainer(workouts: 1)
            _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
            let target = try makeContainer(workouts: 2)
            let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
            await store.failNextRestore(failure)
            do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected invalid backup error") }
            catch { XCTAssertTrue(error is DecodingError || error is BackupArchiveError, "Unexpected error: \(error)") }
            XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target), "\(failure)")
            XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
            let resumed = try await service.resumePendingRestore()
            XCTAssertNil(resumed)
            // A format failure must not leave a phantom restore blocking backups.
            let fetched = try await store.fetchManifest()
            let remote = try XCTUnwrap(fetched)
            try BackupLocalJournal.save(.init(account: "account-a", generation: remote.generation, manifest: remote), for: target)
            _ = try await service.exportCurrentBackup()
        }
    }

    func testBoundRestoreRejectsAccountSwitchDuringRetry() async throws {
        let target = try makeContainer(workouts: 0)
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected failure") }
        catch ArchiveTestError.publication { }
        XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: target)?.account, "account-a")
        await store.changeAccount()
        do { _ = try await service.resumePendingRestore(); XCTFail("Must reject a different account") }
        catch UserDataCloudBackupSafetyError.accountChanged { }
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testExplicitPreviousRestoreSupersedesFailedLatestRestore() async throws {
        let source = try makeContainer(workouts: 1)
        let store = MemoryArchiveStore()
        let exporter = UserDataCloudBackupService(localContainer: source, backupStore: store)
        _ = try await exporter.exportCurrentBackup()
        let context = ModelContext(source)
        context.insert(WorkoutSession(name: "New generation", status: .completed, endedAt: .now))
        try context.saveWithRecoveryProtection()
        _ = try await exporter.exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected failure") }
        catch ArchiveTestError.publication { }
        XCTAssertNotNil(try BackupLocalJournal.restoreRequest(for: target))
        _ = try await service.restoreLatestBackup(replacingLocalData: true, previousGeneration: true)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
    }

    func testExplicitDeviceBackupSupersedesDownloadingRestore() async throws {
        let source = try makeContainer(workouts: 1)
        let target = try makeContainer(workouts: 2)
        let store = MemoryArchiveStore()
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        let started = expectation(description: "Restore download suspended")
        await store.pauseDownload(started: started)
        let restore = Task { try await service.restoreLatestBackup(replacingLocalData: true) }
        await fulfillment(of: [started], timeout: 2)
        let export = Task { try await service.exportCurrentBackup(replacingRemote: true) }
        // The export cancels the old intent before waiting for its network request.
        for _ in 0..<1000 {
            if try BackupLocalJournal.restoreRequest(for: target) == nil { break }
            await Task.yield()
        }
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
        await store.resumeDownload()
        do { _ = try await restore.value; XCTFail("Old restore must not commit") }
        catch is CancellationError { }
        _ = try await export.value
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        let remote = try await store.fetchBackupMetadata()
        XCTAssertEqual(remote?.contentSummary?.completedWorkoutCount, 2)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
    }

    func testReplacementRepairsDuplicateHistoryIDsAndReopens() async throws {
        let source = try makeContainer(workouts: 1)
        let sourceContext = ModelContext(source)
        let session = try XCTUnwrap(sourceContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "pull-up",
            exerciseNameSnapshot: "Pull-up", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: session)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 12, isCompleted: true, sessionExercise: exercise)
        let drop = WorkoutSessionDropStage(sessionSetID: set.id, actualReps: 5, isCompleted: true, sessionSet: set)
        let group = WorkoutSessionSupersetGroup(sessionID: session.id, roundRestSeconds: 90, session: session)
        let cardio = WorkoutSessionCardioBlock(sessionID: session.id, phase: .preWorkout,
            catalogExerciseUUID: "run", exerciseNameSnapshot: "Run", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs", targetDurationSeconds: 60, actualDurationSeconds: 60,
            isCompleted: true, session: session)
        sourceContext.insert(exercise); sourceContext.insert(set); sourceContext.insert(drop)
        sourceContext.insert(group); sourceContext.insert(cardio)
        try sourceContext.saveWithRecoveryProtection()
        let store = MemoryArchiveStore()
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("duplicates.store"), cloudKitDatabase: .none)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        }
        // Exercise each duplicated identity independently, including cascading parents.
        for duplicateKind in 0..<6 {
            let target = try open()
            let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
            _ = try await service.restoreLatestBackup(replacingLocalData: true)
            let context = ModelContext(target)
            switch duplicateKind {
            case 0: context.insert(WorkoutSession(id: session.id, name: "Duplicate", status: .completed, endedAt: .now))
            case 1: context.insert(WorkoutSessionExercise(id: exercise.id, sessionID: session.id,
                catalogExerciseUUID: "pull-up", exerciseNameSnapshot: "Duplicate", categorySnapshot: "Back", muscleSummarySnapshot: "Back"))
            case 2: context.insert(WorkoutSessionSet(id: set.id, sessionExerciseID: exercise.id, actualReps: 1, isCompleted: true))
            case 3: context.insert(WorkoutSessionDropStage(id: drop.id, sessionSetID: set.id, actualReps: 1, isCompleted: true))
            case 4: context.insert(WorkoutSessionSupersetGroup(id: group.id, sessionID: session.id, roundRestSeconds: 0))
            default: context.insert(WorkoutSessionCardioBlock(id: cardio.id, sessionID: session.id, phase: .preWorkout,
                catalogExerciseUUID: "run", exerciseNameSnapshot: "Duplicate", categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs", targetDurationSeconds: 1))
            }
            try context.saveWithRecoveryProtection()
            switch duplicateKind {
            case 0: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
            case 1: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSessionExercise>()), 2)
            case 2: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSessionSet>()), 2)
            case 3: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSessionDropStage>()), 2)
            case 4: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSessionSupersetGroup>()), 2)
            default: XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSessionCardioBlock>()), 2)
            }
            _ = try await service.restoreLatestBackup(replacingLocalData: true)
            XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
        }
        let reopened = try open()
        let read = ModelContext(reopened)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSessionExercise>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSessionSet>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSessionDropStage>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSessionSupersetGroup>()), 1)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSessionCardioBlock>()), 1)
        XCTAssertEqual(try read.fetch(FetchDescriptor<WorkoutSessionCardioBlock>()).first?.actualDurationSeconds, 60)
        let restoredSet = try XCTUnwrap(read.fetch(FetchDescriptor<WorkoutSessionSet>()).first)
        XCTAssertEqual(restoredSet.actualReps, 12)
        XCTAssertEqual(restoredSet.sessionExercise?.session?.id, session.id)
        XCTAssertEqual(try read.fetch(FetchDescriptor<WorkoutSessionDropStage>()).first?.sessionSet?.id, set.id)
    }

    func testPackedHistoryBoundsUploadsAndIncludesEditsBelowMaximumTimestamp() throws {
        let container = try makeContainer(workouts: 2500)
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let batches = try BackupHistoryBatch.make(sessions)
        XCTAssertTrue(batches.allSatisfy { $0.entries.count <= 64 })
        XCTAssertLessThan(batches.count, 80)
        XCTAssertEqual(Set(batches.flatMap { $0.entries.map(\.id) }), Set(sessions.map(\.id)))
        let first = try BackupExportPlan.build(container: container, previous: nil)
        defer { first.cleanUp() }
        context.insert(WorkoutSession(name: "Added", status: .completed, endedAt: .now))
        try context.saveWithRecoveryProtection()
        let added = try BackupExportPlan.build(container: container, previous: first.manifest)
        defer { added.cleanUp() }
        XCTAssertLessThanOrEqual(added.chunkFiles.count, 2)
        let group = try XCTUnwrap(batches.first { $0.entries.count > 2 })
        let a = try XCTUnwrap(sessions.first { $0.id == group.entries[0].id })
        let b = try XCTUnwrap(sessions.first { $0.id == group.entries[1].id })
        a.updatedAt = .distantFuture
        try context.saveWithRecoveryProtection()
        let future = try BackupExportPlan.build(container: container, previous: added.manifest)
        defer { future.cleanUp() }
        b.name = "Changed below the maximum date"
        b.updatedAt = .now
        try context.saveWithRecoveryProtection()
        let changed = try BackupExportPlan.build(container: container, previous: future.manifest)
        defer { changed.cleanUp() }
        XCTAssertEqual(changed.chunkFiles.count, 1)
        context.delete(b)
        try context.saveWithRecoveryProtection()
        let deleted = try BackupExportPlan.build(container: container, previous: changed.manifest)
        defer { deleted.cleanUp() }
        XCTAssertEqual(deleted.manifest.summary.completedWorkoutCount, 2500)
        XCTAssertFalse(deleted.chunkFiles.isEmpty)
    }

    func testPendingRestoreRetriesTransportFailureAndStopsAfterNewLocalSave() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected transport failure") }
        catch ArchiveTestError.publication { }
        XCTAssertNotNil(try BackupLocalJournal.restoreRequest(for: target))
        _ = try await service.resumePendingRestore()
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected transport failure") }
        catch ArchiveTestError.publication { }
        let context = ModelContext(target)
        context.insert(UserProfile(displayName: "New local edit"))
        try context.saveWithRecoveryProtection()
        let result = try await service.resumePendingRestore()
        XCTAssertNil(result)
        XCTAssertEqual(try ModelContext(target).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "New local edit")
    }

    func testFailedPersistentRestoreRollsBackAndWaitsForExplicitRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("restore.store")
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self, configurations: configuration)
        }
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        do {
            let container = try open()
            let context = ModelContext(container)
            context.insert(UserProfile(displayName: "Original"))
            try context.saveWithRecoveryProtection()
            let requestURL = try XCTUnwrap(BackupLocalJournal.directory(for: container)).appendingPathComponent("restore.json")
            var originalRequestBytes: Data?
            var originalFileNumber: NSNumber?
            let transaction = UserDataCloudRestoreTransaction(container: container, dependencies: .init(save: {
                originalRequestBytes = try Data(contentsOf: requestURL)
                originalFileNumber = try FileManager.default.attributesOfItem(atPath: requestURL.path)[.systemFileNumber] as? NSNumber
                try $0.save()
                throw ArchiveTestError.publication // Simulate failure after SQLite commits, before the receipt.
            }))
            do {
                _ = try await UserDataCloudBackupService(localContainer: container, backupStore: store,
                    restoreTransaction: transaction).restoreLatestBackup(replacingLocalData: true)
                XCTFail("Expected interrupted transaction")
            } catch is PersistentRestoreRecovery.RecoveryRequired { }
            XCTAssertEqual(try BackupLocalJournal.restoreRequest(for: container)?.requiresExplicitRetry, true)
            // The pause reuses the same file/inode and bytes; it requires no JSON
            // rewrite or new data allocation when the transaction ran out of space.
            let pausedURL = requestURL.deletingLastPathComponent().appendingPathComponent("restore-paused.json")
            XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL.path))
            XCTAssertEqual(try Data(contentsOf: pausedURL), originalRequestBytes)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: pausedURL.path)[.systemFileNumber] as? NSNumber,
                try XCTUnwrap(originalFileNumber))
        }
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: [configuration])
        let reopened = try open()
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Original")
        let service = UserDataCloudBackupService(localContainer: reopened, backupStore: store)
        for _ in 0..<2 {
            do { _ = try await service.resumePendingRestore(); XCTFail("Known save failure must not loop automatically") }
            catch UserDataCloudRestorePause.localSaveFailed { }
        }
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Original")
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: reopened))
        XCTAssertNil(try PersistentRestoreRecovery.committedTicket(container: reopened))
        AppRuntimeState.shared.requiresStorageRecovery = false
    }

    func testReplacementReusesHistoryAndRelinksChildrenFromRemovedParents() async throws {
        let source = try makeContainer(workouts: 0)
        let sourceContext = ModelContext(source)
        let session = WorkoutSession(name: "Keep", status: .completed, endedAt: .now)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "pull-up",
            exerciseNameSnapshot: "Pull-up", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: session)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 12, isCompleted: true, sessionExercise: exercise)
        sourceContext.insert(session); sourceContext.insert(exercise); sourceContext.insert(set)
        try sourceContext.saveWithRecoveryProtection()
        let store = MemoryArchiveStore()
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let context = ModelContext(target)
        let oldParent = WorkoutSession(name: "Remove", status: .completed, endedAt: .now)
        let kept = WorkoutSession(id: session.id, name: "Old", status: .completed, endedAt: .now)
        let oldExercise = WorkoutSessionExercise(id: exercise.id, sessionID: oldParent.id, catalogExerciseUUID: "pull-up",
            exerciseNameSnapshot: "Old name", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: oldParent)
        let oldSet = WorkoutSessionSet(id: set.id, sessionExerciseID: oldExercise.id, actualReps: 3, isCompleted: true, sessionExercise: oldExercise)
        context.insert(oldParent); context.insert(kept); context.insert(oldExercise); context.insert(oldSet)
        try context.saveWithRecoveryProtection()
        _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store).restoreLatestBackup(replacingLocalData: true)
        let read = ModelContext(target)
        XCTAssertEqual(try read.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        let restoredExercise = try XCTUnwrap(read.fetch(FetchDescriptor<WorkoutSessionExercise>()).first)
        XCTAssertEqual(restoredExercise.session?.id, session.id)
        let restoredSet = try XCTUnwrap(read.fetch(FetchDescriptor<WorkoutSessionSet>()).first)
        XCTAssertEqual(restoredSet.id, set.id)
        XCTAssertEqual(restoredSet.actualReps, 12)
        XCTAssertEqual(restoredSet.sessionExercise?.id, exercise.id)
        XCTAssertEqual(try read.fetch(FetchDescriptor<CompletedSetFact>()).first?.reps, 12)
    }

    func testPendingRestoreRejectsChangedCloudHead() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 2)
        let export = UserDataCloudBackupService(localContainer: source, backupStore: store)
        _ = try await export.exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let service = UserDataCloudBackupService(localContainer: target, backupStore: store)
        await store.failNextDownload()
        do { _ = try await service.restoreLatestBackup(replacingLocalData: true); XCTFail("Expected transport failure") }
        catch ArchiveTestError.publication { }
        let context = ModelContext(source)
        context.insert(UserProfile(displayName: "New cloud version"))
        try context.saveWithRecoveryProtection()
        _ = try await export.exportCurrentBackup()
        do { _ = try await service.resumePendingRestore(); XCTFail("Must not restore another version silently") }
        catch UserDataCloudBackupSafetyError.remoteChanged { }
        XCTAssertNil(try BackupLocalJournal.restoreRequest(for: target))
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testPerWorkoutArchiveMigratesToPackedHistoryAndBothGenerationsRestore() async throws {
        let source = try makeContainer(workouts: 130)
        let context = ModelContext(source)
        let directory = try BackupTemporaryFiles.makeArchiveDirectory()
        defer { BackupTemporaryFiles.remove(directory) }
        var references: [BackupChunkReference] = []
        var files: [String: URL] = [:]
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        for id in [nil] + sessions.map({ Optional($0.id) }) {
            let (data, summary) = try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: id)
            let reference = BackupChunkReference(key: id?.uuidString ?? "shared", digest: BackupArchiveCodec.digest(data),
                sourceUpdatedAt: .now, summary: summary)
            let url = directory.appendingPathComponent(reference.recordName)
            try BackupArchiveCodec.encode(data).write(to: url)
            references.append(reference)
            files[reference.recordName] = url
        }
        let old = BackupManifest(generation: UUID().uuidString, updatedAt: .now, chunks: references,
            previousGenerations: [], summary: try UserDataCloudBackupContentSummary.loadLocal(context: context))
        let store = MemoryArchiveStore()
        try await store.saveArchive(old, chunkFiles: files, expectedGeneration: nil, expectedAccount: "account-a")
        try BackupLocalJournal.save(.init(account: "account-a", generation: old.generation, manifest: old), for: source)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let current = try await store.fetchManifest()
        XCTAssertLessThan(try XCTUnwrap(current).chunks.count, 10)
        for previous in [false, true] {
            let target = try makeContainer(workouts: 0)
            _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store)
                .restoreLatestBackup(replacingLocalData: true, previousGeneration: previous)
            XCTAssertEqual(Set(try ModelContext(target).fetch(FetchDescriptor<WorkoutSession>()).map(\.id)), Set(sessions.map(\.id)))
        }
    }

    func testChunkEncodingPreservesExistingBytesAndDigest() throws {
        let container = try makeContainer(workouts: 2)
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Åsa / 🏋️ \"training\"")
        profile.avatarImageData = Data([0, 127, 255])
        profile.bodyWeightKilograms = 72.125
        context.insert(profile)
        for name in ["z-custom", "a-custom"] {
            context.insert(ExerciseCatalogItem(remoteUUID: name, displayName: name, sourceName: "custom"))
        }
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "pull-up",
            exerciseNameSnapshot: "Pull-Up", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: session)
        context.insert(exercise)
        for weight: Double? in [nil, 0, 1.23456789, 100] {
            context.insert(WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 8,
                actualWeight: weight, isCompleted: true, sessionExercise: exercise))
        }
        try context.saveWithRecoveryProtection()
        for sessionID: UUID? in [nil, session.id] {
            var payload = try UserDataCloudBackupPayload(context: context, sessionID: sessionID,
                includeShared: sessionID == nil, includeHistory: sessionID != nil, includeTemplates: false)
            payload.generatedAt = .distantPast
            // Reproduce the shipped encoder, including its redundant first key sort.
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupArchiveCodec.json(payload)) as? [String: Any])
            for (key, value) in legacy {
                if let rows = value as? [[String: Any]] {
                    legacy[key] = rows.sorted {
                        String(describing: $0["id"] ?? $0["remoteUUID"] ?? "") < String(describing: $1["id"] ?? $1["remoteUUID"] ?? "")
                    }
                }
            }
            let expected = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            let (actual, summary) = try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: sessionID)
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(BackupArchiveCodec.digest(actual), BackupArchiveCodec.digest(expected))
            XCTAssertEqual(summary, payload.contentSummary)
        }
    }

    func testRetentionBatchesManifestReadsAndPreservesEveryRetainedChunk() async throws {
        let container = try makeContainer(workouts: 2)
        let plan = try BackupExportPlan.build(container: container, previous: nil)
        defer { plan.cleanUp() }
        let oldest = plan.manifest
        var previous = oldest
        previous.generation = UUID().uuidString
        previous.chunks[0].storageID = UUID().uuidString
        var current = previous
        current.generation = UUID().uuidString
        current.previousGenerations = [previous.generation, oldest.generation]
        var retired = oldest
        retired.generation = UUID().uuidString
        retired.chunks[0].storageID = UUID().uuidString
        let all = [oldest, previous, retired]
        let byName = Dictionary(uniqueKeysWithValues: all.map { ("backup-generation-v3-\($0.generation)", $0) })
        let retiredName = "backup-generation-v3-\(retired.generation)"
        let protected = Set([oldest, previous, current].flatMap { $0.chunks.map(\.recordName) })
        let garbage = protected.union([retiredName, "abandoned-chunk"])
        var reads: [Set<String>] = []
        var deletions: [Set<String>] = []
        try await BackupRetentionCleanup.remove(garbage, retaining: current,
            loadManifests: { names in reads.append(names); return byName },
            delete: { deletions.append($0) })
        XCTAssertEqual(reads, [Set(byName.keys)])
        XCTAssertEqual(deletions, [[retired.chunks[0].recordName, "abandoned-chunk"], [retiredName]])
        XCTAssertTrue(deletions.allSatisfy { $0.isDisjoint(with: protected) })

        // A partial read must not permit even the first deletion phase.
        deletions = []
        do {
            try await BackupRetentionCleanup.remove(garbage, retaining: current,
                loadManifests: { _ in [retiredName: retired] }, delete: { deletions.append($0) })
            XCTFail("Missing retained manifest must stop cleanup")
        } catch BackupArchiveError.missingChunk { }
        XCTAssertTrue(deletions.isEmpty)
    }

    func testRetentionRetryCanRediscoverChunksAfterPartialDeletion() async throws {
        let plan = try BackupExportPlan.build(container: makeContainer(workouts: 1), previous: nil)
        defer { plan.cleanUp() }
        let current = plan.manifest
        var retired = current
        retired.generation = UUID().uuidString
        retired.chunks[0].storageID = UUID().uuidString
        let name = "backup-generation-v3-\(retired.generation)"
        var deleted: [Set<String>] = []
        do {
            try await BackupRetentionCleanup.remove([name], retaining: current,
                loadManifests: { _ in [name: retired] }, delete: { names in
                    deleted.append(names)
                    throw ArchiveTestError.publication
                })
            XCTFail("Expected partial delete failure")
        } catch ArchiveTestError.publication { }
        XCTAssertEqual(deleted, [[retired.chunks[0].recordName]])
        deleted = []
        try await BackupRetentionCleanup.remove([name], retaining: current,
            loadManifests: { _ in [name: retired] }, delete: { deleted.append($0) })
        XCTAssertEqual(deleted, [[retired.chunks[0].recordName], [name]])
    }

    func testLargeRetentionBacklogBoundsReadsAndProtectsLateRetainedVersions() async throws {
        let plan = try BackupExportPlan.build(container: makeContainer(workouts: 1), previous: nil)
        defer { plan.cleanUp() }
        var current = plan.manifest
        // Put retained generations last so retired chunks are seen before their
        // protection is known. Every manifest represents a substantial history.
        current.previousGenerations = ["FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"]
        for _ in 0..<1_000 {
            var chunk = current.chunks[1]
            chunk.key = UUID().uuidString
            chunk.storageID = UUID().uuidString
            current.chunks.append(chunk)
        }
        let retired = Set((0..<129).map { String(format: "backup-generation-v3-00000000-0000-0000-0000-%012d", $0) })
        let retained = Set(current.previousGenerations.map { "backup-generation-v3-\($0)" })
        let uniqueChunks = Dictionary(uniqueKeysWithValues: retired.union(retained).map { ($0, UUID().uuidString) })
        let protected = Set(current.chunks.map(\.recordName))
            .union(retained.map { "backup-chunk-v3-\(uniqueChunks[$0]!)" })
        let expectedDeletedChunks = Set(retired.map { "backup-chunk-v3-\(uniqueChunks[$0]!)" })
        var requests: [Set<String>] = []
        var deletions: [Set<String>] = []
        // Reuse the fixture to check success, a late missing recovery manifest,
        // and a failure after one batch. Neither failed read may delete anything.
        for scenario in 0..<3 {
            requests = []
            deletions = []
            do {
                try await BackupRetentionCleanup.remove(retired.union(protected), retaining: current,
                    loadManifests: { names in
                        XCTAssertLessThanOrEqual(names.count, BackupManifestBatches.limit)
                        requests.append(names)
                        if scenario == 2 && requests.count == 2 { throw ArchiveTestError.publication }
                        var batch: [String: BackupManifest] = [:]
                        for name in names {
                            if scenario == 1 && retained.contains(name) { continue }
                            var manifest = current
                            manifest.generation = String(name.dropFirst("backup-generation-v3-".count))
                            manifest.previousGenerations = []
                            manifest.chunks[0].storageID = uniqueChunks[name]!
                            batch[name] = manifest
                        }
                        return batch
                    }, delete: { deletions.append($0) })
                XCTAssertEqual(scenario, 0, "An incomplete read must stop cleanup")
                XCTAssertEqual(requests.count, 33)
                XCTAssertEqual(requests.reduce(into: Set<String>()) { $0.formUnion($1) }, retired.union(retained))
                XCTAssertEqual(deletions, [expectedDeletedChunks, retired])
            } catch BackupArchiveError.missingChunk {
                XCTAssertEqual(scenario, 1)
            } catch ArchiveTestError.publication {
                XCTAssertEqual(scenario, 2)
            }
            if scenario != 0 { XCTAssertTrue(deletions.isEmpty) }
            XCTAssertTrue(deletions.allSatisfy { $0.isDisjoint(with: protected) })
        }
    }

    func testCorruptOrMissingChunkNeverReplacesLocalData() async throws {
        for missing in [false, true] {
            let store = MemoryArchiveStore()
            let source = try makeContainer(workouts: 3)
            _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
            await store.damageCurrentChunk(removing: missing)
            let target = try makeContainer(workouts: 1)
            let before = try UserDataCloudBackupPayload(context: ModelContext(target))
            do {
                _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store)
                    .restoreLatestBackup(replacingLocalData: true)
                XCTFail("Invalid backup must never replace local data")
            } catch is BackupArchiveError { }
            let after = try UserDataCloudBackupPayload(context: ModelContext(target))
            XCTAssertEqual(try UserDataBackupPayloadCodec.canonicalData(BackupArchiveCodec.json(before)),
                           try UserDataBackupPayloadCodec.canonicalData(BackupArchiveCodec.json(after)))
        }
    }

    func testExplicitReplacementRecreatesBackupDeletedByAnotherDevice() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let old = try XCTUnwrap(BackupLocalJournal.state(for: container).manifest)
        try await store.deleteBackup() // A different device leaves this installation's journal intact.
        do { _ = try await service.exportCurrentBackup(); XCTFail("Automatic recreation must remain blocked") }
        catch UserDataCloudBackupSafetyError.remoteChanged { }
        _ = try await service.exportCurrentBackup(replacingRemote: true)
        let recreated = try XCTUnwrap(BackupLocalJournal.state(for: container).manifest)
        XCTAssertTrue(recreated.previousGenerations.isEmpty)
        XCTAssertTrue(Set(old.chunks.map(\.storageID)).isDisjoint(with: recreated.chunks.map(\.storageID)))
        let backup = try await store.fetchBackup()
        XCTAssertEqual(backup?.contentSummary?.completedWorkoutCount, 2)
    }

    func testRestorePreservesFailedUploadAndRetiredRecordCleanup() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Unpublished edit"))
        try context.save()
        await store.failNextPublication()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected publication failure") }
        catch ArchiveTestError.publication { }
        var state = try BackupLocalJournal.state(for: container)
        let abandoned = try XCTUnwrap(state.attemptedManifest)
        let committed = try XCTUnwrap(state.manifest)
        let abandonedChunks = Set(abandoned.chunks.map(\.recordName)).subtracting(committed.chunks.map(\.recordName))
        XCTAssertFalse(abandonedChunks.isEmpty)
        let orphan = "backup-chunk-v3-\(UUID())"
        state.garbageRecords = [orphan]
        try BackupLocalJournal.save(state, for: container)
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        let restored = try BackupLocalJournal.state(for: container)
        XCTAssertNil(restored.attemptedManifest)
        XCTAssertTrue(restored.garbageRecords?.contains(orphan) == true)
        XCTAssertTrue(restored.garbageRecords?.contains("backup-generation-v3-\(abandoned.generation)") == true)
        XCTAssertTrue(Set(abandoned.chunks.map(\.recordName)).isSubset(of: restored.garbageRecords ?? []))
        _ = try await service.exportCurrentBackup()
        await waitForCleanup()
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
        let remaining = await store.storedChunkNames()
        XCTAssertTrue(remaining.isDisjoint(with: abandonedChunks))
        let backup = try await store.fetchBackup()
        XCTAssertEqual(backup?.contentSummary?.completedWorkoutCount, 2)
    }

    func testRestoreDoesNotCarryCleanupIntoAnotherAccount() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        var state = try BackupLocalJournal.state(for: container)
        state.garbageRecords = ["backup-chunk-v3-\(UUID())"]
        try BackupLocalJournal.save(state, for: container)
        await store.changeAccount()
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        let restored = try BackupLocalJournal.state(for: container)
        XCTAssertEqual(restored.account, "account-b")
        XCTAssertNil(restored.garbageRecords)
    }

    func testMissingRetainedManifestKeepsCleanupQueuedUntilRetry() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Second generation"))
        try context.save()
        _ = try await service.exportCurrentBackup()
        let removed = try await store.removePreviousManifest()
        var state = try BackupLocalJournal.state(for: container)
        let garbage: Set<String> = ["backup-chunk-v3-\(UUID())"]
        state.garbageRecords = garbage
        try BackupLocalJournal.save(state, for: container)
        _ = try await service.exportCurrentBackup()
        await waitForCleanup()
        XCTAssertEqual(try BackupLocalJournal.state(for: container).garbageRecords, garbage)
        await store.restoreManifest(removed)
        _ = try await service.exportCurrentBackup()
        await waitForCleanup()
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
        let previous = try await store.fetchPreviousBackup()
        XCTAssertNotNil(previous)
    }

    func testOlderNonemptyDeviceCannotReplaceNewGeneration() async throws {
        let store = MemoryArchiveStore()
        let owner = try makeContainer(workouts: 10)
        _ = try await UserDataCloudBackupService(localContainer: owner, backupStore: store).exportCurrentBackup()
        let before = try await store.fetchManifest()
        let stale = try makeContainer(workouts: 1)
        do {
            _ = try await UserDataCloudBackupService(localContainer: stale, backupStore: store).exportCurrentBackup()
            XCTFail("Stale device replaced another lineage")
        } catch UserDataCloudBackupSafetyError.unrelatedDevice { }
        let after = try await store.fetchManifest()
        XCTAssertEqual(after, before)
    }

    func testFailedPublicationKeepsPreviousBackupAndRetryReusesUnchangedWorkouts() async throws {
        let store = MemoryArchiveStore()
        let owner = try makeContainer(workouts: 12)
        let service = UserDataCloudBackupService(localContainer: owner, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let before = try await store.fetchManifest()
        let context = ModelContext(owner)
        context.insert(UserProfile(displayName: "New name"))
        try context.save()
        await store.failNextPublication()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected failure") }
        catch ArchiveTestError.publication { }
        let unchanged = try await store.fetchManifest()
        XCTAssertEqual(unchanged, before)
        _ = try await service.exportCurrentBackup()
        let count = await store.lastUploadedChunkCount
        XCTAssertEqual(count, 1)
        let record = try await store.fetchBackup()
        XCTAssertEqual(record?.contentSummary?.completedWorkoutCount, 12)
    }

    func testRestoredDeviceCanContinueLineageAndRoundTripAllChunks() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 3)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let targetService = UserDataCloudBackupService(localContainer: target, backupStore: store)
        let result = try await targetService.restoreLatestBackup()
        XCTAssertNotNil(result)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 3)
        _ = try await targetService.exportCurrentBackup()
        let uploaded = await store.lastUploadedChunkCount
        // Restore recalculates derived summaries, so changed summaries may re-upload once.
        XCTAssertLessThanOrEqual(uploaded, 4)
        let beforeNoOp = try await store.fetchManifest()
        let publications = await store.publicationCount
        _ = try await targetService.exportCurrentBackup()
        let afterNoOp = try await store.fetchManifest()
        let afterPublications = await store.publicationCount
        XCTAssertEqual(beforeNoOp, afterNoOp)
        XCTAssertEqual(publications, afterPublications)
    }

    func testAccountSwitchDoesNotSendExistingLocalHistoryToNewAccount() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: source, backupStore: store)
        _ = try await service.exportCurrentBackup()
        await store.changeAccount()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected account protection") }
        catch UserDataCloudBackupSafetyError.accountChanged { }
    }

    func testExplicitReplacementKeepsPreviousGenerationRestorable() async throws {
        let store = MemoryArchiveStore()
        let first = try makeContainer(workouts: 3)
        _ = try await UserDataCloudBackupService(localContainer: first, backupStore: store).exportCurrentBackup()
        let second = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: second, backupStore: store)
        _ = try await service.exportCurrentBackup(replacingRemote: true)
        let result = try await service.restoreLatestBackup(replacingLocalData: true, previousGeneration: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(try ModelContext(second).fetchCount(FetchDescriptor<WorkoutSession>()), 3)
    }

    func testPublicationAcknowledgmentCanRecoverAfterProcessExit() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let remote = try await store.fetchManifest()
        let manifest = try XCTUnwrap(remote)
        try BackupLocalJournal.save(.init(account: "account-a", attemptedManifest: manifest), for: container)
        _ = try await service.exportCurrentBackup()
        XCTAssertEqual(try BackupLocalJournal.state(for: container).generation, manifest.generation)
        XCTAssertNil(try BackupLocalJournal.state(for: container).attemptedManifest)
        let publications = await store.publicationCount
        XCTAssertEqual(publications, 1)
    }

    func testFailedRetentionCleanupRetriesWithoutPublishingAnotherGeneration() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Profile")
        context.insert(profile)
        try context.save()
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        for index in 0..<4 {
            profile.displayName = "Profile \(index)"
            try context.save()
            if index == 3 { await store.failNextCleanup() }
            _ = try await service.exportCurrentBackup()
        }
        await waitForCleanup()
        XCTAssertFalse(try BackupLocalJournal.state(for: container).garbageRecords?.isEmpty ?? true)
        let previousCount = await store.publicationCount
        _ = try await service.exportCurrentBackup()
        let count = await store.publicationCount
        XCTAssertEqual(count, previousCount)
        await waitForCleanup()
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
    }

    func testCloudDeletionClearsLocalLineageAndPendingBackupTicket() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        try BackupLocalJournal.markPending(for: container)
        XCTAssertFalse(try BackupLocalJournal.knownRecordNames(for: container).isEmpty)
        try await service.deleteRemoteBackup()
        XCTAssertNil(try BackupLocalJournal.pending(for: container))
        XCTAssertNil(try BackupLocalJournal.state(for: container).generation)
        XCTAssertTrue(try BackupLocalJournal.knownRecordNames(for: container).isEmpty)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        _ = try await service.exportCurrentBackup()
        let recreated = try await store.fetchManifest()
        XCTAssertEqual(recreated?.summary.completedWorkoutCount, 2)
    }

    func testBackupAcknowledgesBeforeCleanupAndSerializesRestore() async throws {
        for changed in [false, true] {
            let store = MemoryArchiveStore()
            let container = try makeContainer(workouts: 1)
            let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
            _ = try await service.exportCurrentBackup()
            await waitForCleanup()
            var state = try BackupLocalJournal.state(for: container)
            let garbage: Set<String> = ["abandoned-chunk"]
            state.garbageRecords = garbage
            try BackupLocalJournal.save(state, for: container)
            if changed {
                let context = ModelContext(container)
                context.insert(UserProfile(displayName: "Changed"))
                try context.saveWithRecoveryProtection()
            }
            try BackupLocalJournal.markPending(for: container)
            let cleanupStarted = expectation(description: "Cleanup started")
            let exported = expectation(description: "Export returns while cleanup is suspended")
            await store.pauseCleanup(started: cleanupStarted)
            let export = Task {
                defer { exported.fulfill() }
                return try await service.exportCurrentBackup()
            }
            await fulfillment(of: [cleanupStarted, exported], timeout: 5)
            let acknowledged = try BackupLocalJournal.state(for: container)
            let remote = try await store.fetchManifest()
            XCTAssertEqual(acknowledged.generation, remote?.generation)
            XCTAssertNil(acknowledged.attemptedManifest)
            XCTAssertNil(try BackupLocalJournal.pending(for: container))
            XCTAssertEqual(acknowledged.garbageRecords, garbage)
            // A new edit must stay pending even when older cleanup finishes.
            try BackupLocalJournal.markPending(for: container)
            let nextTicket = try BackupLocalJournal.pending(for: container)
            let restored = expectation(description: "Restore waits for cleanup")
            restored.isInverted = true
            let restore = Task {
                defer { restored.fulfill() }
                return try await service.restoreLatestBackup(replacingLocalData: true)
            }
            await fulfillment(of: [restored], timeout: 0.1)
            XCTAssertEqual(try BackupLocalJournal.pending(for: container), nextTicket)
            await store.resumeCleanup()
            _ = try await export.value
            _ = try await restore.value
            await waitForCleanup()
            XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        }
    }

    func testCleanupAcknowledgmentPreservesNewWorkAndDoesNotResurrectResetLineage() throws {
        let container = try makeContainer(workouts: 0)
        var state = BackupLocalJournal.State(account: "account-a", generation: "generation-a",
            garbageRecords: ["old", "new"])
        try BackupLocalJournal.save(state, for: container)
        try BackupLocalJournal.markPending(for: container)
        let ticket = try BackupLocalJournal.pending(for: container)
        try BackupLocalJournal.finishCleanup(["old"], account: "account-a", generation: "generation-a", for: container)
        XCTAssertEqual(try BackupLocalJournal.state(for: container).garbageRecords, ["new"])
        XCTAssertEqual(try BackupLocalJournal.pending(for: container), ticket)
        for replacement in [
            BackupLocalJournal.State(),
            BackupLocalJournal.State(account: "account-b", generation: "generation-a", garbageRecords: ["old"]),
            BackupLocalJournal.State(account: "account-a", generation: "generation-b", garbageRecords: ["old"])
        ] {
            state = replacement
            try BackupLocalJournal.save(state, for: container)
            try BackupLocalJournal.finishCleanup(["old"], account: "account-a", generation: "generation-a", for: container)
            let result = try BackupLocalJournal.state(for: container)
            XCTAssertEqual(result.account, state.account)
            XCTAssertEqual(result.generation, state.generation)
            XCTAssertEqual(result.garbageRecords, state.garbageRecords)
        }
    }

    private func waitForCleanup() async {
        await BackupOperationGate.shared.acquire()
        await BackupOperationGate.shared.release()
    }

    private func makeContainer(workouts: Int) throws -> ModelContainer {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        for index in 0..<workouts { context.insert(WorkoutSession(name: "Workout \(index)", status: .completed, endedAt: .now)) }
        try context.save()
        return container
    }
}

private enum ArchiveTestError: Error { case publication }
private enum RestoreFixtureFailure: CaseIterable { case metadata, payload, compressed, chunk, missingCloudChunk, missingCloudBatch }


private actor MemoryArchiveStore: IncrementalBackupStoring {
    private var current: BackupManifest?
    private var generations: [String: BackupManifest] = [:]
    private var failCleanup = false
    private var cleanupStarted: XCTestExpectation?
    private var cleanupContinuation: CheckedContinuation<Void, Never>?
    func pauseCleanup(started: XCTestExpectation) { cleanupStarted = started }
    func resumeCleanup() {
        cleanupStarted = nil
        cleanupContinuation?.resume()
        cleanupContinuation = nil
    }
    private var chunks: [String: Data] = [:]
    private var restoreFailure: RestoreFixtureFailure?
    func failNextRestore(_ failure: RestoreFixtureFailure) { restoreFailure = failure }
    private var cloudChunkError: CKError.Code?
    func failNextCloudChunkRead(_ error: CKError.Code) { cloudChunkError = error }
    private(set) var accountLookupCount = 0
    private var failAccountLookup = false
    func failNextAccountLookup() { failAccountLookup = true }
    private var downloadStarted: XCTestExpectation?
    private var downloadContinuation: CheckedContinuation<Void, Never>?
    func pauseDownload(started: XCTestExpectation) { downloadStarted = started }
    func resumeDownload() {
        downloadStarted = nil
        downloadContinuation?.resume()
        downloadContinuation = nil
    }
    private var failDownload = false
    func failNextDownload() { failDownload = true }
    private var failPublication = false
    private var account = "account-a"
    private(set) var lastUploadedChunkCount = 0
    private(set) var publicationCount = 0

    func accountIdentifier() async throws -> String {
        accountLookupCount += 1
        if failAccountLookup { failAccountLookup = false; throw ArchiveTestError.publication }
        return account
    }
    func changeAccount() { account = "account-b" }
    func failNextCleanup() { failCleanup = true }
    func removeOrphanedRecords(_ names: Set<String>, retaining: BackupManifest) async throws {
        if let cleanupStarted {
            await withCheckedContinuation { continuation in
                cleanupContinuation = continuation
                cleanupStarted.fulfill()
            }
        }
        if failCleanup { failCleanup = false; throw ArchiveTestError.publication }
        try await BackupRetentionCleanup.remove(names, retaining: retaining,
            loadManifests: { names in
                names.reduce(into: [:]) { result, name in result[name] = self.manifest(named: name) }
            },
            delete: { self.deleteRecords($0) })
    }
    private func manifest(named name: String) -> BackupManifest? {
        generations[String(name.dropFirst("backup-generation-v3-".count))]
    }
    private func deleteRecords(_ names: Set<String>) {
        for name in names {
            chunks[name] = nil
            if name.hasPrefix("backup-generation-v3-") {
                generations[String(name.dropFirst("backup-generation-v3-".count))] = nil
            }
        }
    }
    func removePreviousManifest() throws -> BackupManifest {
        let id = try XCTUnwrap(current?.previousGenerations.first)
        return try XCTUnwrap(generations.removeValue(forKey: id))
    }
    func restoreManifest(_ manifest: BackupManifest) { generations[manifest.generation] = manifest }
    func storedChunkNames() -> Set<String> { Set(chunks.keys) }
    func damageCurrentChunk(removing: Bool) {
        guard let name = current?.chunks.first?.recordName else { return }
        chunks[name] = removing ? nil : Data("{}".utf8)
    }
    func failNextPublication() { failPublication = true }
    func fetchManifest() async throws -> BackupManifest? { current }
    func saveArchive(_ manifest: BackupManifest, chunkFiles: [String: URL], expectedGeneration: String?, expectedAccount: String) async throws {
        guard account == expectedAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
        guard expectedGeneration == current?.generation else { throw UserDataCloudBackupSafetyError.remoteChanged }
        lastUploadedChunkCount = chunkFiles.count
        for (name, url) in chunkFiles { chunks[name] = try Data(contentsOf: url) }
        if failPublication { failPublication = false; throw ArchiveTestError.publication }
        current = manifest
        generations[manifest.generation] = manifest
        publicationCount += 1
    }
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        if restoreFailure == .metadata {
            restoreFailure = nil
            return try JSONDecoder().decode(UserDataCloudBackupRemoteMetadata.self, from: Data("{}".utf8))
        }
        return current.map { .init(updatedAt: $0.updatedAt, contentSummary: $0.summary, generation: $0.generation) }
    }
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        if let downloadStarted {
            await withCheckedContinuation { continuation in
                downloadContinuation = continuation
                downloadStarted.fulfill()
            }
        }
        if let failure = restoreFailure {
            restoreFailure = nil
            switch failure {
            case .payload:
                return .init(updatedAt: .now, payloadData: Data("{}".utf8), contentSummary: nil)
            case .compressed:
                _ = try BackupArchiveCodec.decode(Data("WGJZ1\0bad compressed bytes".utf8))
            case .chunk:
                try UserDataBackupPayloadCodec.Combiner().append(Data("not JSON".utf8))
            case .missingCloudChunk:
                cloudChunkError = .unknownItem
            case .missingCloudBatch:
                _ = try await CloudKitUserDataCloudBackupStore.requiredArchiveRecords(recordIDs: [CKRecord.ID(recordName: "missing")]) {
                    throw CKError(.unknownItem)
                }
            case .metadata: XCTFail("Metadata error should have been consumed first")
            }
        }
        if let code = cloudChunkError {
            cloudChunkError = nil
            let id = CKRecord.ID(recordName: "chunk")
            _ = try await CloudKitUserDataCloudBackupStore.requiredArchiveRecords(recordIDs: [id]) {
                [id: .failure(CKError(code))]
            }
        }
        if failDownload { failDownload = false; throw ArchiveTestError.publication }
        guard let current else { return nil }
        return try record(current)
    }
    func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard let previous = current?.previousGenerations.first, let manifest = generations[previous] else { return nil }
        return try record(manifest)
    }
    private func record(_ current: BackupManifest) throws -> UserDataCloudBackupRemoteRecord {
        let parts = try current.chunks.map { reference in
            guard let data = chunks[reference.recordName] else { throw BackupArchiveError.missingChunk }
            let decoded = try BackupArchiveCodec.decode(data)
            guard BackupArchiveCodec.digest(decoded) == reference.digest else { throw BackupArchiveError.corruptChunk }
            return decoded
        }
        return try UserDataCloudBackupRemoteRecord(updatedAt: current.updatedAt,
                payloadData: UserDataBackupPayloadCodec.combine(parts, generatedAt: current.updatedAt),
                contentSummary: current.summary, generation: current.generation)
    }
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws { XCTFail("Incremental export used legacy upload") }
    func deleteBackup() async throws { current = nil; chunks = [:] }
}
