import Observation

nonisolated struct ActiveWorkoutFinishSummaryInput: Sendable {
    let revision: UInt64
    let exerciseDrafts: [[WorkoutSessionSetDraft]]
    let cardioBlocks: [WorkoutCardioBlockDraft]
}

@Observable
nonisolated final class ActiveWorkoutFinishSummaryModel {
    private(set) var content: ActiveWorkoutFinishConfirmationContent?
    private(set) var presentedRevision: UInt64?
    @ObservationIgnored private let build: (
        ActiveWorkoutFinishSummaryInput
    ) -> ActiveWorkoutFinishConfirmationContent

    init(
        build: @escaping (
            ActiveWorkoutFinishSummaryInput
        ) -> ActiveWorkoutFinishConfirmationContent = { input in
            ActiveWorkoutFinishConfirmationContent(
                exerciseDrafts: input.exerciseDrafts,
                cardioBlocks: input.cardioBlocks
            )
        }
    ) {
        self.build = build
    }

    func present(_ input: ActiveWorkoutFinishSummaryInput) {
        if presentedRevision != input.revision {
            content = build(input)
            presentedRevision = input.revision
        }
    }

    func refreshIfPresented(_ input: ActiveWorkoutFinishSummaryInput) {
        guard presentedRevision != nil else { return }
        present(input)
    }

    func dismiss() {
        content = nil
        presentedRevision = nil
    }
}
