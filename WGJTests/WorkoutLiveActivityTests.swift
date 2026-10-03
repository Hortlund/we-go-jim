import ActivityKit
import XCTest
@testable import WGJ

@MainActor
final class WorkoutLiveActivityTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10000)

    func testLiveActivitiesDefaultOffPersistPreferenceAndEndWhenDisabled() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestLiveActivityClient()
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: defaults, canStart: { true })
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Workout"))
        XCTAssertFalse(publisher.isEnabled)
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 0)
        publisher.setEnabled(true)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        XCTAssertTrue(WorkoutLiveActivityPublisher(client: client, defaults: defaults).isEnabled)
        publisher.setEnabled(false)
        await publisher.waitForPendingUpdates()
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertFalse(WorkoutLiveActivityPublisher(client: client, defaults: defaults).isEnabled)
        publisher.setEnabled(true)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 2)
    }

    func testDefaultOffRemovesActivitiesLeftByEarlierVersions() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Workout"))
        let state = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil)).state
        let client = TestLiveActivityClient()
        client.records = [.init(id: "old", sessionID: snapshot.session.id, state: state)]
        // Earlier versions remembered activity identity without an opt-in key.
        defaults.set(snapshot.session.id.uuidString, forKey: "workoutLiveActivity.lastStartedSession")
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: defaults, canStart: { true })
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertEqual(client.startCount, 0)
        publisher.setEnabled(true)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
    }

    func testIdleCardioDoesNotStartAndRunningTimerIncludesEarlierSegments() throws {
        var snapshot = cardioSnapshot()
        XCTAssertNil(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil, at: date))
        snapshot.session.cardioBlocks[0].timerState = .running
        snapshot.session.cardioBlocks[0].timerAccumulatedSeconds = 120
        snapshot.session.cardioBlocks[0].timerSegmentStartedAt = date.addingTimeInterval(-30)
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil, at: date))
        XCTAssertEqual(projection.state.timerStart, date.addingTimeInterval(-150))
        XCTAssertEqual(projection.state.elapsedSeconds, 150)
        XCTAssertNil(projection.state.distance)
    }

    func testPausedCardioFreezesTimeAndRejectsAnotherSessionsDistance() throws {
        var snapshot = cardioSnapshot()
        snapshot.session.cardioBlocks[0].timerState = .paused
        snapshot.session.cardioBlocks[0].timerAccumulatedSeconds = 120
        var route = CardioRoute(sessionID: UUID(), activityID: snapshot.session.cardioBlocks[0].id)
        route.distanceMeters = 1000
        let wrong = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route, at: date))
        XCTAssertNil(wrong.state.timerStart)
        XCTAssertEqual(wrong.state.elapsedSeconds, 120)
        XCTAssertNil(wrong.state.distance)
        route = CardioRoute(sessionID: snapshot.session.id, activityID: snapshot.session.cardioBlocks[0].id)
        route.distanceMeters = 1000
        let matching = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route, at: date))
        XCTAssertEqual(matching.state.distance, "\(Double(1).formatted(.number.precision(.fractionLength(2)))) km")
        XCTAssertEqual(matching.state.pace, "2:00 /km")
        let later = WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route, at: date.addingTimeInterval(500))
        XCTAssertEqual(later, matching)
    }

    func testCompletedCardioUsesSavedManualResultRatherThanGPSCache() throws {
        var snapshot = cardioSnapshot()
        snapshot.session.cardioBlocks[0].isCompleted = true
        snapshot.session.cardioBlocks[0].actualDurationSeconds = 600
        snapshot.session.cardioBlocks[0].actualDistanceMeters = 1609.344
        snapshot.session.cardioBlocks[0].preferredDistanceUnit = .miles
        var route = CardioRoute(sessionID: snapshot.session.id, activityID: snapshot.session.cardioBlocks[0].id)
        route.distanceMeters = 9000
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route, at: date))
        XCTAssertNil(projection.state.timerStart)
        XCTAssertEqual(projection.state.elapsedSeconds, 600)
        XCTAssertEqual(projection.state.pace, "10:00 /mi")
        XCTAssertEqual(projection.state.status, "Completed")
    }

    func testStrengthAndMixedWorkoutsUseSessionClockAllSetsAndRest() throws {
        let exercise = ActiveWorkoutRuntimeExercise(catalogExerciseUUID: "bench", exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", setDrafts: [
                .init(isWarmup: true, isCompleted: true), .init(isCompleted: true), .init()
            ])
        var snapshot = cardioSnapshot()
        snapshot.session.exercises = [exercise]
        snapshot.session.startedAt = date.addingTimeInterval(-1800)
        snapshot.restTimer = RestTimerSnapshot(endsAt: date.addingTimeInterval(60), exerciseName: "Bench",
            setLabel: "Set 1", sourceSetID: UUID())
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil, at: date))
        XCTAssertFalse(projection.state.isCardio)
        XCTAssertEqual(projection.state.timerStart, snapshot.session.startedAt)
        XCTAssertEqual(projection.state.progress, "2/3 sets")
        XCTAssertEqual(projection.state.restEndsAt, snapshot.restTimer?.endsAt)
        XCTAssertNil(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil, at: date.addingTimeInterval(61))?.state.restEndsAt)
    }

    func testWarmupOnlyWorkoutShowsCompletedSetProgress() throws {
        let exercise = ActiveWorkoutRuntimeExercise(catalogExerciseUUID: "bench", exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", setDrafts: [
                .init(isWarmup: true, isCompleted: true), .init(isWarmup: true)
            ])
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Warmup", exercises: [exercise]))
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil, at: date))
        XCTAssertEqual(projection.state.progress, "1/2 sets")
    }

    func testSystemUpdatesDoNotDuplicateActivitiesAndNilEndsThePresentation() async {
        let client = TestLiveActivityClient()
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Push Day"))
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        XCTAssertEqual(client.updateCount, 0)
        var changed = snapshot
        changed.session.name = "Pull Day"
        publisher.synchronize(snapshot: changed, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.updateCount, 1)
        XCTAssertEqual(client.records.first?.state.title, "Pull Day")
        publisher.synchronize(snapshot: nil, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertEqual(client.endCount, 1)
    }

    func testDisabledAndBackgroundStartsAreRetriedOnlyWhenAvailable() async {
        let client = TestLiveActivityClient()
        client.isEnabled = false
        var foreground = false
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { foreground }, initiallyEnabled: true)
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Workout"))
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 0)
        client.isEnabled = true
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 0)
        foreground = true
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
    }

    func testDismissalRemainsRespectedAfterPublisherRecreation() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestLiveActivityClient()
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Walk"))
        let first = WorkoutLiveActivityPublisher(client: client, defaults: defaults, canStart: { true }, initiallyEnabled: true)
        first.synchronize(snapshot: snapshot, route: nil)
        await first.waitForPendingUpdates()
        client.records = [] // The person dismissed it on the Lock Screen.
        let second = WorkoutLiveActivityPublisher(client: client, defaults: defaults, canStart: { true }, initiallyEnabled: true)
        second.synchronize(snapshot: snapshot, route: nil)
        await second.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        let next = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "New Workout"))
        second.synchronize(snapshot: next, route: nil)
        await second.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 2)
    }

    func testRestoreReusesMatchingActivityAndEndsOrphans() async throws {
        let client = TestLiveActivityClient()
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Restored"))
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil))
        client.records = [.init(id: "matching", sessionID: snapshot.session.id, state: projection.state),
            .init(id: "orphan", sessionID: UUID(), state: projection.state)]
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.records.map(\.id), ["matching"])
        XCTAssertEqual(client.startCount, 0)
        XCTAssertEqual(client.endCount, 1)
    }

    func testExpiredActivityIsRemovedWithoutRestartingSameWorkout() async throws {
        let client = TestLiveActivityClient()
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Long Workout"))
        let projection = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: nil))
        client.records = [.init(id: "expired", sessionID: snapshot.session.id, state: projection.state, isActive: false)]
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 0)
        XCTAssertEqual(client.endCount, 1)
    }

    func testQueuedFinishCannotLeaveAnActivityRunning() async {
        let client = TestLiveActivityClient()
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Workout"))
        publisher.synchronize(snapshot: snapshot, route: nil)
        publisher.synchronize(snapshot: nil, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertEqual(client.startCount, 0)
    }

    func testAddingCardioToEmptyWorkoutKeepsItsExistingLiveActivity() async {
        let client = TestLiveActivityClient()
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        var snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Empty Workout"))
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        snapshot.session.cardioBlocks = cardioSnapshot().session.cardioBlocks
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.endCount, 0)
        XCTAssertEqual(client.records.first?.state.status, "Ready to start")
        snapshot.session.cardioBlocks[0].timerState = .running
        snapshot.session.cardioBlocks[0].timerSegmentStartedAt = .now
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        XCTAssertNotNil(client.records.first?.state.timerStart)
    }

    func testCoordinatorWaitsForDurableRestoreThenEndsActivityOnCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: root)
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Recovered"))
        _ = try await store.save(snapshot)
        let client = TestLiveActivityClient()
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: LiveActivityTestPersistence(),
            routeRecorder: nil, liveActivityPublisher: publisher)
        coordinator.refreshLiveActivity() // Foreground before the startup disk lookup.
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.records.count, 1)
        await coordinator.restore()
        await publisher.waitForPendingUpdates()
        XCTAssertEqual(client.startCount, 1)
        _ = try await coordinator.complete(notes: nil)
        await publisher.waitForPendingUpdates()
        XCTAssertTrue(client.records.isEmpty)
        XCTAssertNil(coordinator.storedSnapshot)
    }

    func testPausedOutdoorRestoreKeepsLiveActivityDistanceAndPaceWithoutStartingGPS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: root.appendingPathComponent("draft"))
        let routeStore = CardioRouteStore(directory: root.appendingPathComponent("routes"))
        var snapshot = cardioSnapshot()
        snapshot.session.cardioBlocks[0].timerState = .paused
        snapshot.session.cardioBlocks[0].timerAccumulatedSeconds = 120
        snapshot.presentationMode = .collapsed
        var route = CardioRoute(sessionID: snapshot.session.id, activityID: snapshot.session.cardioBlocks[0].id)
        route.distanceMeters = 1_000
        let generation = await routeStore.writeGeneration()
        try await routeStore.save(route, generation: generation)
        _ = try await snapshotStore.save(snapshot)

        // The system retained the correct summary, but the relaunched app has
        // an empty recorder cache and no distance in the unfinished draft.
        let expected = try XCTUnwrap(WorkoutLiveActivityProjection.make(snapshot: snapshot, route: route))
        let client = TestLiveActivityClient()
        client.records = [.init(id: "paused-walk", sessionID: snapshot.session.id, state: expected.state)]
        let publisher = WorkoutLiveActivityPublisher(client: client, defaults: nil, canStart: { true }, initiallyEnabled: true)
        let recorder = CardioRouteRecorder(store: routeStore)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: snapshotStore, persistence: LiveActivityTestPersistence(),
            routeRecorder: recorder, liveActivityPublisher: publisher)
        await coordinator.restore()
        await publisher.waitForPendingUpdates()

        XCTAssertEqual(client.records.first?.state.distance, expected.state.distance)
        XCTAssertEqual(client.records.first?.state.pace, "2:00 /km")
        XCTAssertEqual(client.records.first?.state.status, "Paused")
        XCTAssertNil(client.records.first?.state.timerStart)
        XCTAssertEqual(client.records.first?.state.elapsedSeconds, 120)
        XCTAssertEqual(client.startCount, 0)
        XCTAssertEqual(client.endCount, 0)
        XCTAssertEqual(recorder.route, route)
        XCTAssertEqual(recorder.gpsState, .paused)
        XCTAssertEqual(recorder.route?.isRecording, false)
        let savedRoute = try await routeStore.load(activityID: route.activityID)
        XCTAssertEqual(savedRoute, route)
        XCTAssertNil(coordinator.storedSnapshot?.session.cardioBlocks[0].actualDistanceMeters)
    }

    func testDeepLinkTargetsOnlyTheExpectedAppAndWorkout() {
        let id = UUID()
        let url = WorkoutActivityAttributes.workoutURL(sessionID: id, scheme: "wgj-dev")
        XCTAssertEqual(AppRouteParser.parse(url, expectedScheme: "wgj-dev"), .activeWorkout(id))
        XCTAssertNil(AppRouteParser.parse(url, expectedScheme: "wgj"))
        XCTAssertNil(AppRouteParser.parse(URL(string: "wgj-dev://workout/invalid")!, expectedScheme: "wgj-dev"))
    }

    func testSystemActivityKitStartsUpdatesAndEndsTheInstalledWidget() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities are disabled on this device") }
        let publisher = WorkoutLiveActivityPublisher(defaults: nil, canStart: { true }, initiallyEnabled: true)
        let snapshot = ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Live Activity integration test"))
        publisher.synchronize(snapshot: snapshot, route: nil)
        await publisher.waitForPendingUpdates()
        let activity = try XCTUnwrap(Activity<WorkoutActivityAttributes>.activities.first {
            $0.attributes.sessionID == snapshot.session.id && $0.activityState == .active
        })
        XCTAssertEqual(activity.content.state.title, snapshot.session.name)
        var changed = snapshot
        changed.session.name = "Updated integration test"
        publisher.synchronize(snapshot: changed, route: nil)
        await publisher.waitForPendingUpdates()
        // ActivityKit delivers its observed content asynchronously after the RPC.
        for _ in 0..<50 where activity.content.state.title != changed.session.name {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(activity.content.state.title, changed.session.name)
        publisher.synchronize(snapshot: nil, route: nil)
        await publisher.waitForPendingUpdates()
        for _ in 0..<50 where Activity<WorkoutActivityAttributes>.activities.contains(where: {
            $0.attributes.sessionID == snapshot.session.id && $0.activityState == .active
        }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(Activity<WorkoutActivityAttributes>.activities.contains {
            $0.attributes.sessionID == snapshot.session.id && $0.activityState == .active
        })
    }

    private func cardioSnapshot() -> ActiveWorkoutStoredSnapshot {
        let activity = ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout, role: .main,
            catalogExerciseUUID: "seed-outdoor-walk", exerciseNameSnapshot: "Outdoor Walk", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "", trackingProfile: .walkRun, goalKind: .open, targetDurationSeconds: 0)
        return ActiveWorkoutStoredSnapshot(session: ActiveWorkoutRuntimeSession(name: "Walk", cardioBlocks: [activity]))
    }
}

@MainActor
private final class TestLiveActivityClient: WorkoutLiveActivityClient {
    var isEnabled = true
    var records: [WorkoutLiveActivityRecord] = []
    var startCount = 0
    var updateCount = 0
    var endCount = 0
    func start(_ projection: WorkoutLiveActivityProjection) throws {
        startCount += 1
        records.append(.init(id: UUID().uuidString, sessionID: projection.sessionID, state: projection.state))
    }
    func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        updateCount += 1
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index] = .init(id: id, sessionID: records[index].sessionID, state: state)
        }
    }
    func end(id: String) async {
        endCount += 1
        records.removeAll { $0.id == id }
    }
}

private struct LiveActivityTestPersistence: ActiveWorkoutPersistence {
    func isCompleted(sessionID: UUID) async throws -> Bool { false }
    func complete(session: ActiveWorkoutRuntimeSession, notes: String?) async throws -> WorkoutCompletionCommitResult {
        .init(sessionID: session.id, disposition: .inserted)
    }
}
