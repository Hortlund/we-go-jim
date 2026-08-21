#if DEBUG
import SwiftData
import XCTest
@testable import WGJ

final class DemoSeedServiceTests: XCTestCase {
    @MainActor
    func testSeedsRealisticDataOnceAndCanResetLocalDevelopmentData() async throws {
        let container = try AppSchema.makeInMemoryContainer(name: "DemoSeedServiceTests")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let service = DemoSeedService(modelContext: context)

        try service.seedDemoDataIfEmpty()
        try service.seedDemoDataIfEmpty()

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.status == .completed }
        let facts = try context.fetch(FetchDescriptor<CompletedSetFact>())

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.displayName, "Demo Lifter")
        XCTAssertEqual(templates.count, 3)
        XCTAssertEqual(workouts.count, 6)
        XCTAssertTrue(workouts.allSatisfy { $0.totalVolume > 0 })
        XCTAssertTrue(workouts.contains { $0.prHitsCount > 0 })
        XCTAssertFalse(facts.isEmpty)

        try await service.resetLocalDevelopmentData()

        XCTAssertTrue(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemplateExerciseSet>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemplateExerciseComponent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSetFact>()).isEmpty)
    }
}
#endif
