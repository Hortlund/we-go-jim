import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct HistoryProjectionRepositoryTests {
    @Test
    func rebuildFactsCapturesWeightedWarmupAndBodyweightButSkipsUnsupportedSets() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "projection-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let pullUp = ExerciseCatalogItem(
            remoteUUID: "projection-pullup",
            displayName: "Pull Up",
            categoryName: "Back",
            equipmentSummary: "Bodyweight",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(pullUp)

        let session = try sessionRepository.createEmptySession(name: "Mixed Day")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: bench)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: pullUp)

        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        let benchExercise = try #require(exercises.first { $0.catalogExerciseUUID == bench.remoteUUID })
        let pullUpExercise = try #require(exercises.first { $0.catalogExerciseUUID == pullUp.remoteUUID })

        var benchDrafts = try sessionRepository.setDrafts(sessionExerciseID: benchExercise.id)
        benchDrafts[0].actualWeight = 40
        benchDrafts[0].actualReps = 10
        benchDrafts[0].actualLoadUnit = .kg
        benchDrafts[0].isCompleted = true
        benchDrafts[1].actualWeight = 100
        benchDrafts[1].actualReps = 5
        benchDrafts[1].actualLoadUnit = .kg
        benchDrafts[1].isCompleted = true
        benchDrafts[2].targetWeight = 110
        benchDrafts[2].targetReps = 3
        benchDrafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: benchExercise.id, drafts: benchDrafts)

        var pullUpDrafts = try sessionRepository.setDrafts(sessionExerciseID: pullUpExercise.id)
        pullUpDrafts[0].actualReps = 12
        pullUpDrafts[0].actualLoadUnit = .bodyweight
        pullUpDrafts[0].isCompleted = true
        pullUpDrafts[1].actualReps = 8
        pullUpDrafts[1].actualLoadUnit = .bodyweight
        pullUpDrafts[1].isCompleted = false
        try sessionRepository.saveSetDrafts(sessionExerciseID: pullUpExercise.id, drafts: pullUpDrafts)

        try sessionRepository.finishSession(sessionID: session.id)

        let facts = try projectionRepository.facts(forSessionID: session.id)
        #expect(facts.count == 3)

        let warmupFact = try #require(facts.first { $0.sessionExerciseID == benchExercise.id && $0.isWarmup })
        #expect(warmupFact.weight == 40)
        #expect(warmupFact.volumeKg != nil)

        let weightedFact = try #require(facts.first { $0.sessionExerciseID == benchExercise.id && !$0.isWarmup })
        #expect(weightedFact.weight == 100)
        #expect(weightedFact.reps == 5)
        #expect(weightedFact.estimatedOneRepMaxKg != nil)

        let bodyweightFact = try #require(facts.first { $0.sessionExerciseID == pullUpExercise.id })
        #expect(bodyweightFact.loadUnit == .bodyweight)
        #expect(bodyweightFact.weight == nil)
        #expect(bodyweightFact.volumeKg == nil)
    }

    @Test
    func recalculateSessionSummaryRebuildsFactsAfterHistoryEdits() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "projection-edit-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let session = try sessionRepository.createEmptySession(name: "Push")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: bench)
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)

        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        drafts[1].actualWeight = 110
        drafts[1].actualReps = 4
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.recalculateSessionSummary(sessionID: session.id)

        let facts = try projectionRepository.facts(forSessionID: session.id)
        let updatedFact = try #require(facts.first { $0.sessionSetID == drafts[1].id })
        let refreshedSession = try #require(try sessionRepository.session(id: session.id))

        #expect(updatedFact.weight == 110)
        #expect(updatedFact.reps == 4)
        #expect(abs(refreshedSession.totalVolume - 440) < 0.01)
    }

    @Test
    func deletingCompletedSessionRemovesFactsAndUpdatesExerciseTrends() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "projection-delete-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        try makeCompletedSession(
            named: "Baseline",
            weight: 100,
            reps: 5,
            exercise: bench,
            sessionRepository: sessionRepository
        )
        let current = try makeCompletedSession(
            named: "Current",
            weight: 105,
            reps: 5,
            exercise: bench,
            sessionRepository: sessionRepository
        )

        var metrics = WorkoutMetricsService(modelContext: context)
        #expect(try metrics.exerciseOneRepMaxTrend(for: bench.remoteUUID, limit: 8).points.count == 2)

        try sessionRepository.deleteSession(id: current.id)

        metrics = WorkoutMetricsService(modelContext: context)
        let facts = try projectionRepository.allFacts()
        let series = try metrics.exerciseOneRepMaxTrend(for: bench.remoteUUID, limit: 8)

        #expect(facts.allSatisfy { $0.sessionID != current.id })
        #expect(series.points.count == 1)
        #expect(abs((series.points.first?.value ?? 0) - metrics.estimatedOneRepMax(weight: 100, reps: 5)) < 0.01)
    }

    @Test
    func backfillCreatesMissingFactsAndSkipsFreshSessions() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)

        let row = ExerciseCatalogItem(
            remoteUUID: "projection-backfill-row",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(row)

        let session = try makeCompletedSession(
            named: "Backfill",
            weight: 80,
            reps: 8,
            exercise: row,
            sessionRepository: sessionRepository
        )

        #expect(try projectionRepository.backfillIfNeeded(persistChanges: false) == 0)

        try projectionRepository.deleteFacts(forSessionID: session.id, persistChanges: false)
        try context.save()
        #expect(try projectionRepository.facts(forSessionID: session.id).isEmpty)

        #expect(try projectionRepository.backfillIfNeeded() == 1)
        #expect(try projectionRepository.facts(forSessionID: session.id).count == 1)
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

    @discardableResult
    private func makeCompletedSession(
        named name: String,
        weight: Double,
        reps: Int,
        exercise: ExerciseCatalogItem,
        sessionRepository: WorkoutSessionRepository
    ) throws -> WorkoutSession {
        let session = try sessionRepository.createEmptySession(name: name)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[1].actualWeight = weight
        drafts[1].actualReps = reps
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)
        return try #require(try sessionRepository.session(id: session.id))
    }
}
