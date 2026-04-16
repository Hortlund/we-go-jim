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

        let bench = catalogItem(
            remoteUUID: "sync-bench-1",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
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
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 102.5
        drafts[0].actualReps = 7
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        #expect(try syncService.previewTemplateUpdate(forSessionID: session.id) == nil)
    }

    @Test
    func previewIncludesEditedSettingDetailsForRepRangeRestAndSetLayout() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let row = catalogItem(
            remoteUUID: "sync-row-1",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell"
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
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        try sessionRepository.updateExerciseRepRange(sessionExerciseID: exercise.id, minReps: 6, maxReps: 8)
        try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 150)
        try sessionRepository.updateExerciseNotes(
            sessionExerciseID: exercise.id,
            notes: "Drive elbows toward the hips and stay braced."
        )
        try sessionRepository.addSet(sessionExerciseID: exercise.id)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        #expect(preview.addedExercises.isEmpty)
        #expect(preview.removedExercises.isEmpty)
        #expect(preview.reorderedExercises.isEmpty)
        #expect(preview.editedExercises.count == 1)
        #expect(preview.summary.contains("edited exercise"))

        let edited = try #require(preview.editedExercises.first)
        #expect(edited.changes.contains(where: { $0.contains("Rep range") }))
        #expect(edited.changes.contains(where: { $0.contains("Rest") }))
        #expect(edited.changes.contains(where: { $0.contains("Notes") }))
        #expect(edited.changes.contains(where: { $0.contains("Set count") }))
    }

    @Test
    func previewDoesNotMutateTemplateStructureBeforeApply() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = catalogItem(
            remoteUUID: "sync-keep-bench-structure",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        context.insert(bench)

        let template = try makeTemplate(
            name: "Keep Structure",
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
                        TemplateExerciseSetDraft(
                            targetReps: 6,
                            targetWeight: 100,
                            loadUnit: .kg,
                            restSeconds: 120,
                            isWarmup: true
                        ),
                    ]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        try sessionRepository.addSet(sessionExerciseID: exercise.id)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        let editedExercise = try #require(preview.editedExercises.first)
        #expect(editedExercise.changes.contains(where: { $0.contains("Set count") }))
        #expect(preview.mutation.exercises.first?.setDrafts.count == 2)

        let templateExercise = try #require(try templateRepository.exercises(in: template.id).first)
        let templateSetDrafts = try templateRepository.setDrafts(for: templateExercise.id)
        #expect(templateSetDrafts.count == 1)
    }

    @Test
    func previewAndApplyTemplateUpdateHandleWorkoutNoteOnlyChanges() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = catalogItem(
            remoteUUID: "sync-notes-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        context.insert(bench)

        let template = try makeTemplate(
            name: "Push",
            exercises: [
                draft(for: bench, minReps: 6, maxReps: 8, restSeconds: 120, targetWeight: 100),
            ],
            repository: templateRepository
        )
        template.notes = "Original reusable note."
        try context.save()

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        try sessionRepository.updateSessionNotes(
            sessionID: session.id,
            notes: "Updated reusable note from the workout."
        )
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        #expect(preview.editedWorkoutNotes?.changes.contains("Notes updated") == true)
        #expect(preview.editedExercises.isEmpty)
        #expect(preview.addedExercises.isEmpty)
        #expect(preview.removedExercises.isEmpty)
        #expect(preview.summary.contains("updated workout notes"))

        try syncService.applyTemplateUpdate(preview)

        let updatedTemplate = try #require(try templateRepository.template(id: template.id))
        #expect(updatedTemplate.notes == "Updated reusable note from the workout.")
    }

    @Test
    func previewTreatsTemplateSwapAsRemoveAddAndReorder() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = catalogItem(
            remoteUUID: "sync-bench-structure",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        let row = catalogItem(
            remoteUUID: "sync-row-structure",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell"
        )
        let squat = catalogItem(
            remoteUUID: "sync-squat-structure",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell"
        )
        let curl = catalogItem(
            remoteUUID: "sync-curl-structure",
            displayName: "Hammer Curl",
            categoryName: "Arms",
            equipmentSummary: "Dumbbell"
        )
        context.insert(bench)
        context.insert(row)
        context.insert(squat)
        context.insert(curl)

        let template = try makeTemplate(
            name: "Full Body",
            exercises: [
                draft(for: bench, minReps: 6, maxReps: 8, restSeconds: 120, targetWeight: 100),
                draft(for: row, minReps: 8, maxReps: 10, restSeconds: 120, targetWeight: 80),
                draft(for: squat, minReps: 5, maxReps: 8, restSeconds: 180, targetWeight: 140),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        let benchExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == bench.remoteUUID }))
        let rowExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == row.remoteUUID }))
        let squatExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == squat.remoteUUID }))

        try sessionRepository.removeExercise(sessionID: session.id, sessionExerciseID: benchExercise.id)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: curl)

        rowExercise.sortOrder = 1
        squatExercise.sortOrder = 0
        try context.save()
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        #expect(preview.addedExercises.map(\.catalogExerciseUUID) == [curl.remoteUUID])
        #expect(preview.removedExercises.map(\.catalogExerciseUUID) == [bench.remoteUUID])
        #expect(preview.reorderedExercises.count == 2)
        #expect(preview.reorderedExercises.contains(where: { $0.catalogExerciseUUID == row.remoteUUID }))
        #expect(preview.reorderedExercises.contains(where: { $0.catalogExerciseUUID == squat.remoteUUID }))
    }

    @Test
    func previewIgnoresSessionOnlyExerciseComponentOverride() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let reverseCurl = catalogItem(
            remoteUUID: "sync-component-reverse-curl",
            displayName: "Reverse Curl",
            categoryName: "Arms",
            equipmentSummary: "EZ bar"
        )
        let wristCurl = catalogItem(
            remoteUUID: "sync-component-wrist-curl",
            displayName: "Wrist Curl",
            categoryName: "Arms",
            equipmentSummary: "Barbell"
        )
        context.insert(reverseCurl)
        context.insert(wristCurl)

        let template = try makeTemplate(
            name: "Forearms",
            exercises: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: reverseCurl.remoteUUID,
                    exerciseNameSnapshot: reverseCurl.displayName,
                    categorySnapshot: reverseCurl.categoryName,
                    muscleSummarySnapshot: reverseCurl.primaryMuscleNames,
                    targetRepMin: 10,
                    targetRepMax: 12,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 12, targetWeight: 20, loadUnit: .kg, restSeconds: 60),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: reverseCurl),
                        TemplateExerciseComponentDraft(catalogItem: wristCurl),
                    ]
                ),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        session.startedAt = Date(timeIntervalSince1970: 1_000)
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        exercise.catalogExerciseUUID = wristCurl.remoteUUID
        exercise.exerciseNameSnapshot = wristCurl.displayName
        exercise.categorySnapshot = wristCurl.categoryName
        exercise.muscleSummarySnapshot = wristCurl.primaryMuscleNames
        try context.save()

        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 22.5
        drafts[0].actualReps = 12
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        #expect(try syncService.previewTemplateUpdate(forSessionID: session.id) == nil)

        let templateExercise = try #require(try templateRepository.exercises(in: template.id).first)
        #expect(try templateRepository.components(for: templateExercise.id).map(\.catalogExerciseUUID) == [
            reverseCurl.remoteUUID,
            wristCurl.remoteUUID,
        ])
    }

    @Test
    func previewAndApplyTemplateUpdateHandleCardioPhaseChanges() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bike = catalogItem(
            remoteUUID: "sync-cardio-bike",
            displayName: "Bike",
            categoryName: "Cardio",
            equipmentSummary: "Bike"
        )
        let treadmill = catalogItem(
            remoteUUID: "sync-cardio-treadmill",
            displayName: "Incline Treadmill Walk",
            categoryName: "Cardio",
            equipmentSummary: "Treadmill"
        )
        let bench = catalogItem(
            remoteUUID: "sync-cardio-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        context.insert(bike)
        context.insert(treadmill)
        context.insert(bench)

        let template = try makeTemplate(
            name: "Hybrid",
            exercises: [
                draft(for: bench, minReps: 6, maxReps: 8, restSeconds: 120, targetWeight: 100),
            ],
            repository: templateRepository
        )
        try templateRepository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: bike.remoteUUID,
                    exerciseNameSnapshot: bike.displayName,
                    categorySnapshot: bike.categoryName,
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
            ]
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let preCardio = try #require(try sessionRepository.sessionCardioBlocks(sessionID: session.id).first)
        preCardio.catalogExerciseUUID = treadmill.remoteUUID
        preCardio.exerciseNameSnapshot = treadmill.displayName
        preCardio.categorySnapshot = treadmill.categoryName
        preCardio.muscleSummarySnapshot = "Cooldown"
        preCardio.targetDurationSeconds = 480

        let postCardio = WorkoutSessionCardioBlock(
            sessionID: session.id,
            phase: .postWorkout,
            catalogExerciseUUID: bike.remoteUUID,
            exerciseNameSnapshot: bike.displayName,
            categorySnapshot: bike.categoryName,
            muscleSummarySnapshot: "Cooldown",
            targetDurationSeconds: 1200,
            isCompleted: false,
            session: session
        )
        context.insert(postCardio)
        session.cardioBlocks = [preCardio, postCardio]
        try context.save()
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        #expect(preview.addedCardioBlocks.map(\.phase) == [.postWorkout])
        #expect(preview.editedCardioBlocks.map(\.phase) == [.preWorkout])
        #expect(preview.removedCardioBlocks.isEmpty)

        try syncService.applyTemplateUpdate(preview)

        let updatedCardio = try templateRepository.cardioBlocks(templateID: template.id)
        #expect(updatedCardio.map(\.phase) == [.preWorkout, .postWorkout])
        #expect(updatedCardio.map(\.exerciseNameSnapshot) == ["Incline Treadmill Walk", "Bike"])
        #expect(updatedCardio.map(\.targetDurationSeconds) == [480, 1200])
    }

    @Test
    func applyTemplateUpdateKeepsActualLogsOutOfTemplateTargets() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let squat = catalogItem(
            remoteUUID: "sync-squat-targets",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell"
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
        let exercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 210)
        try sessionRepository.updateExerciseNotes(
            sessionExerciseID: exercise.id,
            notes: "Sit back into the heels before each rep."
        )
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].actualWeight = 165
        drafts[1].actualReps = 6
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        try syncService.applyTemplateUpdate(preview)

        let templateExercise = try #require(try templateRepository.exercises(in: template.id).first)
        let updatedSetDrafts = try templateRepository.setDrafts(for: templateExercise.id)

        #expect(templateExercise.restSeconds == 210)
        #expect(templateExercise.notes == "Sit back into the heels before each rep.")
        #expect(updatedSetDrafts[1].targetWeight == 160)
        #expect(updatedSetDrafts[1].targetReps == 5)
    }

    @Test
    func applyTemplateUpdateMutatesRosterAndPreservesMatchedExerciseIdentity() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = catalogItem(
            remoteUUID: "sync-bench-apply",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        let row = catalogItem(
            remoteUUID: "sync-row-apply",
            displayName: "Seated Row",
            categoryName: "Back",
            equipmentSummary: "Cable"
        )
        let curl = catalogItem(
            remoteUUID: "sync-curl-apply",
            displayName: "Hammer Curl",
            categoryName: "Arms",
            equipmentSummary: "Dumbbell"
        )
        context.insert(bench)
        context.insert(row)
        context.insert(curl)

        let template = try makeTemplate(
            name: "Upper",
            exercises: [
                draft(for: bench, minReps: 6, maxReps: 8, restSeconds: 120, targetWeight: 100),
                draft(for: row, minReps: 8, maxReps: 10, restSeconds: 90, targetWeight: 60),
            ],
            repository: templateRepository
        )
        let originalExercises = try templateRepository.exercises(in: template.id)
        let originalRowID = try #require(originalExercises.first(where: { $0.catalogExerciseUUID == row.remoteUUID })).id

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        let benchExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == bench.remoteUUID }))
        let rowExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == row.remoteUUID }))

        try sessionRepository.removeExercise(sessionID: session.id, sessionExerciseID: benchExercise.id)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: curl)
        try sessionRepository.updateExerciseRest(sessionExerciseID: rowExercise.id, restSeconds: 150)

        let refreshedExercises = try sessionRepository.sessionExercises(sessionID: session.id)
        let curlExercise = try #require(refreshedExercises.first(where: { $0.catalogExerciseUUID == curl.remoteUUID }))
        rowExercise.sortOrder = 0
        curlExercise.sortOrder = 1
        try context.save()
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        try syncService.applyTemplateUpdate(preview)

        let updatedExercises = try templateRepository.exercises(in: template.id)
        #expect(updatedExercises.map(\.catalogExerciseUUID) == [row.remoteUUID, curl.remoteUUID])
        let updatedRow = try #require(updatedExercises.first(where: { $0.catalogExerciseUUID == row.remoteUUID }))
        #expect(updatedRow.id == originalRowID)
        #expect(updatedRow.restSeconds == 150)
    }

    @Test
    func applyTemplateUpdatePreservesMatchedExerciseOrderChanges() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let syncService = WorkoutTemplateSyncService(modelContext: context)

        let bench = catalogItem(
            remoteUUID: "sync-bench-order",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell"
        )
        let row = catalogItem(
            remoteUUID: "sync-row-order",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell"
        )
        context.insert(bench)
        context.insert(row)

        let template = try makeTemplate(
            name: "Push Pull",
            exercises: [
                draft(for: bench, minReps: 6, maxReps: 8, restSeconds: 120, targetWeight: 100),
                draft(for: row, minReps: 8, maxReps: 10, restSeconds: 120, targetWeight: 80),
            ],
            repository: templateRepository
        )

        let session = try sessionRepository.createSessionFromTemplate(templateID: template.id)
        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        let benchExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == bench.remoteUUID }))
        let rowExercise = try #require(exercises.first(where: { $0.catalogExerciseUUID == row.remoteUUID }))
        benchExercise.sortOrder = 1
        rowExercise.sortOrder = 0
        try context.save()
        try sessionRepository.finishSession(sessionID: session.id)

        let preview = try #require(try syncService.previewTemplateUpdate(forSessionID: session.id))
        try syncService.applyTemplateUpdate(preview)

        let updatedExercises = try templateRepository.exercises(in: template.id)
        #expect(updatedExercises.map(\.catalogExerciseUUID) == [row.remoteUUID, bench.remoteUUID])
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

    private func draft(
        for item: ExerciseCatalogItem,
        minReps: Int?,
        maxReps: Int?,
        restSeconds: Int,
        targetWeight: Double
    ) -> TemplateExerciseDraft {
        TemplateExerciseDraft(
            catalogExerciseUUID: item.remoteUUID,
            exerciseNameSnapshot: item.displayName,
            categorySnapshot: item.categoryName,
            muscleSummarySnapshot: item.primaryMuscleNames,
            targetRepMin: minReps,
            targetRepMax: maxReps,
            restSeconds: restSeconds,
            setDrafts: [
                TemplateExerciseSetDraft(
                    targetReps: minReps,
                    targetWeight: targetWeight,
                    loadUnit: .kg,
                    restSeconds: restSeconds,
                    isWarmup: true
                ),
            ]
        )
    }

    private func catalogItem(
        remoteUUID: String,
        displayName: String,
        categoryName: String,
        equipmentSummary: String
    ) -> ExerciseCatalogItem {
        ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            isCurated: true,
            sourceName: "seed"
        )
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
