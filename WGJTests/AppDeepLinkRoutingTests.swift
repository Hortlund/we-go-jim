import XCTest
@testable import WGJ

final class AppDeepLinkRoutingTests: XCTestCase {
    @MainActor
    func testWeeklyGoalRouteIsConsumedOnlyByMatchingRequest() {
        let state = AppRouteState()
        let request = state.enqueue(.profile(.weeklyGoal))

        state.consume(id: UUID())
        XCTAssertEqual(state.pendingRequest?.id, request.id)
        state.consume(id: request.id)
        XCTAssertNil(state.pendingRequest)
    }

    func testParserAcceptsOnlyWeeklyGoalURL() throws {
        XCTAssertEqual(
            AppRouteParser.parse(
                try XCTUnwrap(URL(string: "wgj-dev://profile/weekly-goal")),
                expectedScheme: "wgj-dev"
            ),
            .profile(.weeklyGoal)
        )
        XCTAssertNil(AppRouteParser.parse(
            try XCTUnwrap(URL(string: "wgj-dev://unknown")),
            expectedScheme: "wgj-dev"
        ))
        XCTAssertNil(AppRouteParser.parse(
            try XCTUnwrap(URL(string: "wgj://profile/weekly-goal")),
            expectedScheme: "wgj-dev"
        ))
    }
}
