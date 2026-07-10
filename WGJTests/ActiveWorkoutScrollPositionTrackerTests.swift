import XCTest
import SwiftUI
@testable import WGJ

@MainActor
final class ActiveWorkoutScrollPositionTrackerTests: XCTestCase {
    func testBindingStoresLatestScrollTarget() {
        let tracker = ActiveWorkoutScrollPositionTracker()
        let exerciseID = UUID()

        tracker.binding.wrappedValue = .exercise(exerciseID)

        XCTAssertEqual(tracker.currentTarget, .exercise(exerciseID))
    }

    func testRestorePolicyPrefersFocusedExercise() {
        let focusedID = UUID()
        let trackedTarget = ActiveWorkoutScrollTarget.exercise(UUID())

        let target = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: focusedID,
            keyboardExerciseID: nil,
            trackedTarget: trackedTarget,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [],
            isRestorable: { _ in true },
            hasSession: true
        )

        XCTAssertEqual(target, .exercise(focusedID))
    }

    func testRestorePolicyFallsBackToFirstExpandedExerciseThenHeader() {
        let expandedID = UUID()
        let expandedTarget = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: nil,
            expandedExerciseIDs: [expandedID],
            orderedExerciseIDs: [UUID(), expandedID],
            isRestorable: { _ in true },
            hasSession: true
        )
        let headerTarget = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: nil,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [],
            isRestorable: { _ in true },
            hasSession: true
        )

        XCTAssertEqual(expandedTarget, .exercise(expandedID))
        XCTAssertEqual(headerTarget, .header)
    }
}
