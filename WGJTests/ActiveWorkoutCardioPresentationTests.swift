import XCTest
@testable import WGJ

final class ActiveWorkoutCardioPresentationTests: XCTestCase {
    func testTimerTickChangesOnlyElapsedText() {
        let activity = ActiveWorkoutRuntimeCardioBlock.runningFixture()

        let first = ActiveWorkoutCardioPresentation.make(
            activity: activity,
            at: Date(timeIntervalSince1970: 100)
        )
        let second = ActiveWorkoutCardioPresentation.make(
            activity: activity,
            at: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.role, second.role)
        XCTAssertEqual(first.actionLayout, second.actionLayout)
        XCTAssertEqual(first.reservedTimerWidth, second.reservedTimerWidth)
        XCTAssertEqual(first.layoutIdentity, second.layoutIdentity)
        XCTAssertNotEqual(first.elapsedText, second.elapsedText)
    }

    func testCardStatesExposeStableExpectedActions() {
        let idle = ActiveWorkoutCardioPresentation.make(activity: .fixture(timerState: .idle))
        let running = ActiveWorkoutCardioPresentation.make(activity: .runningFixture())
        let paused = ActiveWorkoutCardioPresentation.make(
            activity: .fixture(timerState: .paused, timerAccumulatedSeconds: 75)
        )
        let completed = ActiveWorkoutCardioPresentation.make(
            activity: .fixture(actualDurationSeconds: 600, isCompleted: true)
        )

        XCTAssertEqual(idle.state, .idle)
        XCTAssertEqual(idle.actionLayout, [.start])
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(running.actionLayout, [.pause, .finish])
        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.actionLayout, [.resume, .finish])
        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(completed.actionLayout, [.editResult])
    }

    func testQuickAddDefaultsToMainWithoutStrengthAndFinisherWithStrength() {
        XCTAssertEqual(
            ActiveWorkoutCardioQuickAddPolicy.defaultRole(hasStrengthExercises: false),
            .main
        )
        XCTAssertEqual(
            ActiveWorkoutCardioQuickAddPolicy.defaultRole(hasStrengthExercises: true),
            .finisher
        )
    }

    func testResultRemovalRequiresConfirmationButEmptyPlanDoesNot() {
        XCTAssertFalse(
            ActiveWorkoutCardioRemovalPolicy.requiresConfirmation(
                activity: .fixture()
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRemovalPolicy.requiresConfirmation(
                activity: .fixture(actualDurationSeconds: 600)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRemovalPolicy.requiresConfirmation(
                activity: .fixture(actualDistanceMeters: 5_000)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRemovalPolicy.requiresConfirmation(
                activity: .fixture(isCompleted: true)
            )
        )
    }

    func testFinishedResultPrefillRetainsExactActivityResult() {
        let activity = ActiveWorkoutRuntimeCardioBlock.fixture(
            actualDurationSeconds: 755,
            actualDistanceMeters: 2_500,
            isCompleted: true
        )
        let prefill = ActiveWorkoutPendingCardioResult.make(activity: activity)

        XCTAssertEqual(prefill.id, activity.id)
        XCTAssertEqual(prefill.activityName, activity.exerciseNameSnapshot)
        XCTAssertEqual(prefill.actualDurationSeconds, 755)
        XCTAssertEqual(prefill.actualDistanceMeters, 2_500)
        XCTAssertTrue(prefill.isCompleted)
    }
}

private extension ActiveWorkoutRuntimeCardioBlock {
    static func runningFixture() -> Self {
        fixture(
            timerState: .running,
            timerSegmentStartedAt: Date(timeIntervalSince1970: 90),
            timerAccumulatedSeconds: 5
        )
    }

    static func fixture(
        timerState: WorkoutCardioTimerState = .idle,
        timerSegmentStartedAt: Date? = nil,
        timerAccumulatedSeconds: Int = 0,
        actualDurationSeconds: Int? = nil,
        actualDistanceMeters: Double? = nil,
        isCompleted: Bool = false
    ) -> Self {
        ActiveWorkoutRuntimeCardioBlock(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            phase: .preWorkout,
            role: .main,
            catalogExerciseUUID: "seed-treadmill-walk",
            exerciseNameSnapshot: "Treadmill Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            trackingProfile: .treadmill,
            goalKind: .time,
            targetDurationSeconds: 1_200,
            targetDistanceMeters: nil,
            actualDurationSeconds: actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters,
            preferredDistanceUnit: .kilometers,
            timerState: timerState,
            timerSegmentStartedAt: timerSegmentStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds,
            isCompleted: isCompleted,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
