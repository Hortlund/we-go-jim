import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
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

        try waitForProjectedFacts(
            sessionID: session.id,
            expectedCount: 1,
            repository: projectionRepository
        )
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
    func duplicateTemplatePreservesFullTemplateStructureWithFreshIDs() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let press = ExerciseCatalogItem(
            remoteUUID: "template-duplicate-press",
            displayName: "Incline DB Press",
            categoryName: "Chest",
            equipmentSummary: "Dumbbells",
            isCurated: true,
            sourceName: "seed"
        )
        let row = ExerciseCatalogItem(
            remoteUUID: "template-duplicate-row",
            displayName: "Chest Supported Row",
            categoryName: "Back",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        let fly = ExerciseCatalogItem(
            remoteUUID: "template-duplicate-fly",
            displayName: "Cable Fly",
            categoryName: "Chest",
            equipmentSummary: "Cable",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(press)
        context.insert(row)
        context.insert(fly)

        let folder = try repository.createFolder(name: "Upper")
        let supersetID = UUID()
        let source = try repository.createTemplate(
            folderID: folder.id,
            name: "Upper Density",
            notes: "Keep transitions tight."
        )
        try repository.setCardioBlocks(
            templateID: source.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: "template-duplicate-bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: "template-duplicate-walk",
                    exerciseNameSnapshot: "Incline Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Cooldown",
                    targetDurationSeconds: 900
                ),
            ]
        )
        try repository.setExercises(
            templateID: source.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: press.remoteUUID,
                    exerciseNameSnapshot: press.displayName,
                    categorySnapshot: press.categoryName,
                    muscleSummarySnapshot: press.primaryMuscleNames,
                    notes: "Pause at the bottom.",
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 75,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 28,
                            loadUnit: .kg,
                            restSeconds: 75,
                            isWarmup: true,
                            dropStages: [
                                TemplateExerciseDropStageDraft(targetReps: 8, targetWeight: 22, loadUnit: .kg),
                                TemplateExerciseDropStageDraft(targetReps: 10, targetWeight: 18, loadUnit: .kg),
                            ]
                        ),
                    ],
                    components: [
                        TemplateExerciseComponentDraft(catalogItem: press),
                        TemplateExerciseComponentDraft(catalogItem: fly),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .first,
                        roundRestSeconds: 90
                    )
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: row.remoteUUID,
                    exerciseNameSnapshot: row.displayName,
                    categorySnapshot: row.categoryName,
                    muscleSummarySnapshot: row.primaryMuscleNames,
                    notes: "Drive elbows back.",
                    targetRepMin: 8,
                    targetRepMax: 12,
                    restSeconds: 75,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 12, targetWeight: 55, loadUnit: .kg, restSeconds: 75),
                    ],
                    components: [TemplateExerciseComponentDraft(catalogItem: row)],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .second,
                        roundRestSeconds: 90
                    )
                ),
            ]
        )

        let duplicate = try repository.duplicateTemplate(id: source.id, name: "Upper Density Copy")
        let sourceExercises = try repository.exercises(in: source.id)
        let copiedExercises = try repository.exercises(in: duplicate.id)
        let copiedFirstSetDrafts = try repository.setDrafts(for: try #require(copiedExercises.first).id)
        let copiedCardioBlocks = try repository.cardioBlocks(templateID: duplicate.id)
        let sourceCardioBlocks = try repository.cardioBlocks(templateID: source.id)

        #expect(duplicate.id != source.id)
        #expect(duplicate.folderID == folder.id)
        #expect(duplicate.name == "Upper Density Copy")
        #expect(duplicate.notes == "Keep transitions tight.")
        #expect(copiedCardioBlocks.map(\.phase) == [.preWorkout, .postWorkout])
        #expect(copiedCardioBlocks.map(\.targetDurationSeconds) == [300, 900])
        #expect(copiedCardioBlocks.map(\.id) != sourceCardioBlocks.map(\.id))
        #expect(copiedExercises.map(\.id) != sourceExercises.map(\.id))
        #expect(copiedExercises.map(\.exerciseNameSnapshot) == ["Incline DB Press", "Chest Supported Row"])
        #expect(copiedExercises.map(\.notes) == ["Pause at the bottom.", "Drive elbows back."])
        #expect(try repository.components(for: copiedExercises[0].id).map(\.exerciseNameSnapshot) == [
            "Incline DB Press",
            "Cable Fly",
        ])
        #expect(copiedFirstSetDrafts.first?.dropStages.map(\.targetWeight) == [22, 18])
        #expect(copiedExercises[0].supersetGroupID != supersetID)
        #expect(copiedExercises[0].supersetGroupID == copiedExercises[1].supersetGroupID)
        #expect(copiedExercises[0].supersetPosition == .first)
        #expect(copiedExercises[1].supersetPosition == .second)
        #expect(copiedExercises[0].supersetGroup?.roundRestSeconds == 90)
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
    func updatingExerciseToleratesDuplicatePersistedComponentIDs() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-duplicate-component-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let template = try repository.createTemplate(name: "Push", notes: "")
        try repository.setExercises(
            templateID: template.id,
            drafts: [TemplateExerciseDraft(catalogItem: bench)]
        )

        let storedExercise = try #require(try repository.exercises(in: template.id).first)
        let existingComponent = try #require(try repository.components(for: storedExercise.id).first)
        let duplicateComponent = TemplateExerciseComponent(
            id: existingComponent.id,
            templateExerciseID: storedExercise.id,
            catalogExerciseUUID: existingComponent.catalogExerciseUUID,
            exerciseNameSnapshot: existingComponent.exerciseNameSnapshot,
            categorySnapshot: existingComponent.categorySnapshot,
            muscleSummarySnapshot: existingComponent.muscleSummarySnapshot,
            sortOrder: existingComponent.sortOrder + 1,
            templateExercise: storedExercise
        )
        context.insert(duplicateComponent)
        storedExercise.components?.append(duplicateComponent)
        try context.save()

        var draft = TemplateExerciseDraft(model: storedExercise, preferredLoadUnit: .kg)
        draft.notes = "Updated without crashing."

        try repository.setExercises(templateID: template.id, drafts: [draft])

        let refreshedExercise = try #require(try repository.exercises(in: template.id).first)
        #expect(refreshedExercise.notes == "Updated without crashing.")
        #expect(try repository.components(for: refreshedExercise.id).map(\.id) == [existingComponent.id])
    }

    @Test
    func setExercisesPersistsSupersetPairsAndDropsetStages() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let inclinePress = ExerciseCatalogItem(
            remoteUUID: "template-superset-incline-press",
            displayName: "Incline DB Press",
            categoryName: "Chest",
            equipmentSummary: "Dumbbells",
            isCurated: true,
            sourceName: "seed"
        )
        let chestSupportedRow = ExerciseCatalogItem(
            remoteUUID: "template-superset-supported-row",
            displayName: "Chest Supported Row",
            categoryName: "Back",
            equipmentSummary: "Machine",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(inclinePress)
        context.insert(chestSupportedRow)

        let supersetID = UUID()
        let template = try repository.createTemplate(name: "Push Pull", notes: "")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: inclinePress.remoteUUID,
                    exerciseNameSnapshot: inclinePress.displayName,
                    categorySnapshot: inclinePress.categoryName,
                    muscleSummarySnapshot: inclinePress.primaryMuscleNames,
                    targetRepMin: 8,
                    targetRepMax: 10,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 28,
                            loadUnit: .kg,
                            restSeconds: 60,
                            dropStages: [
                                TemplateExerciseDropStageDraft(targetReps: 8, targetWeight: 22, loadUnit: .kg),
                                TemplateExerciseDropStageDraft(targetReps: 10, targetWeight: 18, loadUnit: .kg),
                                TemplateExerciseDropStageDraft(targetReps: 12, targetWeight: 14, loadUnit: .kg),
                            ]
                        ),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .first,
                        roundRestSeconds: 75
                    )
                ),
                TemplateExerciseDraft(
                    catalogExerciseUUID: chestSupportedRow.remoteUUID,
                    exerciseNameSnapshot: chestSupportedRow.displayName,
                    categorySnapshot: chestSupportedRow.categoryName,
                    muscleSummarySnapshot: chestSupportedRow.primaryMuscleNames,
                    targetRepMin: 8,
                    targetRepMax: 12,
                    restSeconds: 60,
                    setDrafts: [
                        TemplateExerciseSetDraft(targetReps: 12, targetWeight: 55, loadUnit: .kg, restSeconds: 60),
                    ],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetID,
                        position: .second,
                        roundRestSeconds: 75
                    )
                ),
            ]
        )

        let exercises = try repository.exercises(in: template.id)
        let firstExercise = try #require(exercises.first)
        let secondExercise = try #require(exercises.last)
        let firstSetDrafts = try repository.setDrafts(for: firstExercise.id)

        #expect(firstExercise.supersetGroupID == supersetID)
        #expect(secondExercise.supersetGroupID == supersetID)
        #expect(firstExercise.supersetPosition == .first)
        #expect(secondExercise.supersetPosition == .second)
        #expect(firstExercise.supersetGroup?.roundRestSeconds == 75)
        #expect(secondExercise.supersetGroup?.roundRestSeconds == 75)
        #expect(firstSetDrafts.count == 1)
        #expect(firstSetDrafts[0].dropStages.map(\.targetWeight) == [22, 18, 14])
        #expect(firstSetDrafts[0].dropStages.map(\.targetReps) == [8, 10, 12])
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

    @Test
    func updateTemplateSkipsTimestampBumpWhenNameAndNotesAreUnchanged() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Push Day", notes: "Stable notes")
        let originalUpdatedAt = template.updatedAt

        try repository.updateTemplate(id: template.id, name: "Push Day", notes: "Stable notes")

        let refreshedTemplate = try #require(try repository.template(id: template.id))
        #expect(refreshedTemplate.updatedAt == originalUpdatedAt)
    }

    @Test
    func updateTemplateContentsPreservesTemplateExerciseIdentityAndLeavesActiveDraftUntouched() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let activeWorkoutRepository = ActiveWorkoutDraftRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-update-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let row = ExerciseCatalogItem(
            remoteUUID: "template-update-row",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(row)

        let template = try repository.createTemplate(name: "Push", notes: "Original reusable notes")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: bench.remoteUUID,
                    exerciseNameSnapshot: bench.displayName,
                    categorySnapshot: bench.categoryName,
                    muscleSummarySnapshot: bench.primaryMuscleNames,
                    notes: "Pause on the chest.",
                    targetRepMin: 6,
                    targetRepMax: 8,
                    restSeconds: 150,
                    setDrafts: [
                        TemplateExerciseSetDraft(
                            targetReps: 10,
                            targetWeight: 60,
                            loadUnit: .kg,
                            restSeconds: 150,
                            isWarmup: true
                        ),
                        TemplateExerciseSetDraft(
                            targetReps: 8,
                            targetWeight: 100,
                            loadUnit: .kg,
                            restSeconds: 150
                        ),
                        TemplateExerciseSetDraft(
                            targetReps: 6,
                            targetWeight: 110,
                            loadUnit: .kg,
                            restSeconds: 150
                        ),
                    ],
                    components: [TemplateExerciseComponentDraft(catalogItem: bench)]
                ),
            ]
        )

        let storedExercise = try #require(try repository.exercises(in: template.id).first)
        let storedSetDrafts = try repository.setDrafts(for: storedExercise.id)

        let draftSession = try activeWorkoutRepository.createSessionFromTemplate(templateID: template.id)
        let activeDraftExercise = try #require(try activeWorkoutRepository.sessionExercises(sessionID: draftSession.id).first)
        let originalActiveSetDrafts = try activeWorkoutRepository.setDrafts(sessionExerciseID: activeDraftExercise.id)
        let originalActiveNotes = activeDraftExercise.notes
        let originalActiveRest = activeDraftExercise.restSeconds

        var updatedPrimaryDraft = TemplateExerciseDraft(model: storedExercise, preferredLoadUnit: .kg)
        updatedPrimaryDraft.notes = "Touch-and-go only on the final set."
        updatedPrimaryDraft.restSeconds = 165
        let appendedSetDraft = TemplateExerciseSetDraft(
            targetReps: 5,
            targetWeight: 115,
            loadUnit: .kg,
            restSeconds: 165
        )
        updatedPrimaryDraft.setDrafts = [
            storedSetDrafts[1],
            storedSetDrafts[0],
            storedSetDrafts[2],
            appendedSetDraft,
        ]

        var addedExerciseDraft = TemplateExerciseDraft(catalogItem: row, preferredLoadUnit: .kg)
        addedExerciseDraft.notes = "Keep the torso rigid."
        addedExerciseDraft.targetRepMin = 8
        addedExerciseDraft.targetRepMax = 10
        addedExerciseDraft.restSeconds = 120

        try repository.updateTemplateContents(
            id: template.id,
            name: "Push Updated",
            notes: "Updated reusable notes",
            exerciseDrafts: [updatedPrimaryDraft, addedExerciseDraft],
            cardioDrafts: []
        )

        let refreshedTemplate = try #require(try repository.template(id: template.id))
        let refreshedExercises = try repository.exercises(in: template.id)
        let refreshedPrimaryExercise = try #require(refreshedExercises.first)
        let refreshedPrimarySetDrafts = try repository.setDrafts(for: refreshedPrimaryExercise.id)
        let unchangedActiveExercise = try #require(
            try activeWorkoutRepository.sessionExercises(sessionID: draftSession.id).first
        )
        let unchangedActiveSetDrafts = try activeWorkoutRepository.setDrafts(
            sessionExerciseID: unchangedActiveExercise.id
        )

        #expect(refreshedTemplate.name == "Push Updated")
        #expect(refreshedTemplate.notes == "Updated reusable notes")
        #expect(refreshedExercises.count == 2)
        #expect(refreshedPrimaryExercise.id == storedExercise.id)
        #expect(refreshedExercises[1].id == addedExerciseDraft.id)
        #expect(refreshedPrimarySetDrafts.map(\.id) == [
            storedSetDrafts[1].id,
            storedSetDrafts[0].id,
            storedSetDrafts[2].id,
            appendedSetDraft.id,
        ])
        #expect(unchangedActiveExercise.templateExerciseID == storedExercise.id)
        #expect(unchangedActiveExercise.notes == originalActiveNotes)
        #expect(unchangedActiveExercise.restSeconds == originalActiveRest)
        #expect(unchangedActiveSetDrafts == originalActiveSetDrafts)
    }

    @Test
    func updateExerciseRestSecondsSkipsNoOpWhenExerciseAlreadyMatchesDefaultRest() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-rest-noop-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let template = try repository.createTemplate(name: "Push", notes: "")
        try repository.addExercise(templateID: template.id, catalogItem: bench)

        let exercise = try #require(try repository.exercises(in: template.id).first)
        let originalUpdatedAt = exercise.updatedAt
        let originalSetTimestamps = try repository.setDrafts(for: exercise.id)
        let storedSetUpdatedAt = (exercise.prescribedSets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        try repository.updateExerciseRestSeconds(templateExerciseID: exercise.id, restSeconds: exercise.restSeconds)

        let refreshedExercise = try #require(
            try repository.exercises(in: template.id).first(where: { $0.id == exercise.id })
        )
        let refreshedSetTimestamps = (refreshedExercise.prescribedSets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        #expect(refreshedExercise.updatedAt == originalUpdatedAt)
        #expect(try repository.setDrafts(for: exercise.id) == originalSetTimestamps)
        #expect(refreshedSetTimestamps == storedSetUpdatedAt)
    }

    @Test
    func updateTemplateContentsSkipsNoOpWithoutTouchingTemplateOrPendingCloudExport() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)

        let bench = ExerciseCatalogItem(
            remoteUUID: "template-editor-noop-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let template = try repository.createTemplate(name: "Push", notes: "No-op baseline")
        try repository.addExercise(templateID: template.id, catalogItem: bench)
        let exportFinishedAt = Date()
        _ = tracker.recordCloudEvent(
            CloudSyncEventSummary(
                type: .export,
                status: .succeeded,
                storeIdentifier: "UserData",
                startedAt: exportFinishedAt.addingTimeInterval(-1),
                endedAt: exportFinishedAt,
                error: nil
            )
        )

        let storedTemplate = try #require(try repository.template(id: template.id))
        let originalUpdatedAt = storedTemplate.updatedAt
        let exerciseDrafts = try repository.exercises(in: template.id).map {
            TemplateExerciseDraft(model: $0, preferredLoadUnit: .kg)
        }
        let cardioDrafts = try repository.cardioBlocks(templateID: template.id).map(TemplateCardioBlockDraft.init(model:))

        try repository.updateTemplateContents(
            id: template.id,
            name: storedTemplate.name,
            notes: storedTemplate.notes,
            exerciseDrafts: exerciseDrafts,
            cardioDrafts: cardioDrafts
        )

        let refreshedTemplate = try #require(try repository.template(id: template.id))
        #expect(refreshedTemplate.updatedAt == originalUpdatedAt)
        #expect(tracker.currentSnapshot().state == .caughtUp)
        #expect(!tracker.currentSnapshot().hasPendingExport)
    }

    @Test
    func templateDetailDraftStoreDoesNotPersistUntilExplicitSave() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let row = ExerciseCatalogItem(
            remoteUUID: "template-detail-draft-row",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(row)

        let template = try repository.createTemplate(name: "Pull", notes: "")
        try repository.addExercise(templateID: template.id, catalogItem: row)
        let exercise = try #require(try repository.exercises(in: template.id).first)
        let originalRange = RepRangeDraft(min: exercise.targetRepMin, max: exercise.targetRepMax)
        let originalRest = exercise.restSeconds

        var draftStore = TemplateDetailDraftStore()
        draftStore.load(exercises: try repository.exercises(in: template.id))
        draftStore.updateRepRange(exerciseID: exercise.id, min: 8, max: 12)
        draftStore.updateRest(exerciseID: exercise.id, restSeconds: 90)

        let unchangedExercise = try #require(try repository.exercises(in: template.id).first)
        #expect(RepRangeDraft(min: unchangedExercise.targetRepMin, max: unchangedExercise.targetRepMax) == originalRange)
        #expect(unchangedExercise.restSeconds == originalRest)

        try draftStore.save(templateID: template.id, repository: repository)

        let refreshedExercise = try #require(try repository.exercises(in: template.id).first)
        #expect(refreshedExercise.targetRepMin == 8)
        #expect(refreshedExercise.targetRepMax == 12)
        #expect(refreshedExercise.restSeconds == 90)
    }

    @Test
    func saveSetDraftsSkipsNoOpWhenIncomingDraftsMatchPersistedSets() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let row = ExerciseCatalogItem(
            remoteUUID: "template-save-noop-row",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(row)

        let template = try repository.createTemplate(name: "Pull", notes: "")
        try repository.addExercise(templateID: template.id, catalogItem: row)

        let exercise = try #require(try repository.exercises(in: template.id).first)
        let persistedDrafts = try repository.setDrafts(for: exercise.id)
        let originalUpdatedAt = exercise.updatedAt
        let originalSetUpdatedAt = (exercise.prescribedSets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        try repository.saveSetDrafts(templateExerciseID: exercise.id, drafts: persistedDrafts)

        let refreshedExercise = try #require(
            try repository.exercises(in: template.id).first(where: { $0.id == exercise.id })
        )
        let refreshedSetUpdatedAt = (refreshedExercise.prescribedSets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        #expect(refreshedExercise.updatedAt == originalUpdatedAt)
        #expect(refreshedSetUpdatedAt == originalSetUpdatedAt)
    }

    @Test
    func ensureDefaultSetPlansIsNoOpWhenTemplateAlreadyHasNormalizedSets() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let squat = ExerciseCatalogItem(
            remoteUUID: "template-default-plan-squat",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(squat)

        let template = try repository.createTemplate(name: "Leg Day", notes: "")
        try repository.addExercise(templateID: template.id, catalogItem: squat)

        let refreshedTemplate = try #require(try repository.template(id: template.id))
        let originalUpdatedAt = refreshedTemplate.updatedAt

        try repository.ensureDefaultSetPlans(templateID: template.id)

        let afterEnsure = try #require(try repository.template(id: template.id))
        #expect(afterEnsure.updatedAt == originalUpdatedAt)
    }

    @Test
    func generatedDefaultSetsUseExerciseRestSeconds() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Rest Canonical", notes: "")
        try repository.setExercises(
            templateID: template.id,
            drafts: [
                TemplateExerciseDraft(
                    catalogExerciseUUID: "template-rest-curl",
                    exerciseNameSnapshot: "EZ Bar Curl",
                    categorySnapshot: "Biceps",
                    muscleSummarySnapshot: "Biceps",
                    restSeconds: 90,
                    setDrafts: []
                ),
            ]
        )

        let exercise = try #require(try repository.exercises(in: template.id).first)
        let drafts = try repository.setDrafts(for: exercise.id)

        #expect(drafts.count == 3)
        #expect(drafts.allSatisfy { $0.restSeconds == 90 })
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
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func waitForProjectedFacts(
        sessionID: UUID,
        expectedCount: Int,
        repository: HistoryProjectionRepository,
        timeout: TimeInterval = 1.0
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? repository.facts(forSessionID: sessionID).count) == expectedCount {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        #expect(try repository.facts(forSessionID: sessionID).count == expectedCount)
    }
}
