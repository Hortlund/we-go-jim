import Foundation

@MainActor
final class TemplateExerciseEditingCoordinator {
    private let commitDebounce: Duration
    private let onNotesCommitted: (String) -> Void
    private let onRepRangeCommitted: (Int?, Int?) -> Void
    private let onRestCommitted: (Int) -> Void
    private let onSetDraftsCommitted: ([TemplateExerciseSetDraft]) -> Void

    private var lastCommittedNotes: String
    private var lastCommittedTargetRepMin: Int?
    private var lastCommittedTargetRepMax: Int?
    private var lastCommittedRestSeconds: Int
    private var lastCommittedSetDrafts: [TemplateExerciseSetDraft]
    private var pendingNotesCommitTask: Task<Void, Never>?
    private var pendingRepRangeCommitTask: Task<Void, Never>?
    private var pendingRestCommitTask: Task<Void, Never>?
    private var pendingSetDraftCommitTask: Task<Void, Never>?

    init(
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft],
        commitDebounce: Duration = .milliseconds(120),
        onNotesCommitted: @escaping (String) -> Void,
        onRepRangeCommitted: @escaping (Int?, Int?) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onSetDraftsCommitted: @escaping ([TemplateExerciseSetDraft]) -> Void
    ) {
        self.commitDebounce = commitDebounce
        self.onNotesCommitted = onNotesCommitted
        self.onRepRangeCommitted = onRepRangeCommitted
        self.onRestCommitted = onRestCommitted
        self.onSetDraftsCommitted = onSetDraftsCommitted
        lastCommittedNotes = notes
        lastCommittedTargetRepMin = targetRepMin
        lastCommittedTargetRepMax = targetRepMax
        lastCommittedRestSeconds = restSeconds
        lastCommittedSetDrafts = setDrafts
    }

    deinit {
        pendingNotesCommitTask?.cancel()
        pendingRepRangeCommitTask?.cancel()
        pendingRestCommitTask?.cancel()
        pendingSetDraftCommitTask?.cancel()
    }

    func syncCommittedState(
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        lastCommittedNotes = notes
        lastCommittedTargetRepMin = targetRepMin
        lastCommittedTargetRepMax = targetRepMax
        lastCommittedRestSeconds = restSeconds
        lastCommittedSetDrafts = setDrafts
    }

    func scheduleNotesCommit(_ notes: String) {
        pendingNotesCommitTask?.cancel()
        pendingNotesCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingNotesCommitTask = nil
            commitNotesIfNeeded(notes)
        }
    }

    func scheduleRepRangeCommit(
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        pendingRepRangeCommitTask?.cancel()
        pendingRepRangeCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingRepRangeCommitTask = nil
            commitRepRangeIfNeeded(targetRepMin: targetRepMin, targetRepMax: targetRepMax)
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

    func scheduleSetDraftCommit(_ setDrafts: [TemplateExerciseSetDraft]) {
        pendingSetDraftCommitTask?.cancel()
        pendingSetDraftCommitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDebounce)
            guard !Task.isCancelled else { return }
            pendingSetDraftCommitTask = nil
            commitSetDraftsIfNeeded(setDrafts)
        }
    }

    func requestImmediateCommit(
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        flushCommits(
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            setDrafts: setDrafts
        )
    }

    func hasPendingChanges(
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) -> Bool {
        let normalizedRestSeconds = max(0, min(3600, restSeconds))
        return lastCommittedNotes != notes
            || lastCommittedTargetRepMin != targetRepMin
            || lastCommittedTargetRepMax != targetRepMax
            || lastCommittedRestSeconds != normalizedRestSeconds
            || lastCommittedSetDrafts != setDrafts
    }

    func flushCommits(
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        pendingNotesCommitTask?.cancel()
        pendingNotesCommitTask = nil
        pendingRepRangeCommitTask?.cancel()
        pendingRepRangeCommitTask = nil
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = nil
        pendingSetDraftCommitTask?.cancel()
        pendingSetDraftCommitTask = nil

        commitNotesIfNeeded(notes)
        commitRepRangeIfNeeded(targetRepMin: targetRepMin, targetRepMax: targetRepMax)
        commitRestIfNeeded(restSeconds)
        commitSetDraftsIfNeeded(setDrafts)
    }

    private func commitNotesIfNeeded(_ notes: String) {
        guard lastCommittedNotes != notes else { return }
        WGJPerformance.measure("template-row.commit.notes") {
            onNotesCommitted(notes)
        }
        lastCommittedNotes = notes
    }

    private func commitRepRangeIfNeeded(
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        guard lastCommittedTargetRepMin != targetRepMin || lastCommittedTargetRepMax != targetRepMax else {
            return
        }
        WGJPerformance.measure("template-row.commit.rep-range") {
            onRepRangeCommitted(targetRepMin, targetRepMax)
        }
        lastCommittedTargetRepMin = targetRepMin
        lastCommittedTargetRepMax = targetRepMax
    }

    private func commitRestIfNeeded(_ restSeconds: Int) {
        let normalized = max(0, min(3600, restSeconds))
        guard lastCommittedRestSeconds != normalized else { return }
        WGJPerformance.measure("template-row.commit.rest") {
            onRestCommitted(normalized)
        }
        lastCommittedRestSeconds = normalized
    }

    private func commitSetDraftsIfNeeded(_ setDrafts: [TemplateExerciseSetDraft]) {
        guard lastCommittedSetDrafts != setDrafts else { return }
        WGJPerformance.measure("template-row.commit.drafts") {
            onSetDraftsCommitted(setDrafts)
        }
        lastCommittedSetDrafts = setDrafts
    }
}
