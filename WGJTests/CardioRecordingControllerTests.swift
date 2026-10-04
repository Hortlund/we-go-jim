import CoreLocation
import XCTest
@testable import WGJ

@MainActor
final class CardioRecordingControllerTests: XCTestCase {
    func testCancelledStartCannotChangeTimerOrTakeOverGPS() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TestCardioLocationManager()
        let recorder = CardioRouteRecorder(store: CardioRouteStore(directory: directory.appendingPathComponent("routes")), manager: manager)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft")),
            persistence: CardioTestPersistence(), routeRecorder: recorder)
        let activity = makeActivity(outdoor: true)
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Walk", cardioBlocks: [activity])))
        let controller = CardioRecordingController(activityID: activity.id, coordinator: coordinator, recorder: recorder)
        let task = Task { await controller.startOrResume() }
        task.cancel()
        await task.value
        XCTAssertEqual(controller.activity?.timerState, .idle)
        XCTAssertNil(recorder.route)
        XCTAssertEqual(manager.permissionRequests, 0)
        XCTAssertEqual(manager.updateStarts, 0)
        XCTAssertNil(controller.errorMessage)
    }

    func testOpeningRestoredRunningRouteRequestsExpiredLocationPermissionWithoutRestartingSegment() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft"))
        let manager = TestCardioLocationManager()
        let recorder = CardioRouteRecorder(store: routeStore, manager: manager)
        var activity = makeActivity(outdoor: true)
        activity.timerState = .running
        activity.timerSegmentStartedAt = .now.addingTimeInterval(-60)
        let session = ActiveWorkoutRuntimeSession(name: "Recovered run", cardioBlocks: [activity])
        var route = CardioRoute(sessionID: session.id, activityID: activity.id)
        route.beginSegment()
        route.distanceMeters = 250
        try await routeStore.save(route, generation: routeStore.writeGeneration())
        _ = try await snapshotStore.save(ActiveWorkoutStoredSnapshot(session: session))
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: snapshotStore, persistence: CardioTestPersistence(), routeRecorder: recorder)
        await coordinator.restore()
        XCTAssertEqual(manager.permissionRequests, 0)
        XCTAssertEqual(manager.updateStarts, 0)
        let restoredRoute = try XCTUnwrap(recorder.route)
        let controller = CardioRecordingController(activityID: activity.id, coordinator: coordinator, recorder: recorder)
        await controller.prepare()
        XCTAssertEqual(manager.permissionRequests, 1)
        XCTAssertEqual(manager.updateStarts, 0)
        XCTAssertEqual(recorder.route, restoredRoute)
        XCTAssertEqual(controller.activity?.timerState, .running)

        manager.stubAuthorizationStatus = .authorizedWhenInUse
        recorder.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.updateStarts, 1)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        let authorizedState = recorder.gpsState
        await controller.prepare()
        XCTAssertEqual(manager.permissionRequests, 1)
        XCTAssertEqual(manager.updateStarts, 1)
        XCTAssertEqual(recorder.gpsState, authorizedState)
        XCTAssertEqual(recorder.route, restoredRoute)
        await controller.pause()
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        XCTAssertEqual(recorder.gpsState, .paused)
    }

    func testPreservedPausedRouteReopensAfterCloudRestoreGenerationChanges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft"))
        let recorder = CardioRouteRecorder(store: routeStore)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: snapshotStore, persistence: CardioTestPersistence(), routeRecorder: recorder)
        var activity = makeActivity(outdoor: true)
        activity.timerState = .paused
        let session = ActiveWorkoutRuntimeSession(name: "Newer walk", cardioBlocks: [activity])
        var route = CardioRoute(sessionID: session.id, activityID: activity.id)
        route.distanceMeters = 250
        try await routeStore.save(route, generation: routeStore.writeGeneration())
        coordinator.send(.start(session))
        try await recorder.prepare(sessionID: session.id, activityID: activity.id)
        // Route installation fences old writes. A retained draft must rebind its
        // paused route before resuming or recording more GPS samples.
        CardioRouteFiles(directory: directory.appendingPathComponent("routes")).advanceGeneration()
        recorder.invalidateAfterRestore()
        await coordinator.reloadRouteAfterRestore()
        XCTAssertEqual(recorder.route?.activityID, activity.id)
        XCTAssertEqual(recorder.route?.distanceMeters, 250)
        XCTAssertEqual(recorder.gpsState, .paused)
        await recorder.flush()
        let saved = try await routeStore.load(activityID: activity.id)
        XCTAssertEqual(saved?.distanceMeters, 250)
    }

    func testIndoorFinishPreservesSessionAndPresentationWhileSavingMeasuredTime() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft"))
        let recorder = CardioRouteRecorder(store: CardioRouteStore(directory: directory.appendingPathComponent("routes")))
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: CardioTestPersistence(), routeRecorder: recorder)
        var activity = makeActivity(outdoor: false)
        activity.timerState = .running
        activity.timerSegmentStartedAt = Date.now.addingTimeInterval(-60)
        let session = ActiveWorkoutRuntimeSession(name: "Morning walk", notes: "Keep my notes", cardioBlocks: [activity])
        let expandedID = UUID()
        let rest = RestTimerSnapshot(endsAt: .now.addingTimeInterval(120), exerciseName: "Bench", setLabel: nil, sourceSetID: UUID())
        coordinator.send(.start(session))
        coordinator.send(.synchronize(session: session, restTimer: rest, presentationMode: .collapsed, scrollTarget: nil, expandedExerciseIDs: [expandedID]))
        let controller = CardioRecordingController(activityID: activity.id, coordinator: coordinator, recorder: recorder)

        await controller.pause()
        XCTAssertEqual(controller.activity?.timerState, .paused)
        let pausedSeconds = try XCTUnwrap(controller.activity?.timerAccumulatedSeconds)
        XCTAssertGreaterThanOrEqual(pausedSeconds, 60)
        await controller.startOrResume()
        let finished = await controller.finish()
        XCTAssertTrue(finished)
        XCTAssertTrue(controller.canSaveWorkout)
        XCTAssertGreaterThanOrEqual(controller.activity?.actualDurationSeconds ?? 0, pausedSeconds)
        XCTAssertLessThanOrEqual(controller.activity?.actualDurationSeconds ?? 0, pausedSeconds + 5)
        XCTAssertNil(controller.activity?.actualDistanceMeters)
        XCTAssertNil(recorder.route)
        let saved = try await store.loadStoredSnapshot()
        XCTAssertEqual(saved?.session.name, "Morning walk")
        XCTAssertEqual(saved?.session.notes, "Keep my notes")
        XCTAssertEqual(coordinator.storedSnapshot?.restTimer, rest)
        XCTAssertEqual(saved?.restTimer?.sourceSetID, rest.sourceSetID)
        XCTAssertEqual(saved?.restTimer?.exerciseName, rest.exerciseName)
        XCTAssertEqual(try XCTUnwrap(saved?.restTimer?.endsAt).timeIntervalSince1970,
                       rest.endsAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(saved?.presentationMode, .collapsed)
        XCTAssertEqual(saved?.expandedExerciseIDs, [expandedID])
        XCTAssertEqual(saved?.session.cardioBlocks.first?.isCompleted, true)
    }

    func testRecoveredOutdoorRouteDistanceIsCommittedWhenPausedActivityFinishes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft"))
        var activity = makeActivity(outdoor: true)
        activity.timerState = .paused
        activity.timerAccumulatedSeconds = 600
        let session = ActiveWorkoutRuntimeSession(name: "Recovered run", cardioBlocks: [activity])
        var route = CardioRoute(sessionID: session.id, activityID: activity.id)
        route.beginSegment()
        route.distanceMeters = 1_250
        route.stop()
        let generation = await routeStore.writeGeneration()
        try await routeStore.save(route, generation: generation)
        _ = try await snapshotStore.save(ActiveWorkoutStoredSnapshot(session: session))
        let recorder = CardioRouteRecorder(store: routeStore)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: snapshotStore, persistence: CardioTestPersistence(), routeRecorder: recorder)
        await coordinator.restore()
        let controller = CardioRecordingController(activityID: activity.id, coordinator: coordinator, recorder: recorder)
        await controller.prepare()
        XCTAssertEqual(controller.route?.distanceMeters, 1_250)
        let finished = await controller.finish()
        XCTAssertTrue(finished)
        XCTAssertEqual(controller.activity?.actualDistanceMeters, 1_250)
        XCTAssertEqual(controller.activity?.actualDurationSeconds, 600)
        let saved = try await snapshotStore.loadStoredSnapshot()
        XCTAssertEqual(saved?.session.cardioBlocks.first?.actualDistanceMeters, 1_250)
        let savedRoute = try await routeStore.load(activityID: activity.id)
        XCTAssertEqual(savedRoute?.isRecording, false)
    }

    func testOtherRunningActivityPreventsRecorderTakeover() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = CardioRouteRecorder(store: CardioRouteStore(directory: directory.appendingPathComponent("routes")))
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft")), persistence: CardioTestPersistence(), routeRecorder: recorder)
        let requested = makeActivity(outdoor: true)
        var running = makeActivity(outdoor: false)
        running.timerState = .running
        running.timerSegmentStartedAt = .now
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Mixed", cardioBlocks: [running, requested])))
        let controller = CardioRecordingController(activityID: requested.id, coordinator: coordinator, recorder: recorder)
        await controller.startOrResume()
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.activity?.timerState, .idle)
        XCTAssertEqual(coordinator.storedSnapshot?.session.cardioBlocks.first(where: { $0.id == running.id })?.timerState, .running)
        XCTAssertNil(recorder.route)
    }

    func testRouteCannotBeLoadedForAnotherSession() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let route = CardioRoute(sessionID: UUID(), activityID: UUID())
        let generation = await store.writeGeneration()
        try await store.save(route, generation: generation)
        let recorder = CardioRouteRecorder(store: store)
        do {
            try await recorder.prepare(sessionID: UUID(), activityID: route.activityID)
            XCTFail("A route from another session must not be reused")
        } catch {
            XCTAssertNil(recorder.route)
        }
    }

    func testConflictFinishCommitsDistanceBeforeAnotherOutdoorRecorderTakesOver() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft"))
        let recorder = CardioRouteRecorder(store: routeStore)
        let persistence = CardioTestPersistence()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: snapshotStore, persistence: persistence, routeRecorder: recorder)
        var outdoor = makeActivity(outdoor: true)
        outdoor.timerState = .running
        outdoor.timerSegmentStartedAt = .now.addingTimeInterval(-600)
        let machine = ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout, role: .main,
            catalogExerciseUUID: "seed-bike", exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio", muscleSummarySnapshot: "", trackingProfile: .machineDistance,
            goalKind: .open, targetDurationSeconds: 0)
        let nextOutdoor = makeActivity(outdoor: true)
        var session = ActiveWorkoutRuntimeSession(name: "Mixed", cardioBlocks: [outdoor, machine, nextOutdoor])
        var route = CardioRoute(sessionID: session.id, activityID: outdoor.id)
        route.distanceMeters = 1_250
        try await routeStore.save(route, generation: routeStore.writeGeneration())
        coordinator.send(.start(session))
        try await recorder.prepare(sessionID: session.id, activityID: outdoor.id)

        let conflict = ActiveWorkoutCardioTimerConflict(runningActivityID: outdoor.id, requestedTransition: .start(activityID: machine.id))
        try ActiveWorkoutCardioConflictTransitionOrchestrator.perform(conflict: conflict) { boundary in
            switch boundary {
            case .finishCurrent(let id):
                try WorkoutCardioTimerCoordinator.finish(activityID: id, blocks: &session.cardioBlocks, at: .now)
            case .requested(let transition):
                try transition.apply(to: &session.cardioBlocks, at: .now)
            }
            let receipt = coordinator.send(.synchronize(session: session, restTimer: nil,
                presentationMode: .presented, scrollTarget: nil, expandedExerciseIDs: []))
            session = receipt.session
        }
        XCTAssertEqual(session.cardioBlocks.first?.actualDistanceMeters, 1_250)
        XCTAssertTrue(session.cardioBlocks.first?.isCompleted == true)
        XCTAssertGreaterThanOrEqual(session.cardioBlocks.first?.actualDurationSeconds ?? 0, 600)
        try await recorder.prepare(sessionID: session.id, activityID: nextOutdoor.id)
        XCTAssertEqual(recorder.route?.activityID, nextOutdoor.id)
        await coordinator.flushSnapshot()
        let saved = try await snapshotStore.loadStoredSnapshot()
        XCTAssertEqual(saved?.session.cardioBlocks.first?.actualDistanceMeters, 1_250)
        _ = try await coordinator.complete(notes: nil)
        let completed = await persistence.completedSession
        XCTAssertEqual(completed?.cardioBlocks.first?.actualDistanceMeters, 1_250)
    }

    func testCompletedRouteCanBeViewedWithoutInterruptingAnotherOutdoorActivity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let recorder = CardioRouteRecorder(store: routeStore)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft")),
            persistence: CardioTestPersistence(), routeRecorder: recorder)
        var completed = makeActivity(outdoor: true)
        completed.isCompleted = true
        completed.actualDurationSeconds = 600
        completed.actualDistanceMeters = 1_250
        var running = makeActivity(outdoor: true)
        running.timerState = .running
        running.timerSegmentStartedAt = .now
        let session = ActiveWorkoutRuntimeSession(name: "Two routes", cardioBlocks: [completed, running])
        var savedRoute = CardioRoute(sessionID: session.id, activityID: completed.id)
        savedRoute.distanceMeters = 1_250
        savedRoute.points = [.init(latitude: 59.33, longitude: 18.06, timestamp: .now, horizontalAccuracy: 5, segment: 1)]
        try await routeStore.save(savedRoute, generation: routeStore.writeGeneration())
        coordinator.send(.start(session))
        try await recorder.prepare(sessionID: session.id, activityID: running.id)
        let liveRoute = recorder.route
        let gpsState = recorder.gpsState
        let revision = coordinator.storedSnapshot?.revision

        let controller = CardioRecordingController(activityID: completed.id, coordinator: coordinator, recorder: recorder)
        await controller.prepare()
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.route, savedRoute)
        XCTAssertEqual(recorder.route, liveRoute)
        XCTAssertEqual(recorder.gpsState, gpsState)
        XCTAssertEqual(coordinator.storedSnapshot?.revision, revision)
        XCTAssertEqual(coordinator.storedSnapshot?.session.cardioBlocks.last?.timerState, .running)
    }

    func testEditingCompletedDistanceDoesNotRestoreGPSOverManualResult() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("routes"))
        let recorder = CardioRouteRecorder(store: routeStore)
        let persistence = CardioTestPersistence()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: ActiveWorkoutSnapshotStore(baseDirectory: directory.appendingPathComponent("draft")),
            persistence: persistence, routeRecorder: recorder)
        var completed = makeActivity(outdoor: true)
        completed.isCompleted = true
        completed.actualDurationSeconds = 600
        completed.actualDistanceMeters = 1_250
        var session = ActiveWorkoutRuntimeSession(name: "Edited result", cardioBlocks: [completed])
        var route = CardioRoute(sessionID: session.id, activityID: completed.id)
        route.distanceMeters = 1_250
        try await routeStore.save(route, generation: routeStore.writeGeneration())
        try await recorder.prepare(sessionID: session.id, activityID: completed.id)
        for distance in [nil, 900] as [Double?] {
            session.cardioBlocks[0].actualDistanceMeters = 1_250
            coordinator.send(.start(session))
            session.cardioBlocks[0].actualDistanceMeters = distance
            let receipt = coordinator.send(.synchronize(session: session, restTimer: nil,
                presentationMode: .presented, scrollTarget: nil, expandedExerciseIDs: []))
            XCTAssertEqual(receipt.session.cardioBlocks[0].actualDistanceMeters, distance)
            _ = try await coordinator.complete(notes: nil)
            let saved = await persistence.completedSession
            XCTAssertEqual(saved?.cardioBlocks[0].actualDistanceMeters, distance)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CardioControllerTests-\(UUID())")
    }

    private func makeActivity(outdoor: Bool) -> ActiveWorkoutRuntimeCardioBlock {
        ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout, role: .main,
            catalogExerciseUUID: outdoor ? "seed-outdoor-run" : "seed-treadmill-walk",
            exerciseNameSnapshot: outdoor ? "Outdoor Run" : "Treadmill Walk",
            categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            trackingProfile: outdoor ? .walkRun : .treadmill,
            goalKind: .open, targetDurationSeconds: 0, preferredDistanceUnit: .kilometers)
    }
}

final class CardioSessionStarterTests: XCTestCase {
    func testQuickStartUsesOpenGoalPreferredUnitsAndExplicitOutdoorIdentity() throws {
        for choice in CardioActivityQuickChoice.all where [.walkRun, .treadmill].contains(choice.trackingProfile) {
            let empty = ActiveWorkoutRuntimeSession(name: "Empty Workout")
            let session = CardioSessionStarter.configuredSession(from: empty, selection: choice.selection, distanceUnit: .miles)
            let activity = try XCTUnwrap(session.cardioBlocks.first)
            XCTAssertEqual(session.id, empty.id)
            XCTAssertEqual(session.name, choice.displayName)
            XCTAssertTrue(session.exercises.isEmpty)
            XCTAssertEqual(activity.goalKind, .open)
            XCTAssertEqual(activity.targetDurationSeconds, 0)
            XCTAssertNil(activity.targetDistanceMeters)
            XCTAssertEqual(activity.preferredDistanceUnit, .miles)
            XCTAssertTrue(CardioRecordingPolicy.usesSessionScreen(activity))
            XCTAssertEqual(CardioRecordingPolicy.recordsGPS(activity), choice.remoteUUID.hasPrefix("seed-outdoor-"))
        }
    }

    func testGenericCustomWalkDoesNotRequestLocationBasedOnItsName() {
        let activity = ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout,
            catalogExerciseUUID: "custom-outdoor-name", exerciseNameSnapshot: "Outdoor Walk",
            categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            trackingProfile: .walkRun, goalKind: .open, targetDurationSeconds: 0)
        XCTAssertTrue(CardioRecordingPolicy.usesSessionScreen(activity))
        XCTAssertFalse(CardioRecordingPolicy.recordsGPS(activity))
    }
}

private final class TestCardioLocationManager: CLLocationManager {
    private weak var stubDelegate: (any CLLocationManagerDelegate)?
    var stubAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var permissionRequests = 0
    var updateStarts = 0
    override var delegate: (any CLLocationManagerDelegate)? {
        get { stubDelegate }
        set { stubDelegate = newValue }
    }
    override var authorizationStatus: CLAuthorizationStatus { stubAuthorizationStatus }
    override var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
    override func requestWhenInUseAuthorization() { permissionRequests += 1 }
    override func startUpdatingLocation() { updateStarts += 1 }
    override func stopUpdatingLocation() { }
}

private actor CardioTestPersistence: ActiveWorkoutPersistence {
    private(set) var completedSession: ActiveWorkoutRuntimeSession?
    func isCompleted(sessionID: UUID) async throws -> Bool { false }
    func complete(session: ActiveWorkoutRuntimeSession, notes: String?) async throws -> WorkoutCompletionCommitResult {
        completedSession = session
        return .init(sessionID: session.id, disposition: .inserted)
    }
}
