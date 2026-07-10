import Foundation

nonisolated struct WorkoutExerciseDraftStateSnapshot: Equatable, Sendable {
    var draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    var restsByExerciseID: [UUID: Int]
    var notesByExerciseID: [UUID: String]

    static let empty = WorkoutExerciseDraftStateSnapshot(
        draftsByExerciseID: [:],
        restsByExerciseID: [:],
        notesByExerciseID: [:]
    )
}

/// Mutable input storage that deliberately does not participate in SwiftUI observation.
/// Row views own immediate field rendering; session projections refresh only for structural
/// or completion changes instead of for every committed character.
nonisolated final class WorkoutExerciseDraftStateStore {
    @MainActor private var state = WorkoutExerciseDraftStateSnapshot.empty
    @MainActor private(set) var revision = 0

    @MainActor
    @discardableResult
    func setDrafts(_ value: [WorkoutSessionSetDraft], for exerciseID: UUID) -> Bool {
        guard state.draftsByExerciseID[exerciseID] != value else { return false }
        state.draftsByExerciseID[exerciseID] = value
        revision += 1
        return true
    }

    @MainActor
    @discardableResult
    func setRestSeconds(_ value: Int, for exerciseID: UUID) -> Bool {
        let normalized = max(0, min(3_600, value))
        guard state.restsByExerciseID[exerciseID] != normalized else { return false }
        state.restsByExerciseID[exerciseID] = normalized
        revision += 1
        return true
    }

    @MainActor
    @discardableResult
    func setNotes(_ value: String, for exerciseID: UUID) -> Bool {
        guard state.notesByExerciseID[exerciseID] != value else { return false }
        state.notesByExerciseID[exerciseID] = value
        revision += 1
        return true
    }

    @MainActor
    func drafts(for exerciseID: UUID) -> [WorkoutSessionSetDraft]? {
        state.draftsByExerciseID[exerciseID]
    }

    @MainActor
    func restSeconds(for exerciseID: UUID) -> Int? {
        state.restsByExerciseID[exerciseID]
    }

    @MainActor
    func notes(for exerciseID: UUID) -> String? {
        state.notesByExerciseID[exerciseID]
    }

    @MainActor
    func replace(with snapshot: WorkoutExerciseDraftStateSnapshot) {
        guard state != snapshot else { return }
        state = snapshot
        revision += 1
    }

    @MainActor
    func merge(_ snapshot: WorkoutExerciseDraftStateSnapshot) {
        var merged = state
        merged.draftsByExerciseID.merge(snapshot.draftsByExerciseID) { _, new in new }
        merged.restsByExerciseID.merge(snapshot.restsByExerciseID) { _, new in new }
        merged.notesByExerciseID.merge(snapshot.notesByExerciseID) { _, new in new }
        replace(with: merged)
    }

    @MainActor
    func remove(exerciseID: UUID) {
        var updated = state
        updated.draftsByExerciseID.removeValue(forKey: exerciseID)
        updated.restsByExerciseID.removeValue(forKey: exerciseID)
        updated.notesByExerciseID.removeValue(forKey: exerciseID)
        replace(with: updated)
    }

    @MainActor
    func removeAll() {
        replace(with: .empty)
    }

    @MainActor
    func snapshot() -> WorkoutExerciseDraftStateSnapshot {
        state
    }

    @MainActor
    func snapshot(keeping exerciseIDs: Set<UUID>) -> WorkoutExerciseDraftStateSnapshot {
        WorkoutExerciseDraftStateSnapshot(
            draftsByExerciseID: state.draftsByExerciseID.filter { exerciseIDs.contains($0.key) },
            restsByExerciseID: state.restsByExerciseID.filter { exerciseIDs.contains($0.key) },
            notesByExerciseID: state.notesByExerciseID.filter { exerciseIDs.contains($0.key) }
        )
    }
}
