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

    func testCardioActionsIncludeTheActivityName() {
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioAction(.start, activityName: "Treadmill Walk"),
            "Start Treadmill Walk"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioAction(.pause, activityName: "Bike"),
            "Pause Bike"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioAction(.resume, activityName: "Bike"),
            "Resume Bike"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioAction(.finish, activityName: "Outdoor Run"),
            "Finish Outdoor Run"
        )
    }

    func testCardioMetricSpeechExpandsDistanceAndSpeedUnits() {
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "5",
                semantic: .distance(.kilometers)
            ),
            "5 kilometers"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "3.1",
                semantic: .distance(.miles)
            ),
            "3.1 miles"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "500",
                semantic: .distance(.meters)
            ),
            "500 meters"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "12",
                semantic: .speed(.kilometers)
            ),
            "12 kilometers per hour"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "7.5",
                semantic: .speed(.miles)
            ),
            "7.5 miles per hour"
        )
    }

    func testCardioMetricSpeechExpandsPaceInclineAndRowingUnits() {
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "05:00",
                semantic: .pace(.kilometers)
            ),
            "05:00 per kilometer"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "08:03",
                semantic: .pace(.miles)
            ),
            "08:03 per mile"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                "1:58",
                semantic: .rowingPace
            ),
            "1:58 per 500 meters"
        )
        XCTAssertEqual(
            WorkoutMetricAccessibilityPolicy.cardioMetricValue("4", semantic: .incline),
            "4 percent incline"
        )
    }
}
