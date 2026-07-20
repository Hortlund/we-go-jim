import XCTest
@testable import WGJ

final class ActiveWorkoutFinishSummaryModelTests: XCTestCase {
    func testBuildsOnlyWhilePresentedAndOnlyForNewRevision() {
        let counter = FinishSummaryBuildCounter()
        let model = ActiveWorkoutFinishSummaryModel { input in
            counter.increment()
            return ActiveWorkoutFinishConfirmationContent(
                exerciseDrafts: input.exerciseDrafts,
                cardioBlocks: input.cardioBlocks
            )
        }
        let first = ActiveWorkoutFinishSummaryInput(
            revision: 1,
            exerciseDrafts: [[]],
            cardioBlocks: []
        )

        model.refreshIfPresented(first)
        XCTAssertEqual(counter.value, 0)
        model.present(first)
        XCTAssertEqual(counter.value, 1)
        model.present(first)
        XCTAssertEqual(counter.value, 1)
        model.refreshIfPresented(ActiveWorkoutFinishSummaryInput(
            revision: 2,
            exerciseDrafts: [[]],
            cardioBlocks: []
        ))
        XCTAssertEqual(counter.value, 2)
        model.dismiss()
        model.refreshIfPresented(ActiveWorkoutFinishSummaryInput(
            revision: 3,
            exerciseDrafts: [[]],
            cardioBlocks: []
        ))
        XCTAssertEqual(counter.value, 2)
    }

    func testWalkRunSummaryFormatsPaceBeforeSpeedWithDisplayUnits() {
        let summary = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 1_500,
            distanceMeters: 5_000,
            displayUnit: .kilometers,
            profile: .walkRun,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: "Steady"
        )

        XCTAssertEqual(summary.metrics.map(\.title), ["Duration", "Distance", "Pace", "Avg Speed"])
        XCTAssertEqual(summary.metrics.map(\.value), ["25 min", "5 km", "5:00 /km", "12 km/h"])
        XCTAssertEqual(summary.notes, "Steady")
    }

    func testActivityAwareSummariesPrioritizeMachineSpeedRowerPaceAndStairLevel() {
        let machine = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 1_800,
            distanceMeters: 15_000,
            displayUnit: .kilometers,
            profile: .machineDistance,
            inclinePercent: nil,
            resistanceLevel: 6,
            notes: ""
        )
        XCTAssertEqual(
            machine.metrics.map(\.title),
            ["Duration", "Distance", "Avg Speed", "Resistance"]
        )
        XCTAssertEqual(machine.metrics[2].value, "30 km/h")

        let rower = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 480,
            distanceMeters: 2_000,
            displayUnit: .meters,
            profile: .rower,
            inclinePercent: nil,
            resistanceLevel: 5,
            notes: ""
        )
        XCTAssertEqual(
            rower.metrics.map(\.title),
            ["Duration", "Distance", "500 m Pace", "Resistance"]
        )
        XCTAssertEqual(rower.metrics[2].value, "2:00 /500 m")

        let stairs = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 600,
            distanceMeters: nil,
            displayUnit: .kilometers,
            profile: .stairClimber,
            inclinePercent: nil,
            resistanceLevel: 9,
            notes: ""
        )
        XCTAssertEqual(stairs.metrics.map(\.title), ["Duration", "Level"])
        XCTAssertEqual(stairs.metrics.map(\.value), ["10 min", "9"])
    }
}

private final class FinishSummaryBuildCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
