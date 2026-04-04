import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WorkoutSessionRepositoryTests {
    @Test
    func sessionLifecycleStartLogAndFinish() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        guard let exercise = try repository.sessionExercises(sessionID: session.id).first else {
            Issue.record("Expected session exercise")
            return
        }

        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(drafts.count == 3)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)

        try repository.finishSession(sessionID: session.id, notes: "Solid day")

        let refreshed = try repository.session(id: session.id)
        #expect(refreshed?.status == .completed)
        #expect(refreshed?.notes == "Solid day")
        #expect((refreshed?.totalVolume ?? 0) > 0)
    }

    @Test
    func addExerciseUsesPreferredWeightUnitForDefaultSets() throws {
        let context = try makeInMemoryContext()
        let profileRepository = ProfileRepository(modelContext: context)
        try profileRepository.updatePreferredWeightUnit(.lb)

        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "bench-lb-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        guard let exercise = try repository.sessionExercises(sessionID: session.id).first else {
            Issue.record("Expected session exercise")
            return
        }

        let drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(drafts.count == 3)
        #expect(drafts.allSatisfy { $0.targetLoadUnit == .lb })
        #expect(drafts.allSatisfy { $0.actualLoadUnit == .lb })
    }

    @Test
    func previousSetLookupMatchesExerciseAndSetIndex() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "squat-1",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let first = try repository.createEmptySession(name: "Legs 1")
        try repository.addExercise(sessionID: first.id, catalogItem: item)
        let firstExercise = try repository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try repository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].actualWeight = 140
        firstDrafts[0].actualReps = 4
        firstDrafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try repository.finishSession(sessionID: first.id)

        let second = try repository.createEmptySession(name: "Legs 2")
        let previous = try repository.previousSet(
            for: item.remoteUUID,
            setIndex: 0,
            before: second.startedAt,
            excludingSessionID: second.id
        )

        #expect(previous?.actualWeight == 140)
        #expect(previous?.actualReps == 4)
    }

    @Test
    func previousSetMapProvidesFallbackForMissingIndexes() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "row-previous-map",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let first = try repository.createEmptySession(name: "Back 1")
        try repository.addExercise(sessionID: first.id, catalogItem: item)
        let firstExercise = try repository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try repository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].actualWeight = 80
        firstDrafts[0].actualReps = 8
        firstDrafts[0].isCompleted = true
        firstDrafts[1].actualWeight = 90
        firstDrafts[1].actualReps = 6
        firstDrafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try repository.finishSession(sessionID: first.id)

        let second = try repository.createEmptySession(name: "Back 2")
        let map = try repository.previousSetMap(
            for: item.remoteUUID,
            before: second.startedAt,
            excludingSessionID: second.id,
            maxSetCount: 4
        )

        #expect(map.count == 4)
        #expect(map[0]?.weight == 80)
        #expect(map[0]?.reps == 8)
        #expect(map[1]?.weight == 90)
        #expect(map[1]?.reps == 6)
        #expect(map[2]?.weight == nil)
        #expect(map[2]?.reps == nil)
        #expect(map[3]?.weight == nil)
        #expect(map[3]?.reps == nil)
    }

    @Test
    func createTemplateFromCompletedSessionUsesLoggedValues() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let templateRepository = TemplateRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "deadlift-1",
            displayName: "Deadlift",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try sessionRepository.createEmptySession(name: "Back Day")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 180
        drafts[0].actualReps = 3
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let template = try templateRepository.createTemplate(fromSessionID: session.id, name: "Deadlift Template")
        let templateExercise = try templateRepository.exercises(in: template.id).first
        let setDrafts = try templateExercise.map { try templateRepository.setDrafts(for: $0.id) } ?? []

        #expect(templateExercise?.exerciseNameSnapshot == "Deadlift")
        #expect(setDrafts.first?.targetWeight == 180)
        #expect(setDrafts.first?.targetReps == 3)
    }

    @Test
    func backfillCompletedSessionSummariesUpdatesStaleMetricVersions() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "backfill-bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 200
        drafts[0].actualReps = 1
        drafts[0].actualLoadUnit = .lb
        drafts[0].isCompleted = true
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try repository.finishSession(sessionID: session.id)

        let stored = try #require(try repository.session(id: session.id))
        stored.totalVolume = 999
        stored.prHitsCount = 99
        stored.summaryMetricsVersion = 0
        try context.save()

        let updatedCount = try repository.backfillCompletedSessionSummariesIfNeeded()
        let refreshed = try #require(try repository.session(id: session.id))

        #expect(updatedCount == 1)
        #expect(abs(refreshed.totalVolume - 500) < 0.01)
        #expect(refreshed.prHitsCount == 1)
        #expect(refreshed.summaryMetricsVersion == WorkoutMetricsService.currentSummaryMetricsVersion)
    }

    @Test
    func updateExerciseRestPersists() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "row-1",
            displayName: "Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!

        try repository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 165)
        let refreshed = try repository.sessionExercises(sessionID: session.id).first
        #expect(refreshed?.restSeconds == 165)
    }

    @Test
    func updateExerciseRestPreservesCustomSetOverrides() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "rest-override-1",
            displayName: "Incline Press",
            categoryName: "Chest",
            equipmentSummary: "Dumbbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].restSeconds = 180
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)

        try repository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 150)

        let updatedDrafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        #expect(updatedDrafts[0].restSeconds == 150)
        #expect(updatedDrafts[1].restSeconds == 180)
        #expect(updatedDrafts[2].restSeconds == 150)
    }

    @Test
    func updateExerciseRepRangePersists() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "rep-range-1",
            displayName: "Lat Pulldown",
            categoryName: "Back",
            equipmentSummary: "Cable",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession()
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        let exercise = try repository.sessionExercises(sessionID: session.id).first!

        try repository.updateExerciseRepRange(sessionExerciseID: exercise.id, minReps: 8, maxReps: 12)

        let refreshed = try repository.sessionExercises(sessionID: session.id).first
        #expect(refreshed?.targetRepMin == 8)
        #expect(refreshed?.targetRepMax == 12)
    }

    @Test
    func saveSetDraftsOnlyTouchesChangedSetAndPreservesParentStamps() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let item = ExerciseCatalogItem(
            remoteUUID: "draft-delta-1",
            displayName: "Leg Press",
            categoryName: "Legs",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)

        let session = try repository.createEmptySession(name: "Lower")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let initialSession = try #require(try repository.session(id: session.id))
        let initialExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let initialSets = (initialExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        #expect(initialSets.count == 3)

        let baselineSessionUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let baselineExerciseUpdatedAt = Date(timeIntervalSince1970: 2_000)
        initialSession.updatedAt = baselineSessionUpdatedAt
        initialExercise.updatedAt = baselineExerciseUpdatedAt

        var baselineSetUpdatedAtByID: [UUID: Date] = [:]
        for (index, set) in initialSets.enumerated() {
            let updatedAt = Date(timeIntervalSince1970: 3_000 + Double(index))
            set.updatedAt = updatedAt
            baselineSetUpdatedAtByID[set.id] = updatedAt
        }
        try context.save()

        var drafts = try repository.setDrafts(sessionExerciseID: initialExercise.id)
        drafts[1].actualWeight = 180
        drafts[1].actualReps = 10
        drafts[1].actualLoadUnit = .lb
        drafts[1].isCompleted = true

        try repository.saveSetDrafts(sessionExerciseID: initialExercise.id, drafts: drafts)

        let refreshedSession = try #require(try repository.session(id: session.id))
        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedSets = (refreshedExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }

        #expect(refreshedSession.updatedAt == baselineSessionUpdatedAt)
        #expect(refreshedExercise.updatedAt == baselineExerciseUpdatedAt)
        #expect(refreshedSets[0].updatedAt == baselineSetUpdatedAtByID[refreshedSets[0].id])
        #expect(refreshedSets[2].updatedAt == baselineSetUpdatedAtByID[refreshedSets[2].id])
        #expect((refreshedSets[1].updatedAt) > (baselineSetUpdatedAtByID[refreshedSets[1].id] ?? .distantFuture))
    }

    @Test
    func deleteSessionRemovesFromHistory() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try repository.createEmptySession(name: "Delete Me")
        try repository.deleteSession(id: session.id)
        #expect(try repository.session(id: session.id) == nil)
    }

    @Test
    func cancelSessionDiscardsActiveWorkout() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let session = try repository.createEmptySession(name: "Cancel Me")
        #expect(try repository.activeSession()?.id == session.id)

        try repository.cancelSession(sessionID: session.id)

        #expect(try repository.session(id: session.id) == nil)
        #expect(try repository.activeSession() == nil)
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
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
