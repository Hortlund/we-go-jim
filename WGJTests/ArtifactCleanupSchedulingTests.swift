import XCTest
import SwiftData
@testable import WGJ

@MainActor
final class ArtifactCleanupSchedulingTests: XCTestCase {
    func testOverlappingRestoreCleanupAndRetryNeverEmitWorkoutReset() async throws {
        let suiteName = "RestoreCleanupNotification.\(UUID())"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let target = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let cutoff = Date.now
        try BackupLocalJournal.saveRestoreCleanup(cutoff, for: target)
        let unexpected = expectation(description: "Deferred cleanup must not reset the workout UI")
        unexpected.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .wgjUserDataRestoreDidComplete,
            object: nil, queue: nil) { _ in unexpected.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let started = expectation(description: "Cleanup suspended")
        let probe = ArtifactCleanupProbe(started: started)
        let queue = AppDataArtifactCleanupQueue(defaultsSuiteName: suiteName) { await probe.clean($0) }
        // There is only a cleanup receipt, so this never contacts CloudKit.
        let service = UserDataCloudBackupService(localContainer: target,
            backupStore: CloudKitUserDataCloudBackupStore(), artifactCleanupQueue: queue)
        let first = Task { try await service.resumePendingRestore() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await service.resumePendingRestore() }
        await Task.yield()
        await probe.release()
        _ = try await first.value
        _ = try await second.value
        // Simulate a receipt left behind by an interrupted journal cleanup.
        try BackupLocalJournal.saveRestoreCleanup(cutoff, for: target)
        _ = try await service.resumePendingRestore()
        XCTAssertNil(try BackupLocalJournal.restoreCleanup(for: target))
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testCleanupRetryKeepsOriginalCutoffAcrossQueueRecreation() async throws {
        let suiteName = "ArtifactCleanupCutoff.\(UUID())"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let first = AppDataArtifactCleanupQueue(defaults: UserDefaults(suiteName: suiteName)!, datedCleanup: { _, received in
            XCTAssertEqual(received, cutoff)
            throw CancellationError()
        })
        let warnings = await first.enqueue([.activeWorkoutSnapshot], before: cutoff)
        XCTAssertEqual(warnings.count, 1)
        let retried = expectation(description: "Retried using original cutoff")
        let reopened = AppDataArtifactCleanupQueue(defaults: UserDefaults(suiteName: suiteName)!, datedCleanup: { _, received in
            XCTAssertEqual(received, cutoff)
            retried.fulfill()
        })
        let retryWarnings = await reopened.retryPending()
        XCTAssertTrue(retryWarnings.isEmpty)
        await fulfillment(of: [retried], timeout: 1)
    }

    func testSnapshotCleanupUsesSubsecondCutoffAndPreservesNewerSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let file = directory.appendingPathComponent("active-workout-snapshot.json")
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000.75)
        var snapshot = ActiveWorkoutRuntimeSession(id: UUID(), name: "Draft", startedAt: cutoff,
            updatedAt: cutoff.addingTimeInterval(-0.25))
        try await store.save(snapshot)
        // A delayed write does not make old content newer than the restore request.
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(10)], ofItemAtPath: file.path)
        try await store.invalidateSnapshotsSavedBefore(cutoff)
        let removed = try await store.loadStoredSnapshot()
        XCTAssertNil(removed)
        snapshot.touch(date: cutoff.addingTimeInterval(0.25))
        try await store.save(snapshot)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(-10)], ofItemAtPath: file.path)
        try await store.invalidateSnapshotsSavedBefore(cutoff)
        let preserved = try await store.loadStoredSnapshot()
        XCTAssertEqual(preserved?.session.id, snapshot.id)
    }

    func testOverlappingEnqueuesRunCleanupOncePerArtifact() async {
        let suiteName = "ArtifactCleanupSchedulingTests.\(UUID())"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "First cleanup started")
        let probe = ArtifactCleanupProbe(started: started)
        let queue = AppDataArtifactCleanupQueue(defaultsSuiteName: suiteName) { artifact in
            await probe.clean(artifact)
        }
        let first = Task { await queue.enqueue([.activeWorkoutSnapshot]) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await queue.enqueue([.weeklyGoalWidgetSnapshot]) }
        // The second request must be durable even while cleanup is suspended.
        await assertEventually {
            UserDefaults(suiteName: suiteName)?
                .stringArray(forKey: "appDataArtifactCleanupQueue.pendingArtifacts")?
                .contains(AppDataArtifact.weeklyGoalWidgetSnapshot.rawValue) == true
        }
        await probe.release()
        let firstWarnings = await first.value
        let secondWarnings = await second.value
        XCTAssertTrue(firstWarnings.isEmpty)
        XCTAssertTrue(secondWarnings.isEmpty)
        let calls = await probe.calls
        XCTAssertEqual(calls, [.activeWorkoutSnapshot, .weeklyGoalWidgetSnapshot])
        let retryWarnings = await queue.retryPending()
        XCTAssertTrue(retryWarnings.isEmpty)
        let callsAfterRetry = await probe.calls
        XCTAssertEqual(callsAfterRetry, calls)
    }
}

private actor ArtifactCleanupProbe {
    let started: XCTestExpectation
    private(set) var calls: [AppDataArtifact] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(started: XCTestExpectation) { self.started = started }

    func clean(_ artifact: AppDataArtifact) async {
        calls.append(artifact)
        if calls.count == 1 {
            started.fulfill()
            if !released { await withCheckedContinuation { continuation = $0 } }
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
