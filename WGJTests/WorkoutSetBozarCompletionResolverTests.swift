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

        #expect(resolution.actualWeight == 100)
        #expect(resolution.actualReps == 8)
        #expect(resolution.actualLoadUnit == .kg)
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

        #expect(resolution.actualReps == 10)
        #expect(resolution.actualWeight == 45)
        #expect(resolution.actualLoadUnit == .kg)
    }

    @Test
    func leavesDraftEmptyWhenNoPreviousValuesExist() {
        let draft = WorkoutSessionSetDraft(
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: .kg
        )

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: nil
        )

        #expect(resolution.actualWeight == nil)
        #expect(resolution.actualReps == nil)
        #expect(resolution.actualLoadUnit == .kg)
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

        #expect(resolution.actualReps == 12)
        #expect(resolution.actualWeight == nil)
        #expect(resolution.actualLoadUnit == .bodyweight)
    }
}
