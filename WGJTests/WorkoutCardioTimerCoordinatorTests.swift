import XCTest
@testable import WGJ

final class WorkoutCardioTimerCoordinatorTests: XCTestCase {
    private enum TestError: Error { case finish }

    func testConflictOrchestratorCommitsFinishBeforeRequestedTransition() throws {
        let runningID = UUID()
        let requested = ActiveWorkoutCardioRequestedTimerTransition.start(activityID: UUID())
        var boundaries: [ActiveWorkoutCardioConflictTransitionOrchestrator.Boundary] = []

        try ActiveWorkoutCardioConflictTransitionOrchestrator.perform(
            conflict: .init(runningActivityID: runningID, requestedTransition: requested)
        ) { boundary in
            boundaries.append(boundary)
        }

        XCTAssertEqual(boundaries, [.finishCurrent(runningID), .requested(requested)])
    }

    func testConflictOrchestratorDoesNotAttemptRequestedTransitionWhenFinishFails() {
        let runningID = UUID()
        let requested = ActiveWorkoutCardioRequestedTimerTransition.resume(activityID: UUID())
        var boundaries: [ActiveWorkoutCardioConflictTransitionOrchestrator.Boundary] = []

        XCTAssertThrowsError(
            try ActiveWorkoutCardioConflictTransitionOrchestrator.perform(
                conflict: .init(runningActivityID: runningID, requestedTransition: requested)
            ) { boundary in
                boundaries.append(boundary)
                if case .finishCurrent = boundary { throw TestError.finish }
            }
        )

        XCTAssertEqual(boundaries, [.finishCurrent(runningID)])
    }

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

    func testStartConflictResolutionFinishesCurrentAndStartsRequestedActivity() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        let runningID = UUID()
        let requestedID = UUID()
        var blocks = [
            ActiveWorkoutRuntimeCardioBlock.fixture(
                id: runningID,
                timerState: .running,
                timerSegmentStartedAt: base
            ),
            .fixture(id: requestedID)
        ]
        let requestedTransition = ActiveWorkoutCardioRequestedTimerTransition.start(
            activityID: requestedID
        )

        XCTAssertThrowsError(
            try requestedTransition.apply(to: &blocks, at: base.addingTimeInterval(60))
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .anotherActivityRunning(runningID))
        }

        let conflict = ActiveWorkoutCardioTimerConflict(
            runningActivityID: runningID,
            requestedTransition: requestedTransition
        )
        blocks = try conflict.resolvedBlocks(from: blocks, at: base.addingTimeInterval(60))

        XCTAssertTrue(blocks[0].isCompleted)
        XCTAssertEqual(blocks[0].actualDurationSeconds, 60)
        XCTAssertEqual(blocks[0].timerState, .idle)
        XCTAssertEqual(blocks[1].timerState, .running)
        XCTAssertEqual(blocks[1].timerSegmentStartedAt, base.addingTimeInterval(60))
        XCTAssertFalse(blocks[1].isCompleted)
    }

    func testResumeConflictResolutionFinishesCurrentAndResumesRequestedActivity() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        let runningID = UUID()
        let requestedID = UUID()
        var blocks = [
            ActiveWorkoutRuntimeCardioBlock.fixture(
                id: runningID,
                timerState: .running,
                timerSegmentStartedAt: base
            ),
            .fixture(
                id: requestedID,
                timerState: .paused,
                timerAccumulatedSeconds: 30
            )
        ]
        let requestedTransition = ActiveWorkoutCardioRequestedTimerTransition.resume(
            activityID: requestedID
        )

        XCTAssertThrowsError(
            try requestedTransition.apply(to: &blocks, at: base.addingTimeInterval(60))
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .anotherActivityRunning(runningID))
        }

        let conflict = ActiveWorkoutCardioTimerConflict(
            runningActivityID: runningID,
            requestedTransition: requestedTransition
        )
        blocks = try conflict.resolvedBlocks(from: blocks, at: base.addingTimeInterval(60))

        XCTAssertTrue(blocks[0].isCompleted)
        XCTAssertEqual(blocks[0].actualDurationSeconds, 60)
        XCTAssertEqual(blocks[0].timerState, .idle)
        XCTAssertEqual(blocks[1].timerState, .running)
        XCTAssertEqual(blocks[1].timerSegmentStartedAt, base.addingTimeInterval(60))
        XCTAssertEqual(blocks[1].timerAccumulatedSeconds, 30)
        XCTAssertFalse(blocks[1].isCompleted)
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

    func testStartRejectsCompletedActivityWithoutMutation() {
        let activity = ActiveWorkoutRuntimeCardioBlock.fixture(
            actualDurationSeconds: 75,
            timerAccumulatedSeconds: 90,
            isCompleted: true
        )
        var blocks = [activity]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.start(activityID: activity.id, blocks: &blocks, at: .now)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [activity])
    }

    func testFinishRejectsCompletedActivityWithoutMutation() {
        let activity = ActiveWorkoutRuntimeCardioBlock.fixture(
            actualDurationSeconds: 75,
            timerAccumulatedSeconds: 90,
            isCompleted: true
        )
        var blocks = [activity]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.finish(activityID: activity.id, blocks: &blocks, at: .now)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [activity])
    }

    func testPauseAndResumeRejectCompletedActivitiesWithoutMutation() {
        let base = Date(timeIntervalSince1970: 1_000)
        let running = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .running,
            timerSegmentStartedAt: base,
            isCompleted: true
        )
        let paused = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .paused,
            timerAccumulatedSeconds: 30,
            isCompleted: true
        )
        var blocks = [running, paused]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.pause(
                activityID: running.id,
                blocks: &blocks,
                at: base.addingTimeInterval(30)
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.resume(
                activityID: paused.id,
                blocks: &blocks,
                at: base.addingTimeInterval(30)
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [running, paused])
    }

    func testResumeRejectsConflictWithoutMutation() {
        let base = Date(timeIntervalSince1970: 1_000)
        let running = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .running,
            timerSegmentStartedAt: base
        )
        let paused = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .paused,
            timerAccumulatedSeconds: 30
        )
        var blocks = [running, paused]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.resume(
                activityID: paused.id,
                blocks: &blocks,
                at: base.addingTimeInterval(60)
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .anotherActivityRunning(running.id))
        }
        XCTAssertEqual(blocks, [running, paused])
    }

    func testStartRejectsAlreadyRunningActivityWithoutMutation() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]
        try WorkoutCardioTimerCoordinator.start(activityID: blocks[0].id, blocks: &blocks, at: base)
        let running = blocks[0]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.start(
                activityID: running.id,
                blocks: &blocks,
                at: base.addingTimeInterval(30)
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [running])
    }

    func testResumeRejectsIdleAndRunningActivitiesWithoutMutation() {
        let base = Date(timeIntervalSince1970: 1_000)
        let idle = ActiveWorkoutRuntimeCardioBlock.fixture()
        let running = ActiveWorkoutRuntimeCardioBlock.fixture(
            timerState: .running,
            timerSegmentStartedAt: base
        )
        var blocks = [idle, running]

        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.resume(activityID: idle.id, blocks: &blocks, at: base)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertThrowsError(
            try WorkoutCardioTimerCoordinator.resume(activityID: running.id, blocks: &blocks, at: base)
        ) {
            XCTAssertEqual($0 as? WorkoutCardioTimerError, .invalidTransition)
        }
        XCTAssertEqual(blocks, [idle, running])
    }

    func testFinishFromPausedCopiesAccumulatedDuration() throws {
        var blocks = [
            ActiveWorkoutRuntimeCardioBlock.fixture(
                timerState: .paused,
                timerAccumulatedSeconds: 45
            )
        ]

        try WorkoutCardioTimerCoordinator.finish(activityID: blocks[0].id, blocks: &blocks, at: .now)

        XCTAssertEqual(blocks[0].timerState, .idle)
        XCTAssertNil(blocks[0].timerSegmentStartedAt)
        XCTAssertEqual(blocks[0].timerAccumulatedSeconds, 45)
        XCTAssertEqual(blocks[0].actualDurationSeconds, 45)
        XCTAssertTrue(blocks[0].isCompleted)
    }
}

private extension ActiveWorkoutRuntimeCardioBlock {
    static func fixture(
        id: UUID = UUID(),
        actualDurationSeconds: Int? = nil,
        timerState: WorkoutCardioTimerState = .idle,
        timerSegmentStartedAt: Date? = nil,
        timerAccumulatedSeconds: Int = 0,
        isCompleted: Bool = false
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
            actualDurationSeconds: actualDurationSeconds,
            timerState: timerState,
            timerSegmentStartedAt: timerSegmentStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds,
            isCompleted: isCompleted,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
