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

    func testRecordedDataPolicyCoversIncompleteResultsDetailsAndTimerProgress() {
        XCTAssertFalse(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(activity: .fixture())
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(actualDurationSeconds: 600)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(actualDistanceMeters: 5_000)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(inclinePercent: 4.5)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(resistanceLevel: 7)
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(cardioNotes: "Steady effort")
            )
        )
        XCTAssertTrue(
            ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(
                activity: .fixture(timerAccumulatedSeconds: 45)
            )
        )
    }

    func testReplacementRequiresConfirmationUnlessActivityIsIdleAndRecordedDataEmpty() {
        XCTAssertEqual(
            ActiveWorkoutCardioReplacementPolicy.decision(activity: .fixture()),
            .replaceDirectly
        )

        let recordedActivities: [ActiveWorkoutRuntimeCardioBlock] = [
            .fixture(actualDurationSeconds: 600),
            .fixture(actualDistanceMeters: 5_000),
            .fixture(inclinePercent: 4.5),
            .fixture(resistanceLevel: 7),
            .fixture(cardioNotes: "Steady effort"),
            .fixture(timerAccumulatedSeconds: 45),
            .fixture(isCompleted: true),
            .fixture(
                timerState: .running,
                timerSegmentStartedAt: Date(timeIntervalSince1970: 50)
            )
        ]

        for activity in recordedActivities {
            XCTAssertEqual(
                ActiveWorkoutCardioReplacementPolicy.decision(activity: activity),
                .confirmClearingRecordedData
            )
        }
        XCTAssertEqual(
            ActiveWorkoutCardioReplacementPolicy.confirmationMessage,
            "Recorded cardio data will be cleared."
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
        inclinePercent: Double? = nil,
        resistanceLevel: Double? = nil,
        cardioNotes: String = "",
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
            inclinePercent: inclinePercent,
            resistanceLevel: resistanceLevel,
            cardioNotes: cardioNotes,
            timerState: timerState,
            timerSegmentStartedAt: timerSegmentStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds,
            isCompleted: isCompleted,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
