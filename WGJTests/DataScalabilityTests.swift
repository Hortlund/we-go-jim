import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class DataScalabilityTests: XCTestCase {
    func testMainThreadSaveReturnsPromptlyWhileRestoreOwnsBarrier() async throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Pending edit"))
        let ready = expectation(description: "Restore reached exclusive section")
        let release = DispatchSemaphore(value: 0)
        let restore = Task.detached {
            let transaction = UserDataCloudRestoreTransaction(container: container, dependencies: .init(checkpoint: {
                if $0 == .afterValidation {
                    ready.fulfill()
                    _ = release.wait(timeout: .now() + 5)
                }
            }))
            try transaction.commit(replacingLocalData: false, mergeDatabaseGraph: { _ in }, relinkRelationships: { _ in })
        }
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(Thread.isMainThread)
        let start = ContinuousClock.now
        XCTAssertThrowsError(try context.saveWithRecoveryProtection()) {
            XCTAssertTrue($0 is LocalStoreWriteBarrier.RestoreInProgress)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<UserProfile>()), 0)
        release.signal()
        try await restore.value
        try context.saveWithRecoveryProtection()
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Pending edit")
    }

    func testLocalStoreResetDiscardsPendingRecoveryAndBackupLineage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("UserData.store")
        try autoreleasepool {
            let container = try diskContainer(url: url)
            let context = ModelContext(container)
            context.insert(UserProfile(displayName: "Must stay deleted"))
            try context.saveWithRecoveryProtection()
            try BackupLocalJournal.save(.init(account: "old-account", generation: UUID().uuidString), for: container)
            try BackupLocalJournal.markPending(for: container)
            _ = try PersistentRestoreRecovery.prepare(container: container)
        }
        let unrelated = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        AppStoreLayout.requestPersistentStoreResetOnNextLaunch(defaults: defaults)
        try AppStoreLayout.performPendingPersistentStoreReset(defaults: defaults) {
            try AppStoreLayout.clearPersistentStoreFiles(in: [root])
        }
        let config = ModelConfiguration(schema: AppSchema.makeFull(), url: url, cloudKitDatabase: .none)
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: [config])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["keep.txt"])
        let reopened = try diskContainer(url: url)
        XCTAssertEqual(try ModelContext(reopened).fetchCount(FetchDescriptor<UserProfile>()), 0)
        XCTAssertNil(try BackupLocalJournal.state(for: reopened).generation)
        XCTAssertNil(try BackupLocalJournal.pending(for: reopened))
    }

    func testHistoryEditLeavesProjectionFreshAtBothSaveBoundaries() throws {
        for deferred in [false, true] {
            let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
            let context = ModelContext(container)
            let session = WorkoutSession(name: "Workout", status: .completed, endedAt: .now)
            let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
                exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
            let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 5, actualWeight: 100,
                isCompleted: true, sessionExercise: exercise)
            context.insert(session); context.insert(exercise); context.insert(set)
            try context.save()
            _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()
            let repository = WorkoutSessionRepository(modelContext: context, weeklyGoalWidgetPublisher: nil,
                autoSaveChanges: !deferred, boundaryEffects: .init(scheduleBackup: { _, _ in }))
            set.actualReps = 8
            try repository.recalculateSessionSummary(sessionID: session.id)
            if deferred { try repository.finalizeDeferredUserDataChangesIfNeeded() }
            let read = ModelContext(container)
            XCTAssertFalse(try HistoryProjectionRepository(modelContext: read).needsBackfill())
            XCTAssertEqual(session.projectionSourceUpdatedAt, session.updatedAt)
            let row = try XCTUnwrap(read.fetch(FetchDescriptor<ExerciseSessionSummary>()).first)
            let entry = try JSONDecoder().decode(CompletedExerciseHistoryEntry.self, from: row.payload)
            XCTAssertEqual(entry.totalReps, 8)
            XCTAssertEqual(entry.totalWeightedVolumeInKilograms, 800)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testRestoreExcludesConcurrentSaveAndRejectsItAfterFailedCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try diskContainer(url: root.appendingPathComponent("store.sqlite"))
        let original = ModelContext(container)
        original.insert(UserProfile(displayName: "Before"))
        try original.saveWithRecoveryProtection()
        let enteredRestore = expectation(description: "Restore owns the write barrier")
        let attemptedWrite = expectation(description: "Concurrent writer reached save")
        let writerFinished = expectation(description: "Writer must wait for restore")
        writerFinished.isInverted = true
        let releaseRestore = DispatchSemaphore(value: 0)
        enum Failure: Error { case save }
        let restore = Task.detached {
            let transaction = UserDataCloudRestoreTransaction(container: container, dependencies: .init(
                checkpoint: { checkpoint in
                    if checkpoint == .afterValidation {
                        enteredRestore.fulfill()
                        _ = releaseRestore.wait(timeout: .now() + 10)
                    }
                }, save: { context in
                    try context.save() // Simulate a store commit followed by a multi-store failure.
                    throw Failure.save
                }))
            do {
                try transaction.commit(replacingLocalData: true,
                    mergeDatabaseGraph: { $0.insert(UserProfile(displayName: "Partial restore")) },
                    relinkRelationships: { _ in })
                return false
            } catch is PersistentRestoreRecovery.RecoveryRequired { return true }
        }
        await fulfillment(of: [enteredRestore], timeout: 10)
        let writer = Task.detached {
            let context = ModelContext(container)
            context.insert(UserProfile(displayName: "Concurrent edit"))
            attemptedWrite.fulfill()
            defer { writerFinished.fulfill() }
            do { try context.saveWithRecoveryProtection(); return false }
            catch is PersistentRestoreRecovery.RecoveryRequired { return true }
        }
        await fulfillment(of: [attemptedWrite], timeout: 5)
        await fulfillment(of: [writerFinished], timeout: 0.1)
        releaseRestore.signal()
        let requiresRecovery = try await restore.value
        let rejectedWrite = try await writer.value
        XCTAssertTrue(requiresRecovery)
        XCTAssertTrue(rejectedWrite)
        let names = try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).map(\.displayName)
        XCTAssertFalse(names.contains("Concurrent edit"))
    }

    func testCompressedEnvelopeRoundTripsAndReadsLegacyJSON() throws {
        let input = Data(String(repeating: "workout sets and exercise history ", count: 10_000).utf8)
        let compressed = try BackupArchiveCodec.encode(input)
        XCTAssertLessThan(compressed.count, input.count / 10)
        XCTAssertEqual(try BackupArchiveCodec.decode(compressed), input)
        XCTAssertEqual(try BackupArchiveCodec.decode(input), input)
    }

    func testWidgetEditDoesNotReencodeUnchangedWorkoutChunks() throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        for index in 0..<250 {
            context.insert(WorkoutSession(name: "Workout \(index)", status: .completed, endedAt: .now))
        }
        try context.save()
        let first = try BackupExportPlan.build(container: container, previous: nil)
        defer { first.cleanUp() }
        XCTAssertEqual(first.chunkFiles.count, 251)
        context.insert(UserProfile(displayName: "Changed profile"))
        try context.save()
        let next = try BackupExportPlan.build(container: container, previous: first.manifest)
        defer { next.cleanUp() }
        XCTAssertEqual(next.chunkFiles.count, 1)
        XCTAssertEqual(next.manifest.chunks.filter { $0.key != "shared" }, first.manifest.chunks.filter { $0.key != "shared" })
        XCTAssertEqual(next.manifest.summary.completedWorkoutCount, 250)
    }

    func testPendingAcknowledgmentCannotClearNewerSaveAndSurvivesDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let container = try diskContainer(url: url)
        try BackupLocalJournal.markPending(for: container)
        let first = try XCTUnwrap(BackupLocalJournal.pending(for: container))
        try BackupLocalJournal.markPending(for: container)
        try BackupLocalJournal.finish(first, for: container)
        let second = try XCTUnwrap(BackupLocalJournal.pending(for: container))
        XCTAssertNotEqual(second.ticket, first.ticket)
        let reopened = try diskContainer(url: url)
        XCTAssertEqual(try BackupLocalJournal.pending(for: reopened)?.ticket, second.ticket)
        try BackupLocalJournal.finish(second, for: reopened)
        XCTAssertNil(try BackupLocalJournal.pending(for: container))
    }

    func testUnversionedShippedStoreMigratesWithoutLosingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let id = UUID()
        try autoreleasepool {
            let oldSchema = Schema(AppSchemaV1.models)
            let configuration = ModelConfiguration(schema: oldSchema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: oldSchema, configurations: configuration)
            let context = ModelContext(old)
            let session = AppSchemaV1.WorkoutSession()
            session.id = id
            session.name = "Existing install"
            session.statusRaw = "completed"
            let exercise = AppSchemaV1.WorkoutSessionExercise()
            exercise.sessionID = id
            exercise.catalogExerciseUUID = "bench"
            exercise.session = session
            let set = AppSchemaV1.WorkoutSessionSet()
            set.sessionExerciseID = exercise.id
            set.sessionExercise = exercise
            set.actualReps = 8
            set.actualWeight = 100
            set.isCompleted = true
            context.insert(session)
            context.insert(exercise)
            context.insert(set)
            try context.save()
        }
        let migrated = try diskContainer(url: url)
        let context = ModelContext(migrated)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.name, "Existing install")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSessionSet>()).first?.actualReps, 8)
        XCTAssertEqual(session.projectionVersion, 0)
        XCTAssertTrue(try HistoryProjectionRepository(modelContext: context).needsBackfill())
        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()
        XCTAssertFalse(try HistoryProjectionRepository(modelContext: context).needsBackfill())
        XCTAssertEqual(try ExerciseHistoryRepository(context: context).entries(for: "bench").first?.totalReps, 8)
    }

    func testRangeMilestonesDoNotCallSubLifetimePerformanceAPersonalRecord() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func session(day: Int, weight: Double) -> ExerciseProgressSession {
            .init(sessionID: UUID(), completedAt: start.addingTimeInterval(Double(day) * 86400),
                  estimatedOneRepMaxKilograms: weight, heaviestWeightKilograms: weight,
                  sessionVolumeKilograms: weight * 5, bestSetReps: 5, totalReps: 5,
                  completedSetCount: 1, displayUnit: .kg)
        }
        let dataset = ExerciseProgressDataset(exerciseUUID: "bench", exerciseName: "Bench", sessions: [
            session(day: 0, weight: 120), session(day: 100, weight: 80), session(day: 110, weight: 90)
        ], preferredLoadUnit: .kg)
        let projection = ExerciseProgressProjector.project(dataset: dataset, metric: .heaviestWeight,
            range: .oneMonth, now: start.addingTimeInterval(111 * 86400), calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(projection.points.count, 2)
        XCTAssertFalse(projection.milestones.contains { $0.kind == .personalRecord || $0.kind == .firstPerformance })
    }

    func testCompletedDropsAndCardioSurviveProjectionAndScopedQueries() throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        let session = WorkoutSession(name: "Hybrid", status: .completed, endedAt: .now)
        context.insert(session)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
        context.insert(exercise)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 5, actualWeight: 100, isCompleted: true, sessionExercise: exercise)
        context.insert(set)
        context.insert(WorkoutSessionDropStage(sessionSetID: set.id, actualReps: 8, actualWeight: 60, isCompleted: true, sessionSet: set))
        let cardio = WorkoutSessionCardioBlock(sessionID: session.id, phase: .postWorkout,
            catalogExerciseUUID: "run", exerciseNameSnapshot: "Run", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs", targetDurationSeconds: 600,
            actualDurationSeconds: 600, actualDistanceMeters: 2000, isCompleted: true, session: session)
        context.insert(cardio)
        try context.save()
        let cold = try XCTUnwrap(WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: "run"))
        XCTAssertEqual(cold.sessions.first?.durationSeconds, 600)
        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()
        let bench = try XCTUnwrap(ExerciseHistoryRepository(context: context).entries(for: "bench").first)
        XCTAssertEqual(bench.totalReps, 13)
        XCTAssertEqual(bench.totalWeightedVolumeInKilograms, 980)
        let run = try XCTUnwrap(ExerciseHistoryRepository(context: context).entries(for: "run").first)
        XCTAssertEqual(run.durationSeconds, 600)
        XCTAssertEqual(run.distanceMeters, 2000)
        XCTAssertEqual(run.completedSetCount, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testProductionStyleSeparateStoresMigrateTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func configs(_ models: [any PersistentModel.Type]) -> [ModelConfiguration] {
            productionConfigurations(root: root, models: models)
        }
        try autoreleasepool {
            let old = try ModelContainer(for: Schema(AppSchemaV1.models), configurations: configs(AppSchemaV1.models))
            let context = ModelContext(old)
            let profile = AppSchemaV1.UserProfile()
            profile.displayName = "Existing profile"
            let session = AppSchemaV1.WorkoutSession()
            session.statusRaw = "completed"
            context.insert(profile)
            context.insert(session)
            try context.save()
        }
        let migrated = try ModelContainer(for: AppSchema.makeFull(), migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configs(AppSchema.models))
        let context = ModelContext(migrated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Existing profile")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()
        XCTAssertFalse(try HistoryProjectionRepository(modelContext: context).needsBackfill())
    }

    func testInterruptedRestoreRecoversSQLiteIncludingDraftsBeforeReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        try autoreleasepool {
            let container = try diskContainer(url: url)
            let context = ModelContext(container)
            context.insert(UserProfile(displayName: "Before restore"))
            context.insert(ActiveWorkoutDraftSession(name: "Active draft"))
            try context.save()
            _ = try PersistentRestoreRecovery.prepare(container: container)
            // Simulate a store committed, but the process exited before restore completion.
            let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first)
            profile.displayName = "Interrupted restore"
            for draft in try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()) { context.delete(draft) }
            try context.save()
        }
        let config = ModelConfiguration(schema: AppSchema.makeFull(), url: url, cloudKitDatabase: .none)
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: [config])
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: [config]) // Idempotent after recovery.
        let container = try diskContainer(url: url)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Before restore")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).first?.name, "Active draft")
    }

    func testInterruptedRestoreRecoversAllProductionStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configs = productionConfigurations(root: root, models: AppSchema.models)
        try autoreleasepool {
            let container = try ModelContainer(for: AppSchema.makeFull(), migrationPlan: AppSchemaMigrationPlan.self, configurations: configs)
            let context = ModelContext(container)
            context.insert(UserProfile(displayName: "Original profile"))
            context.insert(ActiveWorkoutDraftSession(name: "Original draft"))
            context.insert(HistoryProjectionCheckpoint(version: 5))
            try context.save()
            _ = try PersistentRestoreRecovery.prepare(container: container)
            XCTAssertThrowsError(try PersistentRestoreRecovery.requireHealthyStore(container))
            try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first).displayName = "Partial restore"
            for draft in try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()) { context.delete(draft) }
            for checkpoint in try context.fetch(FetchDescriptor<HistoryProjectionCheckpoint>()) { context.delete(checkpoint) }
            try context.save()
        }
        try PersistentRestoreRecovery.recoverIfNeeded(configurations: configs)
        let container = try ModelContainer(for: AppSchema.makeFull(), migrationPlan: AppSchemaMigrationPlan.self, configurations: configs)
        try PersistentRestoreRecovery.requireHealthyStore(container)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).first?.displayName, "Original profile")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).first?.name, "Original draft")
        XCTAssertEqual(try context.fetch(FetchDescriptor<HistoryProjectionCheckpoint>()).first?.version, 5)
    }

    func testChildSetEditInvalidatesOnlyItsWorkoutBackupChunk() throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        let session = WorkoutSession(name: "Workout", status: .completed, endedAt: .now)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 5, actualWeight: 100,
            isCompleted: true, sessionExercise: exercise)
        context.insert(session); context.insert(exercise); context.insert(set)
        context.insert(WorkoutSession(name: "Unchanged", status: .completed, endedAt: .now))
        try context.save()
        let first = try BackupExportPlan.build(container: container, previous: nil)
        defer { first.cleanUp() }
        set.actualReps = 6
        try WorkoutCommitPreparation.stampChangedWorkouts(in: context)
        try context.save()
        let next = try BackupExportPlan.build(container: container, previous: first.manifest)
        defer { next.cleanUp() }
        XCTAssertEqual(next.chunkFiles.count, 1)
        XCTAssertNotEqual(next.manifest.chunks.first { $0.key == session.id.uuidString }?.digest,
                          first.manifest.chunks.first { $0.key == session.id.uuidString }?.digest)
    }

    func testHistoricalArchiveAndDeleteRecomputeLaterRecordsWithoutNoOpChurn() throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions: [WorkoutSession] = []
        for index in 0..<2 {
            let date = start.addingTimeInterval(Double(index) * 86400)
            let session = WorkoutSession(name: "Session", status: .completed,
                startedAt: date, endedAt: date.addingTimeInterval(3600))
            let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
                exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
            let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 5,
                actualWeight: index == 0 ? 100 : 80, isCompleted: true, sessionExercise: exercise)
            context.insert(session); context.insert(exercise); context.insert(set)
            sessions.append(session)
        }
        try context.save()
        let projections = HistoryProjectionRepository(modelContext: context)
        _ = try projections.backfillIfNeeded()
        _ = try HistoryRecordRebuilder.rebuild(in: context)
        try context.save()
        XCTAssertEqual(sessions.map(\.prHitsCount), [1, 0])
        XCTAssertEqual(try projections.backfillIfNeeded(), 0)
        XCTAssertFalse(context.hasChanges)
        let repository = WorkoutSessionRepository(modelContext: context, weeklyGoalWidgetPublisher: nil,
            boundaryEffects: .init(scheduleBackup: { _, _ in }))
        try repository.archiveSession(id: sessions[0].id)
        XCTAssertEqual(sessions[1].prHitsCount, 1)
        try repository.restoreArchivedSession(id: sessions[0].id)
        XCTAssertEqual(sessions[1].prHitsCount, 0)
        try repository.deleteSession(id: sessions[0].id)
        XCTAssertEqual(sessions[1].prHitsCount, 1)
    }

    func testPersistentHistory250Workouts7500Sets() throws { try verifyPersistentHistory(workouts: 250) }
    func testPersistentHistory2500Workouts75000Sets() throws { try verifyPersistentHistory(workouts: 2_500) }

    private func verifyPersistentHistory(workouts: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try diskContainer(url: root.appendingPathComponent("history.store"))
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        // Separate contexts bound fixture creation's working set.
        for batch in stride(from: 0, to: workouts, by: 50) {
            try autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                for index in batch..<min(batch + 50, workouts) {
                    let date = start.addingTimeInterval(Double(index) * 86400)
                    let session = WorkoutSession(name: "Workout \(index)", status: .completed,
                        startedAt: date, endedAt: date.addingTimeInterval(3600))
                    context.insert(session)
                    for exerciseIndex in 0..<6 {
                        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "exercise-\(exerciseIndex)",
                            exerciseNameSnapshot: "Exercise \(exerciseIndex)", categorySnapshot: "Chest",
                            muscleSummarySnapshot: "Chest", sortOrder: exerciseIndex, session: session)
                        context.insert(exercise)
                        for setIndex in 0..<5 {
                            context.insert(WorkoutSessionSet(sessionExerciseID: exercise.id, sortOrder: setIndex,
                                actualReps: 8, actualWeight: Double(60 + exerciseIndex), isCompleted: true, sessionExercise: exercise))
                        }
                    }
                }
                try context.save()
            }
        }
        let context = ModelContext(container)
        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()
        let read = ModelContext(container)
        let entries = try ExerciseHistoryRepository(context: read).entries(for: "exercise-0", limit: 8, metric: .volume)
        XCTAssertEqual(entries.count, 8)
        XCTAssertTrue(entries.allSatisfy { $0.totalReps == 40 && $0.totalWeightedVolumeInKilograms == 2400 })
        XCTAssertFalse(read.hasChanges)
        XCTAssertFalse(try HistoryProjectionRepository(modelContext: read).needsBackfill())
        let initialStarted = ContinuousClock.now
        let first = try BackupExportPlan.build(container: container, previous: nil)
        let initialDuration = initialStarted.duration(to: .now)
        defer { first.cleanUp() }
        XCTAssertEqual(first.manifest.summary.workoutSetCount, workouts * 30)
        XCTAssertLessThan(first.compressedChunkBytes, first.rawChunkBytes / 2)
        read.insert(UserProfile(displayName: "Only profile changed"))
        try read.save()
        let incrementalStarted = ContinuousClock.now
        let next = try BackupExportPlan.build(container: container, previous: first.manifest)
        let incrementalDuration = incrementalStarted.duration(to: .now)
        defer { next.cleanUp() }
        XCTAssertEqual(next.chunkFiles.count, 1)
        XCTAssertLessThan(next.compressedChunkBytes, 10_000)
        let manifestBytes = try BackupArchiveCodec.encode(BackupArchiveCodec.json(next.manifest)).count
        print("WGJ scale: \(workouts) workouts / \(workouts * 30) sets; initial \(first.rawChunkBytes) -> \(first.compressedChunkBytes) bytes; profile edit \(next.compressedChunkBytes) chunk bytes + \(manifestBytes) manifest bytes")
        print("WGJ backup planning: \(workouts) workouts; initial \(initialDuration); profile edit \(incrementalDuration)")
    }

    private func productionConfigurations(root: URL, models: [any PersistentModel.Type]) -> [ModelConfiguration] {
        func group(_ type: any PersistentModel.Type) -> String {
            let name = String(describing: type)
            if name.hasPrefix("ActiveWorkout") { return "Draft" }
            if name.hasPrefix("Completed") || name.hasPrefix("CachedCoach") || name == "ExerciseSessionSummary" || name == "HistoryProjectionCheckpoint" { return "Projection" }
            if ["ExerciseCatalogItem", "MuscleGroup", "ExerciseAlias", "ExerciseImageAsset", "ExerciseAttribution", "ExerciseCatalogSyncState"].contains(name) { return "Catalog" }
            return "UserData"
        }
        return ["Catalog", "UserData", "Draft", "Projection"].map { name in
                ModelConfiguration(name, schema: Schema(models.filter { group($0) == name }),
                    url: root.appendingPathComponent("\(name).store"), cloudKitDatabase: .none)
            }
    }

    private func diskContainer(url: URL) throws -> ModelContainer {
        let schema = AppSchema.makeFull()
        return try ModelContainer(for: schema, migrationPlan: AppSchemaMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }
}
