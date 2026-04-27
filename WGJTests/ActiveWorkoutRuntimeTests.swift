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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCatalogItem(context: ModelContext) -> ExerciseCatalogItem {
        let item = ExerciseCatalogItem(
            remoteUUID: "bench-press",
            displayName: "Bench Press",
            categoryName: "Chest",
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
