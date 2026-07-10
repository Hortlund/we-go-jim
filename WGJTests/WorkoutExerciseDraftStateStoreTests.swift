import XCTest
@testable import WGJ

@MainActor
final class WorkoutExerciseDraftStateStoreTests: XCTestCase {
    func testNoOpMutationDoesNotAdvanceRevision() {
        let exerciseID = UUID()
        let store = WorkoutExerciseDraftStateStore()

        XCTAssertTrue(store.setNotes("Tempo", for: exerciseID))
        let revision = store.revision

        XCTAssertFalse(store.setNotes("Tempo", for: exerciseID))
        XCTAssertEqual(store.revision, revision)
    }

    func testSnapshotFiltersRemovedExercisesWithoutMutatingStore() {
        let keptID = UUID()
        let removedID = UUID()
        let store = WorkoutExerciseDraftStateStore()
        _ = store.setRestSeconds(90, for: keptID)
        _ = store.setRestSeconds(120, for: removedID)

        let snapshot = store.snapshot(keeping: [keptID])

        XCTAssertEqual(snapshot.restsByExerciseID, [keptID: 90])
        XCTAssertEqual(store.restSeconds(for: removedID), 120)
    }

    func testMergeReplacesOnlyProvidedExerciseValues() {
        let firstID = UUID()
        let secondID = UUID()
        let store = WorkoutExerciseDraftStateStore()
        _ = store.setNotes("Original", for: firstID)
        _ = store.setRestSeconds(60, for: secondID)

        store.merge(
            WorkoutExerciseDraftStateSnapshot(
                draftsByExerciseID: [:],
                restsByExerciseID: [:],
                notesByExerciseID: [firstID: "Updated"]
            )
        )

        XCTAssertEqual(store.notes(for: firstID), "Updated")
        XCTAssertEqual(store.restSeconds(for: secondID), 60)
    }

    func testRemoveClearsAllValuesForOneExercise() {
        let exerciseID = UUID()
        let store = WorkoutExerciseDraftStateStore()
        _ = store.setDrafts([WorkoutSessionSetDraft()], for: exerciseID)
        _ = store.setRestSeconds(90, for: exerciseID)
        _ = store.setNotes("Controlled", for: exerciseID)

        store.remove(exerciseID: exerciseID)

        XCTAssertNil(store.drafts(for: exerciseID))
        XCTAssertNil(store.restSeconds(for: exerciseID))
        XCTAssertNil(store.notes(for: exerciseID))
    }
}
