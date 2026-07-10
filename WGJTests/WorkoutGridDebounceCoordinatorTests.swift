import XCTest
@testable import WGJ

@MainActor
final class WorkoutGridDebounceCoordinatorTests: XCTestCase {
    func testRescheduleRunsOnlyLatestCommit() async {
        let sleeper = ControlledDebounceSleeper()
        let recorder = DebounceValueRecorder()
        let coordinator = WorkoutGridDebounceCoordinator(sleep: sleeper.sleep)
        let latestCommitCompleted = expectation(description: "Latest commit completed")

        coordinator.scheduleCommit(.currentState, after: .seconds(1)) {
            recorder.append(1)
        }
        coordinator.scheduleCommit(.bufferedInput, after: .seconds(1)) {
            recorder.append(2)
            latestCommitCompleted.fulfill()
        }
        await sleeper.waitUntilPending()
        await sleeper.resumeAll()
        await fulfillment(of: [latestCommitCompleted], timeout: 1)

        XCTAssertEqual(recorder.values, [2])
        XCTAssertNil(coordinator.pendingCommitKind)
    }

    func testCancelPreventsDisplayRefresh() async {
        let sleeper = ControlledDebounceSleeper()
        let recorder = DebounceValueRecorder()
        let coordinator = WorkoutGridDebounceCoordinator(sleep: sleeper.sleep)

        coordinator.scheduleDisplayRefresh(after: .seconds(1)) {
            recorder.append(1)
        }
        await sleeper.waitUntilPending()
        XCTAssertTrue(coordinator.cancelDisplayRefresh())
        await sleeper.resumeAll()
        await Task.yield()

        XCTAssertTrue(recorder.values.isEmpty)
    }
}

private actor ControlledDebounceSleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(_ duration: Duration) async throws {
        _ = duration
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: ()) }
    }

    func waitUntilPending() async {
        while continuations.isEmpty {
            await Task.yield()
        }
    }
}

@MainActor
private final class DebounceValueRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}
