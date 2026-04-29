import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct HistoryDetailSnapshotTests {
    @Test
    func overviewSummaryRowsIncludeEveryExercise() {
        let session = WorkoutSession(name: "Long Session", status: .completed)
        session.exercises = (0..<8).map { index in
            let exercise = WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "history-summary-\(index)",
                exerciseNameSnapshot: "Exercise \(index + 1)",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Training",
                sortOrder: index,
                session: session
            )
            exercise.sets = [
                WorkoutSessionSet(
                    sessionExerciseID: exercise.id,
                    sortOrder: 0,
                    actualReps: 10 + index,
                    actualWeight: nil,
                    isCompleted: true,
                    sessionExercise: exercise
                ),
            ]
            return exercise
        }

        let rows = HistorySessionSummaryBuilder.rows(for: session)

        #expect(rows.count == 8)
        #expect(rows.map(\.exercise).last == "1 x Exercise 8")
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
