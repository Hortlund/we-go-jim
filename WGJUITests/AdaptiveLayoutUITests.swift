import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryStartWorkoutActionSurvivesIPadRotation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ]
        app.launch()

        let continueLocally = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
        continueLocally.tap()

        let startEmpty = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 8))
        let isInitiallyHittable = startEmpty.isHittable
        XCTAssertTrue(isInitiallyHittable)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 4))
        let isLandscapeHittable = startEmpty.isHittable
        XCTAssertTrue(isLandscapeHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 4))
        let isPortraitHittable = startEmpty.isHittable
        XCTAssertTrue(isPortraitHittable)
    }
}
