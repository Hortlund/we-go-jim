import Foundation
import CoreGraphics
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

    @Test
    func confettiTapOriginUsesGestureCoordinateDirectly() {
        let tapLocation = CGPoint(x: 184, y: 318)
        let heroFrame = CGRect(x: 16, y: 132, width: 361, height: 190)

        #expect(
            WorkoutCompletionConfettiOrigin.tapOrigin(
                locationInSummarySpace: tapLocation,
                heroFrame: heroFrame
            ) == tapLocation
        )
    }
}
