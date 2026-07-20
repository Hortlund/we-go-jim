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
}
