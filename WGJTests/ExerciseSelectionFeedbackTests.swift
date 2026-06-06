import Testing
@testable import WGJ

struct ExerciseSelectionFeedbackTests {
    @Test
    func duplicateNoticeNamesSelectedExerciseAndDestination() {
        let workoutNotice = ExerciseSelectionDuplicateNotice(
            exerciseName: "Bench Press",
            destination: .activeWorkout
        )
        let templateNotice = ExerciseSelectionDuplicateNotice(
            exerciseName: "Bench Press",
            destination: .template
        )

        #expect(workoutNotice.title == "Exercise already added")
        #expect(workoutNotice.message == "Bench Press is already in this workout.")
        #expect(templateNotice.message == "Bench Press is already in this template.")
    }
}
