import Foundation

@MainActor
final class TemplateExerciseEditingCoordinator {
    private let commitDebounce: Duration
    private let onRepRangeCommitted: (Int?, Int?) -> Void
    private let onRestCommitted: (Int) -> Void
    private let onSetDraftsCommitted: ([TemplateExerciseSetDraft]) -> Void

    private var lastCommittedTargetRepMin: Int?
    private var lastCommittedTargetRepMax: Int?
    private var lastCommittedRestSeconds: Int
    private var lastCommittedSetDrafts: [TemplateExerciseSetDraft]
    private var pendingRepRangeCommitTask: Task<Void, Never>?
    private var pendingRestCommitTask: Task<Void, Never>?
    private var pendingSetDraftCommitTask: Task<Void, Never>?

    init(
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft],
        commitDebounce: Duration = .milliseconds(120),
        onRepRangeCommitted: @escaping (Int?, Int?) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onSetDraftsCommitted: @escaping ([TemplateExerciseSetDraft]) -> Void
    ) {
        self.commitDebounce = commitDebounce
        self.onRepRangeCommitted = onRepRangeCommitted
        self.onRestCommitted = onRestCommitted
        self.onSetDraftsCommitted = onSetDraftsCommitted
        lastCommittedTargetRepMin = targetRepMin
        lastCommittedTargetRepMax = targetRepMax
        lastCommittedRestSeconds = restSeconds
        lastCommittedSetDrafts = setDrafts
    }

    deinit {
        pendingRepRangeCommitTask?.cancel()
        pendingRestCommitTask?.cancel()
        pendingSetDraftCommitTask?.cancel()
    }

    func syncCommittedState(
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        lastCommittedTargetRepMin = targetRepMin
        lastCommittedTargetRepMax = targetRepMax
        lastCommittedRestSeconds = restSeconds
        lastCommittedSetDrafts = setDrafts
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
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        flushCommits(
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            setDrafts: setDrafts
        )
    }

    func flushCommits(
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft]
    ) {
        pendingRepRangeCommitTask?.cancel()
        pendingRepRangeCommitTask = nil
        pendingRestCommitTask?.cancel()
        pendingRestCommitTask = nil
        pendingSetDraftCommitTask?.cancel()
        pendingSetDraftCommitTask = nil

        commitRepRangeIfNeeded(targetRepMin: targetRepMin, targetRepMax: targetRepMax)
        commitRestIfNeeded(restSeconds)
        commitSetDraftsIfNeeded(setDrafts)
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
