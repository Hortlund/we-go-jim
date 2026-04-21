import Foundation

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

    var hasMeaningfulChange: Bool {
        hasStructuralChange || hasCompletionChange
    }

    static func compare(
        previous: [WorkoutSessionSetDraft],
        current: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutSetDraftChangeSummary {
        if previous.count != current.count {
            return ActiveWorkoutSetDraftChangeSummary(
                hasStructuralChange: true,
                hasCompletionChange: completionChanged(previous: previous, current: current)
            )
        }

        var hasStructuralChange = false
        var hasCompletionChange = false

        for (previousDraft, currentDraft) in zip(previous, current) {
            if previousDraft.id != currentDraft.id {
                hasStructuralChange = true
            }
            if previousDraft.isCompleted != currentDraft.isCompleted {
                hasCompletionChange = true
            }

            if hasStructuralChange && hasCompletionChange {
                break
            }
        }

        return ActiveWorkoutSetDraftChangeSummary(
            hasStructuralChange: hasStructuralChange,
            hasCompletionChange: hasCompletionChange
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
}
