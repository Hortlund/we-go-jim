import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    @MainActor
    func testGymLogoSecretUnlocksOptionalModeAndPersists() {
        let app = launchLocalApp(additionalArguments: ["UITEST_RESET_GYM_EASTER_EGGS"])
        func openSettings() {
            app.buttons["Profile"].firstMatch.tap()
            let settings = app.buttons["profile-settings-tile"]
            for _ in 0..<12 where !settings.isHittable { app.swipeUp() }
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            XCTAssertTrue(app.buttons["gym-secret-logo"].waitForExistence(timeout: 5))
        }
        openSettings()
        XCTAssertFalse(app.switches["gym-bro-mode-toggle"].exists)
        for _ in 0..<6 { app.buttons["gym-secret-logo"].tap() }
        XCTAssertFalse(app.switches["gym-bro-mode-toggle"].exists)
        app.buttons["gym-secret-logo"].tap()
        let toggle = app.switches["gym-bro-mode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Gym-bro mode unlocked."].exists)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gym-bro mode unlocked"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        app.launchArguments.removeAll { $0 == "UITEST_RESET_GYM_EASTER_EGGS" }
        app.launch()
        let local = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        local.tap()
        openSettings()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    func testGymSearchSecretKeepsNormalSearchWorking() {
        let app = launchLocalApp()
        openExercisesTab(in: app)
        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("motivation")
        let message = app.staticTexts["gym-search-easter-egg"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "No results. We go jim.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gym search secret"
        attachment.lifetime = .keepAlways
        add(attachment)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "excuses")
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "bench")
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testGymWarmupSaluteLeavesSetEditingAvailable() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_TEMPLATE_REVIEW"])
        let start = app.buttons["start-workout-template-start-button-review-fixture"]
        for _ in 0..<5 where !start.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        app.buttons["template-preview-start-button"].tap()
        let expand = app.buttons["active-workout-exercise-ui-test-bench-expand-button"]
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        expand.tap()
        let actions = app.buttons["workout-set-actions-button-0"].firstMatch
        for _ in 0..<5 {
            if actions.isHittable && actions.frame.maxY < app.frame.maxY - 160 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        actions.tap()
        app.buttons["Mark as warmup"].firstMatch.tap()
        let salute = app.buttons["gym-warmup-salute"]
        XCTAssertTrue(salute.waitForExistence(timeout: 5))
        salute.tap()
        XCTAssertTrue(app.staticTexts["Respect the empty bar. It was here before you."].exists)
        XCTAssertTrue(app.textFields["workout-set-0-weight-field"].isEnabled)
        XCTAssertTrue(app.buttons["workout-set-0-completion-button"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Empty-bar salute"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testGymBroRecapStillOffersHistoryAndShare() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_TEMPLATE_REVIEW", "-wgj.gymBro.enabled", "YES"])
        finishTemplateReviewFixture(in: app)
        let keep = app.buttons["active-workout-template-review-keep-button"]
        XCTAssertTrue(keep.waitForExistence(timeout: 8))
        keep.tap()
        let egg = app.descendants(matching: .any)["gym-completion-easter-egg"].firstMatch
        XCTAssertTrue(egg.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["View History"].isHittable)
        XCTAssertTrue(app.buttons["Share"].firstMatch.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gym-bro workout recap"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["View History"].tap()
        XCTAssertTrue(app.staticTexts["400 kg"].firstMatch.waitForExistence(timeout: 8))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProfileWidgetReorderPersistsAfterClosingManager() {
        let app = launchLocalApp()
        app.buttons["Profile"].firstMatch.tap()
        let manage = app.buttons["profile-dashboard-manage-button"]
        for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        app.buttons["profile-widgets-reorder-button"].tap()
        let up = app.buttons["profile-widget-move-up-weeklyGoals"]
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reorder Weekly Goal"].exists)
        XCTAssertFalse(app.buttons["Reorder PRs"].exists)
        up.tap()
        // Both arrow directions work without entering native drag edit mode.
        app.buttons["profile-widget-move-down-weeklyGoals"].tap()
        up.tap()
        XCTAssertFalse(app.buttons["profile-widget-move-up-weeklyGoals"].isEnabled)
        // Move a second row while the first save may still be completing.
        app.buttons["profile-widget-move-up-weeklyMuscleHeatmap"].tap()
        app.buttons["profile-widget-move-up-weeklyMuscleHeatmap"].tap()
        let done = app.buttons["profile-widgets-done-button"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        done.tap()
        manage.tap()
        let heatmap = app.staticTexts["Muscle Heatmap"].firstMatch
        let prs = app.staticTexts["PRs"]
        XCTAssertTrue(prs.waitForExistence(timeout: 5))
        let cells = app.cells.allElementsBoundByIndex
        let heatmapIndex = cells.firstIndex { $0.staticTexts["Muscle Heatmap"].exists }
        let goalIndex = cells.firstIndex { $0.staticTexts["Weekly Goal"].exists }
        let prsIndex = cells.firstIndex { $0.staticTexts["PRs"].exists }
        XCTAssertNotNil(heatmapIndex)
        XCTAssertNotNil(goalIndex)
        XCTAssertNotNil(prsIndex)
        XCTAssertLessThan(heatmapIndex ?? 99, goalIndex ?? 0)
        XCTAssertLessThan(goalIndex ?? 99, prsIndex ?? 0)
        XCTAssertTrue(heatmap.exists)
    }

    @MainActor
    func testProfileBodyweightTrendPickerAndExerciseHeadings() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_PROFILE_BODYWEIGHT", "UITEST_SEED_EXERCISE_PROGRESS"])
        app.buttons["Profile"].firstMatch.tap()
        let manage = app.buttons["profile-dashboard-manage-button"]
        for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()

        func addTrend(search: String, exercise: String, metric: String) {
            let add = app.buttons["profile-widget-add-exerciseTrend"]
            for _ in 0..<10 where !add.isHittable { app.swipeUp() }
            XCTAssertTrue(add.isHittable)
            add.tap()
            let searchField = app.searchFields.firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: 5))
            searchField.tap()
            searchField.typeText(search)
            let option = app.buttons.containing(.staticText, identifier: exercise).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            XCTAssertTrue(option.staticTexts[metric].exists)
            option.tap()
            XCTAssertTrue(app.staticTexts["\(metric) — \(exercise)"].waitForExistence(timeout: 5))
        }
        // The default request is 1RM; reps-only exercises must remain searchable.
        addTrend(search: "pull", exercise: "Pull-Up", metric: "Max Reps Trend")
        addTrend(search: "bench", exercise: "Barbell Bench Press", metric: "1RM Trend")
        func editBench(from title: String, to metric: String, segment: String) {
            let row = app.cells.containing(.staticText, identifier: title).firstMatch
            let edit = row.buttons["Edit Trend"]
            for _ in 0..<10 where !edit.isHittable { app.swipeDown() }
            XCTAssertTrue(edit.isHittable)
            edit.tap()
            let picker = app.segmentedControls["profile-widget-trend-metric-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.buttons[segment].tap()
            let search = app.searchFields.firstMatch
            search.tap()
            search.typeText("bench")
            let option = app.buttons.containing(.staticText, identifier: "Barbell Bench Press").firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            XCTAssertTrue(option.staticTexts[metric].exists)
            option.tap()
            XCTAssertTrue(app.staticTexts["\(metric) — Barbell Bench Press"].waitForExistence(timeout: 5))
        }
        editBench(from: "1RM Trend — Barbell Bench Press", to: "Max Reps Trend", segment: "Max Reps")
        editBench(from: "Max Reps Trend — Barbell Bench Press", to: "1RM Trend", segment: "1RM")
        app.buttons["Done"].tap()
        let title = app.staticTexts["Max Reps Trend — Pull-Up"]
        for _ in 0..<12 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(app.staticTexts["10 reps"].exists)
        let graph = app.otherElements["profile-exercise-trend-chart-fixture-pull-up-maxReps"].firstMatch
        XCTAssertGreaterThan(graph.frame.width, 100)
        for _ in 0..<12 {
            if graph.frame.minY > 150 && graph.frame.maxY < app.frame.maxY - 120 { break }
            let down = graph.frame.minY <= 150
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.45 : 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.65 : 0.45)))
        }
        XCTAssertGreaterThan(graph.frame.minY, 100)
        XCTAssertLessThan(graph.frame.maxY, app.frame.maxY - 100)
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let selectedContext = app.staticTexts["profile-trend-context-fixture-pull-up-maxReps"]
        let selectedFirst = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "8 reps"), object: selectedContext)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedFirst], timeout: 3), .completed, selectedContext.label)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Profile bodyweight trend and exercise heading"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let weightedTitle = app.staticTexts["1RM Trend — Barbell Bench Press"]
        for _ in 0..<6 where !weightedTitle.isHittable { app.swipeUp() }
        XCTAssertTrue(weightedTitle.isHittable)
        XCTAssertFalse(app.staticTexts["Max Reps Trend — Barbell Bench Press"].exists)
    }

    @MainActor
    func testThemeSelectionPersistsAndKeepsSettingsNavigation() {
        let app = launchLocalApp()

        func openThemePicker() {
            let profile = app.buttons["Profile"].firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 8))
            profile.tap()
            let settings = app.buttons["profile-settings-tile"]
            for _ in 0..<10 where !settings.isHittable { app.swipeUp() }
            XCTAssertTrue(settings.isHittable)
            settings.tap()
            let themes = app.buttons["settings-app-theme-tile"]
            XCTAssertTrue(themes.waitForExistence(timeout: 5))
            themes.tap()
            XCTAssertTrue(app.buttons["app-theme-original"].waitForExistence(timeout: 5))
        }

        openThemePicker()
        for theme in ["mintCondition", "wheyTooPurple", "sunsOutGunsOut", "electricStrength"] {
            let option = app.buttons["app-theme-\(theme)"]
            for _ in 0..<4 where !option.isHittable { app.swipeUp() }
            XCTAssertTrue(option.isHittable)
            option.tap()
            XCTAssertEqual(option.value as? String, "Selected")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Theme-\(theme)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        app.terminate()
        app.launch()
        let continueLocally = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
        continueLocally.tap()
        openThemePicker()
        let selected = app.buttons["app-theme-electricStrength"]
        for _ in 0..<4 where !selected.isHittable { app.swipeUp() }
        XCTAssertEqual(selected.value as? String, "Selected")

        let original = app.buttons["app-theme-original"]
        for _ in 0..<4 where !original.isHittable { app.swipeDown() }
        original.tap()
        XCTAssertEqual(original.value as? String, "Selected")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-app-theme-tile"].waitForExistence(timeout: 4))
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
    func testAssistanceContextAcrossExerciseProgressAndHistory() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_EXERCISE_PROGRESS", "UITEST_ASSISTED_PROGRESS"])
        openExercisesTab(in: app)
        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("assisted pull")
        let exercise = app.staticTexts["Assisted Pull Up"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 4))
        exercise.tap()
        let selector = app.buttons["exercise-progress-metric-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 4))
        XCTAssertEqual(selector.value as? String, "Best-Set Reps")
        app.buttons["exercise-progress-range-allTime"].tap()
        let context = app.staticTexts["exercise-progress-set-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 4))
        XCTAssertEqual(context.label, "6 reps · 20 kg assistance")
        let scroll = app.scrollViews.firstMatch
        let chart = app.otherElements["exercise-progress-chart"]
        for _ in 0..<6 {
            if chart.frame.minY > 100 && chart.frame.maxY < app.frame.maxY - 80 { break }
            scroll.swipeUp()
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Assisted pull-up progress"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["History"].firstMatch.tap()
        let card = app.buttons["history-session-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.contains("6 reps · 20 kg assistance"))
        card.tap()
        let guidance = app.staticTexts["Weight is machine assistance. Less assistance is harder."]
        for _ in 0..<8 where !guidance.isHittable { app.swipeUp() }
        XCTAssertTrue(guidance.exists)
    }

    @MainActor
    func testCustomExerciseCanChooseAssistanceMeaning() {
        let app = launchLocalApp()
        openExercisesTab(in: app)
        let create = app.buttons["exercises-create-button"]
        for _ in 0..<6 where !create.isHittable { app.swipeDown() }
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let picker = app.buttons["custom-exercise-load-kind"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Assistance"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Log the machine assistance. Less assistance is harder; compare on the same machine."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Custom exercise weight meaning"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMixedLoadProgressShowsActualSetsAndNeutralComparison() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_EXERCISE_PROGRESS", "UITEST_MIXED_LOAD_PROGRESS"])
        openExercisesTab(in: app)
        let search = app.textFields["exercises-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("pull-up")
        let exercise = app.staticTexts["Pull Up"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 4))
        exercise.tap()
        let selector = app.buttons["exercise-progress-metric-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 4))
        XCTAssertEqual(selector.value as? String, "Best-Set Reps")
        app.buttons["exercise-progress-range-allTime"].tap()
        let context = app.staticTexts["exercise-progress-set-context"]
        XCTAssertTrue(context.waitForExistence(timeout: 4))
        XCTAssertEqual(context.label, "10 kg × 6 reps")
        let note = app.otherElements["exercise-progress-load-note"]
        XCTAssertTrue(note.exists || app.staticTexts["exercise-progress-load-note"].exists)
        let scroll = app.scrollViews.firstMatch
        let chart = app.otherElements["exercise-progress-chart"]
        for _ in 0..<6 {
            if chart.frame.minY > 100 && chart.frame.maxY < app.frame.maxY - 80 { break }
            scroll.swipeUp()
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pull-up progress with added weight"
        attachment.lifetime = .keepAlways
        add(attachment)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let earlierSet = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "10 reps"), object: context)
        XCTAssertEqual(XCTWaiter.wait(for: [earlierSet], timeout: 3), .completed)

        for _ in 0..<6 {
            if selector.isHittable { break }
            scroll.swipeDown()
        }
        selector.tap()
        let weight = app.buttons["Heaviest Added Weight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 3))
        weight.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Heaviest Added Weight"), object: selector)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 3), .completed)
    }

    @MainActor
    func testAddedWeightContextInWorkoutComparisonAndHistory() {
        let app = launchLocalApp(additionalArguments: ["UITEST_SEED_EXERCISE_PROGRESS", "UITEST_MIXED_LOAD_PROGRESS"])
        app.buttons["Progress"].firstMatch.tap()
        let comparisonNote = app.staticTexts["Added weight changed · compare reps at the same load"].firstMatch
        for _ in 0..<10 where !comparisonNote.isHittable { app.swipeUp() }
        XCTAssertTrue(comparisonNote.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Added weight workout comparison"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["History"].firstMatch.tap()
        let card = app.buttons["history-session-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.contains("10 kg × 6 reps"))
        card.tap()
        let guidance = app.staticTexts["Weight is added weight. Bodyweight is not included."]
        XCTAssertFalse(guidance.exists)
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

        let metricSelector = app.buttons["exercise-progress-metric-selector"]
        for _ in 0..<6 {
            if metricSelector.isHittable { break }
            scroll.swipeDown()
        }
        // Exercise in-place chart updates across different units and back again.
        // The chart must receive the new projection, not retain the previous metric.
        for metric in ["Heaviest Weight", "Total Reps", "Workout Frequency", "Estimated 1RM"] {
            metricSelector.tap()
            let option = app.buttons[metric].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()
            let selectedMetric = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", metric),
                object: metricSelector
            )
            XCTAssertEqual(XCTWaiter.wait(for: [selectedMetric], timeout: 3), .completed)
            let updatedChart = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", ", \(metric), 6M,"),
                object: chart
            )
            XCTAssertEqual(XCTWaiter.wait(for: [updatedChart], timeout: 3), .completed)
            XCTAssertTrue(app.otherElements["exercise-progress-timeline"].exists)
        }
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
            if setActions.exists && setActions.isHittable && setActions.frame.maxY < app.frame.maxY - 160 { break }
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
