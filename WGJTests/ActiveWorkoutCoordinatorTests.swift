import XCTest
@testable import WGJ

@MainActor
final class ActiveWorkoutCoordinatorTests: XCTestCase {
    func testActiveWorkoutCallersDoNotAccessSnapshotStoreDirectly() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let callerPaths = [
            "WGJ/ContentView.swift",
            "WGJ/Models/AppRuntimeConfig.swift",
            "WGJ/Views/Exercises/ExercisesCatalogView.swift",
            "WGJ/Views/Workout/StartWorkoutHomeView.swift",
            "WGJ/Views/Workout/ActiveWorkoutStripView.swift",
            "WGJ/Views/Workout/ActiveWorkoutView.swift",
        ]

        for callerPath in callerPaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(callerPath),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains("ActiveWorkoutSnapshotStore.shared"), callerPath)
        }
    }

    func testInterleavedCommandsPersistOneLatestRevisionWithoutLosingFields() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: StubActiveWorkoutPersistence()
        )
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let originalExercise = makeExercise(id: exerciseID, name: "Bench", sortOrder: 0)
        let session = ActiveWorkoutRuntimeSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Push",
            exercises: [originalExercise]
        )
        let drafts = [WorkoutSessionSetDraft(actualReps: 8, isCompleted: true)]

        XCTAssertEqual(coordinator.send(.start(session)).revision, 1)
        XCTAssertEqual(
            coordinator.send(.updateMetadata(name: "Push Updated", notes: "Strong" )).revision,
            2
        )
        XCTAssertEqual(
            coordinator.send(.setExerciseDrafts(exerciseID: exerciseID, drafts: drafts)).revision,
            3
        )
        XCTAssertEqual(
            coordinator.send(.updatePresentation(
                mode: .collapsed,
                scrollTarget: .exercise(exerciseID),
                expandedExerciseIDs: [exerciseID]
            )).revision,
            4
        )
        XCTAssertEqual(
            coordinator.send(.appendExercise(makeExercise(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                name: "Row",
                sortOrder: 99
            ))).revision,
            5
        )

        await coordinator.flushSnapshot()

        let recordedSnapshot = await store.lastSnapshot()
        let persisted = try XCTUnwrap(recordedSnapshot)
        XCTAssertEqual(persisted.revision, 5)
        XCTAssertEqual(persisted.session.name, "Push Updated")
        XCTAssertEqual(persisted.session.notes, "Strong")
        XCTAssertEqual(persisted.session.exercises.count, 2)
        XCTAssertEqual(persisted.session.exercises.map(\.sortOrder), [0, 1])
        XCTAssertEqual(persisted.session.exercises.first?.setDrafts, drafts)
        XCTAssertEqual(persisted.presentationMode, .collapsed)
        XCTAssertEqual(persisted.scrollTarget, .exercise(exerciseID))
        XCTAssertEqual(persisted.expandedExerciseIDs, [exerciseID])
    }

    func testRapidCommandsCoalesceAndNeverWriteConcurrently() async throws {
        let store = RecordingActiveWorkoutSnapshotStore(writeDelayNanoseconds: 5_000_000)
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: StubActiveWorkoutPersistence()
        )
        _ = coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Start")))
        for index in 1...10 {
            _ = coordinator.send(.updateMetadata(name: "Push \(index)", notes: ""))
        }

        await coordinator.flushSnapshot()

        let persisted = await store.lastSnapshot()
        let maximumConcurrentWrites = await store.maximumConcurrentWrites()
        XCTAssertEqual(persisted?.revision, 11)
        XCTAssertEqual(persisted?.session.name, "Push 10")
        XCTAssertEqual(maximumConcurrentWrites, 1)
    }

    func testRestoreRejectsCompletedSnapshotBeforePublishing() async throws {
        let session = ActiveWorkoutRuntimeSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Completed"
        )
        let store = RecordingActiveWorkoutSnapshotStore(
            initialSnapshot: ActiveWorkoutStoredSnapshot(revision: 4, session: session)
        )
        let persistence = StubActiveWorkoutPersistence(completedSessionIDs: [session.id])
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: persistence
        )

        await coordinator.restore()

        let retainedSnapshot = await store.lastSnapshot()
        XCTAssertNil(coordinator.storedSnapshot)
        XCTAssertNil(retainedSnapshot)
    }

    func testConcurrentCompletionCallsShareOnePersistenceOperation() async throws {
        let session = ActiveWorkoutRuntimeSession(name: "Push")
        let store = RecordingActiveWorkoutSnapshotStore()
        let persistence = StubActiveWorkoutPersistence(completionDelayNanoseconds: 5_000_000)
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: persistence
        )
        _ = coordinator.send(.start(session))

        async let first = coordinator.complete(notes: "Done")
        async let second = coordinator.complete(notes: "Done")
        let results = try await [first, second]
        let completionCallCount = await persistence.completionCallCount()

        XCTAssertEqual(results[0].sessionID, session.id)
        XCTAssertEqual(results[1].sessionID, session.id)
        XCTAssertEqual(completionCallCount, 1)
        XCTAssertNil(coordinator.storedSnapshot)
    }

    private func makeExercise(id: UUID, name: String, sortOrder: Int) -> ActiveWorkoutRuntimeExercise {
        ActiveWorkoutRuntimeExercise(
            id: id,
            catalogExerciseUUID: name.lowercased(),
            exerciseNameSnapshot: name,
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Upper",
            sortOrder: sortOrder
        )
    }
}

private actor RecordingActiveWorkoutSnapshotStore: ActiveWorkoutSnapshotStoring {
    private var snapshots: [ActiveWorkoutStoredSnapshot] = []
    private var activeWrites = 0
    private var maxActiveWrites = 0
    private let writeDelayNanoseconds: UInt64

    init(
        initialSnapshot: ActiveWorkoutStoredSnapshot? = nil,
        writeDelayNanoseconds: UInt64 = 0
    ) {
        if let initialSnapshot {
            snapshots = [initialSnapshot]
        }
        self.writeDelayNanoseconds = writeDelayNanoseconds
    }

    func loadStoredSnapshot() async throws -> ActiveWorkoutStoredSnapshot? {
        snapshots.last
    }

    func save(_ snapshot: ActiveWorkoutStoredSnapshot) async throws -> ActiveWorkoutSnapshotWriteResult {
        activeWrites += 1
        maxActiveWrites = max(maxActiveWrites, activeWrites)
        if writeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: writeDelayNanoseconds)
        }
        defer { activeWrites -= 1 }
        if snapshots.last == snapshot {
            return .unchanged
        }
        snapshots.append(snapshot)
        return .written
    }

    func delete() async throws {
        snapshots.removeAll()
    }

    func lastSnapshot() -> ActiveWorkoutStoredSnapshot? {
        snapshots.last
    }

    func maximumConcurrentWrites() -> Int {
        maxActiveWrites
    }
}

private actor StubActiveWorkoutPersistence: ActiveWorkoutPersistence {
    private let completedSessionIDs: Set<UUID>
    private let completionDelayNanoseconds: UInt64
    private var completionCalls = 0

    init(
        completedSessionIDs: Set<UUID> = [],
        completionDelayNanoseconds: UInt64 = 0
    ) {
        self.completedSessionIDs = completedSessionIDs
        self.completionDelayNanoseconds = completionDelayNanoseconds
    }

    func isCompleted(sessionID: UUID) async throws -> Bool {
        completedSessionIDs.contains(sessionID)
    }

    func complete(
        session: ActiveWorkoutRuntimeSession,
        notes: String?
    ) async throws -> WorkoutCompletionCommitResult {
        completionCalls += 1
        if completionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: completionDelayNanoseconds)
        }
        return WorkoutCompletionCommitResult(sessionID: session.id, disposition: .inserted)
    }

    func completionCallCount() -> Int {
        completionCalls
    }
}
