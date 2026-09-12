import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFolderEditorCanRetryValidationFailureAndSaveOnce() {
        let app = launchLocalApp()
        let newFolder = app.buttons["start-workout-new-folder-button"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 8))
        newFolder.tap()

        let field = app.textFields["template-folder-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText(String(repeating: "A", count: 61))
        let save = app.buttons["template-folder-save-button"]
        save.tap()
        let error = app.alerts["Start Workout Error"]
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        error.buttons["OK"].tap()
        XCTAssertTrue(field.exists)

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 61) + "Sweep Folder")
        save.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        XCTAssertTrue(field.waitForNonExistence(timeout: 8))
        let folder = app.staticTexts.matching(identifier: "Sweep Folder")
        XCTAssertTrue(folder.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(folder.count, 1)

        newFolder.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertTrue((field.value as? String ?? "").isEmpty || field.value as? String == "Push / Pull / Legs")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 4))
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
        let chart = app.otherElements["exercise-progress-chart"]
        XCTAssertTrue(chart.exists)
        XCTAssertTrue(app.otherElements["exercise-progress-timeline"].exists)
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 {
            if chart.frame.minY > 100 && chart.frame.maxY < app.frame.maxY - 80 { break }
            scroll.swipeUp()
        }
        XCTAssertGreaterThan(chart.frame.minY, 100)
        XCTAssertLessThan(chart.frame.maxY, app.frame.maxY - 80)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        let sixMonths = app.buttons["exercise-progress-range-sixMonths"]
        for _ in 0..<6 {
            if sixMonths.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(sixMonths.isHittable)
        sixMonths.tap()
        let selection = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: sixMonths
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 3), .completed)
        XCTAssertTrue(chart.exists)
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
    func testHistoryDetailRetriesCanceledInitialLoadAfterTabReturn() {
        let app = launchLocalApp(additionalArguments: [
            "UITEST_SEED_HISTORY_MAIN_CARDIO", "UITEST_DELAY_HISTORY_DETAIL_LOAD",
        ])
        let historyTab = app.buttons["History"].firstMatch
        XCTAssertTrue(historyTab.waitForExistence(timeout: 8))
        historyTab.tap()
        let card = app.buttons["history-session-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Cardio Activities"].exists)
        app.buttons["Start Workout"].firstMatch.tap()
        XCTAssertTrue(app.buttons["start-workout-empty-button"].waitForExistence(timeout: 4))
        historyTab.tap()
        // The retained destination must finish its own retry, without popping/reopening it.
        XCTAssertTrue(app.staticTexts["Cardio Activities"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bike"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testTemplateLibraryScrollsToOffscreenRowsAndBack() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_TEMPLATE_LIBRARY"])
        let first = app.staticTexts["Library Plan 01"].firstMatch
        let last = app.staticTexts["Library Plan 16"].firstMatch
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        for _ in 0..<5 {
            if first.exists && first.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(first.isHittable)
        for _ in 0..<20 {
            if last.exists && last.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(last.isHittable, "The last template should be reachable in the lazy library")
        for _ in 0..<20 {
            if first.exists && first.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(first.isHittable, "Returning to recycled template rows should preserve content")
        XCTAssertTrue(app.buttons["start-workout-new-folder-button"].exists)
    }

    @MainActor
    func testSummaryWorkoutShareCanCancelAndRetryAfterBackground() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_TEMPLATE_REVIEW"])
        finishTemplateReviewFixture(in: app)
        let keep = app.buttons["active-workout-template-review-keep-button"]
        XCTAssertTrue(keep.waitForExistence(timeout: 8))
        keep.tap()
        let summaryShare = app.buttons["Share"].firstMatch
        XCTAssertTrue(summaryShare.waitForExistence(timeout: 8))
        summaryShare.tap()
        verifyWorkoutShareCanCancelAndRetry(in: app)
        let history = app.buttons["View History"]
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        XCTAssertTrue(history.isHittable)
        history.tap()
        XCTAssertTrue(app.staticTexts["400 kg"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["50 kg x 8"].firstMatch.exists)
    }

    @MainActor
    func testHistoryWorkoutShareCanCancelAndRetryAfterBackground() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_HISTORY_MAIN_CARDIO"])
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(app.buttons["history-session-card"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Workout Actions"].firstMatch.tap()
        app.buttons["Share Workout"].firstMatch.tap()
        verifyWorkoutShareCanCancelAndRetry(in: app)
        XCTAssertTrue(app.buttons["history-session-card"].firstMatch.isHittable)
    }

    @MainActor
    private func verifyWorkoutShareCanCancelAndRetry(in app: XCUIApplication) {
        let share = app.buttons["workout-share-preview-share-button"]
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        share.tap()
        let copy = app.cells["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 8), app.debugDescription)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(copy.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(share.isHittable, app.debugDescription)
        share.tap()
        let saveToFiles = app.cells["Save to Files"].firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 8))
        saveToFiles.tap()
        let filePicker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(filePicker.waitForExistence(timeout: 8), app.debugDescription)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(filePicker.waitForExistence(timeout: 8))
        let cancel = filePicker.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close'")).firstMatch
        // Files can reopen either its browser or the last destination folder.
        if !cancel.exists {
            filePicker.buttons["BackButton"].tap()
        }
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(filePicker.waitForNonExistence(timeout: 8))
        // A destination may return to the activity list instead of ending it.
        let activityClose = app.buttons["header.closeButton"]
        if activityClose.waitForExistence(timeout: 2) {
            activityClose.tap()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(share.isHittable, app.debugDescription)
        share.tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 8))
        copy.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(share.isHittable, app.debugDescription)
        app.buttons["Close"].firstMatch.tap()
    }

    @MainActor
    func testTemplateReviewSurvivesBackgroundThenKeepTemplate() {
        verifyTemplateReviewSurvivesBackground(action: "keep")
    }

    @MainActor
    func testTemplateReviewSurvivesBackgroundThenUpdateTemplate() {
        verifyTemplateReviewSurvivesBackground(action: "apply")
    }

    @MainActor
    private func verifyTemplateReviewSurvivesBackground(action: String) {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_TEMPLATE_REVIEW"])
        finishTemplateReviewFixture(in: app)
        let start = app.buttons["start-workout-template-start-button-review-fixture"]
        let previewStart = app.buttons["template-preview-start-button"]

        let keep = app.buttons["active-workout-template-review-keep-button"]
        let update = app.buttons["active-workout-template-review-apply-button"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(keep.waitForExistence(timeout: 8))
            XCTAssertTrue(keep.isHittable)
            XCTAssertTrue(update.isHittable)
            XCTAssertFalse(app.buttons["View History"].exists)
        }

        app.buttons["active-workout-template-review-\(action)-button"].tap()
        // The summary container identifier is inherited by its bottom buttons.
        let history = app.buttons["View History"]
        let didShowSummary = history.waitForExistence(timeout: 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Template choice after background - \(action)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(didShowSummary, app.debugDescription)
        history.tap()
        XCTAssertTrue(app.staticTexts["400 kg"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["50 kg x 8"].firstMatch.exists, app.debugDescription)
        let startTab = app.buttons["Start Workout"].firstMatch
        XCTAssertTrue(startTab.waitForExistence(timeout: 8))
        startTab.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(previewStart.waitForExistence(timeout: 4))
        let expectedSets = action == "apply" ? "2 working sets" : "1 working set"
        XCTAssertTrue(app.staticTexts[expectedSets].firstMatch.waitForExistence(timeout: 4))
    }

    @MainActor
    private func finishTemplateReviewFixture(in app: XCUIApplication) {
        let start = app.buttons["start-workout-template-start-button-review-fixture"]
        for _ in 0..<5 {
            if start.exists && start.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()

        let previewStart = app.buttons["template-preview-start-button"]
        XCTAssertTrue(previewStart.waitForExistence(timeout: 4))
        previewStart.tap()

        let expand = app.buttons["active-workout-exercise-ui-test-bench-expand-button"]
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        expand.tap()
        let setActions = app.buttons["workout-set-actions-button-0"].firstMatch
        for _ in 0..<5 {
            if setActions.exists && setActions.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(setActions.waitForExistence(timeout: 8))
        setActions.tap()
        app.buttons["Insert below"].firstMatch.tap()

        let weight = app.textFields["workout-set-0-weight-field"]
        XCTAssertTrue(weight.waitForExistence(timeout: 4))
        weight.tap()
        weight.typeText("50")
        let reps = app.textFields["workout-set-0-reps-field"]
        reps.tap()
        reps.typeText("8")
        app.buttons["workout-set-0-completion-button"].tap()

        let finish = app.buttons["active-workout-finish-button"]
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        finish.tap()
        let confirm = app.buttons["Finish Anyway"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
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
