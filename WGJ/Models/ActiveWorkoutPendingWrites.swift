import Foundation

nonisolated enum WorkoutSetRowIdentityResolver {
    static func currentIndex(
        for setID: UUID,
        in drafts: [WorkoutSessionSetDraft]
    ) -> Int? {
        drafts.firstIndex { $0.id == setID }
    }
}

nonisolated enum ActiveWorkoutEditorCommitDisposition: Equatable, Sendable {
    case none
    case debounced
    case immediate

    static func fieldChange<Value: Equatable>(previous: Value, current: Value) -> Self {
        previous == current ? .none : .debounced
    }
}

nonisolated enum ActiveWorkoutEditorFocusCommitPolicy {
    static func dispositionForMetricFocusChange(
        previousHadFocus: Bool,
        newHasFocus: Bool,
        committedBufferedValueChange: Bool
    ) -> ActiveWorkoutEditorCommitDisposition {
        guard previousHadFocus, committedBufferedValueChange else {
            return .none
        }

        return newHasFocus ? .debounced : .immediate
    }
}

nonisolated struct ActiveWorkoutSetDraftChangeSummary: Equatable, Sendable {
    let hasStructuralChange: Bool
    let hasCompletionChange: Bool
    let hasValueChange: Bool

    var hasMeaningfulChange: Bool {
        hasStructuralChange || hasCompletionChange
    }

    var commitDisposition: ActiveWorkoutEditorCommitDisposition {
        if hasMeaningfulChange {
            return .immediate
        }

        return hasValueChange ? .debounced : .none
    }

    static func compare(
        previous: [WorkoutSessionSetDraft],
        current: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutSetDraftChangeSummary {
        if previous.count != current.count {
            return ActiveWorkoutSetDraftChangeSummary(
                hasStructuralChange: true,
                hasCompletionChange: completionChanged(previous: previous, current: current),
                hasValueChange: false
            )
        }

        var hasStructuralChange = false
        var hasCompletionChange = false
        var hasValueChange = false

        for (previousDraft, currentDraft) in zip(previous, current) {
            if previousDraft.id != currentDraft.id {
                hasStructuralChange = true
            }
            if previousDraft.dropStages.map(\.id) != currentDraft.dropStages.map(\.id) {
                hasStructuralChange = true
            }
            if completionChanged(previous: previousDraft, current: currentDraft) {
                hasCompletionChange = true
            }
            if valueChanged(previous: previousDraft, current: currentDraft) {
                hasValueChange = true
            }

            if hasStructuralChange && hasCompletionChange && hasValueChange {
                break
            }
        }

        return ActiveWorkoutSetDraftChangeSummary(
            hasStructuralChange: hasStructuralChange,
            hasCompletionChange: hasCompletionChange,
            hasValueChange: hasValueChange
        )
    }

    private static func completionChanged(
        previous: [WorkoutSessionSetDraft],
        current: [WorkoutSessionSetDraft]
    ) -> Bool {
        for (previousDraft, currentDraft) in zip(previous, current) {
            if completionChanged(previous: previousDraft, current: currentDraft) {
                return true
            }
        }
        return false
    }

    private static func completionChanged(
        previous: WorkoutSessionSetDraft,
        current: WorkoutSessionSetDraft
    ) -> Bool {
        if previous.isCompleted != current.isCompleted {
            return true
        }

        guard previous.dropStages.count == current.dropStages.count else {
            return true
        }

        return zip(previous.dropStages, current.dropStages).contains { previousStage, currentStage in
            previousStage.id != currentStage.id
                || previousStage.isCompleted != currentStage.isCompleted
        }
    }

    private static func valueChanged(
        previous: WorkoutSessionSetDraft,
        current: WorkoutSessionSetDraft
    ) -> Bool {
        previous.isWarmup != current.isWarmup
            || previous.restSeconds != current.restSeconds
            || previous.targetReps != current.targetReps
            || previous.targetWeight != current.targetWeight
            || previous.targetLoadUnit != current.targetLoadUnit
            || previous.actualReps != current.actualReps
            || previous.actualWeight != current.actualWeight
            || previous.actualLoadUnit != current.actualLoadUnit
            || previous.isLocked != current.isLocked
            || dropStageValuesChanged(previous: previous.dropStages, current: current.dropStages)
    }

    private static func dropStageValuesChanged(
        previous: [WorkoutSessionDropStageDraft],
        current: [WorkoutSessionDropStageDraft]
    ) -> Bool {
        guard previous.count == current.count else {
            return false
        }

        return zip(previous, current).contains { previousStage, currentStage in
            guard previousStage.id == currentStage.id else {
                return false
            }

            return previousStage.targetReps != currentStage.targetReps
                || previousStage.targetWeight != currentStage.targetWeight
                || previousStage.targetLoadUnit != currentStage.targetLoadUnit
                || previousStage.actualReps != currentStage.actualReps
                || previousStage.actualWeight != currentStage.actualWeight
                || previousStage.actualLoadUnit != currentStage.actualLoadUnit
        }
    }
}
