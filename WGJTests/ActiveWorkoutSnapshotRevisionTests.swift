import XCTest
@testable import WGJ

final class ActiveWorkoutSnapshotRevisionTests: XCTestCase {
    func testInvalidationRejectsDelayedOldWriteAndPreservesNewMutationAfterReopen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000.75)
        let old = makeStoredSnapshot(revision: 10, name: "Before restore")
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        // Cleanup can finish before an already queued old write reaches the actor.
        try await store.invalidateSnapshotsSavedBefore(cutoff)
        let rejected = try await store.save(old)
        XCTAssertEqual(rejected, .rejectedInvalidated)
        let empty = try await store.loadStoredSnapshot()
        XCTAssertNil(empty)

        var newer = old
        newer.revision += 1
        newer.mutationTimestamp = cutoff.addingTimeInterval(0.125).timeIntervalSince1970
        newer.scrollOffsetY = 72 // Presentation-only edits do not touch session.updatedAt.
        let saved = try await store.save(newer)
        XCTAssertEqual(saved, .written)
        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        try await reopened.invalidateSnapshotsSavedBefore(cutoff)
        let restored = try await reopened.loadStoredSnapshot()
        XCTAssertEqual(restored?.mutationDate, newer.mutationDate)
        XCTAssertEqual(restored?.scrollOffsetY, 72)
        let lateOldWrite = try await reopened.save(old)
        XCTAssertEqual(lateOldWrite, .rejectedInvalidated)
        let retained = try await reopened.loadStoredSnapshot()
        XCTAssertEqual(retained?.revision, newer.revision)
    }

    func testLegacySnapshotAdoptsOriginalFileDateOnceAndKeepsItOnRetry() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("active-workout-snapshot.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(makeStoredSnapshot(revision: 2, name: "Legacy"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "mutationTimestamp")
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000.25)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: file.path)
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let loaded = try await store.loadStoredSnapshot()
        let migrated = try XCTUnwrap(loaded)
        XCTAssertEqual(migrated.mutationDate, originalDate)
        _ = try await store.save(migrated)
        let cold = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        try await cold.invalidateSnapshotsSavedBefore(originalDate.addingTimeInterval(0.125))
        let removed = try await cold.loadStoredSnapshot()
        XCTAssertNil(removed)
    }

    func testRevisionlessSnapshotDecodesAsZero() throws {
        let snapshot = makeStoredSnapshot(revision: 7, name: "Legacy")
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "revision")
        let revisionlessData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            ActiveWorkoutStoredSnapshot.self,
            from: revisionlessData
        )

        XCTAssertEqual(decoded.revision, 0)
        XCTAssertNil(decoded.scrollOffsetY)
        XCTAssertTrue(decoded.previousSetSnapshotsByExerciseID.isEmpty)
    }

    func testPreviousPerformanceCacheSurvivesColdSnapshotLoad() async throws {
        let directory = try makeTemporaryDirectory()
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let previousSet = WorkoutPreviousSetSnapshot(reps: 13, weight: 12, unit: .kg)
        let snapshot = ActiveWorkoutStoredSnapshot(
            revision: 3,
            session: ActiveWorkoutRuntimeSession(name: "Push"),
            scrollOffsetY: 428.5,
            previousSetSnapshotsByExerciseID: [exerciseID: [0: previousSet]]
        )

        let firstStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let writeResult = try await firstStore.save(snapshot)
        XCTAssertEqual(writeResult, .written)

        let coldStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let restored = try await coldStore.loadStoredSnapshot()

        XCTAssertEqual(restored?.previousSetSnapshotsByExerciseID[exerciseID]?[0], previousSet)
        XCTAssertEqual(restored?.scrollOffsetY, 428.5)
    }

    func testOlderRevisionCannotOverwriteNewerDiskSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let newer = makeStoredSnapshot(revision: 2, name: "New")
        let firstWrite = try await firstStore.save(newer)
        XCTAssertEqual(firstWrite, .written)

        let coldStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let older = makeStoredSnapshot(revision: 1, name: "Old")

        let staleWrite = try await coldStore.save(older)
        XCTAssertEqual(staleWrite, .rejectedStale(currentRevision: 2))
        let retainedSnapshot = try await coldStore.loadStoredSnapshot()
        XCTAssertEqual(retainedSnapshot?.session.name, "New")
    }

    func testEqualSnapshotReturnsUnchanged() async throws {
        let store = ActiveWorkoutSnapshotStore(baseDirectory: try makeTemporaryDirectory())
        let snapshot = makeStoredSnapshot(revision: 4, name: "Push")

        let firstWrite = try await store.save(snapshot)
        let secondWrite = try await store.save(snapshot)
        XCTAssertEqual(firstWrite, .written)
        XCTAssertEqual(secondWrite, .unchanged)
    }

    private func makeStoredSnapshot(
        revision: UInt64,
        name: String
    ) -> ActiveWorkoutStoredSnapshot {
        ActiveWorkoutStoredSnapshot(
            revision: revision,
            session: ActiveWorkoutRuntimeSession(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                name: name,
                startedAt: Date(timeIntervalSince1970: 100),
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJSnapshotRevisionTests", isDirectory: true)
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
