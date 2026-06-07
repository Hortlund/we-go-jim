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

    @Test
    func duplicateNoticeUsesNonModalOverlayFeedback() {
        let notice = ExerciseSelectionDuplicateNotice(
            exerciseName: "Bench Press",
            destination: .activeWorkout
        )

        #expect(notice.presentationStyle == .transientBanner)
    }

    @Test
    func duplicateSelectionResultKeepsPickerOpen() {
        let notice = ExerciseSelectionDuplicateNotice(
            exerciseName: "Bench Press",
            destination: .template
        )

        #expect(ExercisePickerSelectionResult.accepted.shouldDismissPicker)
        #expect(!ExercisePickerSelectionResult.rejected(notice).shouldDismissPicker)
    }

    @Test
    func replacementSelectionRejectsSameExerciseInActiveWorkout() throws {
        let result = ExerciseReplacementSelectionPolicy.result(
            catalogExerciseUUID: "bench-press",
            exerciseName: "Bench Press",
            existingCatalogExerciseUUIDs: ["bench-press", "barbell-row"],
            destination: .activeWorkout
        )

        guard case .rejected(let notice) = result else {
            Issue.record("Expected replacing an active workout exercise with itself to be rejected")
            return
        }

        #expect(!result.shouldDismissPicker)
        #expect(notice.message == "Bench Press is already in this workout.")
    }

    @Test
    func replacementSelectionRejectsSameExerciseInTemplate() throws {
        let result = ExerciseReplacementSelectionPolicy.result(
            catalogExerciseUUID: "bench-press",
            exerciseName: "Bench Press",
            existingCatalogExerciseUUIDs: ["bench-press", "barbell-row"],
            destination: .template
        )

        guard case .rejected(let notice) = result else {
            Issue.record("Expected replacing a template exercise with itself to be rejected")
            return
        }

        #expect(!result.shouldDismissPicker)
        #expect(notice.message == "Bench Press is already in this template.")
    }
}
