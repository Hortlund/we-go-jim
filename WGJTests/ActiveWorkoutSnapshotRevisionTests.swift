import XCTest
@testable import WGJ

final class ActiveWorkoutSnapshotRevisionTests: XCTestCase {
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
        XCTAssertTrue(decoded.previousSetSnapshotsByExerciseID.isEmpty)
    }

    func testPreviousPerformanceCacheSurvivesColdSnapshotLoad() async throws {
        let directory = try makeTemporaryDirectory()
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let previousSet = WorkoutPreviousSetSnapshot(reps: 13, weight: 12, unit: .kg)
        let snapshot = ActiveWorkoutStoredSnapshot(
            revision: 3,
            session: ActiveWorkoutRuntimeSession(name: "Push"),
            previousSetSnapshotsByExerciseID: [exerciseID: [0: previousSet]]
        )

        let firstStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let writeResult = try await firstStore.save(snapshot)
        XCTAssertEqual(writeResult, .written)

        let coldStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let restored = try await coldStore.loadStoredSnapshot()

        XCTAssertEqual(restored?.previousSetSnapshotsByExerciseID[exerciseID]?[0], previousSet)
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
