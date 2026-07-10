import SwiftData
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
}
