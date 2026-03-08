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
        drafts[0].actualWeight = 100
        drafts[0].actualReps = 5
        drafts[0].actualLoadUnit = .kg
        drafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)

        try repository.finishSession(sessionID: session.id, notes: "Solid day")

        let refreshed = try repository.session(id: session.id)
        #expect(refreshed?.status == .completed)
        #expect(refreshed?.notes == "Solid day")
        #expect((refreshed?.totalVolume ?? 0) > 0)
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
