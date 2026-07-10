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

    private func makeContainer(named name: String) throws -> ModelContainer {
        try AppSchema.makeInMemoryContainer(name: name)
    }
}
