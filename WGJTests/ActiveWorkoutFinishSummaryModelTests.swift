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

        XCTAssertEqual(summary.metrics.map(\.title), ["Pace", "Duration", "Distance", "Avg Speed"])
        XCTAssertEqual(summary.metrics.map(\.value), ["5:00 /km", "25 min", "5 km", "12 km/h"])
        XCTAssertEqual(summary.metrics.first?.title, "Pace")
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
            ["Avg Speed", "Duration", "Distance", "Resistance"]
        )
        XCTAssertEqual(machine.metrics.first?.value, "30 km/h")

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
            ["500 m Pace", "Duration", "Distance", "Resistance"]
        )
        XCTAssertEqual(rower.metrics.first?.value, "2:00 /500 m")

        let stairs = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 600,
            distanceMeters: nil,
            displayUnit: .kilometers,
            profile: .stairClimber,
            inclinePercent: nil,
            resistanceLevel: 9,
            notes: ""
        )
        XCTAssertEqual(stairs.metrics.map(\.title), ["Level", "Duration"])
        XCTAssertEqual(stairs.metrics.map(\.value), ["9", "10 min"])
    }

    func testActivityAwareSummaryFallsBackToAvailableRawMetrics() {
        let durationOnlyWalk = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 600,
            distanceMeters: nil,
            displayUnit: .kilometers,
            profile: .walkRun,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: ""
        )
        XCTAssertEqual(durationOnlyWalk.metrics.map(\.title), ["Duration"])

        let distanceOnlyMachine = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: nil,
            distanceMeters: 5_000,
            displayUnit: .kilometers,
            profile: .machineDistance,
            inclinePercent: nil,
            resistanceLevel: 4,
            notes: ""
        )
        XCTAssertEqual(distanceOnlyMachine.metrics.map(\.title), ["Distance", "Resistance"])

        let stairsWithoutLevel = WorkoutCardioResultSummaryFormatter.summary(
            durationSeconds: 600,
            distanceMeters: nil,
            displayUnit: .kilometers,
            profile: .stairClimber,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: ""
        )
        XCTAssertEqual(stairsWithoutLevel.metrics.map(\.title), ["Duration"])
    }
}

private final class FinishSummaryBuildCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
