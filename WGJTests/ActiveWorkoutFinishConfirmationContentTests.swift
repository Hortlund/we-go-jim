import Testing
@testable import WGJ

struct ActiveWorkoutFinishConfirmationContentTests {
    @Test
    func completedWorkoutKeepsStandardFinishCopy() {
        let content = ActiveWorkoutFinishConfirmationContent(
            exerciseDrafts: [
                [Self.draft(completed: true), Self.draft(completed: true)],
                [Self.draft(completed: true)]
            ],
            cardioBlocks: [Self.cardio(completed: true)]
        )

        #expect(content.hasIncompleteWork == false)
        #expect(content.incompleteExerciseCount == 0)
        #expect(content.incompleteSetCount == 0)
        #expect(content.incompleteCardioCount == 0)
        #expect(content.title == "Finish Workout?")
        #expect(content.message == "This will close the active workout and add it to your history.")
        #expect(content.confirmButtonTitle == "Finish and Save")
        #expect(content.cancelButtonTitle == "Not yet")
        #expect(content.iconSystemName == "checkmark.circle.fill")
    }

    @Test
    func unfinishedSetsProduceWarningCopy() {
        let content = ActiveWorkoutFinishConfirmationContent(
            exerciseDrafts: [
                [Self.draft(completed: true), Self.draft(completed: false), Self.draft(completed: false)],
                [Self.draft(completed: false)]
            ],
            cardioBlocks: [Self.cardio(completed: false)]
        )

        #expect(content.hasIncompleteWork)
        #expect(content.incompleteExerciseCount == 2)
        #expect(content.incompleteSetCount == 3)
        #expect(content.incompleteCardioCount == 1)
        #expect(content.title == "Finish With Unfinished Work?")
        #expect(
            content.message ==
                "You still have 3 unfinished sets across 2 exercises, plus 1 unfinished cardio section. Finish anyway or go back and finish them."
        )
        #expect(content.confirmButtonTitle == "Finish Anyway")
        #expect(content.cancelButtonTitle == "Keep Logging")
        #expect(content.iconSystemName == "exclamationmark.triangle.fill")
    }

    @Test
    func exerciseWithoutSetsStillShowsWarning() {
        let content = ActiveWorkoutFinishConfirmationContent(
            exerciseDrafts: [
                [],
                [Self.draft(completed: true)]
            ]
        )

        #expect(content.hasIncompleteWork)
        #expect(content.incompleteExerciseCount == 1)
        #expect(content.incompleteSetCount == 0)
        #expect(
            content.message ==
                "You still have 1 unfinished exercise. Finish anyway or go back before closing this workout."
        )
    }

    @Test
    func incompleteCardioOnlyProducesWarningCopy() {
        let content = ActiveWorkoutFinishConfirmationContent(
            exerciseDrafts: [
                [Self.draft(completed: true)]
            ],
            cardioBlocks: [Self.cardio(completed: false)]
        )

        #expect(content.hasIncompleteWork)
        #expect(content.incompleteExerciseCount == 0)
        #expect(content.incompleteSetCount == 0)
        #expect(content.incompleteCardioCount == 1)
        #expect(
            content.message ==
                "You still have 1 unfinished cardio section. Finish anyway or go back before closing this workout."
        )
    }

    private static func draft(completed: Bool) -> WorkoutSessionSetDraft {
        WorkoutSessionSetDraft(isCompleted: completed)
    }

    private static func cardio(completed: Bool) -> WorkoutCardioBlockDraft {
        WorkoutCardioBlockDraft(
            phase: .preWorkout,
            catalogExerciseUUID: "bike-1",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "",
            targetDurationSeconds: 300,
            isCompleted: completed
        )
    }
}
