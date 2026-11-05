import XCTest
@testable import WGJ

@MainActor
final class ActiveWorkoutCoordinatorTests: XCTestCase {
    func testUnsavedStrengthWorkoutCanBeDiscardedWithUnwritableStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence(),
                                                   routeRecorder: nil)
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Empty Workout"), isNew: true))
        await coordinator.flushSnapshot()
        XCTAssertNotNil(coordinator.persistenceWarning)

        try await coordinator.discard()

        XCTAssertNil(coordinator.storedSnapshot)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testRemovedOutdoorActivityStillQueuesCleanupForAnUnsavedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let cleanupAttempted = expectation(description: "Route cleanup was attempted")
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store, persistence: StubActiveWorkoutPersistence(), routeRecorder: nil,
            deleteDiscardedRoutes: { _, _ in
                cleanupAttempted.fulfill()
                throw CocoaError(.fileWriteNoPermission)
            }
        )
        var session = ActiveWorkoutRuntimeSession(name: "Workout")
        coordinator.send(.start(session, isNew: true), persist: false)

        session.cardioBlocks = [ActiveWorkoutRuntimeCardioBlock(
            phase: .postWorkout, role: .main, catalogExerciseUUID: "seed-outdoor-walk",
            exerciseNameSnapshot: "Outdoor Walk", categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            targetDurationSeconds: 0
        )]
        coordinator.send(.synchronize(session: session, restTimer: nil, presentationMode: .presented,
                                      scrollTarget: nil, expandedExerciseIDs: []), persist: false)
        session.cardioBlocks = []
        coordinator.send(.synchronize(session: session, restTimer: nil, presentationMode: .presented,
                                      scrollTarget: nil, expandedExerciseIDs: []), persist: false)
        try await coordinator.discard()
        await fulfillment(of: [cleanupAttempted], timeout: 2)

        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let recovered = expectation(description: "Retained cleanup for the removed activity")
        let sessionID = session.id
        await reopened.retryDiscardedRouteCleanups { id, _ in
            XCTAssertEqual(id, sessionID)
            recovered.fulfill()
        }
        await fulfillment(of: [recovered], timeout: 2)
    }

    func testDiscardPreservesReplacementWithoutCreatingDeletionHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence(),
                                                   routeRecorder: nil)
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Canceled workout")))
        let canceled = try XCTUnwrap(coordinator.storedSnapshot)
        await coordinator.flushSnapshot()

        // The next workout may already be on disk by the time cleanup reaches it.
        let replacement = ActiveWorkoutStoredSnapshot(revision: canceled.revision + 1,
                                                       session: ActiveWorkoutRuntimeSession(name: "New workout"))
        let saved = try await store.save(replacement)
        XCTAssertEqual(saved, .written)
        try await coordinator.discard()

        let reopened = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let retained = try await reopened.loadStoredSnapshot()
        XCTAssertEqual(retained?.session.id, replacement.session.id)
        XCTAssertNil(coordinator.storedSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(
            "active-workout-deleted-sessions.json"
        ).path))
    }

    func testDiscardCancelsAnInFlightFlush() async throws {
        let writeStarted = expectation(description: "The flush reached snapshot storage")
        let store = RecordingActiveWorkoutSnapshotStore(writeDelayNanoseconds: 5_000_000_000, onSaveStart: {
            writeStarted.fulfill()
        })
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence(),
                                                   routeRecorder: nil)
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Canceled workout")), persist: false)
        let flush = Task { await coordinator.flushSnapshot() }
        await fulfillment(of: [writeStarted], timeout: 3)

        try await coordinator.discard()
        await flush.value

        let saved = await store.lastSnapshot()
        XCTAssertNil(saved)
        XCTAssertNil(coordinator.storedSnapshot)
    }

    func testDiscardReturnsWhileRouteCleanupIsStillRunning() async throws {
        let cleanupStarted = expectation(description: "Route cleanup started")
        let discardReturned = expectation(description: "Draft removal returned")
        let cleanupFinished = expectation(description: "Route cleanup finished")
        let (cleanupGate, releaseCleanup) = AsyncStream<Void>.makeStream()
        defer { releaseCleanup.finish() }
        let activity = ActiveWorkoutRuntimeCardioBlock(
            phase: .postWorkout, role: .main, catalogExerciseUUID: "seed-outdoor-walk",
            exerciseNameSnapshot: "Outdoor Walk", categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            targetDurationSeconds: 0
        )
        let session = ActiveWorkoutRuntimeSession(name: "Canceled workout", cardioBlocks: [activity])
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store, persistence: StubActiveWorkoutPersistence(), routeRecorder: nil,
            deleteDiscardedRoutes: { sessionID, activityIDs in
                XCTAssertEqual(sessionID, session.id)
                XCTAssertEqual(activityIDs, [activity.id])
                cleanupStarted.fulfill()
                for await _ in cleanupGate { }
                cleanupFinished.fulfill()
            }
        )
        coordinator.send(.start(session))
        await coordinator.flushSnapshot()

        let discard = Task {
            try await coordinator.discard()
            discardReturned.fulfill()
        }
        await fulfillment(of: [discardReturned, cleanupStarted], timeout: 3)
        XCTAssertNil(coordinator.storedSnapshot)
        let removed = await store.lastSnapshot()
        XCTAssertNil(removed)

        let replacement = ActiveWorkoutRuntimeSession(name: "New workout")
        coordinator.send(.start(replacement))
        await coordinator.flushSnapshot()
        let saved = await store.lastSnapshot()
        XCTAssertEqual(saved?.session.id, replacement.id)

        releaseCleanup.finish()
        try await discard.value
        await fulfillment(of: [cleanupFinished], timeout: 3)
    }

    func testFailedDiscardKeepsTheWorkoutAvailableForRetry() async throws {
        let store = RecordingActiveWorkoutSnapshotStore(discardFailuresRemaining: 1)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence(),
                                                   routeRecorder: nil)
        let session = ActiveWorkoutRuntimeSession(name: "Canceled workout")
        coordinator.send(.start(session))
        await coordinator.flushSnapshot()

        do {
            try await coordinator.discard()
            XCTFail("Expected the snapshot removal failure")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileWriteNoPermission)
        }
        XCTAssertEqual(coordinator.storedSnapshot?.session.id, session.id)

        try await coordinator.discard()
        let saved = await store.lastSnapshot()
        XCTAssertNil(saved)
        XCTAssertNil(coordinator.storedSnapshot)
    }

    func testNewWorkoutCanSaveWhileAnOlderDraftIsStillOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let older = ActiveWorkoutStoredSnapshot(revision: 20, session: ActiveWorkoutRuntimeSession(name: "Old workout"))
        _ = try await store.save(older)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence(),
                                                   routeRecorder: nil)
        await coordinator.restore()
        coordinator.clearInMemory()
        let replacement = ActiveWorkoutRuntimeSession(name: "New workout")
        coordinator.send(.start(replacement))
        await coordinator.flushSnapshot()

        let saved = try await store.loadStoredSnapshot()
        XCTAssertEqual(saved?.session.id, replacement.id)
        XCTAssertGreaterThan(saved?.revision ?? 0, older.revision)
    }

    func testRestoreKeepsNewerWorkoutPresentationTimerAndPendingEdits() async throws {
        for startsNewWorkout in [false, true] {
            let cutoff = Date.now
            let oldDate = cutoff.addingTimeInterval(-10)
            let original = ActiveWorkoutRuntimeSession(name: "Original", updatedAt: oldDate)
            let store = RecordingActiveWorkoutSnapshotStore(
                initialSnapshot: ActiveWorkoutStoredSnapshot(session: original, mutationDate: oldDate)
            )
            let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
            await coordinator.restore()
            if startsNewWorkout {
                coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "New workout")))
            } else {
                coordinator.send(.updateMetadata(name: "Edited workout", notes: "Keep these edits"))
            }
            let session = try XCTUnwrap(coordinator.storedSnapshot?.session)
            let presentation = ActiveWorkoutPresentationState()
            presentation.present(sessionID: session.id)
            presentation.collapseActiveWorkout()
            let timer = RestTimerState()
            let endsAt = Date.now.addingTimeInterval(120)
            timer.restTimerEndsAt = endsAt
            timer.restTimerExerciseName = "Pull-up"
            let sourceSetID = UUID()
            timer.restTimerSourceSetID = sourceSetID

            presentation.reconcileAfterRestore(savedBefore: cutoff, coordinator: coordinator, restTimerState: timer)
            await coordinator.flushSnapshot()

            XCTAssertEqual(presentation.activeSessionID, session.id)
            XCTAssertTrue(presentation.isActiveWorkoutStripCollapsed)
            XCTAssertEqual(timer.restTimerEndsAt, endsAt)
            XCTAssertEqual(timer.restTimerSourceSetID, sourceSetID)
            XCTAssertEqual(coordinator.storedSnapshot?.session, session)
            let persisted = await store.lastSnapshot()
            XCTAssertEqual(persisted?.session, session)
        }
    }

    func testRestoreClearsOlderWorkoutPresentationAndTimerTogether() {
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: RecordingActiveWorkoutSnapshotStore(), persistence: StubActiveWorkoutPersistence()
        )
        let session = ActiveWorkoutRuntimeSession(name: "Before restore")
        coordinator.send(.start(session), persist: false)
        let presentation = ActiveWorkoutPresentationState()
        presentation.present(sessionID: session.id)
        let timer = RestTimerState()
        timer.restTimerEndsAt = Date.now.addingTimeInterval(120)
        timer.restTimerExerciseName = "Pull-up"

        presentation.reconcileAfterRestore(savedBefore: .now, coordinator: coordinator, restTimerState: timer)

        XCTAssertNil(coordinator.storedSnapshot)
        XCTAssertNil(presentation.activeSessionID)
        XCTAssertFalse(presentation.isActiveWorkoutPresented)
        XCTAssertFalse(presentation.isActiveWorkoutStripCollapsed)
        XCTAssertNil(timer.restTimerEndsAt)
        XCTAssertNil(timer.restTimerExerciseName)
    }

    func testRestoreResetUsesPersistedMutationTimeAfterCoordinatorRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let first = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        first.send(.start(ActiveWorkoutRuntimeSession(name: "Keep", updatedAt: .distantPast)))
        let cutoff = Date.now
        first.send(.updateScrollOffsetY(100), persist: false)
        await first.flushSnapshot()
        let second = ActiveWorkoutCoordinator(snapshotStore: ActiveWorkoutSnapshotStore(baseDirectory: directory),
            persistence: StubActiveWorkoutPersistence())
        await second.restore()
        XCTAssertNotNil(second.storedSnapshot)
        XCTAssertFalse(second.clearInMemory(savedBefore: cutoff))
        XCTAssertEqual(second.storedSnapshot?.scrollOffsetY, 100)
        XCTAssertTrue(second.clearInMemory(savedBefore: .distantFuture))
    }

    func testRestoreResetPreservesNewerWorkoutEditsAndPendingSave() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Old")))
        let cutoff = Date.now
        coordinator.send(.updateMetadata(name: "Newer edit", notes: "Keep me"))
        XCTAssertFalse(coordinator.clearInMemory(savedBefore: cutoff))
        await coordinator.flushSnapshot()
        let saved = await store.lastSnapshot()
        XCTAssertEqual(saved?.session.name, "Newer edit")
        XCTAssertEqual(coordinator.storedSnapshot?.session.notes, "Keep me")
        XCTAssertTrue(coordinator.clearInMemory(savedBefore: .distantFuture))
        XCTAssertNil(coordinator.storedSnapshot)
    }

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
            coordinator.send(.updateScrollOffsetY(428.5)).revision,
            5
        )
        XCTAssertEqual(
            coordinator.send(.appendExercise(makeExercise(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                name: "Row",
                sortOrder: 99
            ))).revision,
            6
        )

        await coordinator.flushSnapshot()

        let recordedSnapshot = await store.lastSnapshot()
        let persisted = try XCTUnwrap(recordedSnapshot)
        XCTAssertEqual(persisted.revision, 6)
        XCTAssertEqual(persisted.session.name, "Push Updated")
        XCTAssertEqual(persisted.session.notes, "Strong")
        XCTAssertEqual(persisted.session.exercises.count, 2)
        XCTAssertEqual(persisted.session.exercises.map(\.sortOrder), [0, 1])
        XCTAssertEqual(persisted.session.exercises.first?.setDrafts, drafts)
        XCTAssertEqual(persisted.presentationMode, .collapsed)
        XCTAssertEqual(persisted.scrollTarget, .exercise(exerciseID))
        XCTAssertEqual(persisted.scrollOffsetY, 428.5)
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

    func testPreviousPerformanceCachePersistsAndInvalidatesWithExerciseIdentity() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: StubActiveWorkoutPersistence()
        )
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let session = ActiveWorkoutRuntimeSession(
            name: "Push",
            exercises: [makeExercise(id: exerciseID, name: "Bench", sortOrder: 0)]
        )
        let previousSet = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        _ = coordinator.send(.start(session))
        _ = coordinator.send(.cachePreviousPerformance([exerciseID: [0: previousSet]]))
        XCTAssertEqual(
            coordinator.storedSnapshot?.previousSetSnapshotsByExerciseID[exerciseID]?[0],
            previousSet
        )

        _ = coordinator.send(.replaceExercise(
            exerciseID: exerciseID,
            replacement: makeExercise(id: exerciseID, name: "Row", sortOrder: 0)
        ))

        XCTAssertNil(coordinator.storedSnapshot?.previousSetSnapshotsByExerciseID[exerciseID])
    }

    func testSynchronizeInvalidatesPreviousPerformanceOnlyWhenExerciseIdentityChanges() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: store,
            persistence: StubActiveWorkoutPersistence()
        )
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let session = ActiveWorkoutRuntimeSession(
            name: "Push",
            exercises: [makeExercise(id: exerciseID, name: "Bench", sortOrder: 0)]
        )
        let previousSet = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)

        _ = coordinator.send(.start(session))
        _ = coordinator.send(.cachePreviousPerformance([exerciseID: [0: previousSet]]))
        _ = coordinator.send(.synchronize(
            session: session,
            restTimer: nil,
            presentationMode: .presented,
            scrollTarget: nil,
            expandedExerciseIDs: [exerciseID]
        ))
        XCTAssertEqual(
            coordinator.storedSnapshot?.previousSetSnapshotsByExerciseID[exerciseID]?[0],
            previousSet
        )

        let replacementSession = ActiveWorkoutRuntimeSession(
            id: session.id,
            name: session.name,
            exercises: [makeExercise(id: exerciseID, name: "Row", sortOrder: 0)]
        )
        _ = coordinator.send(.synchronize(
            session: replacementSession,
            restTimer: nil,
            presentationMode: .presented,
            scrollTarget: nil,
            expandedExerciseIDs: [exerciseID]
        ))

        XCTAssertNil(coordinator.storedSnapshot?.previousSetSnapshotsByExerciseID[exerciseID])
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

    func testFailedCompletionAllowsHydrationRecoveryAndSuccessfulRetry() async throws {
        let session = ActiveWorkoutRuntimeSession(name: "Push")
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: RecordingActiveWorkoutSnapshotStore(),
            persistence: StubActiveWorkoutPersistence(completionFailuresRemaining: 1)
        )
        coordinator.send(.start(session))

        do {
            _ = try await coordinator.complete(notes: "Done")
            XCTFail("Expected the first completion write to fail")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteUnknown.rawValue)
        }

        func canResumeHydration() -> Bool {
            ActiveWorkoutLifecycleWorkPolicy.canMutateActiveSession(
                sessionID: session.id,
                coordinatorSessionID: coordinator.storedSnapshot?.session.id,
                isEndingSession: false,
                completedSessionID: nil
            )
        }
        XCTAssertEqual(coordinator.storedSnapshot?.session, session)
        XCTAssertTrue(canResumeHydration())
        _ = try await coordinator.complete(notes: "Done")
        XCTAssertFalse(canResumeHydration(), "Successful completion must still block late hydration")
    }

    func testUnchangedCommandsKeepRevisionAndSkipDiskWrites() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        let exercise = makeExercise(id: UUID(), name: "Bench", sortOrder: 0)
        let session = ActiveWorkoutRuntimeSession(name: "Push", exercises: [exercise])
        coordinator.send(.start(session))
        coordinator.send(.updatePresentation(mode: .presented, scrollTarget: nil, expandedExerciseIDs: []))
        await coordinator.flushSnapshot()
        let before = try XCTUnwrap(coordinator.storedSnapshot)
        let writesBefore = await store.writeAttempts()
        coordinator.send(.updateMetadata(name: session.name, notes: session.notes))
        coordinator.send(.setExerciseDrafts(exerciseID: exercise.id, drafts: exercise.setDrafts))
        coordinator.send(.setExerciseNotes(exerciseID: exercise.id, notes: exercise.notes))
        coordinator.send(.moveExercise(exerciseID: exercise.id, destinationIndex: 0))
        coordinator.send(.updateRestTimer(nil))
        coordinator.send(.synchronize(session: before.session, restTimer: nil,
            presentationMode: .presented, scrollTarget: nil, expandedExerciseIDs: []))
        await coordinator.flushSnapshot()
        XCTAssertEqual(coordinator.storedSnapshot, before)
        let writesAfter = await store.writeAttempts()
        XCTAssertEqual(writesAfter, writesBefore)
    }

    func testUnchangedCommandRetriesFailedSaveWithoutInventingRevision() async throws {
        let store = RecordingActiveWorkoutSnapshotStore(failuresRemaining: 1)
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Push")), persist: false)
        await coordinator.flushSnapshot()
        XCTAssertNotNil(coordinator.persistenceWarning)
        let revision = coordinator.storedSnapshot?.revision
        coordinator.send(.updateRestTimer(nil))
        await coordinator.flushSnapshot()
        XCTAssertNil(coordinator.persistenceWarning)
        let persisted = await store.lastSnapshot()
        XCTAssertEqual(persisted?.revision, revision)
        let attempts = await store.writeAttempts()
        XCTAssertEqual(attempts, 2)
    }

    func testUnchangedPersistingCommandFlushesPreviouslyStagedState() async throws {
        let store = RecordingActiveWorkoutSnapshotStore()
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Push")))
        await coordinator.flushSnapshot()
        let staged = coordinator.send(.updateScrollOffsetY(300), persist: false)
        coordinator.send(.updateScrollOffsetY(300))
        await coordinator.flushSnapshot()
        let persisted = await store.lastSnapshot()
        XCTAssertEqual(persisted?.revision, staged.revision)
        XCTAssertEqual(persisted?.scrollOffsetY, 300)
    }

    func testUnchangedPersistingCommandReplacesOlderQueuedSaveWithoutFlush() async throws {
        let saved = expectation(description: "Staged revision saved without an explicit flush")
        let store = RecordingActiveWorkoutSnapshotStore(onSave: { snapshot in
            if snapshot.scrollOffsetY == 300 { saved.fulfill() }
        })
        let coordinator = ActiveWorkoutCoordinator(snapshotStore: store, persistence: StubActiveWorkoutPersistence())
        coordinator.send(.start(ActiveWorkoutRuntimeSession(name: "Push")))
        // Stay on the main actor: the initial save is queued but has not run yet.
        let staged = coordinator.send(.updateScrollOffsetY(300), persist: false)
        coordinator.send(.updateScrollOffsetY(300))
        await fulfillment(of: [saved], timeout: 3)
        let persisted = await store.lastSnapshot()
        XCTAssertEqual(persisted?.revision, staged.revision)
        XCTAssertEqual(persisted?.scrollOffsetY, 300)
        XCTAssertEqual(coordinator.storedSnapshot?.revision, staged.revision)
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
    private var attempts = 0
    private var failuresRemaining: Int
    private var discardFailuresRemaining: Int
    private var maxActiveWrites = 0
    private let writeDelayNanoseconds: UInt64
    private let onSaveStart: @Sendable () -> Void
    private let onSave: @Sendable (ActiveWorkoutStoredSnapshot) -> Void

    init(
        initialSnapshot: ActiveWorkoutStoredSnapshot? = nil,
        writeDelayNanoseconds: UInt64 = 0,
        failuresRemaining: Int = 0,
        discardFailuresRemaining: Int = 0,
        onSaveStart: @escaping @Sendable () -> Void = {},
        onSave: @escaping @Sendable (ActiveWorkoutStoredSnapshot) -> Void = { _ in }
    ) {
        self.failuresRemaining = failuresRemaining
        self.discardFailuresRemaining = discardFailuresRemaining
        self.onSaveStart = onSaveStart
        self.onSave = onSave
        if let initialSnapshot {
            snapshots = [initialSnapshot]
        }
        self.writeDelayNanoseconds = writeDelayNanoseconds
    }

    func loadStoredSnapshot() async throws -> ActiveWorkoutStoredSnapshot? {
        snapshots.last
    }

    func save(_ snapshot: ActiveWorkoutStoredSnapshot) async throws -> ActiveWorkoutSnapshotWriteResult {
        attempts += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        activeWrites += 1
        maxActiveWrites = max(maxActiveWrites, activeWrites)
        defer { activeWrites -= 1 }
        onSaveStart()
        if writeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: writeDelayNanoseconds)
        }
        if snapshots.last == snapshot {
            return .unchanged
        }
        snapshots.append(snapshot)
        onSave(snapshot)
        return .written
    }

    func delete() async throws {
        snapshots.removeAll()
    }

    func discardSession(_ snapshot: ActiveWorkoutStoredSnapshot, mayHaveRouteFiles: Bool) throws {
        if discardFailuresRemaining > 0 {
            discardFailuresRemaining -= 1
            throw CocoaError(.fileWriteNoPermission)
        }
        snapshots.removeAll { $0.session.id == snapshot.session.id }
    }

    func cleanUpDiscardedRoutes(sessionID: UUID, activityIDs: Set<UUID>, using deleteRoutes: DiscardedRouteDeletion) async throws {
        try await deleteRoutes(sessionID, activityIDs)
    }

    func lastSnapshot() -> ActiveWorkoutStoredSnapshot? {
        snapshots.last
    }

    func writeAttempts() -> Int { attempts }

    func maximumConcurrentWrites() -> Int {
        maxActiveWrites
    }
}

private actor StubActiveWorkoutPersistence: ActiveWorkoutPersistence {
    private let completedSessionIDs: Set<UUID>
    private let completionDelayNanoseconds: UInt64
    private var completionFailuresRemaining: Int
    private var completionCalls = 0

    init(
        completedSessionIDs: Set<UUID> = [],
        completionDelayNanoseconds: UInt64 = 0,
        completionFailuresRemaining: Int = 0
    ) {
        self.completedSessionIDs = completedSessionIDs
        self.completionDelayNanoseconds = completionDelayNanoseconds
        self.completionFailuresRemaining = completionFailuresRemaining
    }

    func isCompleted(sessionID: UUID) async throws -> Bool {
        completedSessionIDs.contains(sessionID)
    }

    func complete(
        session: ActiveWorkoutRuntimeSession,
        notes: String?
    ) async throws -> WorkoutCompletionCommitResult {
        completionCalls += 1
        if completionFailuresRemaining > 0 {
            completionFailuresRemaining -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        if completionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: completionDelayNanoseconds)
        }
        return WorkoutCompletionCommitResult(sessionID: session.id, disposition: .inserted)
    }

    func completionCallCount() -> Int {
        completionCalls
    }
}
