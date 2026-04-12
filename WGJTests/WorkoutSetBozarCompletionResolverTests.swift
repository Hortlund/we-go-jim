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
    func matchesFillLastByReplacingExistingActualsWithPreviousPerformance() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 10,
            actualWeight: 50,
            actualLoadUnit: .lb
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 45, unit: .kg)

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: previous
        )

        #expect(resolution.actualReps == 8)
        #expect(resolution.actualWeight == 45)
        #expect(resolution.actualLoadUnit == .kg)
    }

    @Test
    func leavesExistingActualsUntouchedWhenNoPreviousValuesExist() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 9,
            actualWeight: 95,
            actualLoadUnit: .lb
        )

        let resolution = WorkoutSetBozarCompletionResolver.resolve(
            draft: draft,
            previous: nil
        )

        #expect(resolution.actualWeight == 95)
        #expect(resolution.actualReps == 9)
        #expect(resolution.actualLoadUnit == .lb)
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
