import XCTest
@testable import WGJ

@MainActor
final class ArtifactCleanupSchedulingTests: XCTestCase {
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
