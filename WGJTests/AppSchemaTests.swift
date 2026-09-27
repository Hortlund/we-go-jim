import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class AppSchemaTests: XCTestCase {
    func testFullSchemaCreatesIsolatedInMemoryContainers() throws {
        let first = try makeContainer(named: "AppSchemaTests.first")
        let second = try makeContainer(named: "AppSchemaTests.second")

        let firstContext = ModelContext(first)
        firstContext.insert(UserProfile(displayName: "First"))
        try firstContext.save()

        XCTAssertEqual(try firstContext.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertEqual(
            try ModelContext(second).fetchCount(FetchDescriptor<UserProfile>()),
            0
        )
    }

    func testVersionTwoCatalogMigratesWithLoadTypeUnsetAndHistoryIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        try autoreleasepool {
            let schema = Schema(versionedSchema: AppSchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            context.autosaveEnabled = false
            let exercise = AppSchemaV1.ExerciseCatalogItem()
            exercise.remoteUUID = "custom-old"
            exercise.displayName = "Assisted Dip"
            exercise.sourceName = "custom"
            exercise.equipmentSummary = "Machine"
            context.insert(exercise)
            context.insert(WorkoutSession(name: "Saved Workout", status: .completed))
            try context.save()
        }
        let schema = AppSchema.makeFull()
        let migrated = try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(migrated)
        context.autosaveEnabled = false
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseCatalogItem>()).first)
        XCTAssertNil(exercise.loadTrackingRaw)
        XCTAssertEqual(exercise.loadKind, .assistance)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.name, "Saved Workout")
        exercise.loadTrackingRaw = "resistance"
        try context.saveWithRecoveryProtection()
        XCTAssertEqual(exercise.loadKind, .resistance)
    }

    private func makeContainer(named name: String) throws -> ModelContainer {
        try AppSchema.makeInMemoryContainer(name: name)
    }
}
