import Testing
@testable import WGJ

@MainActor
struct WorkoutSetInlineHintPresentationTests {
    @Test
    func buildsGhostHintsAndAimFromPreviousWeightedSet() {
        let draft = WorkoutSessionSetDraft(
            targetReps: 10,
            targetWeight: 100,
            targetLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let presentation = WorkoutSetInlineHintPresentation.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(presentation?.weightGhostText == "100")
        #expect(presentation?.repsGhostText == "8")
        #expect(presentation?.aimText == "100 kg x 9")
        #expect(presentation?.canApplyPrevious == true)
    }

    @Test
    func hidesFillActionWhenCurrentActualsAlreadyMatchPrevious() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 8,
            actualWeight: 100,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let presentation = WorkoutSetInlineHintPresentation.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(presentation?.statusText == "Matched last session")
        #expect(presentation?.canApplyPrevious == false)
    }

    @Test
    func showsBodyweightGhostHintWhenPreviousSetWasBodyweight() {
        let draft = WorkoutSessionSetDraft(actualLoadUnit: .bodyweight)
        let previous = WorkoutPreviousSetSnapshot(reps: 12, weight: nil, unit: .bodyweight)

        let presentation = WorkoutSetInlineHintPresentation.make(
            draft: draft,
            previous: previous,
            targetRepMin: 10,
            targetRepMax: 15
        )

        #expect(presentation?.weightGhostText == "BW")
        #expect(presentation?.repsGhostText == "12")
        #expect(presentation?.canApplyPrevious == true)
    }
}
