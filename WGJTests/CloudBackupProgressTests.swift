import XCTest
@testable import WGJ

@MainActor
final class CloudBackupProgressTests: XCTestCase {
    func testRestoreRetryUpdatesPresentedFailureAndIgnoresOldAttemptReports() async throws {
        let center = CloudBackupProgressCenter()
        let ticket = UUID()
        let original = try XCTUnwrap(center.beginRestore(requestID: ticket, foreground: true))
        let staleReporter = original.reporter
        center.finish(original, outcome: .failure("Offline"))
        let retry = try XCTUnwrap(center.beginRestore(requestID: ticket, foreground: true))
        XCTAssertTrue(retry === original)
        XCTAssertTrue(center.presentedOperation === retry)
        XCTAssertEqual(center.operations.count, 1)
        XCTAssertTrue(retry.isRunning)
        XCTAssertTrue(center.hasForegroundOperation)
        XCTAssertEqual(retry.title, "Restoring from iCloud")
        retry.update(.init(stage: .restoring))
        staleReporter(.downloading, completed: 50, total: 200)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(retry.progress.stage, .restoring)
        XCTAssertNil(center.beginRestore(requestID: ticket, foreground: true))
        center.finish(retry, outcome: .success("Restored"))
        XCTAssertEqual(center.presentedOperation?.outcome, .success("Restored"))
        center.didDismiss()
        XCTAssertTrue(center.operations.isEmpty)
    }

    func testRetryDuringFailureDismissalRemainsTrackedAndIsPresentedAgain() throws {
        let center = CloudBackupProgressCenter()
        let ticket = UUID()
        let original = try XCTUnwrap(center.beginRestore(requestID: ticket, foreground: true))
        center.finish(original, outcome: .failure("Offline"))
        center.presentedOperation = nil // SwiftUI has started dismissing the error.
        let retry = try XCTUnwrap(center.beginRestore(requestID: ticket, foreground: true))
        center.didDismiss()
        XCTAssertTrue(center.presentedOperation === retry)
        XCTAssertTrue(center.activeOperation === retry)
        XCTAssertTrue(center.hasForegroundOperation)
        XCTAssertNil(center.beginRestore(requestID: ticket, foreground: true))
    }

    func testAutomaticBackupNeverPresentsAModalEvenOnFailure() async throws {
        let center = CloudBackupProgressCenter()
        let operation = center.begin(kind: .backup, foreground: false)
        operation.update(.init(stage: .uploading, completed: 50, total: 150))
        XCTAssertEqual(center.activeOperation?.id, operation.id)
        XCTAssertFalse(center.hasForegroundOperation)
        center.finish(operation, outcome: .failure("Offline"))
        XCTAssertNil(center.presentedOperation)
        XCTAssertNil(center.activeOperation)
        XCTAssertTrue(center.operations.isEmpty)
    }

    func testFastManualSuccessDoesNotFlashASheetAfterItsDelay() async throws {
        let center = CloudBackupProgressCenter()
        let operation = center.begin(kind: .backup, foreground: true)
        center.finish(operation, outcome: .success("Saved"))
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertNil(center.presentedOperation)
        XCTAssertFalse(center.hasForegroundOperation)
    }

    func testSlowManualBackupPresentsAndKeepsItsResultUntilDismissed() async throws {
        let center = CloudBackupProgressCenter()
        let operation = center.begin(kind: .backup, foreground: true)
        XCTAssertNil(center.presentedOperation)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(center.presentedOperation?.id, operation.id)
        center.finish(operation, outcome: .success("Saved"))
        XCTAssertEqual(center.presentedOperation?.outcome, .success("Saved"))
        XCTAssertFalse(center.hasForegroundOperation)
        center.didDismiss()
        XCTAssertNil(center.presentedOperation)
        XCTAssertTrue(center.operations.isEmpty)
    }

    func testRestorePresentsImmediatelyAndLateReportsCannotReviveFinishedWork() async {
        let center = CloudBackupProgressCenter()
        let operation = center.begin(kind: .restore, foreground: true)
        let reporter = operation.reporter
        XCTAssertEqual(center.presentedOperation?.id, operation.id)
        XCTAssertTrue(center.hasForegroundOperation)
        operation.update(.init(stage: .saving))
        reporter(.downloading, completed: 10, total: 100)
        center.finish(operation, outcome: .failure("Connection lost"))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(operation.progress.stage, .saving)
        XCTAssertEqual(operation.outcome, .failure("Connection lost"))
        XCTAssertFalse(center.hasForegroundOperation)
    }

    func testQueuedFailureSurvivesDismissalOfPreviousResult() {
        let center = CloudBackupProgressCenter()
        let first = center.begin(kind: .restore, foreground: true)
        let second = center.begin(kind: .backup, foreground: true)
        center.finish(second, outcome: .failure("Offline"))
        center.finish(first, outcome: .success("Restored"))
        XCTAssertEqual(center.presentedOperation?.id, first.id)
        center.didDismiss()
        XCTAssertEqual(center.presentedOperation?.id, second.id)
        XCTAssertEqual(center.presentedOperation?.outcome, .failure("Offline"))
        center.didDismiss()
        XCTAssertTrue(center.operations.isEmpty)
    }

    func testProgressIsPerStageAndUnknownTotalsRemainIndeterminate() {
        XCTAssertNil(CloudBackupProgressUpdate(stage: .checking).fraction)
        XCTAssertNil(CloudBackupProgressUpdate(stage: .uploading, completed: 0, total: 0).fraction)
        let transfer = CloudBackupProgressUpdate(stage: .downloading, completed: 50, total: 200)
        XCTAssertEqual(transfer.fraction, 0.25)
        XCTAssertEqual(transfer.countDescription, "50 of 200 backup parts")
        let operation = CloudBackupOperation(kind: .restore, foreground: true)
        operation.update(transfer)
        operation.update(.init(stage: .validating))
        XCTAssertNil(operation.progress.fraction)
        XCTAssertNil(operation.progress.countDescription)
    }

    func testForegroundBackupKeepsScreenAwakeOnlyWhileSceneIsActive() {
        XCTAssertTrue(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: true, keepsScreenAwake: false, hasActiveWorkout: false, hasForegroundBackupOperation: true))
        XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: false, keepsScreenAwake: true, hasActiveWorkout: true, hasForegroundBackupOperation: true))
        XCTAssertFalse(WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: true, keepsScreenAwake: false, hasActiveWorkout: false, hasForegroundBackupOperation: false))
    }
}
