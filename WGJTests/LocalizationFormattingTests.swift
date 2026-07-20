import Foundation
import XCTest
@testable import WGJ

final class LocalizationFormattingTests: XCTestCase {
    func testCoreEnglishFormatting() {
        XCTAssertEqual(L10n.restTimerTitle, "Rest complete")
        XCTAssertEqual(L10n.restTimerBody, "Time for your next set.")
        XCTAssertEqual(L10n.weeklyGoalRemaining(1), "1 to go")
        XCTAssertEqual(L10n.completedWorkoutCount(1), "1 completed workout")
        XCTAssertEqual(L10n.completedWorkoutCount(3), "3 completed workouts")
    }

    func testCardioHelperFormattingUsesLocalizedResources() {
        XCTAssertEqual(WorkoutCardioRole.warmUp.title, "Warm-up")
        XCTAssertEqual(WorkoutCardioRole.main.title, "Main Cardio")
        XCTAssertEqual(WorkoutCardioRole.finisher.compactTitle, "Finisher")
        XCTAssertEqual(WorkoutCardioGoalKind.open.title, "No Target")
        XCTAssertEqual(WorkoutCardioDurationFormatter.text(seconds: 300), "5 min")
    }

    func testCardioValidationAndConfirmationCopyUsesLocalizedResources() {
        XCTAssertEqual(
            WorkoutCardioSetupValidationError.distanceMustBePositive(unit: .kilometers).errorDescription,
            "Enter a distance greater than 0 kilometers."
        )
        XCTAssertEqual(
            WorkoutCardioSetupValidationError.distanceMustBePositive(unit: .miles).errorDescription,
            "Enter a distance greater than 0 miles."
        )
        XCTAssertEqual(
            WorkoutCardioSetupValidationError.distanceMustBePositive(unit: .meters).errorDescription,
            "Enter a distance greater than 0 meters."
        )
        XCTAssertEqual(
            ActiveWorkoutCardioConfirmationCopy.replacementTitle(activityName: "Bike"),
            "Change Bike?"
        )
        XCTAssertEqual(
            ActiveWorkoutCardioConfirmationCopy.removalTitle(activityName: "Bike"),
            "Remove Bike?"
        )
        XCTAssertEqual(
            ActiveWorkoutCardioConfirmationCopy.replacementMessage,
            "Recorded cardio data will be cleared. This cannot be undone."
        )
        XCTAssertEqual(
            ActiveWorkoutCardioConfirmationCopy.removalMessage,
            "This activity contains saved progress or a result. Removing it cannot be undone."
        )
    }

    func testCardioFeatureSourcesDoNotBypassLocalization() throws {
        let cardioFeaturePaths = [
            "WGJ/Models/WorkoutCardioResultDraft.swift",
            "WGJ/Models/WorkoutCardioTracking.swift",
            "WGJ/Models/WorkoutMetricAccessibility.swift",
            "WGJ/Models/UserDomainModels.swift",
            "WGJ/Services/WorkoutCardioTimerCoordinator.swift",
            "WGJ/Services/WorkoutTemplateSyncPreviewBuilder.swift",
            "WGJ/Views/Exercises/ExercisesCatalogView.swift",
            "WGJ/Views/History/HistoryDetailView.swift",
            "WGJ/Views/Shared/CardioActivityQuickPicker.swift",
            "WGJ/Views/Shared/WorkoutCardioResultEditor.swift",
            "WGJ/Views/Shared/WorkoutCardioSetupSheet.swift",
            "WGJ/Views/Shared/WorkoutCardioViews.swift",
            "WGJ/Views/Templates/TemplateDetailView.swift",
            "WGJ/Views/Templates/TemplateEditorView.swift",
            "WGJ/Views/Workout/ActiveWorkoutCardioActivityCard.swift",
            "WGJ/Views/Workout/ActiveWorkoutTemplateSyncReviewSheet.swift",
            "WGJ/Views/Workout/ActiveWorkoutView.swift",
            "WGJ/Views/Workout/WorkoutCompletionSummaryView.swift",
        ]
        let bannedSourceFragments = [
            "title: \"Create Cardio\"",
            "subtitle: \"Name the activity and choose how you want to track it.\"",
            "return \"Outdoor walk or run\"",
            "return \"Treadmill\"",
            "return \"Machine distance\"",
            "return \"Rower\"",
            "return \"Stair climber\"",
            "return \"Time only\"",
            "return \"Pre-workout Cardio\"",
            "return \"Post-workout Cardio\"",
            "return \"Pre Cardio\"",
            "return \"Post Cardio\"",
            "\"Cardio Plan\",",
            "? \"1 activity\" : \"\\(activities.count) activities\"",
            "title: \"Added Cardio\"",
            "title: \"Removed Cardio\"",
            "title: \"Edited Cardio\"",
            "changes.append(\"Role updated\")",
            "changes.append(\"Exercise details updated\")",
            "changes.append(\"Tracking profile updated\")",
            "changes.append(\"Goal updated\")",
            "changes.append(\"Distance target updated\")",
            "changes.append(\"Distance unit updated\")",
            "return \"Cardio to prepare for the main work.\"",
            "return \"Primary cardio for this workout.\"",
            "return \"Cardio to close out the workout.\"",
        ]

        for path in cardioFeaturePaths {
            let source = try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
            for literal in bannedSourceFragments {
                XCTAssertFalse(source.contains(literal), "\(path) contains unlocalized cardio copy: \(literal)")
            }
        }

        let syncBuilder = try String(
            contentsOf: repositoryRoot.appending(path: "WGJ/Services/WorkoutTemplateSyncPreviewBuilder.swift"),
            encoding: .utf8
        )
        for semanticAPI in [
            "localized: \"Order ",
            "localized: \"Exercise ",
            "localized: \"Duration ",
        ] {
            XCTAssertTrue(syncBuilder.contains(semanticAPI), "Missing localized cardio summary API: \(semanticAPI)")
        }
    }

    func testCardioCatalogContainsEveryRequiredSurfaceKey() throws {
        let catalogURL = repositoryRoot.appending(path: "WGJ/WidgetShared/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let requiredKeys = [
            "Create Cardio",
            "Name the activity and choose how you want to track it.",
            "Outdoor walk or run",
            "Treadmill",
            "Machine distance",
            "Rower",
            "Stair climber",
            "Time only",
            "Cardio Plan",
            "Ordered activities saved with this template.",
            "1 activity",
            "%lld activities",
            "1 cardio activity",
            "%lld cardio activities",
            "Added Cardio",
            "Removed Cardio",
            "Edited Cardio",
            "1 cardio section added to the workout",
            "%lld cardio sections added to the workout",
            "1 cardio section removed from the template",
            "%lld cardio sections removed from the template",
            "Cardio phase settings that changed during the workout.",
            "Role updated",
            "Tracking profile updated",
            "Goal updated",
            "Distance target updated",
            "Distance unit updated",
            "Order %lld -> %lld",
            "Exercise %@ -> %@",
            "Exercise details updated",
            "Duration %@ -> %@",
            "Pre-workout Cardio",
            "Post-workout Cardio",
            "Pre Cardio",
            "Post Cardio",
        ]

        for key in requiredKeys {
            XCTAssertNotNil(strings[key], "Missing cardio localization key: \(key)")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
