import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct HistoryDetailSnapshotTests {
    @Test
    func overviewSummaryRowsIncludeEveryExercise() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try repository.createEmptySession(name: "Long Session")

        for index in 0..<8 {
            let item = makeCatalogItem(
                context: context,
                remoteUUID: "history-summary-\(index)",
                displayName: "Exercise \(index + 1)",
                category: "Strength"
            )
            try repository.addExercise(sessionID: session.id, catalogItem: item)
        }

        for exercise in try repository.sessionExercises(sessionID: session.id) {
            let index = exercise.sortOrder
            var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
            drafts[1].actualReps = 10 + index
            drafts[1].actualWeight = nil
            drafts[1].actualLoadUnit = .bodyweight
            drafts[1].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        }

        try repository.finishSession(sessionID: session.id)
        let completedSession = try #require(try repository.session(id: session.id))
        let rows = HistorySessionSummaryBuilder.rows(for: completedSession)

        #expect(rows.count == 8)
        #expect(rows.map(\.exercise).last == "3 x Exercise 8")
        #expect(rows.map(\.bestSet).last == "17 reps")
    }

    @Test
    func snapshotLoadPreloadsEditableStateForAllExercisesWithoutExpansion() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let bench = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-preload-bench",
            displayName: "Bench Press",
            category: "Chest"
        )
        let row = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-preload-row",
            displayName: "Barbell Row",
            category: "Back"
        )
        let session = try repository.createEmptySession(name: "Preload")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        try repository.addExercise(sessionID: session.id, catalogItem: row)
        let exercises = try repository.sessionExercises(sessionID: session.id)
        for exercise in exercises {
            var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
            drafts[0].actualWeight = exercise.catalogExerciseUUID == bench.remoteUUID ? 100 : 80
            drafts[0].actualReps = exercise.catalogExerciseUUID == bench.remoteUUID ? 6 : 10
            drafts[0].isCompleted = true
            try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
            try repository.updateExerciseNotes(sessionExerciseID: exercise.id, notes: "Loaded \(exercise.exerciseNameSnapshot)")
        }
        try repository.finishSession(sessionID: session.id)

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: session.id
        )

        #expect(snapshot.exercises.count == 2)
        #expect(snapshot.localState.setDraftsByExerciseID.keys.count == 2)
        #expect(snapshot.localState.restByExerciseID.keys.count == 2)
        #expect(snapshot.localState.notesByExerciseID.keys.count == 2)
        for exercise in snapshot.exercises {
            #expect(snapshot.localState.setDraftsByExerciseID[exercise.id]?.isEmpty == false)
            #expect(snapshot.localState.notesByExerciseID[exercise.id] == "Loaded \(exercise.exerciseNameSnapshot)")
        }
    }

    @Test
    func snapshotLoadCanSkipHydrationForCollapsedRows() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let bench = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-skip-hydration-bench",
            displayName: "Bench Press",
            category: "Chest"
        )
        let row = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-skip-hydration-row",
            displayName: "Barbell Row",
            category: "Back"
        )
        let session = try repository.createEmptySession(name: "Skip Hydration")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        try repository.addExercise(sessionID: session.id, catalogItem: row)
        try repository.finishSession(sessionID: session.id)

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: session.id,
            hydrationExerciseIDs: []
        )

        #expect(snapshot.exercises.count == 2)
        #expect(snapshot.localState.setDraftsByExerciseID.keys.count == 2)
        #expect(snapshot.hydrationPayloadByExerciseID.isEmpty)
    }

    @Test
    func hydrationPayloadLoadOnlyReturnsRequestedExercises() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let bench = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-targeted-hydration-bench",
            displayName: "Bench Press",
            category: "Chest"
        )
        let row = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-targeted-hydration-row",
            displayName: "Barbell Row",
            category: "Back"
        )
        let session = try repository.createEmptySession(name: "Targeted Hydration")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        try repository.addExercise(sessionID: session.id, catalogItem: row)
        try repository.finishSession(sessionID: session.id)
        let exercises = try repository.sessionExercises(sessionID: session.id)
        let requestedExercise = try #require(exercises.first)

        let payloads = try HistoryDetailSnapshotBuilder.loadHydrationPayloads(
            modelContext: context,
            sessionID: session.id,
            exerciseIDs: [requestedExercise.id]
        )

        #expect(Set(payloads.keys) == [requestedExercise.id])
    }

    @Test
    func snapshotLoadBuildsWorkoutMuscleHeatmapFromCompletedWorkingSets() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)
        let chest = MuscleGroup(remoteID: 3, name: "Chest", nameEn: "Chest")
        context.insert(chest)
        let bench = makeCatalogItem(
            context: context,
            remoteUUID: "history-detail-heatmap-bench",
            displayName: "Bench Press",
            category: "Chest"
        )
        bench.primaryMuscles = [chest]
        chest.primaryExercises = [bench]
        try context.save()

        let session = try repository.createEmptySession(name: "Heatmap")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        let exercise = try #require(repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].isWarmup = false
        drafts[0].actualWeight = 100
        drafts[0].actualReps = 8
        drafts[0].isCompleted = true
        drafts.append(
            WorkoutSessionSetDraft(
                id: UUID(),
                isWarmup: true,
                targetReps: nil,
                targetWeight: nil,
                actualReps: 12,
                actualWeight: 40,
                isCompleted: true
            )
        )
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try repository.finishSession(sessionID: session.id)

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: session.id
        )

        #expect(snapshot.muscleHeatmap.topRegionNames == ["Chest"])
        #expect(snapshot.muscleHeatmap.entries.map(\.region.displayName) == ["Chest"])
        #expect(snapshot.muscleHeatmap.entries.first?.score == 1)
    }

    private func makeCatalogItem(
        context: ModelContext,
        remoteUUID: String,
        displayName: String,
        category: String
    ) -> ExerciseCatalogItem {
        let item = ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: category,
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
        let config = ModelConfiguration("HistoryDetailSnapshot-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
