import XCTest

final class WGJUITests: XCTestCase {
    private enum LaunchMode {
        case iCloud
        case localInMemory

        var launchArguments: [String] {
            switch self {
            case .iCloud:
                return [
                    "UITEST_SKIP_SPLASH",
                    "UITEST_ENABLE_ICLOUD",
                ]
            case .localInMemory:
                return [
                    "UITEST_SKIP_SPLASH",
                    "UITEST_IN_MEMORY_STORE",
                ]
            }
        }
    }

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
    func testColdLaunchProfileAndBrosTabsRespondAfterSplash() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_IN_MEMORY_STORE",
            "UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH",
            "UITEST_FIRST_TAB_CONTENT_MOUNT_DELAY_MS=1500",
        ]
        app.launchEnvironment = [
            "UITEST_PROFILE_STARTUP_WARMUP_DELAY_MS": "2000",
            "UITEST_BROS_STARTUP_WARMUP_DELAY_MS": "2000",
            "UITEST_FIRST_TAB_CONTENT_MOUNT_DELAY_MS": "1500",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))

        tapTabWithoutWaitingForIdle("Profile", in: app)
        let profileSettingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(profileSettingsTile.waitForExistence(timeout: 6))

        tapTabWithoutWaitingForIdle("Bros", in: app)
        XCTAssertTrue(waitForAnyElement([
            identifiedElement("bros-loading-card", in: app),
            app.staticTexts["Bros unavailable"],
            app.staticTexts["Start a bro circle"],
            identifiedElement("bros-manage-circle-button", in: app),
        ], timeout: 6))
    }

    @MainActor
    func testExercisesSearchAndFilterSmoke() throws {
        let app = launchApp(mode: .localInMemory)

        tapTab("Exercises", in: app)

        let title = app.staticTexts["exercises-catalog-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(title.frame.minY, 20)

        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.maxY, searchField.frame.minY)
        XCTAssertTrue(identifiedElement("exercise-catalog-add-button", in: app).waitForExistence(timeout: 10))
        let createButton = app.buttons["exercises-create-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 2))
        XCTAssertTrue(createButton.isHittable)
        XCTAssertLessThan(app.buttons["exercises-category-filter"].frame.maxY, createButton.frame.minY)
        let listDragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
        let listDragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.16))
        listDragStart.press(forDuration: 0.05, thenDragTo: listDragEnd)
        listDragStart.press(forDuration: 0.05, thenDragTo: listDragEnd)
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        XCTAssertTrue(searchField.isHittable)
        XCTAssertGreaterThanOrEqual(searchField.frame.minY, 72)
        XCTAssertTrue(title.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["exercises-create-button"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["exercises-body-part-filter"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["exercises-category-filter"].waitForNonExistence(timeout: 2))

        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["exercises-create-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["exercises-body-part-filter"].exists)
        XCTAssertTrue(app.buttons["exercises-category-filter"].exists)
        let initialHideKeyboardButton = app.buttons["keyboard-hide-button"]
        XCTAssertTrue(initialHideKeyboardButton.exists)
        XCTAssertTrue(initialHideKeyboardButton.isHittable)
        initialHideKeyboardButton.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))

        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
        searchField.typeText("bench")
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        XCTAssertTrue(searchField.isHittable)
        XCTAssertGreaterThanOrEqual(searchField.frame.minY, 72)
        XCTAssertLessThanOrEqual(searchField.frame.maxY, app.keyboards.element.frame.minY - 12)
        XCTAssertLessThanOrEqual(searchField.frame.minY, app.frame.height * 0.45)

        let sortButton = app.buttons["exercises-sort-button"]
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        sortButton.tap()

        XCTAssertTrue(app.buttons["exercises-body-part-filter"].exists)
        XCTAssertTrue(app.buttons["exercises-category-filter"].exists)
        XCTAssertTrue(searchField.value as? String == "bench")

        searchField.tap()
        clearTextField(searchField, replacement: "zzzz-no-exercise")

        let clearFiltersButton = app.buttons["exercises-clear-filters-button"]
        XCTAssertTrue(clearFiltersButton.waitForExistence(timeout: 5))
        if app.keyboards.element.exists {
            let hideKeyboardButton = app.buttons["keyboard-hide-button"]
            XCTAssertTrue(hideKeyboardButton.waitForExistence(timeout: 2))
            hideKeyboardButton.tap()
            XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1))
        }
        clearFiltersButton.tap()
        XCTAssertFalse((searchField.value as? String) == "zzzz-no-exercise")
        XCTAssertFalse(clearFiltersButton.waitForExistence(timeout: 2))
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
    func testTemplateAndFolderExportControlsSmoke() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)
        XCTAssertTrue(identifiedElement("start-workout-import-template-button", in: app).waitForExistence(timeout: 5))

        app.buttons["start-workout-new-folder-button"].tap()
        let folderNameField = app.textFields["template-folder-name-field"]
        XCTAssertTrue(folderNameField.waitForExistence(timeout: 5))
        folderNameField.tap()
        folderNameField.typeText("Export Folder")
        app.buttons["template-folder-save-button"].tap()
        XCTAssertTrue(app.staticTexts["Export Folder"].waitForExistence(timeout: 5))

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
        identifiedElement("start-workout-template-export-button", in: app).tap()
        XCTAssertTrue(app.buttons["WGJ Template File"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["JSON"].exists)
        XCTAssertTrue(app.buttons["Text"].exists)
        app.buttons["Cancel"].tap()

        let folderActionsButton = identifiedElement("start-workout-folder-actions-button", in: app)
        XCTAssertTrue(folderActionsButton.waitForExistence(timeout: 5))
        folderActionsButton.tap()

        let folderExportButton = identifiedElement("start-workout-folder-export-button", in: app)
        XCTAssertTrue(folderExportButton.waitForExistence(timeout: 5))
        folderExportButton.tap()

        XCTAssertTrue(app.buttons["WGJ Template File"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["JSON"].exists)
        XCTAssertTrue(app.buttons["Text"].exists)
    }

    @MainActor
    func testTemplateEditFlowSmoke() throws {
        let app = launchApp(mode: .localInMemory)

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
    func testTemplateEditorSaveRefreshesPreviewRepRangeImmediately() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ], launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Immediate Range Template",
                notes: "Saved prescription changes should refresh locally.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-refresh-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 80,
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1x 6-8 reps"].waitForExistence(timeout: 5))

        let editButton = identifiedElement("template-preview-edit-button", in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()
        XCTAssertTrue(app.buttons["template-editor-save-button"].waitForExistence(timeout: 5))

        let expandButton = firstButton(endingWith: "-expand-button", in: app)
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5))
        expandButton.tap()

        let repMinField = firstElement(endingWith: "-rep-min-field", in: app)
        let repMaxField = firstElement(endingWith: "-rep-max-field", in: app)
        revealElement(repMinField, in: app)
        clearTextField(repMinField, replacement: "10")
        clearTextField(repMaxField, replacement: "12")

        app.buttons["template-editor-save-button"].tap()
        XCTAssertTrue(app.staticTexts["Immediate Range Template"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1x 6-8 reps"].waitForExistence(timeout: 1))

        let startButton = app.buttons["Start"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()
        XCTAssertTrue(identifiedElement("template-preview-sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1x 10-12 reps"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateEditorCardioAddAndRemoveSmoke() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        app.buttons["start-workout-new-template-button"].tap()
        let templateNameField = app.textFields["template-editor-name-field"]
        XCTAssertTrue(templateNameField.waitForExistence(timeout: 5))
        templateNameField.tap()
        templateNameField.typeText("Cardio Template")

        let preAddButton = app.buttons["template-editor-preWorkout-add-button"]
        XCTAssertTrue(preAddButton.waitForExistence(timeout: 5))
        preAddButton.tap()

        let firstPickerSelectButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(firstPickerSelectButton.waitForExistence(timeout: 15))
        firstPickerSelectButton.tap()

        XCTAssertTrue(identifiedElement("template-editor-preWorkout-card", in: app).waitForExistence(timeout: 5))

        let postAddButton = app.buttons["template-editor-postWorkout-add-button"]
        revealElement(postAddButton, in: app)
        XCTAssertTrue(postAddButton.isHittable)
        postAddButton.tap()

        let secondPickerSelectButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(secondPickerSelectButton.waitForExistence(timeout: 15))
        secondPickerSelectButton.tap()

        XCTAssertTrue(identifiedElement("template-editor-postWorkout-card", in: app).waitForExistence(timeout: 5))

        let preActionsButton = app.buttons["template-editor-preWorkout-actions-button"]
        revealElement(preActionsButton, in: app)
        XCTAssertTrue(preActionsButton.isHittable)
        preActionsButton.tap()
        app.buttons["Remove"].tap()

        XCTAssertTrue(app.buttons["template-editor-preWorkout-add-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateEditorMoveExerciseToPositionPersistsOrder() throws {
        let app = launchApp(mode: .localInMemory, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Template Reorder",
                notes: "Move the first exercise to the bottom.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-order-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-order-row",
                        exerciseNameSnapshot: "Barbell Row",
                        categorySnapshot: "Back",
                        muscleSummarySnapshot: "Lats",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 80, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-order-squat",
                        exerciseNameSnapshot: "Back Squat",
                        categorySnapshot: "Legs",
                        muscleSummarySnapshot: "Quads",
                        targetRepMin: 5,
                        targetRepMax: 8,
                        restSeconds: 180,
                        sets: [templatePayloadSet(targetReps: 5, targetWeight: 140, loadUnit: "kg", restSeconds: 180, isWarmup: false)]
                    ),
                ]
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        if !previewSheet.waitForExistence(timeout: 5) {
            tapTab("Start Workout", in: app)
        }
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        tapTab("Start Workout", in: app)

        let actionsButton = identifiedElement("start-workout-template-actions-button", in: app)
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let editButton = identifiedElement("start-workout-template-edit-menu-button", in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let benchActionsButton = app.buttons["template-editor-exercise-template-order-bench-actions-button"]
        XCTAssertTrue(benchActionsButton.waitForExistence(timeout: 5))
        benchActionsButton.tap()

        XCTAssertTrue(app.buttons["Move to position"].waitForExistence(timeout: 5))
        app.buttons["Move to position"].tap()

        let reorderSheet = identifiedElement("template-editor-reorder-sheet", in: app)
        XCTAssertTrue(reorderSheet.waitForExistence(timeout: 5))
        app.buttons["template-editor-reorder-position-3"].tap()

        app.buttons["template-editor-save-button"].tap()
        XCTAssertTrue(app.staticTexts["Template Reorder"].waitForExistence(timeout: 5))

        restartImportedTemplateWorkout(in: app)

        let row = identifiedElement("active-workout-exercise-template-order-row", in: app)
        let squat = identifiedElement("active-workout-exercise-template-order-squat", in: app)
        let bench = identifiedElement("active-workout-exercise-template-order-bench", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        XCTAssertTrue(bench.waitForExistence(timeout: 5))

        XCTAssertLessThan(row.frame.minY, squat.frame.minY)
        XCTAssertLessThan(squat.frame.minY, bench.frame.minY)
    }

    @MainActor
    func testTemplateEditorLongScrollKeepsLowerExerciseInteractive() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Template Long Scroll",
                notes: "Stress the editor scroll path.",
                exercises: (1...10).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-editor-scroll-\(index)",
                        exerciseNameSnapshot: "Template Scroll Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 8,
                                targetWeight: Double(40 + index * 5),
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    )
                }
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        if !previewSheet.waitForExistence(timeout: 5) {
            tapTab("Start Workout", in: app)
        }
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        tapTab("Start Workout", in: app)

        let actionsButton = identifiedElement("start-workout-template-actions-button", in: app)
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let editButton = identifiedElement("start-workout-template-edit-menu-button", in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let lastExercise = identifiedElement("template-editor-exercise-template-editor-scroll-10", in: app)
        let lastExpandButton = identifiedElement(
            "template-editor-exercise-template-editor-scroll-10-expand-button",
            in: app
        )

        var remainingSwipes = 14
        while !lastExercise.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }

        revealElement(lastExercise, in: app, maxSwipes: 6)
        XCTAssertTrue(lastExercise.isHittable)
        XCTAssertTrue(lastExpandButton.waitForExistence(timeout: 5))
        lastExpandButton.tap()

        let notesField = identifiedElement("template-editor-exercise-template-editor-scroll-10-notes-field", in: app)
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        revealElement(notesField, in: app, maxSwipes: 3)
        XCTAssertTrue(notesField.isHittable)
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
    func testJsonTemplateFileLaunchHookImportsAndShowsPreview() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "JSON Launch Hook Template",
                notes: "Imported from JSON launch hook"
            ),
            "UITEST_TEMPLATE_OPEN_FILE_EXTENSION": "json",
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["JSON Launch Hook Template"].waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["JSON Launch Hook Template"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplatePreviewShowsAllExercisesByDefault() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Full Preview Template",
                notes: "Make the whole session visible up front.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-2",
                        exerciseNameSnapshot: "Incline Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Upper chest",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 80, loadUnit: "kg", restSeconds: 90, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-3",
                        exerciseNameSnapshot: "Shoulder Press",
                        categorySnapshot: "Shoulders",
                        muscleSummarySnapshot: "Front delts",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 50, loadUnit: "kg", restSeconds: 90, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-4",
                        exerciseNameSnapshot: "Cable Fly",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 12,
                        targetRepMax: 15,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 20, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-5",
                        exerciseNameSnapshot: "Lateral Raise",
                        categorySnapshot: "Shoulders",
                        muscleSummarySnapshot: "Side delts",
                        targetRepMin: 12,
                        targetRepMax: 15,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 12, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "full-preview-6",
                        exerciseNameSnapshot: "Triceps Pushdown",
                        categorySnapshot: "Arms",
                        muscleSummarySnapshot: "Triceps",
                        targetRepMin: 10,
                        targetRepMax: 12,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 10, targetWeight: 35, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                ]
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("template-preview-exercise-row-6", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Triceps Pushdown"].exists)
    }

    @MainActor
    func testTemplatePreviewShowsCardioSectionsFromLaunchPayload() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Cardio Preview Template",
                notes: "Warm up and cool down.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "preview-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "preview-treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "preview-bench-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        XCTAssertTrue(identifiedElement("template-preview-sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("template-preview-preWorkout-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("template-preview-postWorkout-card", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplatePreviewScrollsFromSummaryWhenCardioExistsOnBothSides() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Scrollable Cardio Preview",
                notes: "Scroll from the summary card to reach the rest of the workout.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "scroll-preview-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "scroll-preview-treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-2",
                        exerciseNameSnapshot: "Incline Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Upper chest",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 80, loadUnit: "kg", restSeconds: 90, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-3",
                        exerciseNameSnapshot: "Shoulder Press",
                        categorySnapshot: "Shoulders",
                        muscleSummarySnapshot: "Front delts",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 50, loadUnit: "kg", restSeconds: 90, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-4",
                        exerciseNameSnapshot: "Cable Fly",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 12,
                        targetRepMax: 15,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 20, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-5",
                        exerciseNameSnapshot: "Lateral Raise",
                        categorySnapshot: "Shoulders",
                        muscleSummarySnapshot: "Side delts",
                        targetRepMin: 12,
                        targetRepMax: 15,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 12, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-preview-6",
                        exerciseNameSnapshot: "Triceps Pushdown",
                        categorySnapshot: "Arms",
                        muscleSummarySnapshot: "Triceps",
                        targetRepMin: 10,
                        targetRepMax: 12,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 10, targetWeight: 35, loadUnit: "kg", restSeconds: 60, isWarmup: false)]
                    ),
                ]
            ),
        ])

        let summaryCard = identifiedElement("template-preview-summary-card", in: app)
        let startButton = identifiedElement("template-preview-start-button", in: app)

        XCTAssertTrue(summaryCard.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertFalse(startButton.isHittable)

        let screenOrigin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let dragX = app.frame.midX
        let dragStartY = summaryCard.frame.maxY + 120
        let dragEndY = summaryCard.frame.minY + 40

        var remainingDrags = 6
        while !startButton.isHittable && remainingDrags > 0 {
            let dragStart = screenOrigin.withOffset(CGVector(dx: dragX, dy: dragStartY))
            let dragEnd = screenOrigin.withOffset(CGVector(dx: dragX, dy: dragEndY))
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
            remainingDrags -= 1
        }

        XCTAssertTrue(startButton.isHittable)
    }

    @MainActor
    func testTemplatePreviewShowsExerciseOptionsForMultiComponentSlot() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Multi Curl Template",
                notes: "Rotate the curl variation.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "ui-preview-reverse-curl",
                        exerciseNameSnapshot: "Reverse Curl",
                        categorySnapshot: "Arms",
                        muscleSummarySnapshot: "Forearms",
                        targetRepMin: 10,
                        targetRepMax: 12,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 20, loadUnit: "kg", restSeconds: 60, isWarmup: false)],
                        components: [
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-preview-reverse-curl",
                                exerciseNameSnapshot: "Reverse Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-preview-wrist-curl",
                                exerciseNameSnapshot: "Wrist Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                        ]
                    ),
                ]
            ),
        ])

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reverse Curl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Options: Reverse Curl, Wrist Curl"].waitForExistence(timeout: 5))
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
    func testProfileCoachBriefOpensAnalysisSheet() throws {
        let app = launchApp()

        tapTab("Profile", in: app)

        let coachWidgetButton = identifiedElement("profile-coach-brief-widget-button", in: app)
        XCTAssertTrue(coachWidgetButton.waitForExistence(timeout: 10))
        coachWidgetButton.tap()

        let analysisSheet = identifiedElement("profile-coach-analysis-sheet", in: app)
        XCTAssertTrue(analysisSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("profile-coach-follow-up-whatChanged", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testProfileCoachWidgetCanBeRemovedAndRestoredFromWidgetManager() throws {
        let app = launchApp()

        tapTab("Profile", in: app)

        let manageButton = identifiedElement("profile-dashboard-manage-button", in: app)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
        manageButton.tap()

        let removeButton = identifiedElement("profile-widget-remove-coachBrief", in: app)
        revealLazyElement(removeButton, in: app)
        XCTAssertTrue(removeButton.isHittable)
        removeButton.tap()

        let addButton = identifiedElement("profile-widget-add-coachBrief", in: app)
        revealLazyElement(addButton, in: app)
        XCTAssertTrue(addButton.isHittable)
        addButton.tap()

        app.buttons["Done"].tap()

        let coachWidgetButton = identifiedElement("profile-coach-brief-widget-button", in: app)
        XCTAssertTrue(coachWidgetButton.waitForExistence(timeout: 10))
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
    func testActiveWorkoutHomeReturnKeepsTypedNotesAndPresentation() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Home Return Workout",
                notes: "Resume after backgrounding.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "active-home-return-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let notesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText(" Home")
        let editedNotes = notesField.value as? String

        XCUIDevice.shared.press(.home)
        app.activate()

        let reopenedNotesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(reopenedNotesField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedNotesField.value as? String, editedNotes)
    }

    @MainActor
    func testActiveWorkoutHomeReturnKeepsTypedSetValuesInteractive() throws {
        let app = launchApp(mode: .localInMemory, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Home Return Set Workout",
                notes: "Resume after backgrounding with typed set values.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "active-home-return-set-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        revealElement(weightField, in: app)
        weightField.tap()
        if !app.keyboards.element.waitForExistence(timeout: 1) {
            weightField.tap()
        }
        weightField.typeText("95")

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        revealElement(repsField, in: app)
        repsField.tap()
        if !app.keyboards.element.waitForExistence(timeout: 1) {
            repsField.tap()
        }
        repsField.typeText("7")

        XCUIDevice.shared.press(.home)
        app.activate()

        let reopenedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let reopenedRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(reopenedWeightField.waitForExistence(timeout: 5))
        XCTAssertTrue(reopenedRepsField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedWeightField.value as? String, "95")
        XCTAssertEqual(reopenedRepsField.value as? String, "7")
        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))

        reopenedWeightField.tap()
        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        let hideKeyboardButton = app.buttons["keyboard-hide-button"]
        XCTAssertTrue(hideKeyboardButton.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(hideKeyboardButton.frame.maxY, keyboard.frame.minY - 6)
        XCTAssertGreaterThanOrEqual(hideKeyboardButton.frame.minY, keyboard.frame.minY - 96)
        XCTAssertFalse(identifiedElement("active-workout-elapsed-timer", in: app).exists)
    }

    @MainActor
    func testActiveWorkoutBackgroundRelaunchResumesStartedWorkoutAndDiscardRemovesSnapshot() throws {
        var app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ], launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Relaunch Resume Workout",
                notes: "Lifecycle snapshot smoke.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "active-relaunch-resume-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = LaunchMode.localInMemory.launchArguments
        app.launch()
        authenticateIfNeeded(app, mode: .localInMemory)

        tapTab("Start Workout", in: app)
        let restoredStrip = identifiedElement("active-workout-strip", in: app)
        if restoredStrip.waitForExistence(timeout: 5) {
            restoredStrip.tap()
        }
        expandFirstActiveWorkoutExerciseIfNeeded(in: app)

        let restoredWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let restoredRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(restoredWeightField.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredRepsField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))

        discardCurrentWorkout(in: app)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = LaunchMode.localInMemory.launchArguments
        app.launch()
        authenticateIfNeeded(app, mode: .localInMemory)

        tapTab("Start Workout", in: app)
        XCTAssertFalse(identifiedElement("active-workout-strip", in: app).waitForExistence(timeout: 2))
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testActiveWorkoutGuidanceBadgeExpandsCoachTip() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Guidance Badge Workout",
                notes: "Smoke the coach guidance badge.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "ui-guidance-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest, Triceps",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 100,
                                loadUnit: "kg",
                                restSeconds: 120,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let badgeButton = identifiedElement(
            "active-workout-exercise-ui-guidance-bench-guidance-badge-button",
            in: app
        )
        let detail = identifiedElement(
            "active-workout-exercise-ui-guidance-bench-guidance-detail",
            in: app
        )

        XCTAssertTrue(badgeButton.waitForExistence(timeout: 5))
        XCTAssertFalse(detail.exists)

        badgeButton.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        badgeButton.tap()
        XCTAssertTrue(waitForElementToDisappear(detail, timeout: 5))
    }

    @MainActor
    func testActiveWorkoutRestoreKeepsScrolledExerciseVisibleAfterMinimize() throws {
        let app = launchApp(mode: .localInMemory, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Scroll Restore Workout",
                notes: "Minimize and reopen should keep the current position.",
                exercises: (1...10).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "scroll-restore-\(index)",
                        exerciseNameSnapshot: "Scroll Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 8,
                                targetWeight: Double(40 + index * 5),
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    )
                }
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let laterExercise = identifiedElement("active-workout-exercise-scroll-restore-10", in: app)
        let laterExerciseActions = identifiedElement(
            "active-workout-exercise-scroll-restore-10-actions-button",
            in: app
        )
        revealLazyElement(laterExerciseActions, in: app, maxSwipes: 12)
        XCTAssertTrue(laterExercise.waitForExistence(timeout: 5))
        XCTAssertTrue(laterExerciseActions.waitForExistence(timeout: 5))
        XCTAssertTrue(laterExerciseActions.isHittable)

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        XCTAssertTrue(laterExercise.waitForExistence(timeout: 5))
        XCTAssertTrue(laterExerciseActions.waitForExistence(timeout: 5))
        revealElement(laterExerciseActions, in: app)
        XCTAssertTrue(laterExerciseActions.isHittable)
        XCTAssertFalse(identifiedElement("active-workout-exercise-scroll-restore-1-actions-button", in: app).isHittable)
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
    func testStartWorkoutTemplateActionsScrollAboveMinimizedActiveWorkoutStrip() throws {
        let templateName = "Strip Clearance Template"
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: templateName,
                notes: "Ensure minimized strip does not cover template actions.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))

        let editButton = identifiedElement(
            startWorkoutTemplateInlineEditButtonID(for: templateName),
            in: app
        )
        revealElementAbove(strip, target: editButton, in: app, maxSwipes: 8)

        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        XCTAssertTrue(editButton.isHittable)
        XCTAssertLessThan(editButton.frame.maxY, strip.frame.minY)
    }

    @MainActor
    func testEditingSameTemplateWhileWorkoutIsMinimizedCanScrollBottomWithoutCrash() throws {
        let templateName = "Active Template Scroll Crash"
        let app = launchApp(mode: .localInMemory, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: templateName,
                notes: "Scroll the editor while the same workout stays active.",
                exercises: (1...11).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "active-template-scroll-\(index)",
                        exerciseNameSnapshot: "Active Template Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 8,
                                targetWeight: Double(40 + index * 5),
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    )
                }
            ),
        ])

        openTemplateEditorFromMinimizedActiveWorkout(templateName: templateName, in: app)
        assertTemplateEditorBottomExerciseRemainsInteractive(
            catalogExerciseUUID: "active-template-scroll-11",
            in: app
        )
    }

    @MainActor
    func testCloudBackedEditingSameTemplateWhileWorkoutIsMinimizedCanScrollBottomWithoutCrash() throws {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let finalExerciseUUID = "icloud-template-scroll-\(suffix)-11"
        let templateName = "iCloud Active Template Scroll \(suffix)"

        let app = launchApp(mode: .iCloud, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: templateName,
                notes: "Scroll the cloud-backed editor while the same workout stays active.",
                exercises: (1...11).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "icloud-template-scroll-\(suffix)-\(index)",
                        exerciseNameSnapshot: "iCloud Active Template Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 8,
                                targetWeight: Double(40 + index * 5),
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    )
                }
            ),
        ])

        openTemplateEditorFromMinimizedActiveWorkout(templateName: templateName, in: app)
        assertTemplateEditorBottomExerciseRemainsInteractive(
            catalogExerciseUUID: finalExerciseUUID,
            in: app
        )
    }

    @MainActor
    func testEditingLegacyTemplateWithoutStoredSetsWhileWorkoutIsMinimizedDoesNotCrash() throws {
        let templateName = "Legacy Empty Set Template"
        let app = launchApp(mode: .localInMemory, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: templateName,
                notes: "Opening the editor should stay read-only until save.",
                exercises: (1...11).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "legacy-template-scroll-\(index)",
                        exerciseNameSnapshot: "Legacy Template Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: []
                    )
                }
            ),
        ])

        openTemplateEditorFromMinimizedActiveWorkout(templateName: templateName, in: app)
        assertTemplateEditorBottomExerciseRemainsInteractive(
            catalogExerciseUUID: "legacy-template-scroll-11",
            in: app
        )
    }

    @MainActor
    func testCloudBackedEditingLegacyTemplateWithoutStoredSetsWhileWorkoutIsMinimizedDoesNotCrash() throws {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let finalExerciseUUID = "icloud-legacy-template-scroll-\(suffix)-11"
        let templateName = "iCloud Legacy Empty Set Template \(suffix)"

        let app = launchApp(mode: .iCloud, launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: templateName,
                notes: "Opening the cloud-backed editor should stay stable before save.",
                exercises: (1...11).map { index in
                    templatePayloadExercise(
                        catalogExerciseUUID: "icloud-legacy-template-scroll-\(suffix)-\(index)",
                        exerciseNameSnapshot: "iCloud Legacy Template Exercise \(index)",
                        categorySnapshot: "Strength",
                        muscleSummarySnapshot: "Full Body",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: []
                    )
                }
            ),
        ])

        openTemplateEditorFromMinimizedActiveWorkout(templateName: templateName, in: app)
        assertTemplateEditorBottomExerciseRemainsInteractive(
            catalogExerciseUUID: finalExerciseUUID,
            in: app
        )
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
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.buttons["history-calendar-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkoutCompletionSummaryHeroCardRetriggersCelebration() throws {
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
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

        let heroCard = identifiedElement("workout-completion-hero-card", in: app)
        XCTAssertTrue(heroCard.waitForExistence(timeout: 5))
        XCTAssertEqual(heroCard.value as? String, "Celebration burst 1")

        heroCard.tap()

        let celebrationValuePredicate = NSPredicate(
            format: "value == %@",
            "Celebration burst 2"
        )
        let expectation = XCTNSPredicateExpectation(predicate: celebrationValuePredicate, object: heroCard)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.buttons["history-calendar-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletedWorkoutDetailEditAndSaveSmoke() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ])

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let emptyAddExerciseButton = identifiedElement("active-workout-empty-add-exercise-button", in: app)
        XCTAssertTrue(emptyAddExerciseButton.waitForExistence(timeout: 5))
        emptyAddExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        let workoutCard = identifiedElement("history-session-card", in: app)
        XCTAssertTrue(workoutCard.waitForExistence(timeout: 10))
        workoutCard.tap()
        XCTAssertTrue(identifiedElement("history-detail-duration-pill", in: app).waitForExistence(timeout: 5))

        let expandButton = firstButton(endingWith: "-expand-button", in: app)
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5))
        expandButton.tap()

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("120")

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        repsField.tap()
        repsField.typeText("6")

        let hideKeyboardButton = app.buttons["Hide"]
        if hideKeyboardButton.waitForExistence(timeout: 1) {
            hideKeyboardButton.tap()
        }

        app.swipeUp()

        let saveChangesButton = identifiedElement("history-detail-save-changes-button", in: app)
        revealElement(saveChangesButton, in: app)
        XCTAssertTrue(saveChangesButton.waitForExistence(timeout: 5))
        saveChangesButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(identifiedElement("history-detail-duration-pill", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletedWorkoutDetailShowsDurationPill() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ])

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let emptyAddExerciseButton = identifiedElement("active-workout-empty-add-exercise-button", in: app)
        XCTAssertTrue(emptyAddExerciseButton.waitForExistence(timeout: 5))
        emptyAddExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        let workoutCard = identifiedElement("history-session-card", in: app)
        XCTAssertTrue(workoutCard.waitForExistence(timeout: 10))
        workoutCard.tap()
        XCTAssertTrue(identifiedElement("history-detail-duration-pill", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testHiddenWorkoutCanBeDeletedFromHistory() throws {
        let app = launchApp()

        tapTab("Start Workout", in: app)

        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let emptyAddExerciseButton = identifiedElement("active-workout-empty-add-exercise-button", in: app)
        XCTAssertTrue(emptyAddExerciseButton.waitForExistence(timeout: 5))
        emptyAddExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        let workoutCard = identifiedElement("history-session-card", in: app)
        XCTAssertTrue(workoutCard.waitForExistence(timeout: 10))
        workoutCard.tap()

        let hideButton = app.buttons["Hide"]
        XCTAssertTrue(hideButton.waitForExistence(timeout: 5))
        hideButton.tap()

        let hideWorkoutButton = app.buttons["Hide Workout"]
        XCTAssertTrue(hideWorkoutButton.waitForExistence(timeout: 5))
        hideWorkoutButton.tap()

        XCTAssertTrue(app.buttons["history-calendar-button"].waitForExistence(timeout: 5))

        let hiddenButton = app.buttons["history-hidden-button"]
        XCTAssertTrue(hiddenButton.waitForExistence(timeout: 5))
        hiddenButton.tap()

        let hiddenCard = identifiedElement("history-hidden-session-card", in: app)
        XCTAssertTrue(hiddenCard.waitForExistence(timeout: 5))

        let deleteWorkoutButton = app.buttons["Delete Permanently"]
        XCTAssertTrue(deleteWorkoutButton.waitForExistence(timeout: 5))
        deleteWorkoutButton.tap()

        let confirmDeleteButton = app.buttons["Delete Workout"]
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 5))
        confirmDeleteButton.tap()

        XCTAssertTrue(app.staticTexts["No hidden workouts"].waitForExistence(timeout: 5))
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
        expandFirstActiveWorkoutExerciseIfNeeded(in: app)

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
    func testActiveWorkoutRestTimerExpiryOnForegroundKeepsWorkoutInteractive() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ], launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Foreground Timer Workout",
                notes: "Timer should expire without blocking foreground.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "foreground-timer-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 1,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 100,
                                loadUnit: "kg",
                                restSeconds: 1,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let completeSetButton = identifiedElement("workout-set-0-completion-button", in: app)
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        revealElement(completeSetButton, in: app)
        completeSetButton.tap()

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("active-workout-elapsed-timer", in: app).waitForExistence(timeout: 5))

        app.buttons["active-workout-finish-button"].tap()
        XCTAssertTrue(
            identifiedElement("active-workout-finish-confirmation-title", in: app).waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testTemplateExerciseRestOverridesStaleSetRestInActiveWorkout() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ], launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Canonical Rest Workout",
                notes: "Exercise rest should beat stale set rest payloads.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "canonical-rest-lateral-raise",
                        exerciseNameSnapshot: "Dumbbell Lateral Raise",
                        categorySnapshot: "Shoulders",
                        muscleSummarySnapshot: "Delts",
                        targetRepMin: 8,
                        targetRepMax: 12,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 12,
                                targetWeight: 8,
                                loadUnit: "kg",
                                restSeconds: 120,
                                isWarmup: true
                            ),
                            templatePayloadSet(
                                targetReps: 12,
                                targetWeight: 10,
                                loadUnit: "kg",
                                restSeconds: 120,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let completeSetButton = identifiedElement("workout-set-0-completion-button", in: app)
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        revealElement(completeSetButton, in: app)
        XCTAssertEqual(completeSetButton.label, "Complete Set + Rest 1:30")
        XCTAssertFalse(app.buttons["Complete Set + Rest 2:00"].exists)

        completeSetButton.tap()

        let restTimer = identifiedElement("active-workout-rest-timer", in: app)
        XCTAssertTrue(restTimer.waitForExistence(timeout: 5))
        XCTAssertTrue(restTimer.label.contains("1:"))
        XCTAssertFalse(restTimer.label.contains("2:"))
    }

    @MainActor
    func testActiveWorkoutManualExpansionAfterPreCardioAndCompletion() throws {
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ], launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Manual Expansion Workout",
                notes: "Completion should not open or jump cards.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "manual-expansion-bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "manual-expansion-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 6,
                                targetWeight: 80,
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "manual-expansion-row",
                        exerciseNameSnapshot: "Cable Row",
                        categorySnapshot: "Back",
                        muscleSummarySnapshot: "Back",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 90,
                        sets: [
                            templatePayloadSet(
                                targetReps: 8,
                                targetWeight: 60,
                                loadUnit: "kg",
                                restSeconds: 90,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app, expandFirstExercise: false)

        XCTAssertFalse(identifiedElement("workout-set-0-completion-button", in: app).waitForExistence(timeout: 1))

        let preToggle = app.buttons["Complete Pre Cardio"]
        XCTAssertTrue(preToggle.waitForExistence(timeout: 5))
        preToggle.tap()
        XCTAssertFalse(identifiedElement("workout-set-0-completion-button", in: app).waitForExistence(timeout: 1))

        expandFirstActiveWorkoutExerciseIfNeeded(in: app, require: true, maxSwipes: 8)

        let completeSetButton = identifiedElement("workout-set-0-completion-button", in: app)
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        XCTAssertEqual(activeWorkoutSetCompletionButtonCount(in: app), 1)
        completeSetButton.tap()

        XCTAssertTrue(identifiedElement("workout-set-0-weight-field", in: app).waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(activeWorkoutSetCompletionButtonCount(in: app), 1)
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
        let app = launchApp(mode: .localInMemory, launchArguments: [
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
        ])

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
        expandFirstActiveWorkoutExerciseIfNeeded(in: app, require: true)

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        revealElement(weightField, in: app)
        weightField.tap()
        if !app.keyboards.element.waitForExistence(timeout: 1) {
            weightField.tap()
        }
        weightField.typeText("100")

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        revealElement(repsField, in: app)
        repsField.tap()
        if !app.keyboards.element.waitForExistence(timeout: 1) {
            repsField.tap()
        }
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
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

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
        expandFirstActiveWorkoutExerciseIfNeeded(in: app, require: true)

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let useLastButton = identifiedElement("workout-set-0-use-last-button", in: app)
        XCTAssertTrue(useLastButton.waitForExistence(timeout: 5))
        useLastButton.tap()

        let weightActual = identifiedElement("workout-set-0-weight-actual", in: app)
        let repsActual = identifiedElement("workout-set-0-reps-actual", in: app)
        let reopenedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let reopenedRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(waitForElementToDisappear(weightGhost, timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(repsGhost, timeout: 5))
        XCTAssertTrue(weightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(repsActual.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Previous 100 kg x 8"].exists)
        XCTAssertEqual(reopenedWeightField.value as? String, "100")
        XCTAssertEqual(reopenedRepsField.value as? String, "8")
    }

    @MainActor
    func testBozarModeCompletesEmptySetWithoutPreviousPerformance() throws {
        let app = launchApp()

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

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

        XCTAssertFalse(app.staticTexts["No previous log for this slot."].exists)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBozarModeFillsPreviousPerformanceWhenCompletingSet() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Bench Template",
                notes: "Seed previous bench performance for Bozar mode.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        finishButton.tap()

        let finishConfirmationButton = app.buttons["Finish Anyway"].waitForExistence(timeout: 2)
            ? app.buttons["Finish Anyway"]
            : app.buttons["Finish and Save"]
        XCTAssertTrue(finishConfirmationButton.waitForExistence(timeout: 5))
        finishConfirmationButton.tap()

        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

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

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let secondCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(secondCompleteSetButton.waitForExistence(timeout: 5))
        secondCompleteSetButton.tap()

        let weightActual = identifiedElement("workout-set-0-weight-actual", in: app)
        let repsActual = identifiedElement("workout-set-0-reps-actual", in: app)
        let completedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let completedRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(waitForElementToDisappear(weightGhost, timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(repsGhost, timeout: 5))
        XCTAssertTrue(weightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(repsActual.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Previous 100 kg x 8"].exists)
        XCTAssertEqual(completedWeightField.value as? String, "100")
        XCTAssertEqual(completedRepsField.value as? String, "8")
        XCTAssertTrue(
            waitForElementToDisappear(
                identifiedElement("workout-set-0-use-last-button", in: app),
                timeout: 5
            )
        )
        sleep(1)
        XCTAssertTrue(weightActual.exists)
        XCTAssertTrue(repsActual.exists)
        XCTAssertFalse(identifiedElement("workout-set-0-weight-ghost", in: app).exists)
        XCTAssertFalse(identifiedElement("workout-set-0-reps-ghost", in: app).exists)
        XCTAssertFalse(identifiedElement("workout-set-0-use-last-button", in: app).exists)
        XCTAssertEqual(completedWeightField.value as? String, "100")
        XCTAssertEqual(completedRepsField.value as? String, "8")
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBozarModeKeepsFocusedManualInputWhenCompletingSet() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Focus Template",
                notes: "Seed previous bench performance for focused-field Bozar completion.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        revealElement(weightField, in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("95")

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        repsField.tap()
        repsField.typeText("6")

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        let weightActual = identifiedElement("workout-set-0-weight-actual", in: app)
        let repsActual = identifiedElement("workout-set-0-reps-actual", in: app)
        XCTAssertTrue(waitForElementToDisappear(weightGhost, timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(repsGhost, timeout: 5))
        XCTAssertTrue(weightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(repsActual.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Previous 100 kg x 8"].exists)
        XCTAssertEqual(weightField.value as? String, "95")
        XCTAssertEqual(repsField.value as? String, "6")
        XCTAssertTrue(
            waitForElementToDisappear(
                identifiedElement("workout-set-0-use-last-button", in: app),
                timeout: 5
            )
        )
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBozarModeKeepsManualWeightAndBackfillsMissingRepsWhenCompletingSet() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Partial Weight Template",
                notes: "Seed previous bench performance for partial Bozar completion.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        revealElement(weightField, in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("95")

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        let weightActual = identifiedElement("workout-set-0-weight-actual", in: app)
        let repsActual = identifiedElement("workout-set-0-reps-actual", in: app)
        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(waitForElementToDisappear(weightGhost, timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(repsGhost, timeout: 5))
        XCTAssertTrue(weightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(repsActual.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Previous 100 kg x 8"].exists)
        XCTAssertEqual(weightField.value as? String, "95")
        XCTAssertEqual(repsField.value as? String, "8")
        XCTAssertTrue(
            waitForElementToDisappear(
                identifiedElement("workout-set-0-use-last-button", in: app),
                timeout: 5
            )
        )
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBozarModeKeepsOtherMetricGhostVisibleWhileTypingWeight() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Ghost Template",
                notes: "Seed previous bench performance for partial ghost visibility.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        revealElement(weightField, in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        weightField.typeText("95")

        XCTAssertTrue(waitForElementToDisappear(weightGhost, timeout: 5))
        XCTAssertTrue(repsGhost.exists)
    }

    @MainActor
    func testBozarModeKeepsOtherMetricGhostVisibleWhileTypingReps() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Reverse Ghost Template",
                notes: "Seed previous bench performance for reverse partial ghost visibility.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()
        pickExercise(named: "bench", in: app)

        let weightGhost = identifiedElement("workout-set-0-weight-ghost", in: app)
        let repsGhost = identifiedElement("workout-set-0-reps-ghost", in: app)
        XCTAssertTrue(weightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(repsGhost.waitForExistence(timeout: 5))

        let repsField = identifiedElement("workout-set-0-reps-field", in: app)
        revealElement(repsField, in: app)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        repsField.tap()
        repsField.typeText("6")

        XCTAssertTrue(waitForElementToDisappear(repsGhost, timeout: 5))
        XCTAssertTrue(weightGhost.exists)
    }

    @MainActor
    func testBozarModeSecondSetCompletionClearsHintUI() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Multi-Set Template",
                notes: "Seed previous bench performance for later-set Bozar completion.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

        tapTab("Start Workout", in: app)
        let startButton = app.buttons["start-workout-empty-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let addExerciseButton = app.buttons["active-workout-empty-add-exercise-button"]
        XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 5))
        addExerciseButton.tap()
        pickExercise(named: "bench", in: app)
        addSetToCurrentExercise(in: app)

        let secondWeightGhost = identifiedElement("workout-set-1-weight-ghost", in: app)
        let secondRepsGhost = identifiedElement("workout-set-1-reps-ghost", in: app)
        let secondUseLastButton = identifiedElement("workout-set-1-use-last-button", in: app)
        revealElement(secondWeightGhost, in: app)
        XCTAssertTrue(secondWeightGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(secondRepsGhost.waitForExistence(timeout: 5))
        XCTAssertTrue(secondUseLastButton.waitForExistence(timeout: 5))

        let completeSetButtons = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        )
        let secondCompleteSetButton = completeSetButtons.element(boundBy: 1)
        revealElement(secondCompleteSetButton, in: app)
        XCTAssertTrue(secondCompleteSetButton.waitForExistence(timeout: 5))
        secondCompleteSetButton.tap()

        let secondWeightActual = identifiedElement("workout-set-1-weight-actual", in: app)
        let secondRepsActual = identifiedElement("workout-set-1-reps-actual", in: app)
        let secondWeightField = identifiedElement("workout-set-1-weight-field", in: app)
        let secondRepsField = identifiedElement("workout-set-1-reps-field", in: app)
        XCTAssertTrue(waitForElementToDisappear(secondWeightGhost, timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(secondRepsGhost, timeout: 5))
        XCTAssertTrue(secondWeightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(secondRepsActual.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(secondUseLastButton, timeout: 5))
        XCTAssertEqual(secondWeightField.value as? String, "100")
        XCTAssertEqual(secondRepsField.value as? String, "8")
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBozarModeWaitsForPreviousPerformanceBeforeCompletingSet() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Bozar Wait Template",
                notes: "Delay previous-performance hydration to exercise the loading path.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "seed-bench-press",
                        exerciseNameSnapshot: "Barbell Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 8,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
            "UITEST_ACTIVE_WORKOUT_PREVIOUS_PERFORMANCE_DELAY_MS": "4000",
        ])

        startPreviewedTemplateWorkout(in: app)

        let firstCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(firstCompleteSetButton.waitForExistence(timeout: 5))
        firstCompleteSetButton.tap()

        finishTemplateWorkout(in: app)
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 10) {
            skipButton.tap()
        }
        confirmWorkoutCompletion(in: app)

        tapTab("Profile", in: app)
        let settingsTile = identifiedElement("profile-settings-tile", in: app)
        XCTAssertTrue(settingsTile.waitForExistence(timeout: 5))
        settingsTile.tap()

        let bozarToggle = identifiedElement("settings-bozar-mode-toggle", in: app)
        XCTAssertTrue(bozarToggle.waitForExistence(timeout: 5))
        if let currentValue = bozarToggle.value as? String, currentValue == "0" {
            bozarToggle.tap()
        }

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

        let secondCompleteSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(secondCompleteSetButton.waitForExistence(timeout: 5))
        secondCompleteSetButton.tap()

        let pendingBozar = identifiedElement("workout-set-0-bozar-pending", in: app)
        XCTAssertTrue(pendingBozar.waitForExistence(timeout: 2))

        let weightActual = identifiedElement("workout-set-0-weight-actual", in: app)
        let repsActual = identifiedElement("workout-set-0-reps-actual", in: app)
        let completedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        let completedRepsField = identifiedElement("workout-set-0-reps-field", in: app)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 14))
        XCTAssertTrue(weightActual.waitForExistence(timeout: 5))
        XCTAssertTrue(repsActual.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Previous 100 kg x 8"].exists)
        XCTAssertEqual(completedWeightField.value as? String, "100")
        XCTAssertEqual(completedRepsField.value as? String, "8")
    }

    @MainActor
    func testActiveWorkoutCardioPhasesGateExerciseFlow() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Gated Cardio Workout",
                notes: "Cardio should gate the session phases.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "gated-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "gated-treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "gated-bench-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let preToggle = app.buttons["Complete Pre Cardio"]
        let postToggle = app.buttons["Complete Post Cardio"]
        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        let completeSetButton = identifiedElement("workout-set-0-completion-button", in: app)

        XCTAssertTrue(preToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(postToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(postToggle.isEnabled)

        preToggle.tap()

        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        XCTAssertTrue(weightField.isEnabled)
        XCTAssertTrue(completeSetButton.isEnabled)
        XCTAssertTrue(postToggle.waitForExistence(timeout: 5))
        completeSetButton.tap()
        XCTAssertTrue(postToggle.isEnabled)
    }

    @MainActor
    func testActiveWorkoutFinishWarningCallsOutIncompletePreWorkoutCardio() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Finish Warmup Warning Workout",
                notes: "Finishing before warmup should call it out.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "finish-warning-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "finish-warning-bench-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        finishButton.tap()

        let title = identifiedElement("active-workout-finish-confirmation-title", in: app)
        let message = identifiedElement("active-workout-finish-confirmation-message", in: app)

        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Pre-workout Cardio Incomplete")
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Pre-workout cardio is still incomplete"))
    }

    @MainActor
    func testActiveWorkoutCardioSectionsUseWideCompletionAndCompactActions() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Cardio Layout Workout",
                notes: "Keep the cardio controls readable.",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "layout-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "layout-treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "layout-bench-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let preCard = identifiedElement("active-workout-preWorkout-card", in: app)
        let preToggle = app.buttons["Complete Pre Cardio"]

        XCTAssertTrue(preCard.waitForExistence(timeout: 5))
        XCTAssertTrue(preToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(preToggle.isHittable)
        XCTAssertEqual(preToggle.label, "Complete Pre Cardio")
        XCTAssertGreaterThan(preToggle.frame.width, preCard.frame.width * 0.55)
    }

    @MainActor
    func testActiveWorkoutKeepsMissingCardioHiddenUntilAdded() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Lift Only Workout",
                notes: "No cardio in the template.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "lift-only-bench-1",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        XCTAssertFalse(identifiedElement("active-workout-preWorkout-card", in: app).waitForExistence(timeout: 1))
        XCTAssertFalse(identifiedElement("active-workout-postWorkout-card", in: app).waitForExistence(timeout: 1))

        let addCardioButton = identifiedElement("active-workout-add-cardio-button", in: app)
        XCTAssertTrue(addCardioButton.waitForExistence(timeout: 5))
        addCardioButton.tap()

        let addPreWorkoutButton = app.buttons["Add Pre-workout Cardio"]
        XCTAssertTrue(addPreWorkoutButton.waitForExistence(timeout: 5))
        addPreWorkoutButton.tap()

        let pickerSelectButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(pickerSelectButton.waitForExistence(timeout: 15))
        pickerSelectButton.tap()

        XCTAssertTrue(identifiedElement("active-workout-preWorkout-card", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(identifiedElement("active-workout-postWorkout-card", in: app).waitForExistence(timeout: 1))
    }

    @MainActor
    func testTemplateWorkoutFinishKeepTemplateCompletesSummaryFlow() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Keep Template Workout",
                notes: "UI test template",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "template-keep-bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "template-keep-treadmill",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
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
        let preToggle = app.buttons["Complete Pre Cardio"]
        XCTAssertTrue(preToggle.waitForExistence(timeout: 5))
        preToggle.tap()
        addSetToCurrentExercise(in: app)
        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-keep-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        XCTAssertTrue(app.buttons["start-workout-empty-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testActiveWorkoutMoveExerciseToPositionCanUpdateTemplateOrder() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Workout Reorder",
                notes: "Reorder during the workout and push it back to the template.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "workout-order-bench",
                        exerciseNameSnapshot: "Bench Press",
                        categorySnapshot: "Chest",
                        muscleSummarySnapshot: "Chest",
                        targetRepMin: 6,
                        targetRepMax: 8,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 6, targetWeight: 100, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "workout-order-row",
                        exerciseNameSnapshot: "Barbell Row",
                        categorySnapshot: "Back",
                        muscleSummarySnapshot: "Lats",
                        targetRepMin: 8,
                        targetRepMax: 10,
                        restSeconds: 120,
                        sets: [templatePayloadSet(targetReps: 8, targetWeight: 80, loadUnit: "kg", restSeconds: 120, isWarmup: false)]
                    ),
                    templatePayloadExercise(
                        catalogExerciseUUID: "workout-order-squat",
                        exerciseNameSnapshot: "Back Squat",
                        categorySnapshot: "Legs",
                        muscleSummarySnapshot: "Quads",
                        targetRepMin: 5,
                        targetRepMax: 8,
                        restSeconds: 180,
                        sets: [templatePayloadSet(targetReps: 5, targetWeight: 140, loadUnit: "kg", restSeconds: 180, isWarmup: false)]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let benchActionsButton = identifiedElement(
            "active-workout-exercise-workout-order-bench-actions-button",
            in: app
        )
        XCTAssertTrue(benchActionsButton.waitForExistence(timeout: 5))
        benchActionsButton.tap()

        XCTAssertTrue(app.buttons["Move to position"].waitForExistence(timeout: 5))
        app.buttons["Move to position"].tap()

        let reorderSheet = identifiedElement("active-workout-reorder-sheet", in: app)
        XCTAssertTrue(reorderSheet.waitForExistence(timeout: 5))
        app.buttons["active-workout-reorder-position-3"].tap()

        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reordered Exercises"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Position 1 -> 3"].waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-apply-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        let row = identifiedElement("active-workout-exercise-workout-order-row", in: app)
        let squat = identifiedElement("active-workout-exercise-workout-order-squat", in: app)
        let bench = identifiedElement("active-workout-exercise-workout-order-bench", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        XCTAssertTrue(bench.waitForExistence(timeout: 5))

        XCTAssertLessThan(row.frame.minY, squat.frame.minY)
        XCTAssertLessThan(squat.frame.minY, bench.frame.minY)
    }

    @MainActor
    func testTemplateWorkoutFinishUpdateTemplateAppliesWorkoutNotes() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Apply Workout Notes",
                notes: "Original reusable note",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-notes-apply-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let notesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText(" Updated")
        let editedNotes = (notesField.value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workout Notes"].waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-apply-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        let reopenedNotesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(reopenedNotesField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedNotesField.value as? String, editedNotes)
    }

    @MainActor
    func testTemplateWorkoutFinishKeepTemplatePreservesWorkoutNotes() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Keep Workout Notes",
                notes: "Original reusable note",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-notes-keep-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let notesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText(" Updated")

        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workout Notes"].waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-keep-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        let reopenedNotesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(reopenedNotesField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedNotesField.value as? String, "Original reusable note")
    }

    @MainActor
    func testActiveWorkoutNotesPersistAcrossMinimizeRestore() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Minimize Workout Notes",
                notes: "Original reusable note",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-notes-minimize-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let notesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        notesField.tap()
        notesField.typeText(" Minimized")
        let editedNotes = notesField.value as? String

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        let reopenedNotesField = identifiedElement("active-workout-notes-field", in: app)
        XCTAssertTrue(reopenedNotesField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedNotesField.value as? String, editedNotes)
    }

    @MainActor
    func testActiveWorkoutFocusedSetInputPersistsAcrossMinimizeRestore() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Minimize Focused Set Input",
                notes: "Keep focused weight edits when minimizing.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "template-focused-minimize-bench",
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
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let weightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap()
        if !app.keyboards.element.waitForExistence(timeout: 1) {
            weightField.tap()
        }
        weightField.typeText("120")

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()

        let reopenedWeightField = identifiedElement("workout-set-0-weight-field", in: app)
        XCTAssertTrue(reopenedWeightField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedWeightField.value as? String, "120")
    }

    @MainActor
    func testTemplateWorkoutFinishUpdateTemplateAppliesNewStructure() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Apply Template Workout",
                notes: "UI test template",
                preWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "template-apply-bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                postWorkoutCardio: templatePayloadCardio(
                    catalogExerciseUUID: "template-apply-treadmill",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
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
        let preToggle = app.buttons["Complete Pre Cardio"]
        XCTAssertTrue(preToggle.waitForExistence(timeout: 5))
        preToggle.tap()
        addSetToCurrentExercise(in: app)
        finishTemplateWorkout(in: app)

        let reviewSheet = identifiedElement("active-workout-template-review-sheet", in: app)
        XCTAssertTrue(reviewSheet.waitForExistence(timeout: 5))
        app.buttons["active-workout-template-review-apply-button"].tap()

        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        XCTAssertTrue(identifiedElement("active-workout-preWorkout-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("active-workout-postWorkout-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(identifiedElement("workout-set-1-weight-field", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testImportedTemplateWorkoutRotatesToNextComponentAfterCompletedSession() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Rotate Curls",
                notes: "Advance to the next component each workout.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "ui-rotation-reverse-curl",
                        exerciseNameSnapshot: "Reverse Curl",
                        categorySnapshot: "Arms",
                        muscleSummarySnapshot: "Forearms",
                        targetRepMin: 10,
                        targetRepMax: 12,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 20, loadUnit: "kg", restSeconds: 60, isWarmup: false)],
                        components: [
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-rotation-reverse-curl",
                                exerciseNameSnapshot: "Reverse Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-rotation-wrist-curl",
                                exerciseNameSnapshot: "Wrist Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-rotation-reverse-curl", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-rotation-reverse-curl-component-summary", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-rotation-reverse-curl-component-summary-next", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            identifiedElement("active-workout-exercise-ui-rotation-reverse-curl-component-summary-next", in: app).label,
            "Next Wrist Curl"
        )

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        finishTemplateWorkout(in: app)
        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)

        let startButton = app.buttons["Start"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let previewSheet = identifiedElement("template-preview-sheet", in: app)
        XCTAssertTrue(previewSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Wrist Curl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            identifiedElement("template-preview-exercise-row-1-component-summary", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            identifiedElement("template-preview-exercise-row-1-component-summary-last", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            identifiedElement("template-preview-exercise-row-1-component-summary-last", in: app).label,
            "Last Reverse Curl"
        )
        XCTAssertTrue(
            app.staticTexts["Next Reverse Curl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            identifiedElement("template-preview-exercise-row-1-options", in: app)
                .waitForExistence(timeout: 5)
        )

        startPreviewedTemplateWorkout(in: app)

        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-rotation-wrist-curl", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testActiveWorkoutComponentOverrideControlsNextSessionRotation() throws {
        let app = launchApp(launchEnvironment: [
            "UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64": makeTemplateOpenPayloadBase64(
                name: "Override Curls",
                notes: "Override the suggested option for this session.",
                exercises: [
                    templatePayloadExercise(
                        catalogExerciseUUID: "ui-override-reverse-curl",
                        exerciseNameSnapshot: "Reverse Curl",
                        categorySnapshot: "Arms",
                        muscleSummarySnapshot: "Forearms",
                        targetRepMin: 10,
                        targetRepMax: 12,
                        restSeconds: 60,
                        sets: [templatePayloadSet(targetReps: 12, targetWeight: 20, loadUnit: "kg", restSeconds: 60, isWarmup: false)],
                        components: [
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-override-reverse-curl",
                                exerciseNameSnapshot: "Reverse Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                            templatePayloadExerciseComponent(
                                catalogExerciseUUID: "ui-override-wrist-curl",
                                exerciseNameSnapshot: "Wrist Curl",
                                categorySnapshot: "Arms",
                                muscleSummarySnapshot: "Forearms"
                            ),
                        ]
                    ),
                ]
            ),
        ])

        startPreviewedTemplateWorkout(in: app)

        let actionsButton = identifiedElement(
            "active-workout-exercise-ui-override-reverse-curl-actions-button",
            in: app
        )
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let chooseExerciseButton = identifiedElement("workout-exercise-choose-component-button", in: app)
        XCTAssertTrue(chooseExerciseButton.waitForExistence(timeout: 5))
        chooseExerciseButton.tap()

        let pickerSheet = identifiedElement("active-workout-component-picker-sheet", in: app)
        XCTAssertTrue(pickerSheet.waitForExistence(timeout: 5))

        let wristCurlOption = identifiedElement("active-workout-component-option-ui-override-wrist-curl", in: app)
        XCTAssertTrue(wristCurlOption.waitForExistence(timeout: 5))
        wristCurlOption.tap()

        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-override-wrist-curl", in: app)
                .waitForExistence(timeout: 5)
        )

        let completeSetButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Complete Set")
        ).firstMatch
        XCTAssertTrue(completeSetButton.waitForExistence(timeout: 5))
        completeSetButton.tap()

        finishTemplateWorkout(in: app)
        confirmWorkoutCompletion(in: app)
        tapTab("Start Workout", in: app)
        restartImportedTemplateWorkout(in: app)

        XCTAssertTrue(
            identifiedElement("active-workout-exercise-ui-override-reverse-curl", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    private func launchApp(
        mode: LaunchMode = .iCloud,
        launchArguments extraLaunchArguments: [String] = [],
        launchEnvironment extraLaunchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = mode.launchArguments + extraLaunchArguments
        app.launchEnvironment = extraLaunchEnvironment
        app.launch()
        authenticateIfNeeded(app, mode: mode)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    private func authenticateIfNeeded(_ app: XCUIApplication, mode: LaunchMode) {
        let tabBar = app.tabBars.firstMatch
        let continueWithICloud = app.buttons["Continue with iCloud"]
        let continueLocally = app.buttons["Continue Locally"]
        let deadline = Date().addingTimeInterval(12)

        while Date() < deadline {
            if tabBar.exists {
                return
            }

            switch mode {
            case .iCloud:
                if continueWithICloud.exists {
                    continueWithICloud.tap()
                    return
                }

                if continueLocally.exists {
                    let statusText = app.staticTexts.allElementsBoundByIndex
                        .first(where: { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                        .label ?? "No login-gate status text captured."
                    XCTFail("Expected an iCloud-backed UI test launch, but the app only offered local mode. First status text: \(statusText)")
                    return
                }
            case .localInMemory:
                if continueLocally.exists {
                    continueLocally.tap()
                    return
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail("Timed out waiting for the app to reach an authenticated state.")
    }

    private func tapTab(_ name: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func tapTabWithoutWaitingForIdle(_ name: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func identifiedElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstElement(endingWith suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier ENDSWITH %@", suffix))
            .firstMatch
    }

    private func firstButton(endingWith suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier ENDSWITH %@", suffix))
            .firstMatch
    }

    private func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return elements.contains(where: { $0.exists })
    }

    private func clearTextField(_ textField: XCUIElement, replacement: String) {
        textField.press(forDuration: 0.1)
        textField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        textField.typeText(replacement)
    }

    private func revealElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))

        var remainingSwipes = maxSwipes
        while (!element.isHittable || element.frame.maxY > app.frame.maxY - 120) && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func revealLazyElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }

        XCTAssertTrue(element.waitForExistence(timeout: 5))
        revealElement(element, in: app, maxSwipes: maxSwipes)
    }

    private func revealElementAbove(
        _ blocker: XCUIElement,
        target: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) {
        guard blocker.waitForExistence(timeout: 2) else { return }

        var remainingSwipes = maxSwipes
        while remainingSwipes > 0 {
            if target.exists, target.frame.maxY < blocker.frame.minY {
                return
            }
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func startPreviewedTemplateWorkout(
        in app: XCUIApplication,
        expandFirstExercise: Bool = true
    ) {
        func startFromPreview() {
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
        }

        startFromPreview()

        if app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5) {
            if expandFirstExercise {
                expandFirstActiveWorkoutExerciseIfNeeded(in: app)
            }
            return
        }

        let resumeCurrentWorkoutButton = app.buttons["Resume Current Workout"]
        if resumeCurrentWorkoutButton.waitForExistence(timeout: 2) {
            resumeCurrentWorkoutButton.tap()
            discardCurrentWorkout(in: app)

            app.terminate()
            app.launch()
            authenticateIfNeeded(app, mode: launchMode(for: app))

            startFromPreview()
        }

        XCTAssertTrue(app.buttons["active-workout-finish-button"].waitForExistence(timeout: 5))
        if expandFirstExercise {
            expandFirstActiveWorkoutExerciseIfNeeded(in: app)
        }
    }

    private func discardCurrentWorkout(in app: XCUIApplication) {
        let finishButton = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))

        let cancelButton = identifiedElement("active-workout-cancel-button", in: app)
        revealLazyElement(cancelButton, in: app)
        let elapsedTimer = identifiedElement("active-workout-elapsed-timer", in: app)
        revealElementAbove(elapsedTimer, target: cancelButton, in: app)

        XCTAssertTrue(cancelButton.isHittable)
        cancelButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()

        let discardButton = app.buttons["Discard Workout"]
        XCTAssertTrue(discardButton.waitForExistence(timeout: 5))
        discardButton.tap()
        XCTAssertTrue(waitForElementToDisappear(finishButton, timeout: 5))
    }

    private func launchMode(for app: XCUIApplication) -> LaunchMode {
        app.launchArguments.contains("UITEST_IN_MEMORY_STORE") ? .localInMemory : .iCloud
    }

    private func startWorkoutTemplateInlineEditButtonID(for templateName: String) -> String {
        "start-workout-template-inline-edit-button-\(accessibilityKey(for: templateName))"
    }

    private func accessibilityKey(for text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func openTemplateEditorFromMinimizedActiveWorkout(
        templateName: String,
        in app: XCUIApplication
    ) {
        startPreviewedTemplateWorkout(in: app)

        let minimizeButton = app.buttons["active-workout-minimize-button"]
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 5))
        minimizeButton.tap()

        tapTab("Start Workout", in: app)

        let strip = identifiedElement("active-workout-strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))

        let editButton = identifiedElement(
            startWorkoutTemplateInlineEditButtonID(for: templateName),
            in: app
        )
        revealElementAbove(strip, target: editButton, in: app, maxSwipes: 10)

        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        XCTAssertTrue(editButton.isHittable)
        editButton.tap()

        XCTAssertTrue(app.buttons["template-editor-save-button"].waitForExistence(timeout: 5))
    }

    private func assertTemplateEditorBottomExerciseRemainsInteractive(
        catalogExerciseUUID: String,
        in app: XCUIApplication
    ) {
        let exerciseIdentifier = "template-editor-exercise-\(catalogExerciseUUID)"
        let exercise = identifiedElement(exerciseIdentifier, in: app)
        revealLazyElement(exercise, in: app, maxSwipes: 16)
        XCTAssertTrue(exercise.isHittable)

        app.swipeDown()
        app.swipeUp()

        revealLazyElement(exercise, in: app, maxSwipes: 8)
        XCTAssertTrue(exercise.isHittable)

        let expandButton = identifiedElement("\(exerciseIdentifier)-expand-button", in: app)
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5))
        XCTAssertTrue(expandButton.isHittable)
        expandButton.tap()

        let notesField = identifiedElement("\(exerciseIdentifier)-notes-field", in: app)
        revealLazyElement(notesField, in: app, maxSwipes: 6)
        XCTAssertTrue(notesField.isHittable)
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

        let finishConfirmationTitle = identifiedElement("active-workout-finish-confirmation-title", in: app)
        XCTAssertTrue(finishConfirmationTitle.waitForExistence(timeout: 5))

        let finishConfirmationButtonTitle = finishConfirmationTitle.label.contains("Unfinished Work")
            ? "Finish Anyway"
            : "Finish and Save"
        let finishConfirmationButton = app.buttons[finishConfirmationButtonTitle]
        XCTAssertTrue(finishConfirmationButton.waitForExistence(timeout: 5))
        finishConfirmationButton.tap()

        XCTAssertTrue(waitForElementToDisappear(finishConfirmationTitle, timeout: 5))
    }

    private func confirmWorkoutCompletion(in app: XCUIApplication) {
        let saveTemplateSheet = identifiedElement("active-workout-template-save-sheet", in: app)
        if saveTemplateSheet.exists || saveTemplateSheet.waitForExistence(timeout: 1) {
            let skipButton = identifiedElement("active-workout-template-skip-button", in: app)
            XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
            skipButton.tap()
            XCTAssertTrue(waitForElementToDisappear(saveTemplateSheet, timeout: 5))
        }

        let summary = identifiedElement("workout-completion-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))

        let confirmButton = identifiedElement("workout-completion-confirm-button", in: app)
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))
        confirmButton.tap()
    }

    private func pickExercise(named query: String, in app: XCUIApplication) {
        let searchField = app.textFields["exercises-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(query)

        let selectExerciseButton = identifiedElement("exercise-picker-select-button", in: app)
        XCTAssertTrue(selectExerciseButton.waitForExistence(timeout: 15))
        selectExerciseButton.tap()
        expandFirstActiveWorkoutExerciseIfNeeded(in: app)
    }

    private func expandFirstActiveWorkoutExerciseIfNeeded(
        in app: XCUIApplication,
        require: Bool = false,
        maxSwipes: Int = 3
    ) {
        if identifiedElement("workout-set-0-weight-field", in: app).exists {
            return
        }

        let expandButton = firstVisibleActiveWorkoutExpandButton(in: app, maxSwipes: maxSwipes)
        guard expandButton.waitForExistence(timeout: 2) else {
            if require {
                XCTFail("Expected a visible active workout exercise expand button.")
            }
            return
        }
        revealElement(expandButton, in: app, maxSwipes: 3)
        expandButton.tap()
    }

    private func firstVisibleActiveWorkoutExpandButton(
        in app: XCUIApplication,
        maxSwipes: Int
    ) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "-expand-button"))
        var remainingSwipes = maxSwipes
        while remainingSwipes >= 0 {
            let button = query.firstMatch
            if button.exists {
                return button
            }
            app.swipeUp()
            remainingSwipes -= 1
        }
        return query.firstMatch
    }

    private func activeWorkoutSetCompletionButtonCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(identifier: "workout-set-0-completion-button")
            .count
    }

    private func makeTemplateOpenPayloadBase64(
        name: String,
        notes: String,
        preWorkoutCardio: [String: Any]? = nil,
        postWorkoutCardio: [String: Any]? = nil,
        exercises: [[String: Any]] = []
    ) -> String {
        var templatePayload: [String: Any] = [
            "name": name,
            "notes": notes,
            "exercises": exercises,
        ]

        if let preWorkoutCardio {
            templatePayload["preWorkoutCardio"] = preWorkoutCardio
        }

        if let postWorkoutCardio {
            templatePayload["postWorkoutCardio"] = postWorkoutCardio
        }

        let hasExerciseComponents = exercises.contains { $0["components"] != nil }
        let hasSupersetOrDropset = exercises.contains { exercise in
            if exercise["superset"] != nil {
                return true
            }
            let sets = exercise["sets"] as? [[String: Any]] ?? []
            return sets.contains { $0["dropStages"] != nil }
        }
        let formatVersion: Int
        if hasSupersetOrDropset || hasExerciseComponents {
            formatVersion = 3
        } else if preWorkoutCardio != nil || postWorkoutCardio != nil {
            formatVersion = 2
        } else {
            formatVersion = 1
        }

        let payload: [String: Any] = [
            "formatVersion": formatVersion,
            "exportedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0)),
            "template": templatePayload,
        ]

        let data = try! JSONSerialization.data(withJSONObject: payload, options: [])
        return data.base64EncodedString()
    }

    private func templatePayloadCardio(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int
    ) -> [String: Any] {
        [
            "catalogExerciseUUID": catalogExerciseUUID,
            "exerciseNameSnapshot": exerciseNameSnapshot,
            "categorySnapshot": categorySnapshot,
            "muscleSummarySnapshot": muscleSummarySnapshot,
            "targetDurationSeconds": targetDurationSeconds,
        ]
    }

    private func templatePayloadExercise(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        sets: [[String: Any]],
        components: [[String: Any]] = [],
        superset: [String: Any]? = nil
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
        if !components.isEmpty {
            payload["components"] = components
        }
        if let superset {
            payload["superset"] = superset
        }
        return payload
    }

    private func templatePayloadSuperset(
        groupID: String,
        position: String,
        roundRestSeconds: Int
    ) -> [String: Any] {
        [
            "groupID": groupID,
            "position": position,
            "roundRestSeconds": roundRestSeconds,
        ]
    }

    private func templatePayloadExerciseComponent(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String
    ) -> [String: Any] {
        [
            "catalogExerciseUUID": catalogExerciseUUID,
            "exerciseNameSnapshot": exerciseNameSnapshot,
            "categorySnapshot": categorySnapshot,
            "muscleSummarySnapshot": muscleSummarySnapshot,
        ]
    }

    private func templatePayloadSet(
        targetReps: Int?,
        targetWeight: Double?,
        loadUnit: String,
        restSeconds: Int,
        isWarmup: Bool,
        isLocked: Bool = false,
        dropStages: [[String: Any]] = []
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "loadUnit": loadUnit,
            "restSeconds": restSeconds,
            "isWarmup": isWarmup,
            "isLocked": isLocked,
        ]

        payload["targetReps"] = targetReps
        payload["targetWeight"] = targetWeight
        if !dropStages.isEmpty {
            payload["dropStages"] = dropStages
        }
        return payload
    }

    private func templatePayloadDropStage(
        targetReps: Int?,
        targetWeight: Double?,
        loadUnit: String
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "loadUnit": loadUnit,
        ]
        payload["targetReps"] = targetReps
        payload["targetWeight"] = targetWeight
        return payload
    }
}
