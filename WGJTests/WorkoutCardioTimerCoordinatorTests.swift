import XCTest
@testable import WGJ

final class WorkoutCardioTimerCoordinatorTests: XCTestCase {
    func testPauseAndResumeAccumulateOnlyRunningIntervals() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]

        try WorkoutCardioTimerCoordinator.start(activityID: blocks[0].id, blocks: &blocks, at: base)
        try WorkoutCardioTimerCoordinator.pause(
            activityID: blocks[0].id,
            blocks: &blocks,
            at: base.addingTimeInterval(40)
        )
        try WorkoutCardioTimerCoordinator.resume(
            activityID: blocks[0].id,
            blocks: &blocks,
            at: base.addingTimeInterval(100)
        )

        XCTAssertEqual(
            WorkoutCardioTimerCoordinator.elapsedSeconds(
                for: blocks[0],
                at: base.addingTimeInterval(130)
            ),
            70
        )
    }

    func testStartingSecondActivityReturnsConflictWithoutMutation() throws {
        let firstID = UUID()
        let secondID = UUID()
        var blocks = [
            ActiveWorkoutRuntimeCardioBlock.fixture(id: firstID),
            .fixture(id: secondID)
        ]

        try WorkoutCardioTimerCoordinator.start(activityID: firstID, blocks: &blocks, at: .now)

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.start(activityID: secondID, blocks: &blocks, at: .now)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .anotherActivityRunning(firstID))
        }
        XCTAssertEqual(blocks[1].timerState, .idle)
        XCTAssertNil(blocks[1].timerSegmentStartedAt)
        XCTAssertEqual(blocks[1].timerAccumulatedSeconds, 0)
    }

    func testElapsedSecondsReconstructsRunningSegmentAfterColdLaunch() {
        let base = Date(timeIntervalSince1970: 1_000)
        let activity = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .running,
            timerSegmentStartedAt: base,
            timerAccumulatedSeconds: 45
        )

        XCTAssertEqual(
            WorkoutCardioTimerCoordinator.elapsedSeconds(for: activity, at: base.addingTimeInterval(25)),
            70
        )
    }

    func testPauseClampsBackwardClockMovementWithoutReducingAccumulatedTime() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var blocks = [
            ActiveWorkoutRuntimeCardioBlock.fixture(
                timerState: .running,
                timerSegmentStartedAt: base.addingTimeInterval(60),
                timerAccumulatedSeconds: 15
            )
        ]

        XCTAssertEqual(WorkoutCardioTimerCoordinator.elapsedSeconds(for: blocks[0], at: base), 15)

        try WorkoutCardioTimerCoordinator.pause(activityID: blocks[0].id, blocks: &blocks, at: base)

        XCTAssertEqual(blocks[0].timerAccumulatedSeconds, 15)
        XCTAssertEqual(blocks[0].timerState, .paused)
        XCTAssertNil(blocks[0].timerSegmentStartedAt)
    }

    func testFinishCopiesPositiveElapsedTimeToActualDurationAndMarksCompleted() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]

        try WorkoutCardioTimerCoordinator.start(activityID: blocks[0].id, blocks: &blocks, at: base)
        try WorkoutCardioTimerCoordinator.finish(
            activityID: blocks[0].id,
            blocks: &blocks,
            at: base.addingTimeInterval(90)
        )

        XCTAssertEqual(blocks[0].timerAccumulatedSeconds, 90)
        XCTAssertEqual(blocks[0].actualDurationSeconds, 90)
        XCTAssertEqual(blocks[0].timerState, .idle)
        XCTAssertNil(blocks[0].timerSegmentStartedAt)
        XCTAssertTrue(blocks[0].isCompleted)
    }

    func testFinishWithZeroElapsedTimeLeavesActualDurationAbsent() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]

        try WorkoutCardioTimerCoordinator.finish(activityID: blocks[0].id, blocks: &blocks, at: base)

        XCTAssertEqual(blocks[0].timerAccumulatedSeconds, 0)
        XCTAssertNil(blocks[0].actualDurationSeconds)
        XCTAssertEqual(blocks[0].timerState, .idle)
        XCTAssertNil(blocks[0].timerSegmentStartedAt)
        XCTAssertTrue(blocks[0].isCompleted)
    }

    func testPauseRejectsIdleActivityWithoutMutation() {
        let activity = ActiveWorkoutRuntimeCardioBlock.fixture()
        var blocks = [activity]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.pause(activityID: activity.id, blocks: &blocks, at: .now)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [activity])
    }

    func testTransitionForMissingActivityReturnsNotFound() {
        var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.start(activityID: UUID(), blocks: &blocks, at: .now)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .activityNotFound)
        }
    }
}

private extension ActiveWorkoutRuntimeCardioBlock {
    static func fixture(
        id: UUID = UUID(),
        timerState: WorkoutCardioTimerState = .idle,
        timerSegmentStartedAt: Date? = nil,
        timerAccumulatedSeconds: Int = 0
    ) -> Self {
        ActiveWorkoutRuntimeCardioBlock(
            id: id,
            phase: .preWorkout,
            role: .warmUp,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 1_200,
            timerState: timerState,
            timerSegmentStartedAt: timerSegmentStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
