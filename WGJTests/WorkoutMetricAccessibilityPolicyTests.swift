import XCTest
@testable import WGJ

final class WorkoutMetricAccessibilityPolicyTests: XCTestCase {
    func testWorkingSetWeightIncludesContextAndUnit() {
        let descriptor = WorkoutMetricAccessibilityPolicy.field(
            exerciseName: "Bench Press",
            setNumber: 2,
            dropStageNumber: nil,
            metric: .weight,
            value: "100",
            unit: "kg"
        )

        XCTAssertEqual(descriptor.label, "Bench Press, working set 2, weight")
        XCTAssertEqual(descriptor.value, "100 kilograms")
    }

    func testDropStageRepsIncludesStageAndEmptyState() {
        let descriptor = WorkoutMetricAccessibilityPolicy.field(
            exerciseName: "Bench Press",
            setNumber: 2,
            dropStageNumber: 1,
            metric: .reps,
            value: "",
            unit: nil
        )

        XCTAssertEqual(descriptor.label, "Bench Press, working set 2, drop stage 1, reps")
        XCTAssertEqual(descriptor.value, "No reps entered")
    }

    func testBodyweightAndWarmupSemantics() {
        let weight = WorkoutMetricAccessibilityPolicy.field(
            exerciseName: "Pull Up",
            setNumber: 1,
            dropStageNumber: nil,
            metric: .weight,
            value: nil,
            unit: "BW"
        )
        let warmup = WorkoutMetricAccessibilityPolicy.warmupControl(
            exerciseName: "Bench Press",
            setNumber: 1,
            isWarmup: true
        )

        XCTAssertEqual(weight.value, "Bodyweight")
        XCTAssertEqual(warmup.value, "Warmup")
    }
}
