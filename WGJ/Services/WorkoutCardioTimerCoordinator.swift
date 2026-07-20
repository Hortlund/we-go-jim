import Foundation

nonisolated enum WorkoutCardioTimerError: Error, Equatable, Sendable {
    case activityNotFound
    case invalidTransition
    case anotherActivityRunning(UUID)
}

nonisolated enum ActiveWorkoutCardioRequestedTimerTransition: Equatable, Sendable {
    case start(activityID: UUID)
    case resume(activityID: UUID)

    var activityID: UUID {
        switch self {
        case .start(let activityID), .resume(let activityID):
            return activityID
        }
    }

    var conflictConfirmationActionTitle: String {
        switch self {
        case .start:
            return String(localized: "Finish current and start new")
        case .resume:
            return String(localized: "Finish current and resume")
        }
    }

    var identifierComponent: String {
        switch self {
        case .start:
            return "start"
        case .resume:
            return "resume"
        }
    }

    func apply(
        to blocks: inout [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws {
        switch self {
        case .start(let activityID):
            try WorkoutCardioTimerCoordinator.start(
                activityID: activityID,
                blocks: &blocks,
                at: date
            )
        case .resume(let activityID):
            try WorkoutCardioTimerCoordinator.resume(
                activityID: activityID,
                blocks: &blocks,
                at: date
            )
        }
    }
}

nonisolated struct ActiveWorkoutCardioTimerConflict: Equatable, Sendable {
    let runningActivityID: UUID
    let requestedTransition: ActiveWorkoutCardioRequestedTimerTransition

    var identifier: String {
        "timer-conflict-\(runningActivityID)-\(requestedTransition.identifierComponent)-\(requestedTransition.activityID)"
    }

    func resolvedBlocks(
        from blocks: [ActiveWorkoutRuntimeCardioBlock],
        at date: Date
    ) throws -> [ActiveWorkoutRuntimeCardioBlock] {
        var resolved = blocks
        try WorkoutCardioTimerCoordinator.finish(
            activityID: runningActivityID,
            blocks: &resolved,
            at: date
        )
        try requestedTransition.apply(to: &resolved, at: date)
        return resolved
    }
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
        guard !blocks[activityIndex].isCompleted,
              blocks[activityIndex].timerState == .idle else {
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
        guard !blocks[activityIndex].isCompleted,
              blocks[activityIndex].timerState == .running else {
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
        guard !blocks[activityIndex].isCompleted,
              blocks[activityIndex].timerState == .paused else {
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
        guard !blocks[activityIndex].isCompleted else {
            throw WorkoutCardioTimerError.invalidTransition
        }

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
