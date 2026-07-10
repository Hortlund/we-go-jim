import XCTest
@testable import WGJ

final class StrictConcurrencyValueTests: XCTestCase {
    func testRenderValuesAreSendable() {
        assertSendable(ActiveWorkoutRenderProjection.self)
        assertSendable(WorkoutSupersetDisplayGroup<ActiveWorkoutRuntimeExercise>.self)
        assertSendable(WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>.self)
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
