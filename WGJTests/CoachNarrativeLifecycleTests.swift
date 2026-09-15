import SwiftData
import Synchronization
import XCTest
@testable import WGJ

@MainActor
final class CoachNarrativeLifecycleTests: XCTestCase {
    func testDisplayReturnsFallbackWithoutStartingGenerationOrWritingCache() async throws {
        let store = CoachNarrativeStore(modelContainer: try AppSchema.makeInMemoryContainer(name: "CoachDisplay"))
        let calls = Mutex(0)
        let service = AppleCoachNarrativeService(
            cache: store,
            availabilityProvider: { true },
            recapGenerator: { _ in
                calls.withLock { $0 += 1 }
                return nil
            }
        )
        let snapshot = snapshot()
        let result = try await service.recapForDisplay(for: snapshot)
        XCTAssertEqual(result.availabilityMode, .fallback)
        XCTAssertEqual(result.body, snapshot.fallbackSummary)
        let cached = try await store.recap(weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey)
        XCTAssertNil(cached)
        XCTAssertEqual(calls.withLock { $0 }, 0)
    }

    func testExplicitRefreshPersistsGeneratedSummaryForDisplay() async throws {
        let store = CoachNarrativeStore(modelContainer: try AppSchema.makeInMemoryContainer(name: "CoachRefresh"))
        let generated = CoachNarrativeSummary(headline: "Steady week", body: "You logged two workouts.", availabilityMode: .generated)
        let service = AppleCoachNarrativeService(
            cache: store,
            availabilityProvider: { true },
            recapGenerator: { _ in generated }
        )
        let snapshot = snapshot()
        let refreshed = try await service.refreshRecapIfNeeded(for: snapshot)
        XCTAssertEqual(refreshed, generated)
        let displayed = try await service.recapForDisplay(for: snapshot)
        XCTAssertEqual(displayed, generated)
    }

    func testCancelledRefreshDoesNotPublishLateGeneration() async throws {
        let store = CoachNarrativeStore(modelContainer: try AppSchema.makeInMemoryContainer(name: "CoachCancel"))
        let started = expectation(description: "Generation started")
        let returned = expectation(description: "Caller canceled")
        let gate = CoachGenerationGate()
        let service = AppleCoachNarrativeService(
            cache: store,
            availabilityProvider: { true },
            recapGenerator: { _ in
                started.fulfill()
                await gate.wait()
                return CoachNarrativeSummary(headline: "Late", body: "Do not publish", availabilityMode: .generated)
            }
        )
        let snapshot = snapshot()
        let request = Task {
            do {
                _ = try await service.refreshRecapIfNeeded(for: snapshot)
                XCTFail("Cancelled generation must not be published")
            } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
            returned.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        await fulfillment(of: [returned], timeout: 2)
        await gate.release()
        await request.value
        let cached = try await store.recap(weekStart: snapshot.weekStart, revisionKey: snapshot.revisionKey)
        XCTAssertNil(cached)
    }

    func testRetryStartsBeforeCancelledGeneratorReturns() async throws {
        let store = CoachNarrativeStore(modelContainer: try AppSchema.makeInMemoryContainer(name: "CoachRetry"))
        let started = expectation(description: "Old generation started")
        let retried = expectation(description: "Retry finished independently")
        let gate = CoachGenerationGate()
        let calls = Mutex(0)
        let service = AppleCoachNarrativeService(
            cache: store,
            availabilityProvider: { true },
            recapGenerator: { _ in
                let call = calls.withLock { $0 += 1; return $0 }
                if call == 1 {
                    started.fulfill()
                    await gate.wait()
                }
                return CoachNarrativeSummary(headline: "Retry", body: "Fresh summary", availabilityMode: .generated)
            }
        )
        let snapshot = snapshot()
        let first = Task { try? await service.refreshRecapIfNeeded(for: snapshot) }
        await fulfillment(of: [started], timeout: 2)
        first.cancel()
        _ = await first.value
        let retry = Task {
            do {
                let result = try await service.refreshRecapIfNeeded(for: snapshot)
                XCTAssertEqual(result.headline, "Retry")
            } catch { XCTFail("Retry failed: \(error)") }
            retried.fulfill()
        }
        await fulfillment(of: [retried], timeout: 2)
        await gate.release()
        await retry.value
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    private func snapshot() -> WeeklyCoachInsightSnapshot {
        WeeklyCoachInsightSnapshot(
            weekStart: Date(timeIntervalSince1970: 1_800_000_000), revisionKey: "lifecycle",
            baselineWeekCount: 4, completedWorkoutCount: 2, totalVolumeDelta: 0,
            consistencyDelta: 0, topRisingSignals: [], topWatchSignals: [],
            fallbackSummary: "You logged two workouts.", followUpKinds: []
        )
    }
}

private actor CoachGenerationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
