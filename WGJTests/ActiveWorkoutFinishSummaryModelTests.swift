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

    @MainActor
    func testWorkoutShareCardRendersAtStoryResolution() {
        let presentation = WorkoutSharePresentation(
            sessionName: "Push Day",
            completedAtText: "Aug 21, 9:00 PM",
            activityLabel: "STRENGTH TRAINING",
            primaryMetric: .init(title: "TOTAL VOLUME", value: "8,420 kg"),
            supportingMetrics: [
                .init(title: "DURATION", value: "1h 4m"),
                .init(title: "SETS", value: "24"),
                .init(title: "EXERCISES", value: "8"),
            ],
            personalRecordCount: 0,
            highlightTitle: "Workout complete",
            highlightDetail: "24 completed sets logged",
            exercises: [
                .init(name: "Bench Press", setProgressText: "4 / 4 sets", bestSetText: "100 kg × 5"),
                .init(name: "Incline Press", setProgressText: "3 / 3 sets", bestSetText: "70 kg × 8"),
                .init(name: "Triceps Pushdown", setProgressText: "3 / 3 sets", bestSetText: "35 kg × 12"),
                .init(name: "Cable Fly", setProgressText: "3 / 3 sets", bestSetText: "20 kg × 12"),
                .init(name: "Overhead Press", setProgressText: "3 / 3 sets", bestSetText: "55 kg × 6"),
                .init(name: "Lateral Raise", setProgressText: "2 / 2 sets", bestSetText: "12 kg × 15"),
                .init(name: "Pec Deck", setProgressText: "3 / 3 sets", bestSetText: "50 kg × 10"),
                .init(name: "Skull Crusher", setProgressText: "3 / 3 sets", bestSetText: "30 kg × 10"),
            ],
            remainingExerciseCount: 0
        )

        let image = WorkoutShareCardRenderer.render(presentation)

        XCTAssertEqual(image?.cgImage?.width, 1_080)
        XCTAssertEqual(image?.cgImage?.height, 1_920)
        if let image {
            let attachment = XCTAttachment(image: image)
            attachment.name = "Workout share story"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testWorkoutSharePresentationUsesCardioMetricsForCardioOnlyWorkout() {
        let snapshot = WorkoutCompletionSnapshot(
            sessionID: UUID(),
            sessionName: "Evening Run",
            celebrationTitle: "Workout Complete",
            celebrationSubtitle: "Saved",
            completedAtText: "Aug 21, 9:00 PM",
            durationText: "25m",
            exerciseCount: 0,
            completedSetCount: 0,
            totalVolume: 0,
            totalVolumeText: "0 kg",
            estimatedActiveCaloriesText: nil,
            estimatedActiveCaloriesAccessibilityLabel: nil,
            prHeadline: "No new PRs today",
            prSupportText: "",
            personalRecords: [],
            cardioRecap: [
                WorkoutCompletionCardioRecap(
                    id: UUID(),
                    role: .main,
                    exerciseName: "Outdoor Run",
                    descriptor: nil,
                    summary: WorkoutCardioResultSummary(
                        metrics: [
                            .init(kind: .pace, title: "Pace", value: "5:00 /km", systemImage: "figure.run"),
                            .init(kind: .duration, title: "Duration", value: "25 min", systemImage: "clock"),
                            .init(kind: .distance, title: "Distance", value: "5 km", systemImage: "ruler"),
                        ],
                        notes: nil
                    ),
                    isCompleted: true
                ),
            ],
            muscleHeatmap: .empty,
            exerciseRecap: []
        )

        let presentation = WorkoutSharePresentation.make(snapshot: snapshot)

        XCTAssertEqual(presentation.activityLabel, "CARDIO")
        XCTAssertEqual(presentation.primaryMetric, .init(title: "DISTANCE", value: "5 km"))
        XCTAssertEqual(presentation.highlightTitle, "Outdoor Run")
        XCTAssertEqual(presentation.exercises.first?.name, "Outdoor Run")
        XCTAssertEqual(presentation.exercises.first?.detailTitle, "RESULT")
        XCTAssertEqual(presentation.exercises.first?.bestSetText, "5:00 /km · 25 min")
        XCTAssertFalse(presentation.supportingMetrics.contains { $0.title == "SETS" })
        XCTAssertFalse(presentation.supportingMetrics.contains { $0.title == "EXERCISES" })
    }

    func testWorkoutSharePresentationIgnoresPreAndPostCardioForMixedActivityLabel() {
        let snapshot = workoutShareSnapshot(
            exerciseCount: 1,
            cardioRoles: [.warmUp, .finisher]
        )

        let presentation = WorkoutSharePresentation.make(snapshot: snapshot)

        XCTAssertEqual(presentation.activityLabel, "STRENGTH TRAINING")
        XCTAssertTrue(presentation.exercises.isEmpty)
    }

    func testWorkoutSharePresentationUsesMixedActivityLabelForMainCardioAndStrength() {
        let snapshot = workoutShareSnapshot(
            exerciseCount: 1,
            cardioRoles: [.warmUp, .main, .finisher]
        )

        let presentation = WorkoutSharePresentation.make(snapshot: snapshot)

        XCTAssertEqual(presentation.activityLabel, "STRENGTH + CARDIO")
        XCTAssertEqual(presentation.exercises.count, 1)
        XCTAssertEqual(presentation.exercises.first?.setProgressText, "MAIN CARDIO")
    }

    private func workoutShareSnapshot(
        exerciseCount: Int,
        cardioRoles: [WorkoutCardioRole]
    ) -> WorkoutCompletionSnapshot {
        WorkoutCompletionSnapshot(
            sessionID: UUID(),
            sessionName: "Mixed Workout",
            celebrationTitle: "Workout Complete",
            celebrationSubtitle: "Saved",
            completedAtText: "Aug 22, 11:00 AM",
            durationText: "45m",
            exerciseCount: exerciseCount,
            completedSetCount: exerciseCount > 0 ? 3 : 0,
            totalVolume: exerciseCount > 0 ? 1_000 : 0,
            totalVolumeText: exerciseCount > 0 ? "1,000 kg" : "0 kg",
            estimatedActiveCaloriesText: nil,
            estimatedActiveCaloriesAccessibilityLabel: nil,
            prHeadline: "No new PRs today",
            prSupportText: "",
            personalRecords: [],
            cardioRecap: cardioRoles.map { role in
                WorkoutCompletionCardioRecap(
                    id: UUID(),
                    role: role,
                    exerciseName: "Cardio",
                    descriptor: nil,
                    summary: WorkoutCardioResultSummary(
                        metrics: [
                            .init(
                                kind: .duration,
                                title: "Duration",
                                value: "10 min",
                                systemImage: "clock"
                            ),
                        ],
                        notes: nil
                    ),
                    isCompleted: true
                )
            },
            muscleHeatmap: .empty,
            exerciseRecap: []
        )
    }
}

private final class FinishSummaryBuildCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
