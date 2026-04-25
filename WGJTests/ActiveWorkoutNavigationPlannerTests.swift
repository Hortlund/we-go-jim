import Foundation
import Testing
@testable import WGJ

@MainActor
struct ActiveWorkoutNavigationPlannerTests {
    @Test
    func newWorkoutStartDoesNotCreateInitialScrollTarget() {
        #expect(ActiveWorkoutScrollRestorePolicy.initialTargetForNewPresentation() == nil)
    }

    @Test
    func restoreTargetIsConsumedOnce() {
        let exerciseID = UUID()
        var policy = ActiveWorkoutScrollRestorePolicy(pendingRestoreTarget: .exercise(exerciseID))

        #expect(policy.consumeRestoreTarget() == .exercise(exerciseID))
        #expect(policy.consumeRestoreTarget() == nil)
    }

    @Test
    func firstSupersetExerciseRoutesToPairedExerciseSameSet() {
        let second = UUID()
        let route = ActiveWorkoutSupersetNavigationPlanner.routeAfterCompletedSetCycle(
            position: .first,
            setIndex: 0,
            pairedExerciseID: second,
            pairedSetCyclesCompleted: [false, false]
        )

        #expect(route == .exercise(second))
    }

    @Test
    func secondSupersetExerciseRoutesBackToFirstExerciseNextSet() {
        let first = UUID()
        let route = ActiveWorkoutSupersetNavigationPlanner.routeAfterCompletedSetCycle(
            position: .second,
            setIndex: 0,
            pairedExerciseID: first,
            pairedSetCyclesCompleted: [true, false]
        )

        #expect(route == .exercise(first))
    }

    @Test
    func finalSecondSupersetSetFallsThroughToNormalCompletion() {
        let first = UUID()
        let route = ActiveWorkoutSupersetNavigationPlanner.routeAfterCompletedSetCycle(
            position: .second,
            setIndex: 1,
            pairedExerciseID: first,
            pairedSetCyclesCompleted: [true, true]
        )

        #expect(route == nil)
    }
}
