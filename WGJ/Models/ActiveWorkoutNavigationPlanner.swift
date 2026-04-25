import Foundation

struct ActiveWorkoutScrollRestorePolicy: Equatable, Sendable {
    private var pendingRestoreTarget: ActiveWorkoutScrollTarget?

    init(pendingRestoreTarget: ActiveWorkoutScrollTarget? = nil) {
        self.pendingRestoreTarget = pendingRestoreTarget
    }

    static func initialTargetForNewPresentation() -> ActiveWorkoutScrollTarget? {
        nil
    }

    mutating func consumeRestoreTarget() -> ActiveWorkoutScrollTarget? {
        defer { pendingRestoreTarget = nil }
        return pendingRestoreTarget
    }
}

enum ActiveWorkoutSupersetNavigationPlanner {
    static func routeAfterCompletedSetCycle(
        position: SupersetExercisePosition,
        setIndex: Int,
        pairedExerciseID: UUID,
        pairedSetCyclesCompleted: [Bool]
    ) -> ActiveWorkoutScrollTarget? {
        switch position {
        case .first:
            guard pairedSetCyclesCompleted.indices.contains(setIndex),
                  !pairedSetCyclesCompleted[setIndex] else {
                return nil
            }
            return .exercise(pairedExerciseID)
        case .second:
            let nextSetIndex = setIndex + 1
            guard pairedSetCyclesCompleted.indices.contains(nextSetIndex),
                  !pairedSetCyclesCompleted[nextSetIndex] else {
                return nil
            }
            return .exercise(pairedExerciseID)
        }
    }
}
