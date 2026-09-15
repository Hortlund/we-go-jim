import XCTest
import SwiftData
@testable import WGJ

@MainActor
final class CoreReadSchedulingTests: XCTestCase {
    func testCanceledReadDoesNotExecuteWhenWaitingForStore() async throws {
        let container = try makeContainer()
        let store = AppBackgroundStore(container: container)
        let started = expectation(description: "Store occupied")
        let requested = expectation(description: "Read requested")
        let gate = DispatchSemaphore(value: 0)
        let probe = ReadExecutionProbe()
        let blocker = Task.detached {
            try await store.perform { _ in
                started.fulfill()
                gate.wait()
            }
        }
        await fulfillment(of: [started], timeout: 5)
        let read = Task.detached {
            requested.fulfill()
            return try await store.performRead { _ in probe.execute() }
        }
        await fulfillment(of: [requested], timeout: 5)
        read.cancel()
        gate.signal()
        try await blocker.value
        do {
            try await read.value
            XCTFail("Canceled reads must not publish a result")
        } catch is CancellationError { }
        XCTAssertEqual(probe.count, 0)
    }

    func testCanceledTaskStillCommitsExplicitWrite() async throws {
        let container = try makeContainer()
        let store = AppBackgroundStore(container: container)
        let write = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.performWrite { context in
                context.insert(UserProfile(displayName: "Saved"))
            }
        }
        try await write.value
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<UserProfile>()), 1)
    }

    func testReadReturnsValueWithoutSavingChanges() async throws {
        let container = try makeContainer()
        let store = AppBackgroundStore(container: container)
        let count = try await store.performRead { context in
            try context.fetchCount(FetchDescriptor<UserProfile>())
        }
        XCTAssertEqual(count, 0)
    }

    func testUploadProgressDoesNotRepeatLocalSummaryRefresh() {
        var state = ProfileBackupSummaryRefreshState()
        let date = Date(timeIntervalSince1970: 100)
        state.observe(.pending(at: date))
        let pending = state
        state.observe(.backedUp(at: date.addingTimeInterval(1)))
        XCTAssertEqual(state, pending)
        state.observe(.checkingStatus())
        state.observe(.statusChecked(at: date))
        XCTAssertEqual(state, pending)
        state.observe(.pending(at: date.addingTimeInterval(2)))
        XCTAssertNotEqual(state, pending, "A later mutation must refresh even during an earlier read")
    }

    func testOldJobCompletionCannotRemoveReplacement() async throws {
        let store = AppBackgroundStore(container: try makeContainer())
        let key = AppBackgroundJobKey.feature("replacement-test")
        let firstStarted = expectation(description: "First job started")
        let secondStarted = expectation(description: "Replacement started")
        let firstGate = DispatchSemaphore(value: 0)
        let secondGate = DispatchSemaphore(value: 0)
        defer { firstGate.signal(); secondGate.signal() }
        let extraExecution = ReadExecutionProbe()

        let first = await store.scheduleCoalesced(key: key) { _ in
            firstStarted.fulfill()
            _ = firstGate.wait(timeout: .now() + 10)
        }
        await fulfillment(of: [firstStarted], timeout: 5)
        let replacement = await store.scheduleCoalesced(key: key, cancelExisting: true) { _ in
            secondStarted.fulfill()
            _ = secondGate.wait(timeout: .now() + 10)
        }
        await fulfillment(of: [secondStarted], timeout: 5)
        firstGate.signal()
        await first.value

        let coalesced = await store.scheduleCoalesced(key: key) { _ in extraExecution.execute() }
        secondGate.signal()
        await replacement.value
        await coalesced.value
        XCTAssertEqual(extraExecution.count, 0, "The replacement must remain registered until it finishes")
    }

    private func makeContainer() throws -> ModelContainer {
        try AppSchema.makeInMemoryContainer(name: "CoreReadSchedulingTests")
    }
}

private final class ReadExecutionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func execute() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
