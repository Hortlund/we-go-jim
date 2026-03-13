import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WorkoutTemplateSyncServiceTests {
    @Test
    func previewIgnoresActualLogsWithoutTemplateOwnedChanges() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "sync-bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let template = try makeTemplate(
            name: "Push",
            exercises: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: bench.remoteUUID,
                    exerciseNameSnapshot: bench.displayName,
                    categorySnapshot: bench.categoryName,
                    muscleSummarySnapshot: bench.primaryMuscleNames,
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 6, targetWeight: 100, loadUnit: .kg, restSeconds: 120, isWarmup: true),
                        TemplateExerciseSetDraft(targetReps: 6, targetWeight: 110, loadUnit: .kg, restSeconds: 120),
                    ]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 102.5
        drafts[0].actualReps = 7
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        #expect(try syncService.previewTemplateUpdate(forSessionID: session.id) == nil)
    }

    @Test
    func previewDetectsTemplateOwnedChanges() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let row = ExerciseCatalogItem(
            remoteUUID: "sync-row-1",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(row)

        let template = try makeTemplate(
            name: "Back",
            exercises: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: row.remoteUUID,
                    exerciseNameSnapshot: row.displayName,
                    categorySnapshot: row.categoryName,
                    muscleSummarySnapshot: row.primaryMuscleNames,
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 120,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 10, targetWeight: 80, loadUnit: .kg, restSeconds: 120, isWarmup: true),
                        TemplateExerciseSetDraft(targetReps: 8, targetWeight: 90, loadUnit: .kg, restSeconds: 120),
                    ]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        try sessionRepository.updateExerciseRepRange(sessionExerciseID: exercise.id, minReps: 6, maxReps: 8)
        try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 150)
        try sessionRepository.addSet(sessionExerciseID: exercise.id)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try syncService.previewTemplateUpdate(forSessionID: session.id)
        #expect(preview?.changedExerciseCount == 1)
        #expect(preview?.summary.contains("1 exercise") == true)
    }

    @Test
    func applyTemplateUpdateUsesLoggedActualValues() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let squat = ExerciseCatalogItem(
            remoteUUID: "sync-squat-1",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(squat)

        let template = try makeTemplate(
            name: "Leg Day",
            exercises: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: squat.remoteUUID,
                    exerciseNameSnapshot: squat.displayName,
                    categorySnapshot: squat.categoryName,
                    muscleSummarySnapshot: squat.primaryMuscleNames,
                    targetRepMin: 5,
                    targetRepMax: 8,
                    restSeconds: 180,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 5, targetWeight: 140, loadUnit: .kg, restSeconds: 180, isWarmup: true),
                        TemplateExerciseSetDraft(targetReps: 5, targetWeight: 160, loadUnit: .kg, restSeconds: 180),
                    ]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 210)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].actualWeight = 165
        drafts[1].actualReps = 6
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try syncService.previewTemplateUpdate(forSessionID: session.id)
        #expect(preview != nil)
        try syncService.applyTemplateUpdate(try #require(preview))

        let templateExercise = try templateRepository.exercises(in: template.id).first
        let updatedSetDrafts = try templateExercise.map { try templateRepository.setDrafts(for: $0.id) } ?? []

        #expect(templateExercise?.restSeconds == 210)
        #expect(updatedSetDrafts[1].targetWeight == 165)
        #expect(updatedSetDrafts[1].targetReps == 6)
    }

    @Test
    func applyTemplateUpdateDoesNotMutateTemplateRoster() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "sync-bench-2",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let row = ExerciseCatalogItem(
            remoteUUID: "sync-row-2",
            displayName: "Seated Row",
            categoryName: "Back",
            equipmentSummary: "Cable",
            isCurated: true,
            sourceName: "seed"
        )
        let curl = ExerciseCatalogItem(
            remoteUUID: "sync-curl-2",
            displayName: "Curl",
            categoryName: "Arms",
            equipmentSummary: "Dumbbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(row)
        context.insert(curl)

        let template = try makeTemplate(
            name: "Upper",
            exercises: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: bench.remoteUUID,
                    exerciseNameSnapshot: bench.displayName,
                    categorySnapshot: bench.categoryName,
                    muscleSummarySnapshot: bench.primaryMuscleNames,
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 120,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 6, targetWeight: 100, loadUnit: .kg, restSeconds: 120)]
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: row.remoteUUID,
                    exerciseNameSnapshot: row.displayName,
                    categorySnapshot: row.categoryName,
                    muscleSummarySnapshot: row.primaryMuscleNames,
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 90,
                    setDrafts: [TemplateExerciseSetDraft(targetReps: 10, targetWeight: 60, loadUnit: .kg, restSeconds: 90)]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let benchExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first(where: { $0.catalogExerciseUUID == bench.remoteUUID }))
        try sessionRepository.updateExerciseRest(sessionExerciseID: benchExercise.id, restSeconds: 150)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: curl)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try syncService.previewTemplateUpdate(forSessionID: session.id)
        #expect(preview?.changedExerciseCount == 1)
        try syncService.applyTemplateUpdate(try #require(preview))

        let updatedExercises = try templateRepository.exercises(in: template.id)
        #expect(updatedExercises.count == 2)
        #expect(Set(updatedExercises.map(\.catalogExerciseUUID)) == Set([bench.remoteUUID, row.remoteUUID]))
    }

    private func makeTemplate(
        name: String,
        exercises: [TemplateExerciseDraft],
        repository: TemplateRepository
    ) throws -> WorkoutTemplate {
        let template = try repository.createTemplate(name: name, notes: "")
        try repository.setExercises(templateID: template.id, drafts: exercises)
        return template
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
