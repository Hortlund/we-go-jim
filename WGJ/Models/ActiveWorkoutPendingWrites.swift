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
