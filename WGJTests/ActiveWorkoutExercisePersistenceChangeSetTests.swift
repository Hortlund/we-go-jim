import Testing
@testable import WGJ

struct ActiveWorkoutExercisePersistenceChangeSetTests {
    @Test
    func notesOnlyChangeDoesNotMarkNormalizedBodyweightDraftsDirty() {
        let normalizedDraft = WorkoutSessionSetDraft(
            restSeconds: 90,
            targetLoadUnit: .bodyweight,
            actualLoadUnit: .bodyweight
        )
        let persisted = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: [normalizedDraft],
            restSeconds: 90,
            notes: ""
        )
        let current = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: [normalizedDraft],
            restSeconds: 90,
            notes: "Keep ribs down."
        )

        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: current,
            persisted: persisted
        )

        #expect(!changes.persistDrafts)
        #expect(!changes.persistRest)
        #expect(changes.persistNotes)
        #expect(changes.hasChanges)
    }

    @Test
    func identicalSnapshotsProduceNoPersistenceWork() {
        let snapshot = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: [
                WorkoutSessionSetDraft(
                    targetReps: 8,
                    targetWeight: 100,
                    targetLoadUnit: .kg,
                    actualReps: 8,
                    actualWeight: 100,
                    actualLoadUnit: .kg,
                    isCompleted: true
                ),
            ],
            restSeconds: 120,
            notes: "Match last session."
        )

        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: snapshot,
            persisted: snapshot
        )

        #expect(!changes.persistDrafts)
        #expect(!changes.persistRest)
        #expect(!changes.persistNotes)
        #expect(!changes.hasChanges)
    }
}
