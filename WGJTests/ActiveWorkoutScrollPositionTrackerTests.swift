import XCTest
import SwiftUI
@testable import WGJ

@MainActor
final class ActiveWorkoutScrollPositionTrackerTests: XCTestCase {
    func testCompletedExerciseCollapsesOnlyWhenEnabledAndExpanded() {
        XCTAssertEqual(
            ActiveWorkoutCompletedExercisePresentationPolicy.effect(
                wasExpanded: true,
                automaticallyClosesCompletedExercises: true
            ),
            .collapseCard
        )
        XCTAssertEqual(
            ActiveWorkoutCompletedExercisePresentationPolicy.effect(
                wasExpanded: false,
                automaticallyClosesCompletedExercises: true
            ),
            .none
        )
        XCTAssertEqual(
            ActiveWorkoutCompletedExercisePresentationPolicy.effect(
                wasExpanded: true,
                automaticallyClosesCompletedExercises: false
            ),
            .none
        )
    }

    func testBindingStoresLatestScrollTarget() {
        let tracker = ActiveWorkoutScrollPositionTracker()
        let activityID = UUID()

        tracker.binding.wrappedValue = .cardio(role: .main, activityID: activityID)

        XCTAssertEqual(tracker.currentTarget, .cardio(role: .main, activityID: activityID))
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
            orderedCardioActivityIDsByRole: [:],
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
            orderedCardioActivityIDsByRole: [:],
            isRestorable: { _ in true },
            hasSession: true
        )
        let headerTarget = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: nil,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [],
            orderedCardioActivityIDsByRole: [:],
            isRestorable: { _ in true },
            hasSession: true
        )

        XCTAssertEqual(expandedTarget, .exercise(expandedID))
        XCTAssertEqual(headerTarget, .header)
    }

    func testRestorePolicyMapsCancelSectionToLastExercise() {
        let firstID = UUID()
        let lastID = UUID()
        let target = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: .cancelSection,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [firstID, lastID],
            orderedCardioActivityIDsByRole: [:],
            isRestorable: { _ in true },
            hasSession: true
        )

        XCTAssertEqual(target, .exercise(lastID))
    }

    func testRestorePolicyMapsCancelSectionToLastFinisherActivityWhenPresent() {
        let firstFinisherID = UUID()
        let lastFinisherID = UUID()
        let target = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: .cancelSection,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [UUID()],
            orderedCardioActivityIDsByRole: [
                .finisher: [firstFinisherID, lastFinisherID],
            ],
            isRestorable: {
                $0 == .cardio(role: .finisher, activityID: firstFinisherID)
                    || $0 == .cardio(role: .finisher, activityID: lastFinisherID)
                    || $0 == .header
            },
            hasSession: true
        )

        XCTAssertEqual(target, .cardio(role: .finisher, activityID: lastFinisherID))
    }

    func testLegacyPreWorkoutTargetRestoresFirstAvailableWarmUpActivity() throws {
        let unavailableID = UUID()
        let firstRestorableID = UUID()
        let decoded = try JSONDecoder().decode(
            ActiveWorkoutScrollTarget.self,
            from: Data(#"{"preWorkoutCardio":{}}"#.utf8)
        )

        let target = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: decoded,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [],
            orderedCardioActivityIDsByRole: [
                .warmUp: [unavailableID, firstRestorableID],
            ],
            isRestorable: {
                $0 == .cardio(role: .warmUp, activityID: firstRestorableID)
            },
            hasSession: true
        )

        XCTAssertEqual(target, .cardio(role: .warmUp, activityID: firstRestorableID))
    }

    func testLegacyPostWorkoutTargetRestoresFirstAvailableFinisherActivity() throws {
        let activityID = UUID()
        let decoded = try JSONDecoder().decode(
            ActiveWorkoutScrollTarget.self,
            from: Data(#"{"postWorkoutCardio":{}}"#.utf8)
        )

        let target = ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: nil,
            keyboardExerciseID: nil,
            trackedTarget: decoded,
            expandedExerciseIDs: [],
            orderedExerciseIDs: [],
            orderedCardioActivityIDsByRole: [.finisher: [activityID]],
            isRestorable: {
                $0 == .cardio(role: .finisher, activityID: activityID)
            },
            hasSession: true
        )

        XCTAssertEqual(target, .cardio(role: .finisher, activityID: activityID))
    }

    func testRoleAndActivityScrollTargetRoundTripsThroughCodable() throws {
        let original = ActiveWorkoutScrollTarget.cardio(role: .main, activityID: UUID())

        let decoded = try JSONDecoder().decode(
            ActiveWorkoutScrollTarget.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
