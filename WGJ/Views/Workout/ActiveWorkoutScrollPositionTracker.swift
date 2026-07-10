import SwiftUI

/// Receives high-frequency `scrollPosition` writes without participating in view observation.
/// ActiveWorkoutView reads the latest value only at explicit persistence/restore boundaries.
nonisolated final class ActiveWorkoutScrollPositionTracker {
    @MainActor var currentTarget: ActiveWorkoutScrollTarget?

    @MainActor
    var binding: Binding<ActiveWorkoutScrollTarget?> {
        Binding(
            get: { [weak self] in self?.currentTarget },
            set: { [weak self] in self?.currentTarget = $0 }
        )
    }
}

nonisolated enum ActiveWorkoutScrollRestorePolicy {
    static func target(
        focusedExerciseID: UUID?,
        keyboardExerciseID: UUID?,
        trackedTarget: ActiveWorkoutScrollTarget?,
        expandedExerciseIDs: Set<UUID>,
        orderedExerciseIDs: [UUID],
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool,
        hasSession: Bool
    ) -> ActiveWorkoutScrollTarget? {
        if let focusedExerciseID {
            return .exercise(focusedExerciseID)
        }

        if let keyboardExerciseID {
            return .exercise(keyboardExerciseID)
        }

        if let trackedTarget,
           trackedTarget != .header,
           isRestorable(trackedTarget) {
            return trackedTarget
        }

        if let expandedExerciseID = orderedExerciseIDs.first(where: expandedExerciseIDs.contains) {
            return .exercise(expandedExerciseID)
        }

        if let trackedTarget, isRestorable(trackedTarget) {
            return trackedTarget
        }

        return hasSession ? .header : nil
    }
}
