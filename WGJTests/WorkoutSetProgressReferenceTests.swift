import Testing
@testable import WGJ

@MainActor
struct WorkoutSetProgressReferenceTests {
    @Test
    func buildsAimFromPreviousSetInsideRepRange() {
        let draft = WorkoutSessionSetDraft(
            targetReps: 10,
            targetWeight: 100,
            targetLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(reference?.lastValue == "100 kg x 8")
        #expect(reference?.aimValue == "100 kg x 9")
        #expect(reference?.statusText == nil)
        #expect(reference?.canReusePrevious == true)
    }

    @Test
    func suggestsLoadJumpWhenTopOfRangeWasOwned() {
        let draft = WorkoutSessionSetDraft(
            targetReps: 10,
            targetWeight: 100,
            targetLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 10, weight: 100, unit: .kg)

        let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        let nextWeightText = WGJFormatters.decimalString(102.5)
        #expect(reference?.aimValue == "\(nextWeightText) kg x 6-10")
    }

    @Test
    func marksRepProgressAgainstPreviousSession() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 9,
            actualWeight: 100,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(reference?.statusText == "+1 rep vs last")
        #expect(reference?.statusTone == .success)
        #expect(reference?.canReusePrevious == true)
    }

    @Test
    func marksCombinedWeightAndRepProgressAgainstPreviousSession() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 9,
            actualWeight: 105,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(reference?.statusText == "+5 kg and +1 rep vs last")
        #expect(reference?.statusTone == .success)
    }

    @Test
    func hidesReuseActionWhenCurrentLogAlreadyMatchesPrevious() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 8,
            actualWeight: 100,
            actualLoadUnit: .kg
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: 6,
            targetRepMax: 10
        )

        #expect(reference?.statusText == "Matched last session")
        #expect(reference?.statusTone == .accent)
        #expect(reference?.canReusePrevious == false)
    }
}
