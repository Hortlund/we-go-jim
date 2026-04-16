import Foundation

@MainActor
final class WorkoutExerciseEditingCoordinator {
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
    private var hasDirtyDrafts = false
    private var hasDirtyRestSeconds = false
    private var hasDirtyNotes = false

    var hasPendingChanges: Bool {
        hasDirtyDrafts || hasDirtyRestSeconds || hasDirtyNotes
    }

    init(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String,
        onDraftsCommitted: @escaping ([WorkoutSessionSetDraft]) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onNotesCommitted: @escaping (String) -> Void,
        onCompletionChanged: @escaping (UUID, String?, Int, Bool) -> Void
    ) {
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

    func syncCommittedState(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String
    ) {
        lastCommittedDrafts = setDrafts
        lastCommittedRestSeconds = max(0, min(3600, restSeconds))
        lastCommittedNotes = notes
        if !hasDirtyDrafts {
            currentDrafts = setDrafts
        }
        if !hasDirtyRestSeconds {
            currentRestSeconds = max(0, min(3600, restSeconds))
        }
        if !hasDirtyNotes {
            currentNotes = notes
        }
    }

    func stageDrafts(_ drafts: [WorkoutSessionSetDraft]) {
        currentDrafts = drafts
        hasDirtyDrafts = lastCommittedDrafts != drafts
    }

    func stageRestCommit(_ restSeconds: Int) {
        currentRestSeconds = max(0, min(3600, restSeconds))
        hasDirtyRestSeconds = lastCommittedRestSeconds != currentRestSeconds
    }

    func stageNotesCommit(_ notes: String) {
        currentNotes = notes
        hasDirtyNotes = lastCommittedNotes != notes
    }

    func scheduleDraftCommit(_ drafts: [WorkoutSessionSetDraft]) {
        stageDrafts(drafts)
    }

    func scheduleRestCommit(_ restSeconds: Int) {
        stageRestCommit(restSeconds)
    }

    func scheduleNotesCommit(_ notes: String) {
        stageNotesCommit(notes)
    }

    func requestImmediateCommit(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String
    ) {
        if !hasDirtyDrafts || lastCommittedDrafts != setDrafts {
            stageDrafts(setDrafts)
        }
        if !hasDirtyRestSeconds || lastCommittedRestSeconds != max(0, min(3600, restSeconds)) {
            stageRestCommit(restSeconds)
        }
        if !hasDirtyNotes || lastCommittedNotes != notes {
            stageNotesCommit(notes)
        }
        flushCommits()
    }

    func flushCommits() {
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
        guard hasDirtyDrafts || lastCommittedDrafts != drafts else { return }
        WGJPerformance.measure("workout-row.commit.drafts") {
            onDraftsCommitted(drafts)
        }
        lastCommittedDrafts = drafts
        hasDirtyDrafts = false
    }

    private func commitRestIfNeeded(_ restSeconds: Int) {
        let normalized = max(0, min(3600, restSeconds))
        guard hasDirtyRestSeconds || lastCommittedRestSeconds != normalized else { return }
        WGJPerformance.measure("workout-row.commit.rest") {
            onRestCommitted(normalized)
        }
        lastCommittedRestSeconds = normalized
        hasDirtyRestSeconds = false
    }

    private func commitNotesIfNeeded(_ notes: String) {
        guard hasDirtyNotes || lastCommittedNotes != notes else { return }
        WGJPerformance.measure("workout-row.commit.notes") {
            onNotesCommitted(notes)
        }
        lastCommittedNotes = notes
        hasDirtyNotes = false
    }
}
