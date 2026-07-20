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

nonisolated enum ActiveWorkoutCompletedExercisePresentationEffect: Equatable, Sendable {
    case none
    case collapseCard
}

nonisolated enum ActiveWorkoutCompletedExercisePresentationPolicy {
    static func effect(
        wasExpanded: Bool,
        automaticallyClosesCompletedExercises: Bool
    ) -> ActiveWorkoutCompletedExercisePresentationEffect {
        wasExpanded && automaticallyClosesCompletedExercises ? .collapseCard : .none
    }
}

nonisolated enum ActiveWorkoutScrollRestorePolicy {
    static func target(
        focusedExerciseID: UUID?,
        keyboardExerciseID: UUID?,
        trackedTarget: ActiveWorkoutScrollTarget?,
        expandedExerciseIDs: Set<UUID>,
        orderedExerciseIDs: [UUID],
        orderedCardioActivityIDsByRole: [WorkoutCardioRole: [UUID]],
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool,
        hasSession: Bool
    ) -> ActiveWorkoutScrollTarget? {
        if let focusedExerciseID {
            return .exercise(focusedExerciseID)
        }

        if let keyboardExerciseID {
            return .exercise(keyboardExerciseID)
        }

        if trackedTarget == .cancelSection {
            return terminalRestoreTarget(
                orderedExerciseIDs: orderedExerciseIDs,
                orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
                isRestorable: isRestorable
            ) ?? (hasSession ? .header : nil)
        }

        if let trackedTarget,
           trackedTarget != .header,
           let resolvedTrackedTarget = resolvedRestorableTarget(
               trackedTarget,
               orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
               isRestorable: isRestorable
           ) {
            return resolvedTrackedTarget
        }

        if let expandedExerciseID = orderedExerciseIDs.first(where: expandedExerciseIDs.contains) {
            return .exercise(expandedExerciseID)
        }

        if let trackedTarget,
           let resolvedTrackedTarget = resolvedRestorableTarget(
               trackedTarget,
               orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
               isRestorable: isRestorable
           ) {
            return resolvedTrackedTarget
        }

        return hasSession ? .header : nil
    }

    private static func terminalRestoreTarget(
        orderedExerciseIDs: [UUID],
        orderedCardioActivityIDsByRole: [WorkoutCardioRole: [UUID]],
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool
    ) -> ActiveWorkoutScrollTarget? {
        if let finisherTarget = lastRestorableCardioTarget(
            role: .finisher,
            orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
            isRestorable: isRestorable
        ) {
            return finisherTarget
        }

        if let exerciseTarget = orderedExerciseIDs.reversed()
            .map(ActiveWorkoutScrollTarget.exercise)
            .first(where: isRestorable) {
            return exerciseTarget
        }

        if let mainTarget = lastRestorableCardioTarget(
            role: .main,
            orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
            isRestorable: isRestorable
        ) {
            return mainTarget
        }

        if let warmUpTarget = lastRestorableCardioTarget(
            role: .warmUp,
            orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
            isRestorable: isRestorable
        ) {
            return warmUpTarget
        }

        if isRestorable(.header) {
            return .header
        }

        return nil
    }

    static func resolvedRestorableTarget(
        _ target: ActiveWorkoutScrollTarget,
        orderedCardioActivityIDsByRole: [WorkoutCardioRole: [UUID]],
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool
    ) -> ActiveWorkoutScrollTarget? {
        if case .cardio(let role, nil) = target {
            return orderedCardioActivityIDsByRole[role, default: []]
                .lazy
                .map { ActiveWorkoutScrollTarget.cardio(role: role, activityID: $0) }
                .first(where: isRestorable)
        }

        return isRestorable(target) ? target : nil
    }

    private static func lastRestorableCardioTarget(
        role: WorkoutCardioRole,
        orderedCardioActivityIDsByRole: [WorkoutCardioRole: [UUID]],
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool
    ) -> ActiveWorkoutScrollTarget? {
        orderedCardioActivityIDsByRole[role, default: []]
            .reversed()
            .lazy
            .map { ActiveWorkoutScrollTarget.cardio(role: role, activityID: $0) }
            .first(where: isRestorable)
    }
}
