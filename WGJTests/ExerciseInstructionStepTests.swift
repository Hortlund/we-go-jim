import Testing
@testable import WGJ

@MainActor
struct ExerciseInstructionStepTests {
    @Test
    func splitsCommaSeparatedInstructionsIntoOrderedSteps() {
        let exercise = ExerciseCatalogItem(
            remoteUUID: "bench",
            displayName: "Bench Press",
            instructionText: "Set your shoulders, lower with control, and press back up smoothly."
        )

        #expect(
            exercise.instructionSteps
                == [
                    "Set your shoulders",
                    "Lower with control",
                    "Press back up smoothly",
                ]
        )
    }

    @Test
    func preservesExplicitMultilineSteps() {
        let exercise = ExerciseCatalogItem(
            remoteUUID: "squat",
            displayName: "Back Squat",
            instructionText: "Step 1: Set your stance.\n2. Brace your torso.\n- Drive up through the full foot."
        )

        #expect(
            exercise.instructionSteps
                == [
                    "Set your stance.",
                    "Brace your torso.",
                    "Drive up through the full foot.",
                ]
        )
    }

    @Test
    func keepsSingleCueAsSingleStep() {
        let exercise = ExerciseCatalogItem(
            remoteUUID: "plank",
            displayName: "Plank",
            instructionText: "Hold a rigid line from head to heels."
        )

        #expect(exercise.instructionSteps == ["Hold a rigid line from head to heels."])
    }
}
