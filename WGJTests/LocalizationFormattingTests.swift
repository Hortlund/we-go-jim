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
}
