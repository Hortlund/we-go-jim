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
    func confettiTapOriginUsesGlobalGestureCoordinateDirectly() {
        let tapLocation = CGPoint(x: 184, y: 318)
        let heroFrame = CGRect(x: 16, y: 132, width: 361, height: 190)

        #expect(
            WorkoutCompletionConfettiOrigin.tapOrigin(
                locationInGlobalSpace: tapLocation,
                heroFrame: heroFrame
            ) == tapLocation
        )
    }

    @Test
    func confettiOverlayOriginConvertsGlobalTapIntoOverlaySpace() {
        let tapLocation = CGPoint(x: 184, y: 365)
        let overlayFrameInGlobalSpace = CGRect(x: 0, y: -47, width: 393, height: 852)

        #expect(
            WorkoutCompletionConfettiOrigin.overlayOrigin(
                locationInGlobalSpace: tapLocation,
                overlayFrameInGlobalSpace: overlayFrameInGlobalSpace
            ) == CGPoint(x: 184, y: 412)
        )
    }

    @Test
    func completedWorkoutConfettiUsesMorePiecesThanManualTap() {
        #expect(WorkoutCompletionConfettiPolicy.pieceCount(for: .manualTap) == 28)
        #expect(
            WorkoutCompletionConfettiPolicy.pieceCount(for: .completedWorkout)
            > WorkoutCompletionConfettiPolicy.pieceCount(for: .manualTap)
        )
    }
}
