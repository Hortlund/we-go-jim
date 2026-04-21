import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct ActiveWorkoutDraftRepositoryTests {
    @Test
    func createEmptySessionStartsLocalDraft() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let session = try repository.createEmptySession(name: "Push Day")

        #expect(session.name == "Push Day")
        #expect(try repository.activeSession()?.id == session.id)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    }

    @Test
    func createSessionFromTemplateCopiesTemplateExercisesIntoDrafts() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "template-bench-1",
            displayName: "Bench Press",
            equipmentSummary: "Barbell",
            context: context
        )

        let template = try templateRepository.createTemplate(name: "Push A", notes: "Heavy")
        try templateRepository.setCardioBlocks(
            templateID: template.id,
            drafts: [
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: item.remoteUUID,
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Warmup",
                    targetDurationSeconds: 300
                ),
            ]
        )
        try templateRepository.addExercise(templateID: template.id, catalogItem: item)
        let templateExercise = try #require(try templateRepository.exercises(in: template.id).first)
        try templateRepository.updateExerciseRepRange(
            templateExerciseID: templateExercise.id,
            minReps: 6,
            maxReps: 8
        )
        try templateRepository.updateExerciseRestSeconds(
            templateExerciseID: templateExercise.id,
            restSeconds: 150
        )
        try templateRepository.updateExerciseNotes(
            templateExerciseID: templateExercise.id,
            notes: "Pause on the chest and keep feet planted."
        )

        var templateSetDrafts = try templateRepository.setDrafts(for: templateExercise.id)
        templateSetDrafts[0].targetReps = 8
        templateSetDrafts[0].targetWeight = 225
        templateSetDrafts[0].loadUnit = .lb
        templateSetDrafts[1].isLocked = true
        try templateRepository.saveSetDrafts(
            templateExerciseID: templateExercise.id,
            drafts: templateSetDrafts
        )

        let draftSession = try repository.createSessionFromTemplate(templateID: template.id)
        let cardioBlocks = try repository.cardioBlocks(sessionID: draftSession.id)
        let draftExercise = try #require(try repository.sessionExercises(sessionID: draftSession.id).first)
        let draftSetDrafts = try repository.setDrafts(sessionExerciseID: draftExercise.id)

        #expect(draftSession.templateID == template.id)
        #expect(draftSession.notes == "Heavy")
        #expect(cardioBlocks.map(\.phase) == [.preWorkout])
        #expect(cardioBlocks.first?.targetDurationSeconds == 300)
        #expect(draftExercise.exerciseNameSnapshot == "Bench Press")
        #expect(draftExercise.notes == "Pause on the chest and keep feet planted.")
        #expect(draftExercise.targetRepMin == 6)
        #expect(draftExercise.targetRepMax == 8)
        #expect(draftExercise.restSeconds == 150)
        #expect(draftSetDrafts.count == 3)
        #expect(draftSetDrafts[0].targetReps == 8)
        #expect(draftSetDrafts[0].targetWeight == 225)
        #expect(draftSetDrafts[0].targetLoadUnit == .lb)
        #expect(draftSetDrafts[1].isLocked)
    }

    @Test
    func overrideExerciseComponentUsesLoggedChoiceForNextDraftRotation() throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let repository = ActiveWorkoutDraftRepository(modelContext: context)
        let completedRepository = WorkoutSessionRepository(modelContext: context)

        let reverseCurl = makeCatalogItem(
            remoteUUID: "draft-override-reverse-curl",
            displayName: "Reverse Curl",
            equipmentSummary: "EZ bar",
            context: context
        )
        let wristCurl = makeCatalogItem(
            remoteUUID: "draft-override-wrist-curl",
            displayName: "Wrist Curl",
            equipmentSummary: "Barbell",
            context: context
        )

        let template = try templateRepository.createTemplate(name: "Forearms", notes: "")
        try templateRepository.setExercises(
            templateID: template.id,
            drafts: [
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
            ]
        )

        let firstDraftSession = try repository.createSessionFromTemplate(templateID: template.id)
        firstDraftSession.startedAt = Date(timeIntervalSince1970: 1_000)
        try context.save()

        let firstExercise = try #require(try repository.sessionExercises(sessionID: firstDraftSession.id).first)
        let firstComponents = try repository.components(sessionExerciseID: firstExercise.id)
        #expect(firstExercise.catalogExerciseUUID == reverseCurl.remoteUUID)
        #expect(firstExercise.templateExerciseID != nil)
        #expect(firstComponents.map(\.catalogExerciseUUID) == [reverseCurl.remoteUUID, wristCurl.remoteUUID])

        let overrideComponent = try #require(
            firstComponents.first(where: { $0.catalogExerciseUUID == wristCurl.remoteUUID })
        )
        try repository.overrideExerciseComponent(
            sessionExerciseID: firstExercise.id,
            componentID: overrideComponent.id
        )

        let overriddenExercise = try #require(try repository.sessionExercises(sessionID: firstDraftSession.id).first)
        #expect(overriddenExercise.catalogExerciseUUID == wristCurl.remoteUUID)
        #expect(overriddenExercise.exerciseNameSnapshot == wristCurl.displayName)

        var drafts = try repository.setDrafts(sessionExerciseID: overriddenExercise.id)
        drafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: overriddenExercise.id, drafts: drafts)

        let completedSessionID = try repository.finishSession(sessionID: firstDraftSession.id)
        let completedExercise = try #require(
            try completedRepository.sessionExercises(sessionID: completedSessionID).first
        )
        #expect(completedExercise.catalogExerciseUUID == wristCurl.remoteUUID)
        #expect(completedExercise.exerciseNameSnapshot == wristCurl.displayName)
        #expect(completedExercise.templateExerciseID == firstExercise.templateExerciseID)

        let secondDraftSession = try repository.createSessionFromTemplate(templateID: template.id)
        let secondExercise = try #require(try repository.sessionExercises(sessionID: secondDraftSession.id).first)
        #expect(secondExercise.catalogExerciseUUID == reverseCurl.remoteUUID)
        #expect(secondExercise.templateExerciseID == firstExercise.templateExerciseID)
    }

    @Test
    func draftEditsPersistWithoutCreatingCompletedWorkout() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "edit-row-1",
            displayName: "Barbell Row",
            equipmentSummary: "Barbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Pull Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].targetWeight = 80
        drafts[0].targetReps = 10
        drafts[0].actualWeight = 85
        drafts[0].actualReps = 8
        drafts[0].actualLoadUnit = .kg
        drafts[0].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
        try repository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: 150)
        try repository.updateExerciseRepRange(sessionExerciseID: exercise.id, minReps: 8, maxReps: 12)
        try repository.updateExerciseNotes(
            sessionExerciseID: exercise.id,
            notes: "Use straps only on the top set."
        )

        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedDrafts = try repository.setDrafts(sessionExerciseID: refreshedExercise.id)

        #expect(refreshedExercise.restSeconds == 150)
        #expect(refreshedExercise.notes == "Use straps only on the top set.")
        #expect(refreshedExercise.targetRepMin == 8)
        #expect(refreshedExercise.targetRepMax == 12)
        #expect(refreshedDrafts[0].targetWeight == 80)
        #expect(refreshedDrafts[0].targetReps == 10)
        #expect(refreshedDrafts[0].actualWeight == 85)
        #expect(refreshedDrafts[0].actualReps == 8)
        #expect(refreshedDrafts[0].actualLoadUnit == .kg)
        #expect(refreshedDrafts[0].isCompleted)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    }

    @Test
    func persistExerciseSnapshotSavesDraftsRestAndNotesTogether() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "persist-snapshot-bench-1",
            displayName: "Bench Press",
            equipmentSummary: "Barbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[0].actualWeight = 90
        drafts[0].actualReps = 8
        drafts[0].actualLoadUnit = .kg
        drafts[0].isCompleted = true

        try repository.persistExerciseSnapshot(
            sessionExerciseID: exercise.id,
            snapshot: ActiveWorkoutExercisePersistenceSnapshot(
                setDrafts: drafts,
                restSeconds: 150,
                notes: "Pause each rep on the chest."
            )
        )

        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedDrafts = try repository.setDrafts(sessionExerciseID: refreshedExercise.id)

        #expect(refreshedExercise.restSeconds == 150)
        #expect(refreshedExercise.notes == "Pause each rep on the chest.")
        #expect(refreshedDrafts[0].restSeconds == 150)
        #expect(refreshedDrafts[1].restSeconds == 150)
        #expect(refreshedDrafts[0].actualWeight == 90)
        #expect(refreshedDrafts[0].actualReps == 8)
        #expect(refreshedDrafts[0].actualLoadUnit == .kg)
        #expect(refreshedDrafts[0].isCompleted)
    }

    @Test
    func persistExerciseSnapshotNoOpsWhenSnapshotMatchesPersistedState() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "persist-snapshot-noop-1",
            displayName: "Row",
            equipmentSummary: "Barbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Pull Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        let originalExerciseUpdatedAt = exercise.updatedAt
        let originalSetUpdatedAt = (exercise.sets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        try repository.persistExerciseSnapshot(
            sessionExerciseID: exercise.id,
            snapshot: ActiveWorkoutExercisePersistenceSnapshot(
                setDrafts: drafts,
                restSeconds: exercise.restSeconds,
                notes: exercise.notes
            )
        )

        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedSetUpdatedAt = (refreshedExercise.sets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.updatedAt)

        #expect(refreshedExercise.updatedAt == originalExerciseUpdatedAt)
        #expect(refreshedSetUpdatedAt == originalSetUpdatedAt)
    }

    @Test
    func persistCheckpointAppliesExerciseSettingsInOnePass() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "checkpoint-settings-1",
            displayName: "Incline Press",
            equipmentSummary: "Dumbbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        let exercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        let updatedSnapshot = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: drafts,
            restSeconds: 150,
            notes: "Keep shoulders packed.",
            targetRepMin: 8,
            targetRepMax: 12
        )
        let persistedSnapshot = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: drafts,
            restSeconds: exercise.restSeconds,
            notes: exercise.notes,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax
        )

        let result = try repository.persistCheckpoint(
            sessionID: session.id,
            sessionName: session.name,
            sessionNotes: session.notes,
            dirtyExerciseIDs: [exercise.id],
            snapshotsByExerciseID: [exercise.id: updatedSnapshot],
            persistedSnapshotsByExerciseID: [exercise.id: persistedSnapshot]
        )

        let refreshedExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let refreshedDrafts = try repository.setDrafts(sessionExerciseID: refreshedExercise.id)

        #expect(result.didPersistSessionMeta == false)
        #expect(result.handledExerciseIDs == [exercise.id])
        #expect(result.persistedExerciseIDs == [exercise.id])
        #expect(refreshedExercise.restSeconds == 150)
        #expect(refreshedExercise.notes == "Keep shoulders packed.")
        #expect(refreshedExercise.targetRepMin == 8)
        #expect(refreshedExercise.targetRepMax == 12)
        #expect(refreshedDrafts[0].restSeconds == 150)
        #expect(refreshedDrafts[1].restSeconds == 150)
    }

    @Test
    func cancelSessionRemovesDraftRows() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "cancel-press-1",
            displayName: "Incline Press",
            equipmentSummary: "Dumbbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Cancel Me")
        try repository.addExercise(sessionID: session.id, catalogItem: item)

        try repository.cancelSession(sessionID: session.id)

        #expect(try repository.session(id: session.id) == nil)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSet>()).isEmpty)
    }

    @Test
    func finishSessionMaterializesCompletedWorkoutAndRemovesDraft() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)
        let completedRepository = WorkoutSessionRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "finish-bench-1",
            displayName: "Bench Press",
            equipmentSummary: "Barbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Push Day")
        try repository.addExercise(sessionID: session.id, catalogItem: item)
        try repository.updateSessionNotes(sessionID: session.id, notes: "Original draft notes")

        let draftExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        try repository.updateExerciseNotes(
            sessionExerciseID: draftExercise.id,
            notes: "Keep the bar path stacked over the wrist."
        )
        let originalSetIDs = try repository.setDrafts(sessionExerciseID: draftExercise.id).map(\.id)

        var drafts = try repository.setDrafts(sessionExerciseID: draftExercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 8
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: draftExercise.id, drafts: drafts)

        let completedSessionID = try repository.finishSession(
            sessionID: session.id,
            notes: "Locked in"
        )

        let completedSession = try #require(try completedRepository.session(id: completedSessionID))
        let completedExercise = try #require(
            try completedRepository.sessionExercises(sessionID: completedSessionID).first
        )
        let completedDrafts = try completedRepository.setDrafts(sessionExerciseID: completedExercise.id)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)

        try waitForProjectedFacts(
            sessionID: completedSessionID,
            expectedCount: 1,
            repository: projectionRepository
        )
        let facts = try context.fetch(FetchDescriptor<CompletedSetFact>())

        #expect(completedSessionID == session.id)
        #expect(completedSession.status == .completed)
        #expect(completedSession.notes == "Locked in")
        #expect(completedSession.totalVolume == 800)
        #expect(completedExercise.id == draftExercise.id)
        #expect(completedExercise.notes == "Keep the bar path stacked over the wrist.")
        #expect(completedDrafts.map(\.id) == originalSetIDs)
        #expect(completedDrafts[1].actualWeight == 100)
        #expect(completedDrafts[1].actualReps == 8)
        #expect(completedDrafts[1].actualLoadUnit == .kg)
        #expect(completedDrafts[1].isCompleted)
        #expect(try repository.session(id: session.id) == nil)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).isEmpty)
        #expect(try completedRepository.activeSession() == nil)
        #expect(facts.count == 1)
        #expect(facts.first?.sessionID == completedSessionID)
    }

    @Test
    func moveExercisePersistsDraftOrdering() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let bench = makeCatalogItem(
            remoteUUID: "move-bench-1",
            displayName: "Bench Press",
            equipmentSummary: "Barbell",
            context: context
        )
        let row = makeCatalogItem(
            remoteUUID: "move-row-1",
            displayName: "Barbell Row",
            equipmentSummary: "Barbell",
            context: context
        )

        let session = try repository.createEmptySession(name: "Upper")
        try repository.addExercise(sessionID: session.id, catalogItem: bench)
        try repository.addExercise(sessionID: session.id, catalogItem: row)

        try repository.moveExercise(sessionID: session.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)

        #expect(try repository.sessionExercises(sessionID: session.id).map(\.catalogExerciseUUID) == [row.remoteUUID, bench.remoteUUID])
    }

    @Test
    func activeSessionMigratesLegacyCloudBackedWorkoutIntoDraftStore() throws {
        let context = try makeInMemoryContext()
        let legacyRepository = WorkoutSessionRepository(modelContext: context)
        let repository = ActiveWorkoutDraftRepository(modelContext: context)

        let item = makeCatalogItem(
            remoteUUID: "legacy-squat-1",
            displayName: "Back Squat",
            equipmentSummary: "Barbell",
            context: context
        )

        let legacySession = try legacyRepository.createEmptySession(name: "Leg Day")
        try legacyRepository.addExercise(sessionID: legacySession.id, catalogItem: item)
        try legacyRepository.updateSessionNotes(sessionID: legacySession.id, notes: "Legacy notes")

        let legacyExercise = try #require(try legacyRepository.sessionExercises(sessionID: legacySession.id).first)
        let legacySetIDs = try legacyRepository.setDrafts(sessionExerciseID: legacyExercise.id).map(\.id)

        let migrated = try #require(try repository.activeSession())
        let migratedExercise = try #require(try repository.sessionExercises(sessionID: migrated.id).first)
        let migratedDrafts = try repository.setDrafts(sessionExerciseID: migratedExercise.id)

        #expect(migrated.id == legacySession.id)
        #expect(migrated.name == "Leg Day")
        #expect(migrated.notes == "Legacy notes")
        #expect(migratedExercise.id == legacyExercise.id)
        #expect(migratedDrafts.map(\.id) == legacySetIDs)
        #expect(try legacyRepository.session(id: legacySession.id) == nil)
        #expect(try legacyRepository.activeSession() == nil)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).count == 1)
    }

    @Test
    func localDraftWinsOverLegacyCloudBackedActiveWorkout() throws {
        let context = try makeInMemoryContext()
        let repository = ActiveWorkoutDraftRepository(modelContext: context)
        let legacyRepository = WorkoutSessionRepository(modelContext: context)

        let draftItem = makeCatalogItem(
            remoteUUID: "draft-pull-1",
            displayName: "Pull-Up",
            equipmentSummary: "Bodyweight",
            context: context
        )
        let legacyItem = makeCatalogItem(
            remoteUUID: "legacy-deadlift-1",
            displayName: "Deadlift",
            equipmentSummary: "Barbell",
            context: context
        )

        let localDraft = try repository.createEmptySession(name: "Current Draft")
        try repository.addExercise(sessionID: localDraft.id, catalogItem: draftItem)

        let legacySession = try legacyRepository.createEmptySession(name: "Old Active")
        try legacyRepository.addExercise(sessionID: legacySession.id, catalogItem: legacyItem)

        let resolved = try #require(try repository.activeSession())

        #expect(resolved.id == localDraft.id)
        #expect(resolved.name == "Current Draft")
        #expect(try legacyRepository.activeSession() == nil)
        #expect(try legacyRepository.session(id: legacySession.id) == nil)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).count == 1)
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
            BlockedBro.self,
        ])

        let configurations = [
            ModelConfiguration(
                AppStoreLayout.localCatalogConfigurationName,
                schema: Schema([
                    ExerciseCatalogItem.self,
                    MuscleGroup.self,
                    ExerciseImageAsset.self,
                    ExerciseAlias.self,
                    ExerciseAttribution.self,
                    ExerciseCatalogSyncState.self,
                ]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.userDataConfigurationName,
                schema: Schema([
                    UserProfile.self,
                    ProfileWidgetConfig.self,
                    TemplateFolder.self,
                    WorkoutTemplate.self,
                    TemplateCardioBlock.self,
                    TemplateExercise.self,
                    TemplateExerciseComponent.self,
                    TemplateExerciseSet.self,
                    WorkoutSession.self,
                    WorkoutSessionCardioBlock.self,
                    WorkoutSessionExercise.self,
                    WorkoutSessionSet.self,
                ]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.activeWorkoutDraftConfigurationName,
                schema: Schema([
                    ActiveWorkoutDraftSession.self,
                    ActiveWorkoutDraftCardioBlock.self,
                    ActiveWorkoutDraftExercise.self,
                    ActiveWorkoutDraftExerciseComponent.self,
                    ActiveWorkoutDraftSet.self,
                ]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.socialOutboxConfigurationName,
                schema: Schema([
                    SocialOutboxItem.self,
                    BlockedBro.self,
                ]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                AppStoreLayout.historyProjectionConfigurationName,
                schema: Schema([
                    CompletedSetFact.self,
                ]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ),
        ]

        let container = try ModelContainer(for: schema, configurations: configurations)
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

    @discardableResult
    private func makeCatalogItem(
        remoteUUID: String,
        displayName: String,
        equipmentSummary: String,
        context: ModelContext
    ) -> ExerciseCatalogItem {
        let item = ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: "Strength",
            equipmentSummary: equipmentSummary,
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(item)
        return item
    }
}
