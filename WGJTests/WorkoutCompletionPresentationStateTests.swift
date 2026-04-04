import Foundation
import Testing
@testable import WGJ

@MainActor
struct WorkoutCompletionPresentationStateTests {
    @Test
    func queuedPresentationPromotesAfterDismiss() {
        let state = WorkoutCompletionPresentationState()
        let sessionID = UUID()

        state.queueAfterActiveWorkoutDismiss(sessionID: sessionID)
        #expect(state.presentedWorkout == nil)

        state.presentQueuedIfNeeded()

        #expect(state.presentedWorkout?.sessionID == sessionID)
    }

    @Test
    func directPresentationClearsAnyQueuedWorkout() {
        let state = WorkoutCompletionPresentationState()
        let queuedSessionID = UUID()
        let presentedSessionID = UUID()

        state.queueAfterActiveWorkoutDismiss(sessionID: queuedSessionID)
        state.present(sessionID: presentedSessionID)
        state.dismiss()
        state.presentQueuedIfNeeded()

        #expect(state.presentedWorkout == nil)
    }
}
