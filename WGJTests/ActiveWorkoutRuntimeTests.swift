import XCTest
@testable import WGJ

final class ActiveWorkoutRuntimeTests: XCTestCase {
    func testSnapshotStorePreservesRestoreMetadataAcrossCachedSaves() async throws {
        let store = ActiveWorkoutSnapshotStore(baseDirectory: try makeTemporaryDirectory())
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let firstSession = ActiveWorkoutRuntimeSession(
            id: sessionID,
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let scrollTarget = ActiveWorkoutScrollTarget.exercise(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let expandedExerciseIDs: Set<UUID> = [
            UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        ]

        try await store.save(
            firstSession,
            restTimer: RestTimerSnapshot(
                endsAt: Date.distantFuture,
                exerciseName: "Bench Press",
                setLabel: "Working Set 1",
                sourceSetID: nil
            ),
            presentationMode: .presented,
            scrollTarget: scrollTarget,
            expandedExerciseIDs: expandedExerciseIDs,
            preservesExistingRestTimer: false,
            preservesExistingPresentationMode: false,
            preservesExistingScrollTarget: false,
            preservesExistingExpandedExerciseIDs: false
        )

        let updatedSession = ActiveWorkoutRuntimeSession(
            id: sessionID,
            name: "Push Updated",
            startedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.save(updatedSession)

        let storedSnapshot = try await store.loadStoredSnapshot()
        XCTAssertEqual(storedSnapshot?.session.name, "Push Updated")
        XCTAssertEqual(storedSnapshot?.restTimer?.exerciseName, "Bench Press")
        XCTAssertEqual(storedSnapshot?.presentationMode, .presented)
        XCTAssertEqual(storedSnapshot?.scrollTarget, scrollTarget)
        XCTAssertEqual(storedSnapshot?.expandedExerciseIDs, expandedExerciseIDs)

        try await store.delete()
        let deletedSnapshot = try await store.loadStoredSnapshot()
        XCTAssertNil(deletedSnapshot)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
