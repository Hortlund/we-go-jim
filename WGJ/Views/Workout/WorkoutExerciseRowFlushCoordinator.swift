import Foundation

@MainActor
final class WorkoutExerciseRowFlushCoordinator {
    private var flushHandlersByExerciseID: [UUID: @MainActor () -> Void] = [:]
    private(set) var dirtyExerciseIDs: Set<UUID> = []

    func register(exerciseID: UUID, handler: @escaping @MainActor () -> Void) {
        flushHandlersByExerciseID[exerciseID] = handler
    }

    func unregister(exerciseID: UUID) {
        flushHandlersByExerciseID.removeValue(forKey: exerciseID)
        dirtyExerciseIDs.remove(exerciseID)
    }

    func setDirty(_ isDirty: Bool, for exerciseID: UUID) {
        if isDirty {
            dirtyExerciseIDs.insert(exerciseID)
        } else {
            dirtyExerciseIDs.remove(exerciseID)
        }
    }

    func flush(for exerciseID: UUID) {
        flushHandlersByExerciseID[exerciseID]?()
        dirtyExerciseIDs.remove(exerciseID)
    }

    func flushAll() {
        for exerciseID in flushHandlersByExerciseID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            flushHandlersByExerciseID[exerciseID]?()
        }
        dirtyExerciseIDs.removeAll()
    }

    func flushDirty() {
        for exerciseID in dirtyExerciseIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            flushHandlersByExerciseID[exerciseID]?()
        }
        dirtyExerciseIDs.removeAll()
    }
}
