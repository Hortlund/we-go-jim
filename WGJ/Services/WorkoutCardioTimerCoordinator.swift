import Foundation

nonisolated enum WorkoutCardioTimerError: Error, Equatable, Sendable {
    case activityNotFound
    case invalidTransition
    case anotherActivityRunning(UUID)
}

nonisolated enum WorkoutCardioTimerCoordinator {
    static func elapsedSeconds(
        for activity: ActiveWorkoutRuntimeCardioBlock,
        at date: Date
    ) -> Int {
        let currentSegmentSeconds = activity.timerState == .running
            ? max(0, Int(date.timeIntervalSince(activity.timerSegmentStartedAt ?? date)))
            : 0

        return max(0, activity.timerAccumulatedSeconds + currentSegmentSeconds)
    }

    static func start(
        activityID: UUID,
        blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws {
        let activityIndex = try index(of: activityID, in: blocks)
        guard blocks[activityIndex].timerState == .idle else {
            throw WorkoutCardioTimerError.invalidTransition
        }
        try ensureNoOtherActivityIsRunning(activityID: activityID, in: blocks)

        blocks[activityIndex].timerState = .running
        blocks[activityIndex].timerSegmentStartedAt = date
    }

    static func pause(
        activityID: UUID,
        blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws {
        let activityIndex = try index(of: activityID, in: blocks)
        guard blocks[activityIndex].timerState == .running else {
            throw WorkoutCardioTimerError.invalidTransition
        }

        foldRunningSegment(at: activityIndex, in: &blocks, at: date)
        blocks[activityIndex].timerState = .paused
    }

    static func resume(
        activityID: UUID,
        blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws {
        let activityIndex = try index(of: activityID, in: blocks)
        guard blocks[activityIndex].timerState == .paused else {
            throw WorkoutCardioTimerError.invalidTransition
        }
        try ensureNoOtherActivityIsRunning(activityID: activityID, in: blocks)

        blocks[activityIndex].timerState = .running
        blocks[activityIndex].timerSegmentStartedAt = date
    }

    static func finish(
        activityID: UUID,
        blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws {
        let activityIndex = try index(of: activityID, in: blocks)

        if blocks[activityIndex].timerState == .running {
            foldRunningSegment(at: activityIndex, in: &blocks, at: date)
        } else {
            blocks[activityIndex].timerSegmentStartedAt = nil
        }

        let elapsedSeconds = blocks[activityIndex].timerAccumulatedSeconds
        blocks[activityIndex].timerState = .idle
        blocks[activityIndex].actualDurationSeconds = elapsedSeconds > 0 ? elapsedSeconds : nil
        blocks[activityIndex].isCompleted = true
    }

    private static func index(
        of activityID: UUID,
        in blocks: [ActiveWorkoutRuntimeCardioBlock]
    ) throws -> Int {
        guard let index = blocks.firstIndex(where: { $0.id == activityID }) else {
            throw WorkoutCardioTimerError.activityNotFound
        }
        return index
    }

    private static func ensureNoOtherActivityIsRunning(
        activityID: UUID,
        in blocks: [ActiveWorkoutRuntimeCardioBlock]
    ) throws {
        if let runningActivityID = blocks.first(where: {
            $0.id != activityID && $0.timerState == .running
        })?.id {
            throw WorkoutCardioTimerError.anotherActivityRunning(runningActivityID)
        }
    }

    private static func foldRunningSegment(
        at activityIndex: Int,
        in blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) {
        blocks[activityIndex].timerAccumulatedSeconds = elapsedSeconds(
            for: blocks[activityIndex],
            at: date
        )
        blocks[activityIndex].timerSegmentStartedAt = nil
    }
}
