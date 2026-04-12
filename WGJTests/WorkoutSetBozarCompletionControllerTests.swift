import Testing
@testable import WGJ

@MainActor
struct WorkoutSetBozarCompletionControllerTests {
    @Test
    func waitsForHistoryWhenPreviousPerformanceIsStillLoading() {
        let draft = WorkoutSessionSetDraft(
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: .kg
        )

        let decision = WorkoutSetBozarCompletionController.decision(
            drafts: [draft],
            at: 0,
            previousResolution: .loading
        )

        #expect(decision == .waitForPreviousPerformance(setID: draft.id))
    }

    @Test
    func completesWithFillLastValuesWhenHistoryHasResolved() {
        let draft = WorkoutSessionSetDraft(
            actualReps: 10,
            actualWeight: 50,
            actualLoadUnit: .lb
        )
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 45, unit: .kg)

        let decision = WorkoutSetBozarCompletionController.decision(
            drafts: [draft],
            at: 0,
            previousResolution: .resolved([0: previous])
        )

        guard case .completeImmediately(let resolvedDrafts)? = decision else {
            Issue.record("Expected immediate completion once previous performance has resolved.")
            return
        }

        #expect(resolvedDrafts.count == 1)
        #expect(resolvedDrafts[0].actualReps == 8)
        #expect(resolvedDrafts[0].actualWeight == 45)
        #expect(resolvedDrafts[0].actualLoadUnit == .kg)
    }

    @Test
    func completesWithoutFillWhenResolvedHistoryHasNoPreviousValues() {
        let draft = WorkoutSessionSetDraft(
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: .kg
        )

        let decision = WorkoutSetBozarCompletionController.decision(
            drafts: [draft],
            at: 0,
            previousResolution: .resolved([:])
        )

        guard case .completeImmediately(let resolvedDrafts)? = decision else {
            Issue.record("Expected immediate completion when history resolves with no previous set.")
            return
        }

        #expect(resolvedDrafts == [draft])
    }
}
