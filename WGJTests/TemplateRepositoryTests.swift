import SwiftData
import Testing
@testable import WGJ

@MainActor
struct TemplateRepositoryTests {
    @Test
    func setCardioBlocksPersistsAndReplacesTemplatePhases() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Hybrid Day", notes: "")
        try repository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
            ]
        )

        #expect(try repository.cardioBlocks(templateID: template.id).map(\.phase) == [.preWorkout, .postWorkout])
        #expect(try repository.cardioBlocks(templateID: template.id).map(\.targetDurationSeconds) == [300, 1200])

        try repository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "bike-2",
                    exerciseNameSnapshot: "Bike Finish",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 900
                ),
            ]
        )

        let refreshedBlocks = try repository.cardioBlocks(templateID: template.id)
        #expect(refreshedBlocks.map(\.phase) == [.postWorkout])
        #expect(refreshedBlocks.first?.exerciseNameSnapshot == "Bike Finish")
        #expect(refreshedBlocks.first?.targetDurationSeconds == 900)
    }

    @Test
    func moveFolderReordersLibraryAndNormalizesSortOrder() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Push")
        try repository.createFolder(name: "Pull")
        try repository.createFolder(name: "Legs")

        let createdFolders = try repository.folders()
        let legsFolder = try #require(createdFolders.first(where: { $0.name == "Legs" }))

        try repository.moveFolder(id: legsFolder.id, toIndex: 0)

        let movedToTop = try repository.folders()
        #expect(movedToTop.map(\.name) == ["Legs", "Push", "Pull"])
        #expect(movedToTop.map(\.sortOrder) == [0, 1, 2])

        try repository.moveFolder(id: legsFolder.id, toIndex: movedToTop.count - 1)

        let movedToBottom = try repository.folders()
        #expect(movedToBottom.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(movedToBottom.map(\.sortOrder) == [0, 1, 2])
    }

    @Test
    func deletingTemplatePreservesCompletedSessionHistoryAndFacts() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-delete-history-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let template = try templateRepository.createTemplate(name: "Push", notes: "")
        try templateRepository.addExercise(templateID: template.id, catalogItem: bench)

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        #expect(try projectionRepository.facts(forSessionID: session.id).count == 1)

        try templateRepository.deleteTemplate(id: template.id)

        #expect(try templateRepository.template(id: template.id) == nil)
        #expect(try sessionRepository.session(id: session.id) != nil)
        #expect(try projectionRepository.facts(forSessionID: session.id).count == 1)
        #expect(try metrics.exerciseOneRepMaxTrend(for: bench.remoteUUID, limit: 8).points.count == 1)
    }

    @Test
    func createTemplateFromCompletedSessionCopiesCardioBlocks() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-copy-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let sourceTemplate = try templateRepository.createTemplate(name: "Source Hybrid", notes: "")
        try templateRepository.setCardioBlocks(
            templateID: sourceTemplate.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "copy-bike-1",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "copy-treadmill-1",
                    exerciseNameSnapshot: "Incline Treadmill Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 1200
                ),
            ]
        )
        try templateRepository.addExercise(templateID: sourceTemplate.id, catalogItem: bench)

        let session = try sessionRepository.createSessionFromTemplate(templateID: sourceTemplate.id)
        try sessionRepository.finishSession(
            sessionID: session.id,
            notes: "Carry this note into the reusable template."
        )

        let savedTemplate = try templateRepository.createTemplate(
            fromSessionID: session.id,
            name: "Saved Hybrid"
        )

        let cardioBlocks = try templateRepository.cardioBlocks(templateID: savedTemplate.id)
        #expect(savedTemplate.notes == "Carry this note into the reusable template.")
        #expect(cardioBlocks.map(\.phase) == [.preWorkout, .postWorkout])
        #expect(cardioBlocks.map(\.targetDurationSeconds) == [300, 1200])
    }

    @Test
    func setExercisesPersistsOrderedExerciseComponents() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let reverseCurl = ExerciseCatalogItem(
            remoteUUID: "template-component-reverse-curl",
            displayName: "Reverse Curl",
            categoryName: "Arms",
            equipmentSummary: "EZ bar",
            isCurated: true,
            sourceName: "seed"
        )
        let wristCurl = ExerciseCatalogItem(
            remoteUUID: "template-component-wrist-curl",
            displayName: "Wrist Curl",
            categoryName: "Arms",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(reverseCurl)
        context.insert(wristCurl)

        let template = try repository.createTemplate(name: "Forearms", notes: "")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: reverseCurl.remoteUUID,
                    exerciseNameSnapshot: reverseCurl.displayName,
                    categorySnapshot: reverseCurl.categoryName,
                    muscleSummarySnapshot: reverseCurl.primaryMuscleNames,
                    targetRepMin: 12,
                    targetRepMax: 15,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 15, targetWeight: 20, loadUnit: .kg, restSeconds: 60),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: reverseCurl),
                        TemplateExerciseComponentDraft(catalogItem: wristCurl),
                    ]
                ),
            ]
        )

        let storedExercise = try #require(try repository.exercises(in: template.id).first)
        let storedComponents = try repository.components(for: storedExercise.id)

        #expect(storedExercise.exerciseNameSnapshot == "Reverse Curl")
        #expect(storedExercise.catalogExerciseUUID == reverseCurl.remoteUUID)
        #expect(storedComponents.map(\.catalogExerciseUUID) == [reverseCurl.remoteUUID, wristCurl.remoteUUID])
        #expect(storedComponents.map(\.exerciseNameSnapshot) == ["Reverse Curl", "Wrist Curl"])
    }

    @Test
    func exercisesLazyNormalizeLegacySingleExerciseIntoOneComponentSlot() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Legacy Template", notes: "")
        let legacyExercise = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "legacy-standing-calf-raise",
            exerciseNameSnapshot: "Standing Calf Raise",
            categorySnapshot: "Legs",
            muscleSummarySnapshot: "Calves",
            targetRepMin: 12,
            targetRepMax: 15,
            restSeconds: 75,
            sortOrder: 0,
            template: template
        )
        legacyExercise.components = nil
        context.insert(legacyExercise)
        try context.save()

        let storedExercise = try #require(try repository.exercises(in: template.id).first)
        let normalizedComponents = try repository.components(for: storedExercise.id)

        #expect(normalizedComponents.count == 1)
        #expect(normalizedComponents.first?.catalogExerciseUUID == "legacy-standing-calf-raise")
        #expect(normalizedComponents.first?.exerciseNameSnapshot == "Standing Calf Raise")
        #expect(storedExercise.exerciseNameSnapshot == "Standing Calf Raise")
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
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
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
