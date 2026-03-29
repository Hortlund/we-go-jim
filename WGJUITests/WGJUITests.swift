import XCTest

final class WGJUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainTabNavigationSmoke() throws {
        let app = launchApp()

        tapTab("Profile", in: app)
        XCTAssertTrue(identifiedElement("profile-settings-tile", in: app).waitForExistence(timeout: 5))

        tapTab("History", in: app)
        XCTAssertTrue(app.buttons["history-calendar-button"].waitForExistence(timeout: 5))

        tapTab("Start Workout", in: app)
        XCTAssertTrue(app.buttons["start-workout-empty-button"].waitForExistence(timeout: 5))

        tapTab("Exercises", in: app)
        XCTAssertTrue(app.textFields["exercises-search-field"].waitForExistence(timeout: 5))

        tapTab("Bros", in: app)
        XCTAssertTrue(app.staticTexts["Bros"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExercisesSearchAndFilterSmoke() throws {
        let app = launchApp()

        tapTab("Exercises", in: app)

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        let sortButton = app.buttons["exercises-sort-button"]
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        sortButton.tap()

        XCTAssertTrue(app.buttons["exercises-body-part-filter"].exists)
        XCTAssertTrue(app.buttons["exercises-category-filter"].exists)
        XCTAssertTrue(searchField.value as? String == "bench")
    }

    @MainActor
    func testTemplateAndFolderAddFlow() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        app.buttons["start-workout-new-folder-button"].tap()
        let folderNameField = app.textFields["template-folder-name-field"]
        XCTAssertTrue(folderNameField.waitForExistence(timeout: 5))
        folderNameField.tap()
        folderNameField.typeText("UI Test Folder")
        app.buttons["template-folder-save-button"].tap()
        XCTAssertFalse(folderNameField.waitForExistence(timeout: 1))

        app.buttons["start-workout-new-template-button"].tap()
        let templateNameField = app.textFields["template-editor-name-field"]
        XCTAssertTrue(templateNameField.waitForExistence(timeout: 5))
        templateNameField.tap()
        templateNameField.typeText("UI Test Template")
        app.buttons["template-editor-save-button"].tap()
        XCTAssertTrue(app.staticTexts["UI Test Template"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsLegalSupportNavigation() throws {
        let app = launchApp()

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let supportTile = identifiedElement("settings-support-tile", in: app)
        XCTAssertTrue(supportTile.waitForExistence(timeout: 5))
        supportTile.tap()

        XCTAssertTrue(app.navigationBars["Support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Email Support"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProfileManagementSheetOpens() throws {
        let app = launchApp()

        tapTab("Profile", in: app)

        let manageButton = identifiedElement("profile-manage-button", in: app)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
        manageButton.tap()

        let nameField = identifiedElement("profile-display-name-field", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("profile-save-button", in: app).exists)
    }

    @MainActor
    func testActiveWorkoutStartMinimizeRestoreFlow() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkoutFinishShowsCelebrationBeforeHistory() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        let selectExerciseButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(selectExerciseButton.waitForExistence(timeout: 15))
        selectExerciseButton.tap()

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        finishButton.tap()

        let finishAndSaveButton = app.buttons["Finish and Save"]
        XCTAssertTrue(finishAndSaveButton.waitForExistence(timeout: 5))
        finishAndSaveButton.tap()

        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.buttons["history-calendar-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testActiveWorkoutRestTimerStartsOnSetCompletion() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        let selectExerciseButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(selectExerciseButton.waitForExistence(timeout: 15))
        selectExerciseButton.tap()

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        XCTAssertTrue(
            identifiedElement("active-workout-rest-timer", in: app).waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testActiveWorkoutUseLastFillsPreviousPerformance() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        let selectExerciseButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(selectExerciseButton.waitForExistence(timeout: 15))
        selectExerciseButton.tap()

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("100")

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        repsField.tap()
        repsField.typeText("8")

        let hideKeyboardButton = app.buttons["Hide"]
        if hideKeyboardButton.waitForExistence(timeout: 1) {
            hideKeyboardButton.tap()
        }

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        finishButton.tap()

        let finishAndSaveButton = app.buttons["Finish and Save"]
        XCTAssertTrue(finishAndSaveButton.waitForExistence(timeout: 5))
        finishAndSaveButton.tap()

        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        tapTab("Start Workout", in: app)

        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        XCTAssertTrue(selectExerciseButton.waitForExistence(timeout: 15))
        selectExerciseButton.tap()

        let useLastButton = identifiedElement("workout-set-0-use-last-button", in: app)
        XCTAssertTrue(useLastButton.waitForExistence(timeout: 5))
        useLastButton.tap()

        XCTAssertEqual(weightField.value as? String, "100")
        XCTAssertEqual(repsField.value as? String, "8")
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
        ]
        app.launch()
        authenticateIfNeeded(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    private func authenticateIfNeeded(_ app: XCUIApplication) {
        let continueLocally = app.buttons["Continue Locally"]
        if continueLocally.waitForExistence(timeout: 5) {
            continueLocally.tap()
        }
    }

    private func tapTab(_ name: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func identifiedElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
