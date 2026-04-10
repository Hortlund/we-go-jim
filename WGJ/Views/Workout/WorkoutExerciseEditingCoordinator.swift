import Foundation

@MainActor
final class WorkoutExerciseEditingCoordinator {
    private let commitDebounce: Duration
    private let onDraftsCommitted: ([WorkoutSessionSetDraft]) -> Void
    private let onRestCommitted: (Int) -> Void
    private let onNotesCommitted: (String) -> Void
    private let onCompletionChanged: (UUID, String?, Int, Bool) -> Void

    private var currentDrafts: [WorkoutSessionSetDraft]
    private var currentRestSeconds: Int
    private var currentNotes: String
    private var lastCommittedDrafts: [WorkoutSessionSetDraft]
    private var lastCommittedRestSeconds: Int
    private var lastCommittedNotes: String
    private var pendingDraftCommitTask: Task<Void, Never>?
    private var pendingRestCommitTask: Task<Void, Never>?
    private var pendingNotesCommitTask: Task<Void, Never>?

    init(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String,
        commitDebounce: Duration = .milliseconds(120),
        onDraftsCommitted: @escaping ([WorkoutSessionSetDraft]) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onNotesCommitted: @escaping (String) -> Void,
        onCompletionChanged: @escaping (UUID, String?, Int, Bool) -> Void
    ) {
        self.commitDebounce = commitDebounce
        self.onDraftsCommitted = onDraftsCommitted
        self.onRestCommitted = onRestCommitted
        self.onNotesCommitted = onNotesCommitted
        self.onCompletionChanged = onCompletionChanged
        currentDrafts = setDrafts
        currentRestSeconds = max(0, min(3600, restSeconds))
        currentNotes = notes
        lastCommittedDrafts = setDrafts
        lastCommittedRestSeconds = max(0, min(3600, restSeconds))
        lastCommittedNotes = notes
    }

    deinit {
        pendingDraftCommitTask?.cancel()
        pendingRestCommitTask?.cancel()
        pendingNotesCommitTask?.cancel()
    }

    func syncCommittedState(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String
    ) {
        lastCommittedDrafts = setDrafts
        lastCommittedRestSeconds = max(0, min(3600, restSeconds))
        lastCommittedNotes = notes
        if pendingDraftCommitTask == nil {
            currentDrafts = setDrafts
        }
        if pendingRestCommitTask == nil {
            currentRestSeconds = max(0, min(3600, restSeconds))
        }
        if pendingNotesCommitTask == nil {
            currentNotes = notes
        }
    }

    func scheduleDraftCommit(_ drafts: [WorkoutSessionSetDraft]) {
        currentDrafts = drafts
        pendingDraftCommitTask?.cancel()
        pendingDraftCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingDraftCommitTask = nil
            commitDraftsIfNeeded(currentDrafts)
        }
    }

    func scheduleRestCommit(_ restSeconds: Int) {
        currentRestSeconds = max(0, min(3600, restSeconds))
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingRestCommitTask = nil
            commitRestIfNeeded(currentRestSeconds)
        }
    }

    func scheduleNotesCommit(_ notes: String) {
        currentNotes = notes
        pendingNotesCommitTask?.cancel()
        pendingNotesCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingNotesCommitTask = nil
            commitNotesIfNeeded(currentNotes)
        }
    }

    func requestImmediateCommit(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String
    ) {
        if lastCommittedDrafts != setDrafts {
            currentDrafts = setDrafts
        }
        let normalizedRestSeconds = max(0, min(3600, restSeconds))
        if lastCommittedRestSeconds != normalizedRestSeconds {
            currentRestSeconds = normalizedRestSeconds
        }
        if lastCommittedNotes != notes {
            currentNotes = notes
        }
        flushCommits()
    }

    func flushCommits() {
        pendingDraftCommitTask?.cancel()
        pendingDraftCommitTask = nil
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = nil
        pendingNotesCommitTask?.cancel()
        pendingNotesCommitTask = nil

        commitDraftsIfNeeded(currentDrafts)
        commitRestIfNeeded(currentRestSeconds)
        commitNotesIfNeeded(currentNotes)
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

    private func commitNotesIfNeeded(_ notes: String) {
        guard lastCommittedNotes != notes else { return }
        WGJPerformance.measure("workout-row.commit.notes") {
            onNotesCommitted(notes)
        }
        lastCommittedNotes = notes
    }
}
