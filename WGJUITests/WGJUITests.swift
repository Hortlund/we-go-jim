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
    func testTemplateImportAndExportControlsSmoke() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)
        XCTAssertTrue(identifiedElement("start-workout-import-template-button", in: app).waitForExistence(timeout: 5))

        app.buttons["start-workout-new-template-button"].tap()
        let templateNameField = app.textFields["template-editor-name-field"]
        XCTAssertTrue(templateNameField.waitForExistence(timeout: 5))
        templateNameField.tap()
        templateNameField.typeText("Smoke Export Template")
        app.buttons["template-editor-save-button"].tap()
        XCTAssertTrue(app.staticTexts["Smoke Export Template"].waitForExistence(timeout: 5))

        let actionsButton = identifiedElement("start-workout-template-actions-button", in: app)
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        XCTAssertTrue(identifiedElement("start-workout-template-export-button", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateEditFlowSmoke() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        app.buttons["start-workout-new-template-button"].tap()
        let templateNameField = app.textFields["template-editor-name-field"]
        XCTAssertTrue(templateNameField.waitForExistence(timeout: 5))
        templateNameField.tap()
        templateNameField.typeText("Editable Template")
        app.buttons["template-editor-save-button"].tap()
        XCTAssertTrue(app.staticTexts["Editable Template"].waitForExistence(timeout: 5))

        let actionsButton = identifiedElement("start-workout-template-actions-button", in: app)
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let editButton = identifiedElement("start-workout-template-edit-menu-button", in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(templateNameField.waitForExistence(timeout: 5))
        templateNameField.tap()
        templateNameField.typeText(" Updated")
        app.buttons["template-editor-save-button"].tap()

        XCTAssertTrue(app.staticTexts["Editable Template Updated"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateFileLaunchHookImportsAndShowsPreview() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Launch Hook Template",
                notes: "Imported from launch hook"
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Launch Hook Template"].waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Launch Hook Template"].waitForExistence(timeout: 5))
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

        let elapsedTimer = identifiedElement("active-workout-elapsed-timer", in: app)
        XCTAssertTrue(elapsedTimer.waitForExistence(timeout: 5))

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExerciseCatalogAddAttachesToMinimizedActiveWorkout() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        tapTab("Exercises", in: app)

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("bench")

        let addButton = identifiedElement("exercise-catalog-add-button", in: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()

        let hideKeyboardButton = app.buttons["Hide"]
        if hideKeyboardButton.waitForExistence(timeout: 1) {
            hideKeyboardButton.tap()
        }

        tapTab("Start Workout", in: app)

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        let benchExercise = identifiedElement("active-workout-exercise-seed-bench-press", in: app)
        XCTAssertTrue(benchExercise.waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("workout-set-0-weight-field", in: app).waitForExistence(timeout: 5))
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

        let finishConfirmationButton = app.buttons["Finish Anyway"].waitForExistence(timeout: 2)
            ? app.buttons["Finish Anyway"]
            : app.buttons["Finish and Save"]
        XCTAssertTrue(finishConfirmationButton.waitForExistence(timeout: 5))
        finishConfirmationButton.tap()

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
    func testActiveWorkoutCancelConfirmationKeepsActionsVisible() throws {
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

        let cancelButton = identifiedElement("active-workout-cancel-button", in: app)
        revealElement(cancelButton, in: app)
        XCTAssertTrue(cancelButton.isHittable)
        let elapsedTimer = identifiedElement("active-workout-elapsed-timer", in: app)
        revealElementAbove(elapsedTimer, target: cancelButton, in: app)
        cancelButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()

        let keepButton = app.buttons["Keep Workout"]
        let discardButton = app.buttons["Discard Workout"]
        XCTAssertTrue(keepButton.waitForExistence(timeout: 5))
        XCTAssertTrue(discardButton.waitForExistence(timeout: 5))
        XCTAssertTrue(keepButton.isHittable)
        XCTAssertTrue(discardButton.isHittable)
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

        let finishConfirmationButton = app.buttons["Finish Anyway"].waitForExistence(timeout: 2)
            ? app.buttons["Finish Anyway"]
            : app.buttons["Finish and Save"]
        XCTAssertTrue(finishConfirmationButton.waitForExistence(timeout: 5))
        finishConfirmationButton.tap()

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

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let useLastButton = identifiedElement("workout-set-0-use-last-button", in: app)
        XCTAssertTrue(useLastButton.waitForExistence(timeout: 5))
        useLastButton.tap()

        let reopenedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let reopenedRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertEqual(reopenedWeightField.value as? String, "100")
        XCTAssertEqual(reopenedRepsField.value as? String, "8")
    }

    @MainActor
    func testTemplateWorkoutFinishKeepTemplatePreservesOriginalStructure() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Keep Template Workout",
                notes: "UI test template",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-keep-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 100,
                                loadUnit: "kg",
                                restSeconds: 120,
                                isWarmup: true
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)
        addSetToCurrentExercise(in: app)
        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-keep-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        XCTAssertTrue(identifiedElement("workout-set-0-weight-field", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(identifiedElement("workout-set-1-weight-field", in: app).waitForExistence(timeout: 1))
    }

    @MainActor
    func testTemplateWorkoutFinishUpdateTemplateAppliesNewStructure() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Apply Template Workout",
                notes: "UI test template",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-apply-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 100,
                                loadUnit: "kg",
                                restSeconds: 120,
                                isWarmup: true
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)
        addSetToCurrentExercise(in: app)
        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-apply-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        XCTAssertTrue(identifiedElement("workout-set-1-weight-field", in: app).waitForExistence(timeout: 5))
    }

    private func launchApp(
        launchArguments extraLaunchArguments: [String] = [],
        launchEnvironment extraLaunchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
        ] + extraLaunchArguments
        app.launchEnvironment = extraLaunchEnvironment
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

    private func revealElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))

        var remainingSwipes = maxSwipes
        while !element.isHittable && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func revealElementAbove(
        _ blocker: XCUIElement,
        target: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) {
        guard blocker.waitForExistence(timeout: 2) else { return }

        var remainingSwipes = maxSwipes
        while target.frame.maxY > blocker.frame.minY && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func startPreviewedTemplateWorkout(in app: XCUIApplication) {
        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))

        let startButton = identifiedElement("template-preview-start-button", in: app)
        if startButton.waitForExistence(timeout: 2) {
            startButton.tap()
        } else {
            let labeledButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Start Workout"))
            let fallbackButton = labeledButtons
                .allElementsBoundByIndex
                .first(where: \.isHittable)
                ?? labeledButtons.element(boundBy: max(0, labeledButtons.count - 1))
            XCTAssertTrue(fallbackButton.waitForExistence(timeout: 5))
            fallbackButton.tap()
        }

        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
    }

    private func restartImportedTemplateWorkout(in app: XCUIApplication) {
        let startButton = app.buttons["Start"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()
        startPreviewedTemplateWorkout(in: app)
    }

    private func addSetToCurrentExercise(in app: XCUIApplication) {
        let addSetButton = app.buttons["Add Set"].firstMatch
        XCTAssertTrue(addSetButton.waitForExistence(timeout: 5))
        addSetButton.tap()
    }

    private func finishTemplateWorkout(in app: XCUIApplication) {
        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        finishButton.tap()

        let finishConfirmationButton = app.buttons["Finish Anyway"].waitForExistence(timeout: 2)
            ? app.buttons["Finish Anyway"]
            : app.buttons["Finish and Save"]
        XCTAssertTrue(finishConfirmationButton.waitForExistence(timeout: 5))
        finishConfirmationButton.tap()
    }

    private func confirmWorkoutCompletion(in app: XCUIApplication) {
        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
    }

    private func makeTemplateOpenPayloadBase64(
        name: String,
        notes: String,
        exercises: [[String: Any]] = []
    ) -> String {
        let payload: [String: Any] = [
            "formatVersion": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0)),
            "template": [
                "name": name,
                "notes": notes,
                "exercises": exercises,
            ],
        ]

        let data = try! JSONSerialization.data(withJSONObject: payload, options: [])
        return data.base64EncodedString()
    }

    private func templatePayloadExercise(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        sets: [[String: Any]]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "catalogExerciseUUID": catalogExerciseUUID,
            "exerciseNameSnapshot": exerciseNameSnapshot,
            "categorySnapshot": categorySnapshot,
            "muscleSummarySnapshot": muscleSummarySnapshot,
            "restSeconds": restSeconds,
            "sets": sets,
        ]

        payload["targetRepMin"] = targetRepMin
        payload["targetRepMax"] = targetRepMax
        return payload
    }

    private func templatePayloadSet(
        targetReps: Int?,
        targetWeight: Double?,
        loadUnit: String,
        restSeconds: Int,
        isWarmup: Bool,
        isLocked: Bool = false
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "loadUnit": loadUnit,
            "restSeconds": restSeconds,
            "isWarmup": isWarmup,
            "isLocked": isLocked,
        ]

        payload["targetReps"] = targetReps
        payload["targetWeight"] = targetWeight
        return payload
    }
}
