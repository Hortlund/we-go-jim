import Foundation
import Testing
@testable import WGJ

@MainActor
struct WorkoutExerciseRowFlushCoordinatorTests {
    @Test
    func flushAllUsesLatestRegisteredHandlerForExercise() {
        let exerciseID = UUID()
        let coordinator = WorkoutExerciseRowFlushCoordinator()
        var events: [String] = []

        coordinator.register(exerciseID: exerciseID) {
            events.append("first")
        }
        coordinator.register(exerciseID: exerciseID) {
            events.append("latest")
        }

        coordinator.flushAll()

        #expect(events == ["latest"])
    }

    @Test
    func unregisterStopsFurtherFlushes() {
        let exerciseID = UUID()
        let coordinator = WorkoutExerciseRowFlushCoordinator()
        var flushCount = 0

        coordinator.register(exerciseID: exerciseID) {
            flushCount += 1
        }
        coordinator.unregister(exerciseID: exerciseID)
        coordinator.flush(for: exerciseID)
        coordinator.flushAll()

        #expect(flushCount == 0)
    }
}
