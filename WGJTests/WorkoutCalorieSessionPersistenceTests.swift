import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCalorieSessionPersistenceTests: XCTestCase {
    func testCompletedSessionPersistsCalorieEstimateResults() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieSessionPersistenceTests-\(UUID().uuidString)"
        )
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let writeContext = ModelContext(container)
        writeContext.autosaveEnabled = false
        writeContext.insert(WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 2_000),
            estimatedActiveCalories: 145,
            calorieEstimateVersion: 1
        ))
        try writeContext.save()

        let readContext = ModelContext(container)
        let restored = try XCTUnwrap(
            readContext.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID }
        )

        XCTAssertEqual(restored.estimatedActiveCalories, 145)
        XCTAssertEqual(restored.calorieEstimateVersion, 1)
    }
}
