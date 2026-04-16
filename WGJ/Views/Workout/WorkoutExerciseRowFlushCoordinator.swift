import Foundation

@MainActor
final class WorkoutExerciseRowFlushCoordinator {
    private var flushHandlersByExerciseID: [UUID: @MainActor () -> Void] = [:]

    func register(exerciseID: UUID, handler: @escaping @MainActor () -> Void) {
        flushHandlersByExerciseID[exerciseID] = handler
    }

    func unregister(exerciseID: UUID) {
        flushHandlersByExerciseID.removeValue(forKey: exerciseID)
    }

    func flush(for exerciseID: UUID) {
        flushHandlersByExerciseID[exerciseID]?()
    }

    func flushAll() {
        for exerciseID in flushHandlersByExerciseID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            flushHandlersByExerciseID[exerciseID]?()
        }
    }
}
