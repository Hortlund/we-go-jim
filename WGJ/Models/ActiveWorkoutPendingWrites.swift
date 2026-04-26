import Foundation

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

struct ActiveWorkoutPendingWrites: Equatable {
    private(set) var dirtyExerciseIDs: Set<UUID> = []
    private(set) var isSessionMetaDirty = false

    var hasDirtyWrites: Bool {
        isSessionMetaDirty || !dirtyExerciseIDs.isEmpty
    }

    func dirtyExerciseIDs(validIDs: Set<UUID>) -> Set<UUID> {
        dirtyExerciseIDs.intersection(validIDs)
    }

    mutating func markExerciseDirty(_ exerciseID: UUID) {
        dirtyExerciseIDs.insert(exerciseID)
    }

    mutating func clearExercise(_ exerciseID: UUID) {
        dirtyExerciseIDs.remove(exerciseID)
    }

    mutating func setSessionMetaDirty(_ isDirty: Bool) {
        isSessionMetaDirty = isDirty
    }

    mutating func clearSessionMeta() {
        isSessionMetaDirty = false
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
            if previousDraft.isCompleted != currentDraft.isCompleted {
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
            if previousDraft.isCompleted != currentDraft.isCompleted {
                return true
            }
        }
        return false
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
    }
}
