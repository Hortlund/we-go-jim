import XCTest

final class DeepLinkAccessibilityUITests: XCTestCase {
    @MainActor
    func testColdWeeklyGoalLinkRoutesToExactSectionOnce() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ]
        app.launchEnvironment["UITEST_INITIAL_URL"] = "wgj://profile/weekly-goal"
        app.launch()

        let continueLocally = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
        continueLocally.tap()

        let weeklyGoal = app.otherElements["profile-weekly-goal-section"]
        XCTAssertTrue(weeklyGoal.waitForExistence(timeout: 10))
        let hittableExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: weeklyGoal
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittableExpectation], timeout: 4),
            .completed
        )

        let startTab = app.buttons["Start Workout"].firstMatch
        let profileTab = app.buttons["Profile"].firstMatch
        XCTAssertTrue(startTab.waitForExistence(timeout: 4))
        startTab.tap()
        XCTAssertTrue(profileTab.waitForExistence(timeout: 4))
        profileTab.tap()
        XCTAssertTrue(weeklyGoal.exists)
    }
}
