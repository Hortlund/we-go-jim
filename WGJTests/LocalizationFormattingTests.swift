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

    func testTypedCardioCopyCoversDomainEnums() {
        XCTAssertEqual(
            WorkoutCardioRole.allCases.map(CardioLocalizedCopy.roleTitle),
            ["Warm-up", "Main Cardio", "Finisher"]
        )
        XCTAssertEqual(
            WorkoutCardioRole.allCases.map(CardioLocalizedCopy.compactRoleTitle),
            ["Warm-up", "Main", "Finisher"]
        )
        XCTAssertEqual(
            WorkoutCardioRole.allCases.map(CardioLocalizedCopy.roleSubtitle),
            [
                "Cardio to prepare for the main work.",
                "Primary cardio for this workout.",
                "Cardio to close out the workout.",
            ]
        )
        XCTAssertEqual(
            WorkoutCardioGoalKind.allCases.map(CardioLocalizedCopy.goalTitle),
            ["Time", "Distance", "No Target"]
        )
        XCTAssertEqual(
            WorkoutCardioGoalKind.allCases.map {
                CardioLocalizedCopy.activeGoalSummary(
                    $0,
                    formattedValue: $0 == .time ? "5:00" : nil
                )
            },
            ["Goal · 5:00", "Distance goal", "No target"]
        )
        XCTAssertEqual(
            WorkoutCardioGoalKind.allCases.map {
                CardioLocalizedCopy.activeGoalAccessibilitySummary(
                    $0,
                    formattedValue: $0 == .time ? "5 minutes, 0 seconds" : "2 kilometers"
                )
            },
            ["Goal, 5 minutes, 0 seconds", "Goal, 2 kilometers", "No target"]
        )
        XCTAssertEqual(
            WorkoutCardioTrackingProfile.allCases.map(CardioLocalizedCopy.trackingProfileTitle),
            ["Outdoor walk or run", "Treadmill", "Machine distance", "Rower", "Stair climber", "Time only"]
        )
        XCTAssertEqual(
            WorkoutCardioPhase.allCases.map(CardioLocalizedCopy.phaseTitle),
            ["Pre-workout Cardio", "Post-workout Cardio"]
        )
        XCTAssertEqual(
            WorkoutCardioPhase.allCases.map(CardioLocalizedCopy.compactPhaseTitle),
            ["Pre Cardio", "Post Cardio"]
        )
    }

    func testTypedCardioCopyCoversActionsStatesAndValidation() {
        XCTAssertEqual(
            CardioLocalizedCopy.Action.allCases.map(CardioLocalizedCopy.actionTitle),
            ["Start", "Pause", "Resume", "Finish", "Edit Result"]
        )
        XCTAssertEqual(
            CardioLocalizedCopy.Action.allCases.map { CardioLocalizedCopy.actionAccessibilityLabel($0, activityName: "Bike") },
            ["Start Bike", "Pause Bike", "Resume Bike", "Finish Bike", "Edit Result Bike"]
        )
        XCTAssertEqual(
            CardioLocalizedCopy.State.allCases.map(CardioLocalizedCopy.stateTitle),
            ["Ready", "Running", "Paused", "Complete"]
        )

        let resultErrors: [WorkoutCardioResultValidationError] = [
            .negativeDuration,
            .invalidDistance,
            .missingDurationAndDistance,
            .invalidIncline,
            .invalidResistanceLevel,
            .negativeResistanceLevel,
        ]
        XCTAssertEqual(
            resultErrors.map(CardioLocalizedCopy.resultValidationMessage),
            [
                "Duration cannot be negative.",
                "Enter a valid distance, or leave it empty.",
                "Enter a duration or distance.",
                "Enter a valid incline percentage.",
                "Enter a valid resistance or level.",
                "Resistance or level cannot be negative.",
            ]
        )
        XCTAssertEqual(
            [
                WorkoutCardioSetupValidationError.durationMustBePositive,
                .distanceMustBePositive(unit: .kilometers),
                .distanceMustBePositive(unit: .miles),
                .distanceMustBePositive(unit: .meters),
            ].map(CardioLocalizedCopy.setupValidationMessage),
            [
                "Enter a duration greater than 0 minutes.",
                "Enter a distance greater than 0 kilometers.",
                "Enter a distance greater than 0 miles.",
                "Enter a distance greater than 0 meters.",
            ]
        )
    }

    func testTypedCardioCopyCoversCountsSyncAndConfirmations() {
        XCTAssertEqual(CardioLocalizedCopy.activityCount(1), "1 activity")
        XCTAssertEqual(CardioLocalizedCopy.activityCount(3), "3 activities")
        XCTAssertEqual(CardioLocalizedCopy.cardioActivityCount(1), "1 cardio activity")
        XCTAssertEqual(CardioLocalizedCopy.cardioActivityCount(3), "3 cardio activities")
        XCTAssertEqual(CardioLocalizedCopy.addedCardioSectionCount(1), "1 cardio section added to the workout")
        XCTAssertEqual(CardioLocalizedCopy.addedCardioSectionCount(3), "3 cardio sections added to the workout")
        XCTAssertEqual(CardioLocalizedCopy.removedCardioSectionCount(1), "1 cardio section removed from the template")
        XCTAssertEqual(CardioLocalizedCopy.removedCardioSectionCount(3), "3 cardio sections removed from the template")

        XCTAssertEqual(
            CardioLocalizedCopy.SyncChange.allCases.map(CardioLocalizedCopy.syncChange),
            [
                "Role updated",
                "Exercise details updated",
                "Tracking profile updated",
                "Goal updated",
                "Distance target updated",
                "Distance unit updated",
            ]
        )
        XCTAssertEqual(CardioLocalizedCopy.syncOrderChange(from: 1, to: 2), "Order 1 -> 2")
        XCTAssertEqual(CardioLocalizedCopy.syncExerciseChange(from: "Walk", to: "Run"), "Exercise Walk -> Run")
        XCTAssertEqual(CardioLocalizedCopy.syncDurationChange(from: "5 min", to: "10 min"), "Duration 5 min -> 10 min")

        XCTAssertEqual(
            CardioLocalizedCopy.Confirmation.allCases.map { CardioLocalizedCopy.confirmationTitle($0, activityName: "Bike") },
            ["Another cardio activity is running", "Change Bike?", "Remove Bike?"]
        )
        XCTAssertEqual(
            CardioLocalizedCopy.Confirmation.allCases.map(CardioLocalizedCopy.confirmationMessage),
            [
                "Only one cardio timer can run at a time.",
                "Recorded cardio data will be cleared. This cannot be undone.",
                "This activity contains saved progress or a result. Removing it cannot be undone.",
            ]
        )
        XCTAssertEqual(
            CardioLocalizedCopy.TimerConflictResolution.allCases.map(CardioLocalizedCopy.timerConflictResolutionTitle),
            ["Finish current and start new", "Finish current and resume"]
        )
        XCTAssertEqual(CardioLocalizedCopy.replacementWarning, "Recorded cardio data will be cleared.")
    }

    func testCardioCatalogContainsEveryRequiredSurfaceKey() throws {
        let catalogURL = repositoryRoot.appending(path: "WGJ/WidgetShared/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let requiredKeys = [
            "Warm-up",
            "Main Cardio",
            "Main",
            "Finisher",
            "Cardio to prepare for the main work.",
            "Primary cardio for this workout.",
            "Cardio to close out the workout.",
            "Time",
            "Distance",
            "No Target",
            "Goal · %@",
            "Goal, %@",
            "Distance goal",
            "No target",
            "Create Cardio",
            "Name the activity and choose how you want to track it.",
            "Outdoor walk or run",
            "Treadmill",
            "Machine distance",
            "Rower",
            "Stair climber",
            "Time only",
            "Start",
            "Pause",
            "Resume",
            "Finish",
            "Edit Result",
            "Start %@",
            "Pause %@",
            "Resume %@",
            "Finish %@",
            "Edit Result %@",
            "Ready",
            "Running",
            "Paused",
            "Complete",
            "Duration cannot be negative.",
            "Enter a valid distance, or leave it empty.",
            "Enter a duration or distance.",
            "Enter a valid incline percentage.",
            "Enter a valid resistance or level.",
            "Resistance or level cannot be negative.",
            "Enter a duration greater than 0 minutes.",
            "Enter a distance greater than 0 kilometers.",
            "Enter a distance greater than 0 miles.",
            "Enter a distance greater than 0 meters.",
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
            "Another cardio activity is running",
            "Change %@?",
            "Remove %@?",
            "Only one cardio timer can run at a time.",
            "Recorded cardio data will be cleared. This cannot be undone.",
            "This activity contains saved progress or a result. Removing it cannot be undone.",
            "Finish current and start new",
            "Finish current and resume",
            "Recorded cardio data will be cleared.",
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
