import XCTest
@testable import WGJ

@MainActor
final class AvatarSelectionCoordinatorTests: XCTestCase {
    func testLatestSelectionWinsWhenOlderLoadFinishesLast() async {
        let gate = AvatarDataGate()
        let coordinator = AvatarSelectionCoordinator(transform: { $0 })
        let first = Data("first".utf8)
        let second = Data("second".utf8)

        coordinator.select { await gate.waitForValue() }
        coordinator.select { second }
        await waitUntil { coordinator.imageData == second }
        await gate.release(first)
        await Task.yield()

        XCTAssertEqual(coordinator.imageData, second)
    }

    func testRemoveWinsOverPendingSelection() async {
        let gate = AvatarDataGate()
        let coordinator = AvatarSelectionCoordinator(transform: { $0 })

        coordinator.select { await gate.waitForValue() }
        coordinator.remove()
        await gate.release(Data("late".utf8))
        await Task.yield()

        XCTAssertNil(coordinator.imageData)
        XCTAssertFalse(coordinator.isLoading)
    }

    func testCancelPreventsLatePublicationWithoutClearingCurrentImage() async {
        let gate = AvatarDataGate()
        let initial = Data("initial".utf8)
        let coordinator = AvatarSelectionCoordinator(
            imageData: initial,
            transform: { $0 }
        )

        coordinator.select { await gate.waitForValue() }
        coordinator.cancel()
        await gate.release(Data("late".utf8))
        await Task.yield()

        XCTAssertEqual(coordinator.imageData, initial)
        XCTAssertFalse(coordinator.isLoading)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true")
    }
}

private actor AvatarDataGate {
    private var continuation: CheckedContinuation<Data?, Never>?
    private var bufferedValue: Data?

    func waitForValue() async -> Data? {
        if let bufferedValue {
            self.bufferedValue = nil
            return bufferedValue
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release(_ value: Data) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            bufferedValue = value
        }
    }
}
