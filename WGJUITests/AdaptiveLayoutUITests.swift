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

    @MainActor
    func testExerciseSearchAndDetailReturnPreserveQuery() {
        let app = launchLocalApp()
        openExercisesTab(in: app)

        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("bench")

        let bench = app.staticTexts["Barbell Bench Press"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 4))
        bench.tap()

        let detailTitle = app.staticTexts["exercise-detail-title"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 4))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertEqual(search.value as? String, "bench")
        XCTAssertTrue(bench.waitForExistence(timeout: 4))
    }

    @MainActor
    func testExerciseSearchRefocusesAfterOpeningFilter() {
        let app = launchLocalApp()
        openExercisesTab(in: app)

        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search
            .coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -22, dy: 0))
            .tap()
        search.typeText("bench")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        app.buttons["exercises-body-part-filter"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        app.buttons
            .matching(identifier: "exercises-body-part-dropdown")
            .matching(NSPredicate(format: "label == %@", "Any Body Part"))
            .firstMatch
            .tap()

        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        search.typeText(" press")
        XCTAssertEqual(search.value as? String, "bench press")
    }

    @MainActor
    func testActiveWorkoutStripHidesDuringExerciseSearchAndReturnsAfterDismissal() {
        let app = launchLocalApp()
        let start = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let minimize = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 8))
        minimize.tap()
        openExercisesTab(in: app)

        let strip = app.buttons["active-workout-strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 4))
        let originalY = strip.frame.midY
        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))

        for query in ["bench", "zzzznoexercise"] {
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let visibleKey = app.keyboards.keys["b"]
            XCTAssertTrue(visibleKey.wait(for: \.isHittable, toEqual: true, timeout: 3),
                          "Enable the Simulator software keyboard before running this test")
            // Focusing an empty field alone must hide the strip.
            XCTAssertTrue(strip.waitForNonExistence(timeout: 3))
            search.typeText(query)
            if query == "bench" {
                XCTAssertTrue(app.staticTexts["Barbell Bench Press"].firstMatch.waitForExistence(timeout: 4))
            } else {
                XCTAssertTrue(app.staticTexts["Barbell Bench Press"].firstMatch.waitForNonExistence(timeout: 4))
            }
            XCTAssertFalse(strip.exists)

            app.buttons["exercises-body-part-filter"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertTrue(strip.waitForExistence(timeout: 3))
            XCTAssertEqual(strip.frame.midY, originalY, accuracy: 3)
            app.buttons
                .matching(identifier: "exercises-body-part-dropdown")
                .matching(NSPredicate(format: "label == %@", "Any Body Part"))
                .firstMatch.tap()
        }

        strip.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 4))
    }

    @MainActor
    func testExerciseProgressSelectors() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_EXERCISE_PROGRESS"])
        openExercisesTab(in: app)

        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("bench")

        let bench = app.staticTexts["Barbell Bench Press"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 4))
        bench.tap()

        XCTAssertTrue(app.buttons["exercise-progress-metric-selector"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["exercise-progress-range-sixMonths"].exists)
        app.buttons["exercise-progress-range-allTime"].tap()
        XCTAssertEqual(app.buttons["exercise-progress-range-allTime"].value as? String, "Selected")
        XCTAssertTrue(app.otherElements["exercise-progress-chart"].exists)
        XCTAssertTrue(app.otherElements["exercise-progress-timeline"].exists)
    }

    @MainActor
    func testHistoryMainCardioSummaryOpensDetailWithoutHanging() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_HISTORY_MAIN_CARDIO"])

        let historyTab = app.buttons["History"].firstMatch
        XCTAssertTrue(historyTab.waitForExistence(timeout: 8))
        historyTab.tap()

        let historyCard = app.buttons["history-session-card"].firstMatch
        XCTAssertTrue(historyCard.waitForExistence(timeout: 8))
        XCTAssertTrue(historyCard.label.contains("Bench Press"))
        XCTAssertTrue(historyCard.label.contains("Bike"))
        XCTAssertFalse(historyCard.label.contains("Warm-up Walk"))
        XCTAssertFalse(historyCard.label.contains("Finisher Stairs"))
        historyCard.tap()

        XCTAssertTrue(app.staticTexts["Cardio Activities"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Bike"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.buttons["history-detail-save-changes-button"].waitForExistence(timeout: 4)
        )
    }

    @MainActor
    private func launchLocalApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ] + additionalArguments
        app.launch()

        let continueLocally = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
        continueLocally.tap()
        return app
    }

    @MainActor
    private func openExercisesTab(in app: XCUIApplication) {
        let tab = app.buttons["Exercises"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
    }
}
