import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class AppDataDeletionArtifactTests: XCTestCase {
    func testDefaultArtifactCleanupRemovesSnapshotAndImagesDespiteHealthResetFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        try await store.save(ActiveWorkoutRuntimeSession(name: "Deleted workout"))
        let images = directory.appendingPathComponent("ExerciseImages")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let suite = "DeletionArtifacts.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Old widget", forKey: "widget")
        let probe = ArtifactDeletionProbe()
        do {
            try await AppDataDeletionService.clearDefaultLocalArtifacts(
                resetAppleHealthState: { throw CocoaError(.fileWriteUnknown) },
                clearExerciseImages: { try? FileManager.default.removeItem(at: images) },
                clearWeeklyGoalWidgetSnapshot: { defaults.removeObject(forKey: "widget") },
                clearActiveWorkoutSnapshot: {
                    await probe.recordSnapshotCleanup()
                    try await store.delete()
                }
            )
            XCTFail("Expected Health reset failure to be reported")
        } catch let error as LocalArtifactCleanupError {
            XCTAssertEqual(error.failures.count, 1)
            XCTAssertTrue(error.failures[0].contains("Apple Health"))
        }
        let snapshot = try await store.loadStoredSnapshot()
        XCTAssertNil(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.path))
        XCTAssertNil(defaults.object(forKey: "widget"))
        let snapshotCalls = await probe.snapshotCalls
        XCTAssertEqual(snapshotCalls, 1)
    }

    func testCommittedDeletionClearsActiveRuntimeAndReturnsToSetupDespiteCleanupFailure() async {
        let coordinator = ActiveWorkoutCoordinator.preview(session: ActiveWorkoutRuntimeSession(name: "Deleted workout"))
        var events: [String] = []
        let outcome = await AppDataDeletionService.performUserDataDeletion(
            deleteCloudBackup: { events.append("cloud") },
            commitLocalDeletion: { events.append("local") },
            didCommitLocalDeletion: {
                events.append("memory")
                coordinator.clearInMemory()
            },
            resetBackupState: { events.append("backup") },
            clearArtifacts: {
                XCTAssertNil(coordinator.storedSnapshot)
                events.append("artifacts")
                throw LocalArtifactCleanupError(failures: ["Apple Health: deferred reset"])
            }
        )
        XCTAssertEqual(events, ["cloud", "local", "memory", "backup", "artifacts"])
        XCTAssertTrue(outcome.didDeleteLocalData)
        XCTAssertEqual(outcome.title, "Data Deleted")
        XCTAssertTrue(outcome.message.contains("Apple Health: deferred reset"))
        XCTAssertNil(coordinator.storedSnapshot)
    }

    func testDeletionFailureBeforeLocalCommitPreservesRuntimeAndDoesNotReturnToSetup() async {
        for failsCloud in [true, false] {
            let coordinator = ActiveWorkoutCoordinator.preview(session: ActiveWorkoutRuntimeSession(name: "Keep workout"))
            let outcome = await AppDataDeletionService.performUserDataDeletion(
                deleteCloudBackup: { if failsCloud { throw CocoaError(.fileWriteUnknown) } },
                commitLocalDeletion: { throw CocoaError(.fileWriteUnknown) },
                didCommitLocalDeletion: { XCTFail("Deletion never committed") },
                resetBackupState: { XCTFail("Must retain backup state") },
                clearArtifacts: { XCTFail("Must retain local artifacts") }
            )
            XCTAssertFalse(outcome.didDeleteLocalData)
            XCTAssertEqual(outcome.title, "Delete Failed")
            XCTAssertNotNil(coordinator.storedSnapshot)
        }
    }

    func testPostCommitBackupFailureStillAttemptsArtifactCleanupAndReturnsToSetup() async {
        var clearedArtifacts = false
        let outcome = await AppDataDeletionService.performUserDataDeletion(
            deleteCloudBackup: {}, commitLocalDeletion: {}, didCommitLocalDeletion: {},
            resetBackupState: { throw CocoaError(.fileWriteUnknown) },
            clearArtifacts: { clearedArtifacts = true }
        )
        XCTAssertTrue(clearedArtifacts)
        XCTAssertTrue(outcome.didDeleteLocalData)
        XCTAssertTrue(outcome.message.contains("Cleanup needs attention"))
    }

    func testSnapshotCleanupFailureIsDurablyRetriedAfterQueueRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let suite = "DeletionSnapshot.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessionID = UUID()
        let queue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        do {
            try await AppDataDeletionService.clearDefaultActiveWorkoutSnapshot(sessionID: sessionID, queue: queue, snapshotStore: store)
            XCTFail("Expected cleanup warning")
        } catch { }
        let retried = expectation(description: "Retry survives queue recreation")
        let recreated = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { id in
            XCTAssertEqual(id, sessionID)
            retried.fulfill()
        })
        let warnings = await recreated.retryPending()
        XCTAssertTrue(warnings.isEmpty)
        await fulfillment(of: [retried], timeout: 1)
    }

    func testDeletionRemovesFutureDatedDraftAndRejectsLateWritesAfterStoreRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ClockRollbackDeletion.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let session = ActiveWorkoutRuntimeSession(name: "Before clock rollback", updatedAt: .now.addingTimeInterval(3_600))
        try await store.save(session)
        let queue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { id in
            try await store.invalidateSession(id)
        })
        // The draft timestamp is later than today's clock, but user deletion targets its identity.
        try await AppDataDeletionService.clearDefaultActiveWorkoutSnapshot(queue: queue, snapshotStore: store)
        let recreated = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let restored = try await recreated.loadStoredSnapshot()
        XCTAssertNil(restored)
        var lateWrite = session
        lateWrite.updatedAt = .now.addingTimeInterval(7_200)
        let result = try await recreated.save(lateWrite)
        XCTAssertEqual(result, .rejectedInvalidated)
        let afterLateWrite = try await recreated.loadStoredSnapshot()
        XCTAssertNil(afterLateWrite)
    }

    func testDelayedDeletionPreservesNewWorkoutEvenWithEarlierTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "DelayedDraftDeletion.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let deleted = ActiveWorkoutRuntimeSession(name: "Deleted", updatedAt: .now.addingTimeInterval(3_600))
        try await store.save(deleted)
        let failingQueue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        do {
            try await AppDataDeletionService.clearDefaultActiveWorkoutSnapshot(queue: failingQueue, snapshotStore: store)
            XCTFail("Expected deferred cleanup")
        } catch { }
        let newWorkout = ActiveWorkoutRuntimeSession(name: "New workout after clock rollback", updatedAt: .now.addingTimeInterval(-60))
        try await store.save(newWorkout)
        let recreatedQueue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { id in
            try await store.invalidateSession(id)
        })
        let warnings = await recreatedQueue.retryPending()
        XCTAssertTrue(warnings.isEmpty)
        let retained = try await ActiveWorkoutSnapshotStore(baseDirectory: directory).loadStoredSnapshot()
        XCTAssertEqual(retained?.session.id, newWorkout.id)
        let lateWrite = try await store.save(deleted)
        XCTAssertEqual(lateWrite, .rejectedInvalidated)
    }

    func testPendingDeletionFencesRestoreAndWritesBeforeStartupCleanupRuns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "PendingDraftDeletion.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory, pendingDeletionIDs: {
            Set((UserDefaults(suiteName: suite)?.stringArray(forKey: AppDataArtifactCleanupQueue.deletedSessionsDefaultsKey) ?? [])
                .compactMap(UUID.init(uuidString:)))
        })
        let deleted = ActiveWorkoutRuntimeSession(name: "Deleted", updatedAt: .now.addingTimeInterval(3_600))
        try await store.save(deleted)
        let queue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        _ = await queue.enqueueSnapshotDeletion(sessionIDs: [deleted.id])
        let restoredBeforeCleanup = try await store.loadStoredSnapshot()
        XCTAssertNil(restoredBeforeCleanup)
        let rejectedBeforeCleanup = try await store.save(deleted)
        XCTAssertEqual(rejectedBeforeCleanup, .rejectedInvalidated)
        let current = ActiveWorkoutRuntimeSession(name: "New workout")
        let newWrite = try await store.save(current)
        XCTAssertEqual(newWrite, .written)
        let recreatedQueue = AppDataArtifactCleanupQueue(defaultsSuiteName: suite, cleanup: { _ in }, snapshotDeletion: { id in
            try await store.invalidateSession(id)
        })
        let warnings = await recreatedQueue.retryPending()
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertEqual(UserDefaults(suiteName: suite)?.stringArray(forKey: AppDataArtifactCleanupQueue.deletedSessionsDefaultsKey), [])
        let rejectedAfterCleanup = try await store.save(deleted)
        XCTAssertEqual(rejectedAfterCleanup, .rejectedInvalidated)
        let retained = try await store.loadStoredSnapshot()
        XCTAssertEqual(retained?.session.id, current.id)
    }

    func testInstanceCleanupReportsBothFailuresAfterAttemptingEveryArtifact() async throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let clearedWidget = expectation(description: "Widget cleared despite reset failure")
        let attemptedSnapshot = expectation(description: "Snapshot cleanup attempted despite reset failure")
        let service = AppDataDeletionService(
            modelContext: context,
            clearWeeklyGoalWidgetSnapshot: { clearedWidget.fulfill() },
            clearActiveWorkoutSnapshot: {
                attemptedSnapshot.fulfill()
                throw CocoaError(.fileWriteNoPermission)
            },
            resetAppleHealthState: { throw CocoaError(.fileReadUnknown) }
        )
        do {
            try await service.clearLocalArtifacts()
            XCTFail("Expected both cleanup failures")
        } catch let error as LocalArtifactCleanupError {
            XCTAssertEqual(error.failures.count, 2)
            XCTAssertTrue(error.localizedDescription.contains("Apple Health"))
            XCTAssertTrue(error.localizedDescription.contains("Active workout"))
        }
        await fulfillment(of: [clearedWidget, attemptedSnapshot], timeout: 1)
    }
}

private actor ArtifactDeletionProbe {
    private(set) var snapshotCalls = 0
    func recordSnapshotCleanup() { snapshotCalls += 1 }
}
