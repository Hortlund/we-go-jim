import XCTest
@testable import WGJ

final class ActiveWorkoutSnapshotRevisionTests: XCTestCase {
    func testDiscardRemovesDraftWhenDeletionMarkerIsUnavailable() async throws {
        let directory = try makeTemporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let snapshot = makeStoredSnapshot(revision: 1, name: "Canceled workout")
        _ = try await store.save(snapshot)
        // A directory at the marker path prevents reading or atomically replacing it.
        let marker = directory.appendingPathComponent("active-workout-deleted-sessions.json", isDirectory: true)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)

        try await store.discardSession(snapshot)

        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let restored = try await reopened.loadStoredSnapshot()
        XCTAssertNil(restored)
    }

    func testDiscardRemovesCorruptDraftSoReplacementCanSave() async throws {
        let directory = try makeTemporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let file = directory.appendingPathComponent("active-workout-snapshot.json")
        try Data("Truncated draft".utf8).write(to: file)

        try await store.discardSession(makeStoredSnapshot(revision: 1, name: "Canceled workout"))

        let replacement = makeStoredSnapshot(revision: 2, name: "New workout")
        let saved = try await store.save(replacement)
        XCTAssertEqual(saved, .written)
    }

    func testDiscardedRoutesRetryAfterRelaunchAndPreserveReplacement() async throws {
        let directory = try makeTemporaryDirectory()
        let routesDirectory = directory.appendingPathComponent("Routes", isDirectory: true)
        let routeStore = CardioRouteStore(directory: routesDirectory)
        let snapshotStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        var discarded = makeStoredSnapshot(revision: 1, name: "Canceled walk")
        _ = try await snapshotStore.save(discarded)

        let activity = makeOutdoorWalk()
        discarded.session.cardioBlocks.append(activity)
        let discardedRoute = makeRecordedRoute(sessionID: discarded.session.id, activityID: activity.id)
        let replacement = ActiveWorkoutStoredSnapshot(revision: 2, session: ActiveWorkoutRuntimeSession(name: "New workout"))
        let retainedRoute = makeRecordedRoute(sessionID: replacement.session.id, activityID: UUID())
        let generation = await routeStore.writeGeneration()
        try await routeStore.save(discardedRoute, generation: generation)
        try await routeStore.save(retainedRoute, generation: generation)

        try await snapshotStore.discardSession(discarded)
        _ = try await snapshotStore.save(replacement)
        // A damaged file still needs removal by the activity ID saved in the cleanup record.
        let damagedFile = routesDirectory.appendingPathComponent("\(activity.id.uuidString).json")
        try Data("Truncated route".utf8).write(to: damagedFile)

        let firstLaunch = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        await firstLaunch.retryDiscardedRouteCleanups { _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: damagedFile.path))

        let secondLaunch = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let reopenedRoutes = CardioRouteStore(directory: routesDirectory)
        await secondLaunch.retryDiscardedRouteCleanups { sessionID, activityIDs in
            XCTAssertEqual(sessionID, discardedRoute.sessionID)
            XCTAssertEqual(activityIDs, [activity.id])
            try await reopenedRoutes.delete(sessionID: sessionID, activityIDs: activityIDs)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: damagedFile.path))
        let savedRoute = try await reopenedRoutes.load(activityID: retainedRoute.activityID)
        let savedDraft = try await secondLaunch.loadStoredSnapshot()
        XCTAssertEqual(savedRoute, retainedRoute)
        XCTAssertEqual(savedDraft?.session.id, replacement.session.id)

        await secondLaunch.retryDiscardedRouteCleanups { _, _ in XCTFail("Completed cleanup must be retired") }
    }

    func testFailedDiscardMovePreservesActiveDraftAndRoute() async throws {
        let directory = try makeTemporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        var snapshot = makeStoredSnapshot(revision: 1, name: "Keep walking")
        let activity = makeOutdoorWalk()
        snapshot.session.cardioBlocks.append(activity)
        _ = try await store.save(snapshot)
        let routeStore = CardioRouteStore(directory: directory.appendingPathComponent("Routes"))
        let route = makeRecordedRoute(sessionID: snapshot.session.id, activityID: activity.id)
        let generation = await routeStore.writeGeneration()
        try await routeStore.save(route, generation: generation)

        let blockedDestination = directory.appendingPathComponent("discarded-workout-\(snapshot.session.id.uuidString).json")
        try FileManager.default.createDirectory(at: blockedDestination, withIntermediateDirectories: false)
        do {
            try await store.discardSession(snapshot)
            XCTFail("Expected the draft move to fail")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileWriteFileExists)
        }

        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        await reopened.retryDiscardedRouteCleanups { _, _ in XCTFail("A failed discard must not delete a route") }
        let retained = try await reopened.loadStoredSnapshot()
        XCTAssertEqual(retained?.session.id, snapshot.session.id)
        XCTAssertEqual(retained?.session.cardioBlocks.map(\.id), [activity.id])
        let retainedRoute = try await routeStore.load(activityID: activity.id)
        XCTAssertEqual(retainedRoute, route)
    }

    func testDiscardWithoutSavedDraftRecordsKnownRouteForRelaunch() async throws {
        let directory = try makeTemporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        var snapshot = makeStoredSnapshot(revision: 1, name: "Unsaved walk")
        let activity = makeOutdoorWalk()
        snapshot.session.cardioBlocks.append(activity)
        try await store.discardSession(snapshot)

        let expectedSessionID = snapshot.session.id
        let deleted = expectation(description: "Recovered the route cleanup record")
        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        await reopened.retryDiscardedRouteCleanups { sessionID, activityIDs in
            XCTAssertEqual(sessionID, expectedSessionID)
            XCTAssertEqual(activityIDs, [activity.id])
            deleted.fulfill()
        }
        await fulfillment(of: [deleted], timeout: 2)
    }

    func testIndependentDropsetsSurviveColdSnapshotLoadAndStageDeletion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exercise = ActiveWorkoutRuntimeExercise(catalogExerciseUUID: "bench", exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", setDrafts: [
                WorkoutSessionSetDraft(isCompleted: true, dropStages: [
                    WorkoutSessionDropStageDraft(targetReps: 8, targetWeight: 40, actualReps: 7, actualWeight: 37.5, isCompleted: true),
                    WorkoutSessionDropStageDraft(targetReps: 6, targetWeight: 25, targetLoadUnit: .lb, actualLoadUnit: .lb),
                ]),
                WorkoutSessionSetDraft(dropStages: [
                    WorkoutSessionDropStageDraft(targetReps: 5, targetLoadUnit: .bodyweight, actualLoadUnit: .bodyweight),
                ]),
            ])
        var snapshot = ActiveWorkoutStoredSnapshot(revision: 1,
            session: ActiveWorkoutRuntimeSession(name: "Dropsets", exercises: [exercise]))
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        _ = try await store.save(snapshot)
        let coldStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let restored = try await coldStore.loadStoredSnapshot()
        XCTAssertEqual(restored?.session.exercises.first?.setDrafts, exercise.setDrafts)

        snapshot.revision += 1
        snapshot.session.exercises[0].setDrafts[0].dropStages.removeFirst()
        _ = try await coldStore.save(snapshot)
        let reopenedStore = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let afterDeletion = try await reopenedStore.loadStoredSnapshot()
        XCTAssertEqual(afterDeletion?.session.exercises.first?.setDrafts, snapshot.session.exercises[0].setDrafts)
        XCTAssertEqual(afterDeletion?.session.exercises.first?.setDrafts[1].dropStages, exercise.setDrafts[1].dropStages)
    }

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

    private func makeOutdoorWalk() -> ActiveWorkoutRuntimeCardioBlock {
        ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout, role: .main, catalogExerciseUUID: "seed-outdoor-walk",
            exerciseNameSnapshot: "Outdoor Walk", categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            targetDurationSeconds: 0)
    }

    private func makeRecordedRoute(sessionID: UUID, activityID: UUID) -> CardioRoute {
        var route = CardioRoute(sessionID: sessionID, activityID: activityID)
        route.points = [CardioRoutePoint(latitude: 59.33, longitude: 18.07,
                                       timestamp: Date(timeIntervalSinceReferenceDate: 100), horizontalAccuracy: 8, segment: 0)]
        return route
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
