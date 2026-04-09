import Foundation

@MainActor
final class WorkoutExerciseEditingCoordinator {
    private let commitDebounce: Duration
    private let onDraftsCommitted: ([WorkoutSessionSetDraft]) -> Void
    private let onRestCommitted: (Int) -> Void
    private let onCompletionChanged: (UUID, String?, Int, Bool) -> Void

    private var lastCommittedDrafts: [WorkoutSessionSetDraft]
    private var lastCommittedRestSeconds: Int
    private var pendingDraftCommitTask: Task<Void, Never>?
    private var pendingRestCommitTask: Task<Void, Never>?

    init(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        commitDebounce: Duration = .milliseconds(120),
        onDraftsCommitted: @escaping ([WorkoutSessionSetDraft]) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onCompletionChanged: @escaping (UUID, String?, Int, Bool) -> Void
    ) {
        self.commitDebounce = commitDebounce
        self.onDraftsCommitted = onDraftsCommitted
        self.onRestCommitted = onRestCommitted
        self.onCompletionChanged = onCompletionChanged
        lastCommittedDrafts = setDrafts
        lastCommittedRestSeconds = restSeconds
    }

    deinit {
        pendingDraftCommitTask?.cancel()
        pendingRestCommitTask?.cancel()
    }

    func syncCommittedState(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int
    ) {
        lastCommittedDrafts = setDrafts
        lastCommittedRestSeconds = restSeconds
    }

    func scheduleDraftCommit(_ drafts: [WorkoutSessionSetDraft]) {
        pendingDraftCommitTask?.cancel()
        pendingDraftCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingDraftCommitTask = nil
            commitDraftsIfNeeded(drafts)
        }
    }

    func scheduleRestCommit(_ restSeconds: Int) {
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingRestCommitTask = nil
            commitRestIfNeeded(restSeconds)
        }
    }

    func requestImmediateCommit(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int
    ) {
        flushCommits(setDrafts: setDrafts, restSeconds: restSeconds)
    }

    func flushCommits(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int
    ) {
        pendingDraftCommitTask?.cancel()
        pendingDraftCommitTask = nil
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = nil

        commitDraftsIfNeeded(setDrafts)
        commitRestIfNeeded(restSeconds)
    }

    func relayCompletionChange(
        setID: UUID,
        setLabel: String?,
        restSeconds: Int,
        isCompleted: Bool
    ) {
        onCompletionChanged(setID, setLabel, restSeconds, isCompleted)
    }

    private func commitDraftsIfNeeded(_ drafts: [WorkoutSessionSetDraft]) {
        guard lastCommittedDrafts != drafts else { return }
        WGJPerformance.measure("workout-row.commit.drafts") {
            onDraftsCommitted(drafts)
        }
        lastCommittedDrafts = drafts
    }

    private func commitRestIfNeeded(_ restSeconds: Int) {
        let normalized = max(0, min(3600, restSeconds))
        guard lastCommittedRestSeconds != normalized else { return }
        WGJPerformance.measure("workout-row.commit.rest") {
            onRestCommitted(normalized)
        }
        lastCommittedRestSeconds = normalized
    }
}
