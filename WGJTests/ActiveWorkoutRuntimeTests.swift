import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
@MainActor
struct ActiveWorkoutRuntimeTests {
    @Test
    func startingRuntimeSessionCreatesOnlyLocalSnapshotWithoutLegacyDraftOrCloudMutation() async throws {
        let context = try makeInMemoryContext()
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)

        let session = ActiveWorkoutSessionFactory(modelContext: context)
            .createEmptySession(name: "Local Only")
        try await store.save(session)

        #expect(try await store.load()?.id == session.id)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).isEmpty)
        #expect(tracker.currentSnapshot().state == .caughtUp)
    }

    @Test
    func snapshotStoreSavesLoadsAndDeletesActiveWorkoutWithoutMarkingCloudMutation() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let session = makeRuntimeSession()
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)

        try await store.save(session)

        #expect(try await store.hasSnapshot())
        #expect(try await store.load()?.id == session.id)
        #expect(tracker.currentSnapshot().state == .caughtUp)

        try await store.delete()

        #expect(try await store.load() == nil)
        #expect(!(try await store.hasSnapshot()))
        #expect(tracker.currentSnapshot().state == .caughtUp)
    }

    @Test
    func snapshotStorePersistsRestTimerWithActiveWorkout() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let session = makeRuntimeSession()
        let setID = UUID()
        let restTimer = RestTimerSnapshot(
            endsAt: futureRestTimerDate(),
            exerciseName: "Bench Press",
            setLabel: "Set 2",
            sourceSetID: setID
        )

        try await store.save(session, restTimer: restTimer)

        let storedSnapshot = try #require(try await store.loadStoredSnapshot())
        #expect(storedSnapshot.session.id == session.id)
        #expect(storedSnapshot.restTimer?.exerciseName == restTimer.exerciseName)
        #expect(storedSnapshot.restTimer?.setLabel == restTimer.setLabel)
        #expect(storedSnapshot.restTimer?.sourceSetID == restTimer.sourceSetID)
        #expect(abs((storedSnapshot.restTimer?.endsAt.timeIntervalSince(restTimer.endsAt) ?? 999)) < 0.01)
    }

    @Test
    func snapshotStorePreservesRestTimerWhenSessionOnlyCallSitesSave() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        var session = makeRuntimeSession()
        let restTimer = RestTimerSnapshot(
            endsAt: futureRestTimerDate(),
            exerciseName: "Bench Press",
            setLabel: "Set 2",
            sourceSetID: UUID()
        )

        try await store.save(session, restTimer: restTimer)
        session.notes = "Updated elsewhere"
        try await store.save(session)

        let storedSnapshot = try #require(try await store.loadStoredSnapshot())
        #expect(storedSnapshot.session.notes == "Updated elsewhere")
        #expect(storedSnapshot.restTimer?.exerciseName == restTimer.exerciseName)
        #expect(storedSnapshot.restTimer?.setLabel == restTimer.setLabel)
        #expect(storedSnapshot.restTimer?.sourceSetID == restTimer.sourceSetID)
        #expect(abs((storedSnapshot.restTimer?.endsAt.timeIntervalSince(restTimer.endsAt) ?? 999)) < 0.01)
    }

    @Test
    func snapshotStoreCanExplicitlyClearRestTimer() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let session = makeRuntimeSession()
        let restTimer = RestTimerSnapshot(
            endsAt: futureRestTimerDate(),
            exerciseName: "Bench Press",
            setLabel: "Set 2",
            sourceSetID: UUID()
        )

        try await store.save(session, restTimer: restTimer)
        try await store.save(session, restTimer: nil, preservesExistingRestTimer: false)

        let storedSnapshot = try #require(try await store.loadStoredSnapshot())
        #expect(storedSnapshot.restTimer == nil)
    }

    @Test
    func sessionFactoryImportsLegacyActiveSwiftDataDraftAndRemovesLegacyRows() async throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)
        let legacy = try repository.createEmptySession(name: "Legacy Active")
        let item = makeCatalogItem(context: context)
        try repository.addExercise(sessionID: legacy.id, catalogItem: item)
        let legacyExercise = try #require(try repository.sessionExercises(sessionID: legacy.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: legacyExercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: legacyExercise.id, drafts: drafts)

        let imported = try ActiveWorkoutSessionFactory(modelContext: context)
            .importLegacyActiveSessionIfNeeded()

        #expect(imported?.id == legacy.id)
        #expect(imported?.name == "Legacy Active")
        #expect(imported?.exercises.first?.setDrafts[1].actualWeight == 100)
        #expect(imported?.exercises.first?.setDrafts[1].actualReps == 5)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).isEmpty)
    }

    @Test
    func completionWriterMaterializesRuntimeSessionAsCompletedWorkoutAndMarksDurableMutation() throws {
        let context = try makeInMemoryContext()
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        let session = makeRuntimeSession()

        let completedID = try ActiveWorkoutCompletionWriter(modelContext: context)
            .finish(session: session, notes: "Finished clean")

        let completed = try #require(try WorkoutSessionRepository(modelContext: context).session(id: completedID))
        let exercises = try WorkoutSessionRepository(modelContext: context).sessionExercises(sessionID: completedID)
        let sets = try #require(exercises.first?.sets?.sorted { $0.sortOrder < $1.sortOrder })

        #expect(completed.status == .completed)
        #expect(completed.name == session.name)
        #expect(completed.notes == "Finished clean")
        #expect(exercises.map(\.exerciseNameSnapshot) == ["Bench Press"])
        #expect(sets.count == 2)
        #expect(sets[1].actualWeight == 100)
        #expect(sets[1].actualReps == 5)
        #expect(tracker.currentSnapshot().state == .pendingExport)
    }

    @Test
    func templateStartNormalizesStaleSetRestToExerciseDefault() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let template = try repository.createTemplate(name: "Pull Day", notes: "")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "runtime-rest-curl",
                    exerciseNameSnapshot: "EZ Bar Curl",
                    categorySnapshot: "Biceps",
                    muscleSummarySnapshot: "Biceps",
                    restSeconds: 90,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 8, loadUnit: .kg, restSeconds: 120, isWarmup: true),
                        TemplateExerciseSetDraft(targetReps: 10, loadUnit: .kg, restSeconds: 120),
                        TemplateExerciseSetDraft(targetReps: 12, loadUnit: .kg, restSeconds: 120),
                    ]
                ),
            ]
        )

        let session = try ActiveWorkoutSessionFactory(modelContext: context)
            .createSessionFromTemplate(templateID: template.id)
        let exercise = try #require(session.exercises.first)

        #expect(exercise.restSeconds == 90)
        #expect(exercise.setDrafts.map(\.restSeconds) == [90, 90, 90])
    }

    @Test
    func snapshotStoreNormalizesStaleSetRestToExerciseDefault() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        var session = makeRuntimeSession()
        session.exercises[0].restSeconds = 90
        for index in session.exercises[0].setDrafts.indices {
            session.exercises[0].setDrafts[index].restSeconds = 120
        }

        try await store.save(session)

        let loaded = try #require(try await store.load())
        #expect(loaded.exercises.first?.setDrafts.map(\.restSeconds) == [90, 90])
    }

    @Test
    func snapshotStoreSkipsIdenticalLifecycleWrites() async throws {
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let session = makeRuntimeSession()
        let snapshotURL = directory.appendingPathComponent("active-workout-snapshot.json", isDirectory: false)

        try await store.save(session)
        let firstModifiedAt = try #require(
            FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.modificationDate] as? Date
        )
        try await Task.sleep(for: .milliseconds(25))
        try await store.save(session)
        let secondModifiedAt = try #require(
            FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.modificationDate] as? Date
        )

        #expect(secondModifiedAt == firstModifiedAt)
    }

    @Test
    func runtimeFirstRenderSnapshotIncludesPreviousValuesForEveryExercise() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let bench = makeCatalogItem(context: context, remoteUUID: "runtime-first-render-bench")
        let row = makeCatalogItem(context: context, remoteUUID: "runtime-first-render-row")
        let previousTemplate = try templateRepository.createTemplate(name: "Previous", notes: "")
        try templateRepository.setExercises(
            templateID: previousTemplate.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: bench.remoteUUID,
                    exerciseNameSnapshot: bench.displayName,
                    categorySnapshot: bench.categoryName,
                    muscleSummarySnapshot: bench.equipmentSummary,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 8, loadUnit: .kg)]
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: row.remoteUUID,
                    exerciseNameSnapshot: row.displayName,
                    categorySnapshot: row.categoryName,
                    muscleSummarySnapshot: row.equipmentSummary,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 10, loadUnit: .kg)]
                ),
            ]
        )
        let previousSession = try sessionRepository.createSessionFromTemplate(templateID: previousTemplate.id)
        for exercise in try sessionRepository.sessionExercises(sessionID: previousSession.id) {
            var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
            drafts[0].actualWeight = exercise.catalogExerciseUUID == bench.remoteUUID ? 100 : 80
            drafts[0].actualReps = exercise.catalogExerciseUUID == bench.remoteUUID ? 6 : 10
            drafts[0].isCompleted = true
            try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        }
        try sessionRepository.finishSession(sessionID: previousSession.id)

        let activeTemplate = try templateRepository.createTemplate(name: "Today", notes: "")
        try templateRepository.setExercises(
            templateID: activeTemplate.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: bench.remoteUUID,
                    exerciseNameSnapshot: bench.displayName,
                    categorySnapshot: bench.categoryName,
                    muscleSummarySnapshot: bench.equipmentSummary,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 8, loadUnit: .kg)]
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: row.remoteUUID,
                    exerciseNameSnapshot: row.displayName,
                    categorySnapshot: row.categoryName,
                    muscleSummarySnapshot: row.equipmentSummary,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 10, loadUnit: .kg)]
                ),
            ]
        )
        let runtime = try ActiveWorkoutSessionFactory(modelContext: context)
            .createSessionFromTemplate(templateID: activeTemplate.id)

        let snapshot = try ActiveWorkoutRuntimeFirstRenderSnapshotBuilder.build(
            session: runtime,
            modelContext: context
        )

        #expect(snapshot.draftsByExerciseID.keys.count == 2)
        #expect(snapshot.previousResolutionByExerciseID.keys.count == 2)
        for exercise in runtime.exercises {
            let previous = try #require(snapshot.previousResolutionByExerciseID[exercise.id]?.previous(at: 0))
            if exercise.catalogExerciseUUID == bench.remoteUUID {
                #expect(previous.weight == 100)
                #expect(previous.reps == 6)
            } else if exercise.catalogExerciseUUID == row.remoteUUID {
                #expect(previous.weight == 80)
                #expect(previous.reps == 10)
            }
        }
    }

    @Test
    func completionWriterMaterializesCanonicalExerciseRestForStaleRuntimeSetDrafts() throws {
        let context = try makeInMemoryContext()
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        var session = makeRuntimeSession()
        session.exercises[0].restSeconds = 90
        for index in session.exercises[0].setDrafts.indices {
            session.exercises[0].setDrafts[index].restSeconds = 120
        }

        let completedID = try ActiveWorkoutCompletionWriter(modelContext: context)
            .finish(session: session)

        let exercises = try WorkoutSessionRepository(modelContext: context).sessionExercises(sessionID: completedID)
        let sets = try #require(exercises.first?.sets?.sorted { $0.sortOrder < $1.sortOrder })

        #expect(sets.map(\.restSeconds) == [90, 90])
    }

    @Test
    func discardDeletesSnapshotWithoutCreatingCompletedWorkoutOrCloudMutation() async throws {
        let context = try makeInMemoryContext()
        let directory = try temporaryDirectory()
        let store = ActiveWorkoutSnapshotStore(baseDirectory: directory)
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)

        try await store.save(makeRuntimeSession())
        try await ActiveWorkoutRuntimeController(snapshotStore: store).discard()

        #expect(try await store.load() == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        #expect(tracker.currentSnapshot().state == .caughtUp)
    }

    private func makeRuntimeSession() -> ActiveWorkoutRuntimeSession {
        let sessionID = UUID()
        let exerciseID = UUID()
        return ActiveWorkoutRuntimeSession(
            id: sessionID,
            templateID: nil,
            name: "Push Day",
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
            notes: "Runtime notes",
            cardioBlocks: [],
            exercises: [
                ActiveWorkoutRuntimeExercise(
                    id: exerciseID,
                    templateExerciseID: nil,
                    catalogExerciseUUID: "bench-press",
                    exerciseNameSnapshot: "Bench Press",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Pecs",
                    notes: "",
                    targetRepMin: 5,
                    targetRepMax: 8,
                    restSeconds: 120,
                    sortOrder: 0,
                    components: [
                        ActiveWorkoutRuntimeExerciseComponent(
                            id: UUID(),
                            catalogExerciseUUID: "bench-press",
                            exerciseNameSnapshot: "Bench Press",
                            categorySnapshot: "Chest",
                            muscleSummarySnapshot: "Pecs",
                            sortOrder: 0
                        ),
                    ],
                    setDrafts: [
                        WorkoutSessionSetDraft(
                            targetReps: 5,
                            targetWeight: 90,
                            targetLoadUnit: .kg,
                            actualReps: nil,
                            actualWeight: nil,
                            actualLoadUnit: .kg,
                            isCompleted: false
                        ),
                        WorkoutSessionSetDraft(
                            targetReps: 5,
                            targetWeight: 100,
                            targetLoadUnit: .kg,
                            actualReps: 5,
                            actualWeight: 100,
                            actualLoadUnit: .kg,
                            isCompleted: true
                        ),
                    ],
                    superset: nil
                ),
            ],
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
    }

    private func futureRestTimerDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 900)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCatalogItem(
        context: ModelContext,
        remoteUUID: String = "bench-press"
    ) -> ExerciseCatalogItem {
        let item = ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            displayName: remoteUUID.contains("row") ? "Barbell Row" : "Bench Press",
            categoryName: remoteUUID.contains("row") ? "Back" : "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "test"
        )
        context.insert(item)
        return item
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
            BlockedBro.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
