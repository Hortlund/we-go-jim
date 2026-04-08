import Testing
@testable import WGJ

struct WorkoutSetBozarCompletionResolverTests {
    @Test
    func autofillsPreviousWeightAndRepsBeforeCompletion() {
        let draft = WorkoutSessionSetDraft(
            targetReps: 8,
            targetWeight: 100,
            targetLoadUnit: .kg,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: previous
        )

        #expect(resolution.draft.actualWeight == 100)
        #expect(resolution.draft.actualReps == 8)
        #expect(resolution.draft.actualLoadUnit == .kg)
        #expect(resolution.shouldConfirmEmptyCompletion == false)
    }

    @Test
    func keepsManualEntriesAndOnlyFillsMissingPreviousValues() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 10,
            actualWeight: nil,
            actualLoadUnit: .lb
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 45, unit: .kg)

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: previous
        )

        #expect(resolution.draft.actualReps == 10)
        #expect(resolution.draft.actualWeight == 45)
        #expect(resolution.draft.actualLoadUnit == .kg)
        #expect(resolution.shouldConfirmEmptyCompletion == false)
    }

    @Test
    func flagsEmptyCompletionWhenNoPreviousValuesExist() {
        let draft = WorkoutSessionSetDraft(
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: .kg
        )

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: nil
        )

        #expect(resolution.draft.actualWeight == nil)
        #expect(resolution.draft.actualReps == nil)
        #expect(resolution.shouldConfirmEmptyCompletion)
    }

    @Test
    func appliesBodyweightUnitWhenPreviousBodyweightSetFillsReps() {
        let draft = WorkoutSessionSetDraft(
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 12, weight: nil, unit: .bodyweight)

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: previous
        )

        #expect(resolution.draft.actualReps == 12)
        #expect(resolution.draft.actualWeight == nil)
        #expect(resolution.draft.actualLoadUnit == .bodyweight)
        #expect(resolution.shouldConfirmEmptyCompletion == false)
    }
}
