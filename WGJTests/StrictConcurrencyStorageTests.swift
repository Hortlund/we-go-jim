import SwiftData
import UIKit
import XCTest
@testable import WGJ

final class StrictConcurrencyStorageTests: XCTestCase {
    func testBackgroundStoreDoesNotExposeAsyncModelContextClosures() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ/Services/AppBackgroundStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("func performAsync"))
        XCTAssertFalse(source.contains("func performWriteAsync"))
        XCTAssertFalse(source.contains("(ModelContext) async"))
    }

    func testCoachNarrativeStorePersistsValueSnapshots() async throws {
        let schema = Schema([
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = CoachNarrativeStore(modelContainer: container)
        let weekStart = Date(timeIntervalSince1970: 1_700_000_000)
        let recap = CoachNarrativeSummary(
            headline: "Steady week",
            body: "Volume moved in the right direction.",
            availabilityMode: .generated
        )

        try await store.saveRecap(recap, weekStart: weekStart, revisionKey: "r1")

        let loaded = try await store.recap(weekStart: weekStart, revisionKey: "r1")
        XCTAssertEqual(loaded, recap)
        let needsRefresh = try await store.needsRecapRefresh(
            weekStart: weekStart,
            revisionKey: "r1",
            now: weekStart,
            maxAge: 3_600
        )
        XCTAssertFalse(needsRefresh)
    }

    func testImageMemoryCacheSupportsConcurrentAccessAndClear() async {
        let cache = ExerciseImageMemoryCache(countLimit: 200, totalCostLimit: 1_000_000)
        let image = UIImage()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let key = "image-\(index)"
                    cache.insert(image, for: key, cost: 1)
                    _ = cache.image(for: key)
                }
            }
        }

        XCTAssertNotNil(cache.image(for: "image-99"))
        cache.removeAll()
        XCTAssertNil(cache.image(for: "image-99"))
    }

    func testHistoryCacheRevisionIsAtomic() async throws {
        let schema = Schema([CachedCoachNarrative.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let cache = HistoryAnalyticsCache()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    cache.invalidate(container: container)
                }
            }
        }

        XCTAssertEqual(cache.currentRevision(for: container), 100)
    }

    func testHistoryProjectionRetriesUseBoundedBackoff() {
        XCTAssertEqual(HistoryProjectionRetryPolicy.delay(forRetryAttempt: 1), 1)
        XCTAssertEqual(HistoryProjectionRetryPolicy.delay(forRetryAttempt: 2), 4)
        XCTAssertNil(HistoryProjectionRetryPolicy.delay(forRetryAttempt: 3))
        XCTAssertNil(HistoryProjectionRetryPolicy.delay(forRetryAttempt: 0))
    }
}
