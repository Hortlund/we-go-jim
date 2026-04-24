import CloudKit
import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WGJTests {
    @Test
    func wgjFormattersParseLocalizedDecimals() {
        let parsedDot = WGJFormatters.parseLocalizedDecimal("123.45")
        let parsedComma = WGJFormatters.parseLocalizedDecimal("123,45")

        #expect(parsedDot != nil)
        #expect(parsedComma != nil)
        #expect(abs((parsedDot ?? 0) - 123.45) < 0.001)
        #expect(abs((parsedComma ?? 0) - 123.45) < 0.001)
        #expect(!WGJFormatters.decimalString(123.45).isEmpty)
        #expect(!WGJFormatters.oneDecimalString(123.45).isEmpty)
        #expect(!WGJFormatters.integerString(123.45).isEmpty)
    }

    @Test
    func workoutSessionRepositoryDefaultsBodyweightExercisesToBodyweightLoadUnit() throws {
        let context = try makeInMemoryContext()
        let repository = WorkoutSessionRepository(modelContext: context)

        let session = try repository.createEmptySession(name: "Bodyweight")
        let exercise = ExerciseCatalogItem(
            remoteUUID: "seed-hanging-leg-raise",
            displayName: "Hanging Leg Raise",
            categoryName: "Abs",
            equipmentSummary: "Bodyweight",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        try repository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try repository.sessionExercises(sessionID: session.id).first)
        let drafts = try repository.setDrafts(sessionExerciseID: sessionExercise.id)

        #expect(!drafts.isEmpty)
        #expect(drafts.allSatisfy { $0.targetLoadUnit == .bodyweight && $0.actualLoadUnit == .bodyweight })
    }

    @Test
    func templateExerciseDraftDefaultsBodyweightExercisesToBodyweightLoadUnit() {
        let exercise = ExerciseCatalogItem(
            remoteUUID: "seed-decline-crunch",
            displayName: "Decline Crunch",
            categoryName: "Abs",
            equipmentSummary: "Body Weight, Bench",
            isCurated: true,
            sourceName: "seed"
        )

        let draft = TemplateExerciseDraft(catalogItem: exercise, preferredLoadUnit: .kg)

        #expect(!draft.setDrafts.isEmpty)
        #expect(draft.setDrafts.allSatisfy { $0.loadUnit == .bodyweight })
    }

    @Test
    func durationFormatterBuildsElapsedLabels() {
        let reference = Date(timeIntervalSinceReferenceDate: 1_000)
        let oneMinuteFive = Date(timeIntervalSinceReferenceDate: 1_065)
        let oneHourThree = Date(timeIntervalSinceReferenceDate: 4_603)

        #expect(WGJDurationFormatter.elapsedString(since: reference, now: oneMinuteFive) == "01:05")
        #expect(WGJDurationFormatter.elapsedString(since: reference, now: oneHourThree) == "01:00:03")
    }

    @Test
    func athleteTypesExposeTitlesAndPickerSubtitles() {
        let titles = ProfileAthleteType.allCases.map(\.title)
        let subtitles = ProfileAthleteType.allCases.map(\.pickerSubtitle)

        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(subtitles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }

    @Test
    func templateRepositoryCreatesMultipleFoldersAndTemplates() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Push")
        try repository.createFolder(name: "Pull")

        let folders = try repository.folders()
        #expect(folders.count == 2)

        guard let pushFolder = folders.first(where: { $0.name == "Push" }) else {
            Issue.record("Expected Push folder")
            return
        }

        _ = try repository.createTemplate(folderID: pushFolder.id, name: "Push A", notes: "Heavy compounds")
        _ = try repository.createTemplate(folderID: pushFolder.id, name: "Push B", notes: "Hypertrophy")

        let templates = try repository.templates(in: pushFolder.id)
        #expect(templates.count == 2)
        #expect(templates.map(\.name).contains("Push A"))
        #expect(templates.map(\.name).contains("Push B"))
    }

    @Test
    func templateRepositoryDeleteFolderCascadesTemplates() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Legs")
        guard let folder = try repository.folders().first else {
            Issue.record("Expected folder")
            return
        }

        let template = try repository.createTemplate(folderID: folder.id, name: "Leg Day", notes: "Squat focus")
        let catalogExercise = ExerciseCatalogItem(
            remoteUUID: "seed-back-squat",
            displayName: "Barbell Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell,Rack",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(catalogExercise)
        try repository.addExercise(templateID: template.id, catalogItem: catalogExercise)
        try repository.upsertCardioBlock(
            templateID: template.id,
            draft: TemplateCardioBlockDraft(
                phase: .preWorkout,
                catalogExerciseUUID: "seed-bike",
                exerciseNameSnapshot: "Bike Warmup",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                targetDurationSeconds: 300
            )
        )

        try repository.deleteFolder(id: folder.id)

        #expect(try repository.folders().isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateCardioBlock>()).isEmpty)
    }

    @Test
    func templateRepositoryAddRemoveAndReorderExercises() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Pull")
        guard let folder = try repository.folders().first else {
            Issue.record("Expected folder")
            return
        }

        let template = try repository.createTemplate(folderID: folder.id, name: "Pull A", notes: "")

        let first = ExerciseCatalogItem(
            remoteUUID: "seed-deadlift",
            displayName: "Conventional Deadlift",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let second = ExerciseCatalogItem(
            remoteUUID: "seed-pull-up",
            displayName: "Pull Up",
            categoryName: "Back",
            equipmentSummary: "Pull-up bar",
            isCurated: true,
            sourceName: "seed"
        )

        context.insert(first)
        context.insert(second)

        try repository.addExercise(templateID: template.id, catalogItem: first)
        try repository.addExercise(templateID: template.id, catalogItem: second)

        var templateExercises = try repository.exercises(in: template.id)
        #expect(templateExercises.count == 2)
        #expect(templateExercises[0].catalogExerciseUUID == "seed-deadlift")

        try repository.moveExercise(templateID: template.id, fromOffsets: IndexSet(integer: 0), toOffset: 2)

        templateExercises = try repository.exercises(in: template.id)
        #expect(templateExercises[0].catalogExerciseUUID == "seed-pull-up")

        if let firstExerciseID = templateExercises.first?.id {
            try repository.removeExercise(templateID: template.id, templateExerciseID: firstExerciseID)
        }

        templateExercises = try repository.exercises(in: template.id)
        #expect(templateExercises.count == 1)
    }

    @Test
    func templateRepositoryAddExerciseCreatesDefaultSetPlans() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Upper", notes: "")
        let catalogExercise = ExerciseCatalogItem(
            remoteUUID: "seed-row",
            displayName: "Barbell Row",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(catalogExercise)

        try repository.addExercise(templateID: template.id, catalogItem: catalogExercise)

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected template exercise")
            return
        }

        let setDrafts = try repository.setDrafts(for: exercise.id)
        #expect(setDrafts.count == 3)
        #expect(setDrafts.allSatisfy { $0.loadUnit == .kg })
        #expect(setDrafts.allSatisfy { $0.targetReps == nil })
        #expect(setDrafts.allSatisfy { $0.targetWeight == nil })
        #expect(setDrafts.allSatisfy { $0.restSeconds == 120 })
        #expect(setDrafts.first?.isWarmup == true)
        #expect(setDrafts.dropFirst().allSatisfy { !$0.isWarmup })
        #expect(setDrafts.allSatisfy { !$0.isLocked })
    }

    @Test
    func templateRepositoryPersistsRepRangeOnSetExercises() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Back", notes: "")
        let draft = TemplateExerciseDraft(
            catalogExerciseUUID: "seed-row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Back",
            muscleSummarySnapshot: "Lats",
            targetRepMin: 12,
            targetRepMax: 8,
            setDrafts: [TemplateExerciseSetDraft(targetReps: 10, targetWeight: 60, loadUnit: .kg)]
        )

        try repository.setExercises(templateID: template.id, drafts: [draft])

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected persisted exercise")
            return
        }

        #expect(exercise.targetRepMin == 12)
        #expect(exercise.targetRepMax == 8)
    }

    @Test
    func templateRepositorySetExercisesPersistsSetDraftsAndOrder() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Push", notes: "")
        let exerciseDraft = TemplateExerciseDraft(
            catalogExerciseUUID: "seed-bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "Pectoralis major",
            setDrafts: [
                TemplateExerciseSetDraft(targetReps: 5, targetWeight: 100, loadUnit: .kg),
                TemplateExerciseSetDraft(targetReps: 8, targetWeight: 225, loadUnit: .lb),
                TemplateExerciseSetDraft(targetReps: 12, targetWeight: nil, loadUnit: .bodyweight),
            ]
        )

        try repository.setExercises(templateID: template.id, drafts: [exerciseDraft])

        guard let persistedExercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected persisted template exercise")
            return
        }

        let setDrafts = try repository.setDrafts(for: persistedExercise.id)
        #expect(setDrafts.count == 3)
        #expect(setDrafts[0].targetReps == 5)
        #expect(setDrafts[0].targetWeight == 100)
        #expect(setDrafts[0].loadUnit == .kg)
        #expect(setDrafts[1].targetReps == 8)
        #expect(setDrafts[1].targetWeight == 225)
        #expect(setDrafts[1].loadUnit == .lb)
        #expect(setDrafts[2].targetReps == 12)
        #expect(setDrafts[2].targetWeight == nil)
        #expect(setDrafts[2].loadUnit == .bodyweight)
    }

    @Test
    func templateRepositoryAddRemoveAndReorderSets() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Legs", notes: "")
        let catalogExercise = ExerciseCatalogItem(
            remoteUUID: "seed-squat",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(catalogExercise)
        try repository.addExercise(templateID: template.id, catalogItem: catalogExercise)

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected template exercise")
            return
        }

        var setDrafts = try repository.setDrafts(for: exercise.id)
        #expect(setDrafts.count == 3)

        try repository.addSet(templateExerciseID: exercise.id)
        setDrafts = try repository.setDrafts(for: exercise.id)
        #expect(setDrafts.count == 4)

        if let firstSet = setDrafts.first {
            try repository.removeSet(templateExerciseID: exercise.id, setID: firstSet.id)
        }
        setDrafts = try repository.setDrafts(for: exercise.id)
        #expect(setDrafts.count == 3)

        let beforeMoveIDs = setDrafts.map(\.id)
        try repository.moveSet(templateExerciseID: exercise.id, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        let afterMoveIDs = try repository.setDrafts(for: exercise.id).map(\.id)

        #expect(afterMoveIDs.count == beforeMoveIDs.count)
        #expect(afterMoveIDs.last == beforeMoveIDs.first)
    }

    @Test
    func templateRepositorySaveSetDraftsSnapshotsPreviousTargets() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Upper", notes: "")
        let draft = TemplateExerciseDraft(
            catalogExerciseUUID: "seed-bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "Pectoralis major",
            setDrafts: [TemplateExerciseSetDraft(targetReps: 5, targetWeight: 100, loadUnit: .kg)]
        )
        try repository.setExercises(templateID: template.id, drafts: [draft])

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected persisted exercise")
            return
        }

        var drafts = try repository.setDrafts(for: exercise.id)
        #expect(drafts.count == 1)
        #expect(drafts[0].previousTargetReps == nil)
        #expect(drafts[0].previousTargetWeight == nil)

        drafts[0].targetReps = 6
        drafts[0].targetWeight = 105
        drafts[0].loadUnit = .kg
        try repository.saveSetDrafts(templateExerciseID: exercise.id, drafts: drafts)

        let updated = try repository.setDrafts(for: exercise.id)
        #expect(updated[0].targetReps == 6)
        #expect(updated[0].targetWeight == 105)
        #expect(updated[0].previousTargetReps == 5)
        #expect(updated[0].previousTargetWeight == 100)
        #expect(updated[0].previousLoadUnit == .kg)
    }

    @Test
    func templateRepositoryApplyRestSecondsToAllSets() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Legs", notes: "")
        let exerciseDraft = TemplateExerciseDraft(
            catalogExerciseUUID: "seed-squat",
            exerciseNameSnapshot: "Back Squat",
            categorySnapshot: "Legs",
            muscleSummarySnapshot: "Quads",
            setDrafts: [
                TemplateExerciseSetDraft(restSeconds: 90),
                TemplateExerciseSetDraft(restSeconds: 120),
                TemplateExerciseSetDraft(restSeconds: 150),
            ]
        )
        try repository.setExercises(templateID: template.id, drafts: [exerciseDraft])

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected persisted exercise")
            return
        }

        try repository.applyRestSecondsToAllSets(templateExerciseID: exercise.id, restSeconds: 165)
        let refreshed = try repository.setDrafts(for: exercise.id)
        #expect(refreshed.count == 3)
        #expect(refreshed.allSatisfy { $0.restSeconds == 165 })
    }

    @Test
    func templateRepositoryDeleteExerciseCascadesSetPlans() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Pull", notes: "")
        let catalogExercise = ExerciseCatalogItem(
            remoteUUID: "seed-deadlift",
            displayName: "Deadlift",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(catalogExercise)
        try repository.addExercise(templateID: template.id, catalogItem: catalogExercise)

        guard let exercise = try repository.exercises(in: template.id).first else {
            Issue.record("Expected template exercise")
            return
        }

        #expect((exercise.prescribedSets ?? []).count == 3)
        try repository.removeExercise(templateID: template.id, templateExerciseID: exercise.id)

        let remainingSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>())
        #expect(remainingSets.isEmpty)
    }

    @Test
    func templateRepositorySupportsTemplatesWithoutFolder() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        _ = try repository.createTemplate(name: "Upper Day", notes: "No folder template")
        _ = try repository.createTemplate(name: "Lower Day", notes: "Another root template")

        let rootTemplates = try repository.templatesWithoutFolder()

        #expect(rootTemplates.count == 2)
        #expect(rootTemplates.allSatisfy { $0.folder == nil })
        #expect(rootTemplates.allSatisfy { $0.folderID == TemplateRepository.unfiledFolderID })
    }

    @Test
    func templateRepositoryMovesTemplatesBetweenFoldersAndUnfiled() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Push")
        try repository.createFolder(name: "Pull")

        let createdFolders = try repository.folders()
        guard
            let pushID = createdFolders.first(where: { $0.name == "Push" })?.id,
            let pullID = createdFolders.first(where: { $0.name == "Pull" })?.id
        else {
            Issue.record("Expected Push and Pull folders")
            return
        }

        let rootTemplate = try repository.createTemplate(name: "Upper Day", notes: "")
        var folderTemplate = try repository.createTemplate(folderID: pushID, name: "Push A", notes: "")

        let customDraft = TemplateExerciseDraft(
            catalogExerciseUUID: "seed-bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "Pectoralis major",
            setDrafts: [
                TemplateExerciseSetDraft(targetReps: 5, targetWeight: 95, loadUnit: .kg),
                TemplateExerciseSetDraft(targetReps: 8, targetWeight: 85, loadUnit: .kg),
                TemplateExerciseSetDraft(targetReps: 10, targetWeight: 75, loadUnit: .kg),
            ]
        )
        try repository.setExercises(templateID: folderTemplate.id, drafts: [customDraft])
        guard let reloadedFolderTemplate = try repository.template(id: folderTemplate.id) else {
            Issue.record("Expected folder template to be reloadable")
            return
        }
        folderTemplate = reloadedFolderTemplate

        try repository.moveTemplate(id: rootTemplate.id, toFolderID: pushID)
        #expect(try repository.template(id: rootTemplate.id)?.folderID == pushID)
        #expect(try repository.templates(in: pushID).contains(where: { $0.id == rootTemplate.id }))

        try repository.moveTemplate(id: folderTemplate.id, toFolderID: pullID)
        #expect(try repository.template(id: folderTemplate.id)?.folderID == pullID)
        #expect(!(try repository.templates(in: pushID)).contains(where: { $0.id == folderTemplate.id }))
        #expect(try repository.templates(in: pullID).contains(where: { $0.id == folderTemplate.id }))

        try repository.moveTemplate(id: folderTemplate.id, toFolderID: nil)
        #expect(try repository.template(id: folderTemplate.id)?.folderID == TemplateRepository.unfiledFolderID)
        #expect(try repository.templatesWithoutFolder().contains(where: { $0.id == folderTemplate.id }))

        guard let movedTemplateExercise = try repository.exercises(in: folderTemplate.id).first else {
            Issue.record("Expected template exercise to remain after moving template")
            return
        }
        let movedSets = try repository.setDrafts(for: movedTemplateExercise.id)
        #expect(movedSets.count == 3)
        #expect(movedSets[0].targetReps == 5)
        #expect(movedSets[0].targetWeight == 95)
    }

    @Test
    func templateRepositoryEnsureDefaultSetPlansBackfillsLegacyExercises() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        let template = try repository.createTemplate(name: "Legacy", notes: "")
        let legacyExercise = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "legacy-1",
            exerciseNameSnapshot: "Legacy Exercise",
            categorySnapshot: "Misc",
            muscleSummarySnapshot: "",
            sortOrder: 0,
            template: template
        )

        context.insert(legacyExercise)
        template.exercises = [legacyExercise]
        try context.save()

        #expect((legacyExercise.prescribedSets ?? []).isEmpty)

        try repository.ensureDefaultSetPlans(templateID: template.id)

        let backfilled = try repository.setDrafts(for: legacyExercise.id)
        #expect(backfilled.count == 3)
        #expect(backfilled.allSatisfy { $0.targetReps == nil })
        #expect(backfilled.allSatisfy { $0.targetWeight == nil })
        #expect(backfilled.allSatisfy { $0.loadUnit == .kg })
    }

    @Test
    func profileRepositoryCreatesAndSavesProfileIdentity() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        let created = try repository.loadOrCreateProfile()
        #expect(created.displayName == "Athlete")
        #expect(created.athleteType == nil)
        #expect(created.preferredWeightUnit == .kg)
        #expect(created.isTrainingGuidanceEnabled)
        #expect(created.keepsScreenAwake == false)
        #expect(created.isBozarModeEnabled == false)

        let avatarData = Data([0x01, 0x02, 0x03, 0x04])
        try repository.saveProfile(
            name: "Demo Lifter",
            athleteType: .garageGymRat,
            avatarImageData: avatarData
        )

        let updated = try repository.currentProfile()
        #expect(updated?.displayName == "Demo Lifter")
        #expect(updated?.athleteType == .garageGymRat)
        #expect(updated?.avatarImageData == avatarData)
    }

    @Test
    func profileRepositoryBootstrapsProfileWithICloudNameWhenAvailable() async throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)
        let provider = CountingProfileDefaultDisplayNameProvider(displayName: "Cloud Bro")

        let profile = try await repository.bootstrapProfileIdentity(
            cloudSyncEnabled: true,
            defaultDisplayNameProvider: provider
        )

        #expect(profile.displayName == "Cloud Bro")
        let callCount = await provider.callCount
        #expect(callCount == 1)
    }

    @Test
    func profileRepositoryUpgradesFallbackNameWhenCloudNameArrivesLater() async throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)
        let provider = CountingProfileDefaultDisplayNameProvider(displayName: "Cloud Bro")

        let created = try repository.loadOrCreateProfile()
        #expect(created.displayName == "Athlete")

        let updated = try await repository.bootstrapProfileIdentity(
            cloudSyncEnabled: true,
            defaultDisplayNameProvider: provider
        )

        #expect(updated.id == created.id)
        #expect(updated.displayName == "Cloud Bro")
        let callCount = await provider.callCount
        #expect(callCount == 1)
    }

    @Test
    func profileRepositoryKeepsAthleteWhenRunningFullyLocal() async throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        let profile = try await repository.bootstrapProfileIdentity(
            cloudSyncEnabled: false,
            defaultDisplayNameProvider: MockProfileDefaultDisplayNameProvider(displayName: "Cloud Bro")
        )

        #expect(profile.displayName == "Athlete")
    }

    @Test
    func profileRepositoryDoesNotOverwriteCustomIdentityName() async throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        try repository.saveProfile(
            name: "Local Bro",
            athleteType: nil,
            avatarImageData: nil
        )

        let profile = try await repository.bootstrapProfileIdentity(
            cloudSyncEnabled: true,
            defaultDisplayNameProvider: MockProfileDefaultDisplayNameProvider(displayName: "Cloud Bro")
        )

        #expect(profile.displayName == "Local Bro")
    }

    @Test
    func profileRepositorySkipsCloudLookupForCustomCanonicalProfile() async throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)
        let customProfile = UserProfile(
            displayName: "Local Bro",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(customProfile)
        try context.save()

        let provider = CountingProfileDefaultDisplayNameProvider(displayName: "Cloud Bro")
        let profile = try await repository.bootstrapProfileIdentity(
            cloudSyncEnabled: true,
            defaultDisplayNameProvider: provider
        )

        #expect(profile.id == customProfile.id)
        #expect(profile.displayName == "Local Bro")
        let callCount = await provider.callCount
        #expect(callCount == 0)
    }

    @Test
    func profileRepositoryPersistsTrainingGuidancePreference() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        _ = try repository.loadOrCreateProfile()
        try repository.updateTrainingGuidanceEnabled(false)

        let updated = try repository.currentProfile()
        #expect(updated?.isTrainingGuidanceEnabled == false)
    }

    @Test
    func profileRepositoryPersistsKeepScreenAwakePreference() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        _ = try repository.loadOrCreateProfile()
        try repository.updateKeepsScreenAwake(true)

        let updated = try repository.currentProfile()
        #expect(updated?.keepsScreenAwake == true)
    }

    @Test
    func profileRepositoryPersistsBozarModePreference() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        _ = try repository.loadOrCreateProfile()
        try repository.updateBozarModeEnabled(true)

        let updated = try repository.currentProfile()
        #expect(updated?.isBozarModeEnabled == true)
    }

    @Test
    func profileRepositoryExposesSnapshotForCurrentIdentity() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)
        let avatarData = Data([0x0a, 0x0b, 0x0c])

        try repository.saveProfile(
            name: "Snapshot Bro",
            athleteType: .garageGymRat,
            avatarImageData: avatarData
        )

        let snapshot = try #require(try repository.currentProfileSnapshot())
        #expect(snapshot.displayName == "Snapshot Bro")
        #expect(snapshot.athleteType == .garageGymRat)
        #expect(snapshot.avatarImageData == avatarData)
    }

    @Test
    func profileWidgetRepositoryReturnsValueSnapshotsInSortOrder() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        let snapshots = try repository.configurationSnapshots()
        #expect(!snapshots.isEmpty)
        #expect(snapshots == snapshots.sorted { $0.sortOrder < $1.sortOrder })
    }

    @Test
    func userProfileSelectionChoosesEarliestCreatedProfileForPreferences() {
        let laterProfile = UserProfile(
            displayName: "Later",
            isTrainingGuidanceEnabled: true,
            isBozarModeEnabled: false,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let earlierProfile = UserProfile(
            displayName: "Earlier",
            isTrainingGuidanceEnabled: false,
            isBozarModeEnabled: true,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let selected = UserProfileSelection.currentProfile(in: [laterProfile, earlierProfile])

        #expect(selected?.id == earlierProfile.id)
        #expect(selected?.isTrainingGuidanceEnabled == false)
        #expect(selected?.isBozarModeEnabled == true)
    }

    @Test
    func profileRepositoryUpdatesCanonicalProfileWhenDuplicateProfilesExist() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)
        let canonicalProfile = UserProfile(
            displayName: "Canonical",
            workoutNotificationStyle: .timeSensitive,
            keepsScreenAwake: false,
            isBozarModeEnabled: false,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let duplicateProfile = UserProfile(
            displayName: "Duplicate",
            workoutNotificationStyle: .timeSensitive,
            keepsScreenAwake: false,
            isBozarModeEnabled: false,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(duplicateProfile)
        context.insert(canonicalProfile)
        try context.save()

        try repository.updateKeepsScreenAwake(true)
        try repository.updateBozarModeEnabled(true)
        try repository.updateWorkoutNotificationStyle(.standard)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let refreshedCanonical = try #require(profiles.first(where: { $0.id == canonicalProfile.id }))
        let refreshedDuplicate = try #require(profiles.first(where: { $0.id == duplicateProfile.id }))

        #expect(refreshedCanonical.keepsScreenAwake == true)
        #expect(refreshedCanonical.isBozarModeEnabled == true)
        #expect(refreshedCanonical.workoutNotificationStyle == .standard)

        #expect(refreshedDuplicate.keepsScreenAwake == false)
        #expect(refreshedDuplicate.isBozarModeEnabled == false)
        #expect(refreshedDuplicate.workoutNotificationStyle == WorkoutNotificationStyle.timeSensitive)
    }

    @Test
    func profileRepositoryPersistsWorkoutNotificationStyle() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        _ = try repository.loadOrCreateProfile()
        try repository.updateWorkoutNotificationStyle(.standard)

        let updated = try repository.currentProfile()
        #expect(updated?.workoutNotificationStyle == .standard)
    }

    @Test
    func profileRepositoryPersistsPreferredWeightUnit() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileRepository(modelContext: context)

        _ = try repository.loadOrCreateProfile()
        try repository.updatePreferredWeightUnit(.lb)

        let updated = try repository.currentProfile()
        #expect(updated?.preferredWeightUnit == .lb)
        #expect(updated?.preferredLoadUnit == .lb)
    }

    @Test
    func templateRepositoryEnsureDefaultSetPlansUsesPreferredWeightUnit() throws {
        let context = try makeInMemoryContext()
        let profileRepository = ProfileRepository(modelContext: context)
        try profileRepository.updatePreferredWeightUnit(.lb)

        let repository = TemplateRepository(modelContext: context)
        let template = try repository.createTemplate(name: "Legacy", notes: "")
        let legacyExercise = TemplateExercise(
            templateID: template.id,
            catalogExerciseUUID: "legacy-lb-1",
            exerciseNameSnapshot: "Legacy Exercise",
            categorySnapshot: "Misc",
            muscleSummarySnapshot: "",
            sortOrder: 0,
            template: template
        )

        context.insert(legacyExercise)
        template.exercises = [legacyExercise]
        try context.save()

        try repository.ensureDefaultSetPlans(templateID: template.id)

        let backfilled = try repository.setDrafts(for: legacyExercise.id)
        #expect(backfilled.count == 3)
        #expect(backfilled.allSatisfy { $0.loadUnit == .lb })
        #expect(backfilled.allSatisfy { $0.previousLoadUnit == .lb })
    }

    @Test
    func accountStatusServiceMapsProviderResponses() async {
        let availableService = AccountStatusService(client: MockCloudAccountStatusClient(status: .available, error: nil))
        let noAccountService = AccountStatusService(client: MockCloudAccountStatusClient(status: .noAccount, error: nil))
        let failingService = AccountStatusService(client: MockCloudAccountStatusClient(status: .couldNotDetermine, error: NSError(domain: "test", code: 1)))

        let available = await availableService.fetchAccountStatus()
        let noAccount = await noAccountService.fetchAccountStatus()
        let failed = await failingService.fetchAccountStatus()

        #expect(available == .available)
        #expect(noAccount == .unavailable(.noAccount))
        #expect(failed == .unavailable(.unknown))
    }

    @Test
    func cloudStartupPreflightChoosesCloudBackedBootstrapWhenAccountIsAvailable() {
        let decision = CloudStartupPreflight.makeDecision(
            statusProvider: MockCloudStartupAccountStatusProvider(status: .available)
        )

        #expect(decision.storeMode == .cloudBacked)
        #expect(decision.cloudSyncEnabled)
        #expect(decision.cloudSyncErrorDescription == nil)
    }

    @Test
    func cloudStartupPreflightChoosesLocalFallbackWithoutICloudAccount() {
        let decision = CloudStartupPreflight.makeDecision(
            statusProvider: MockCloudStartupAccountStatusProvider(status: .noAccount)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(!decision.cloudSyncEnabled)
        #expect(decision.cloudSyncErrorDescription?.contains("No iCloud account") == true)
    }

    @Test
    func cloudStartupPreflightChoosesLocalFallbackWhenICloudIsRestricted() {
        let decision = CloudStartupPreflight.makeDecision(
            statusProvider: MockCloudStartupAccountStatusProvider(status: .restricted)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(!decision.cloudSyncEnabled)
        #expect(decision.cloudSyncErrorDescription?.contains("restricted") == true)
    }

    @Test
    func cloudStartupPreflightChoosesLocalFallbackForAnyUncertainStartupStatus() {
        let expectations: [(CloudStartupAccountStatus, String)] = [
            (.temporarilyUnavailable, "temporarily unavailable"),
            (.couldNotDetermine, "could not verify"),
            (.timedOut, "timed out"),
            (.error, "CloudKit startup error"),
        ]

        for (status, expectedMessageFragment) in expectations {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(decision.storeMode == .localFallback)
            #expect(!decision.cloudSyncEnabled)
            #expect(decision.cloudSyncErrorDescription?.contains(expectedMessageFragment) == true)
        }
    }

    @Test
    func cloudStartupPreflightPreservesFallbackReasonsForAllLocalOnlyStatuses() {
        let expectations: [(CloudStartupAccountStatus, String)] = [
            (.noAccount, "No iCloud account"),
            (.restricted, "restricted"),
            (.containerUnavailable, "CloudKit is unavailable"),
            (.temporarilyUnavailable, "temporarily unavailable"),
            (.couldNotDetermine, "could not verify"),
            (.timedOut, "timed out"),
            (.error, "CloudKit startup error"),
        ]

        for (status, expectedMessageFragment) in expectations {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(decision.storeMode == .localFallback)
            #expect(decision.cloudSyncErrorDescription?.contains(expectedMessageFragment) == true)
        }
    }

    @Test
    func cloudSyncClassifierTreatsNoAccountSetupFailureAsRuntimeError() {
        let summary = makeCloudSyncSummary(
            type: .setup,
            status: .failed,
            error: CloudSyncErrorSnapshot(
                domain: NSCocoaErrorDomain,
                code: 134400,
                underlyingDomain: nil,
                underlyingCode: nil,
                description: "Unable to initialize without an iCloud account."
            )
        )

        let resolution = CloudSyncEventHealthClassifier.resolution(for: summary)
        switch resolution {
        case .setRuntimeError(let description):
            #expect(description.contains("No iCloud account"))
        default:
            Issue.record("Expected a runtime CloudKit error for the no-account setup failure.")
        }
    }

    @Test
    func cloudSyncClassifierClearsRuntimeErrorAfterSuccessfulCloudEvent() {
        resetAppRuntimeState()
        defer { resetAppRuntimeState() }

        AppRuntimeState.shared.updateCloudState(
            isEnabled: true,
            errorDescription: "CloudKit setup failed."
        )

        let summary = makeCloudSyncSummary(type: .export, status: .succeeded)
        let resolution = CloudSyncEventHealthClassifier.resolution(for: summary)
        applyCloudSyncResolution(resolution)

        #expect(AppRuntimeState.shared.cloudSyncErrorDescription == nil)
    }

    @Test
    func cloudSyncClassifierIgnoresBackgroundTaskSchedulerNoise() {
        resetAppRuntimeState()
        defer { resetAppRuntimeState() }

        AppRuntimeState.shared.updateCloudState(isEnabled: true, errorDescription: nil)

        let summary = makeCloudSyncSummary(
            type: .export,
            status: .failed,
            error: CloudSyncErrorSnapshot(
                domain: "BGSystemTaskSchedulerErrorDomain",
                code: 3,
                underlyingDomain: nil,
                underlyingCode: nil,
                description: "Error updating background task request."
            )
        )

        let resolution = CloudSyncEventHealthClassifier.resolution(for: summary)
        applyCloudSyncResolution(resolution)

        #expect(AppRuntimeState.shared.cloudSyncErrorDescription == nil)
        #expect(AppRuntimeState.shared.isBrosCloudAvailable(cloudContainerAvailable: true))
    }

    @Test
    func runtimeCloudAvailabilityRetriesAfterTemporaryFailure() async {
        let runtimeState = AppRuntimeState.makeTestingInstance()
        runtimeState.updateCloudState(isEnabled: true, errorDescription: nil)
        let accountService = MockRuntimeAccountStatusProvider(statuses: [
            .unavailable(.temporarilyUnavailable),
            .available,
        ])
        let firstRefreshAt = Date(timeIntervalSince1970: 1_000)

        runtimeState.refreshCloudAvailabilityIfNeeded(
            accountService: accountService,
            now: firstRefreshAt
        )
        await waitForRuntimeRefresh(fetchCount: 1, accountService: accountService)

        #expect(
            runtimeState.cloudSyncErrorDescription?.contains("temporarily unavailable") == true
        )
        #expect(accountService.fetchCount == 1)

        runtimeState.refreshCloudAvailabilityIfNeeded(
            accountService: accountService,
            now: firstRefreshAt.addingTimeInterval(RuntimeCloudAvailabilityRefreshPolicy.unresolvedRetryInterval)
        )
        await waitForRuntimeRefresh(fetchCount: 2, accountService: accountService)

        #expect(runtimeState.cloudSyncErrorDescription == nil)
        #expect(accountService.fetchCount == 2)
    }

    @Test
    func runtimeCloudAvailabilityStopsRetryingAfterDefinitiveAvailability() async {
        let runtimeState = AppRuntimeState.makeTestingInstance()
        runtimeState.updateCloudState(isEnabled: true, errorDescription: "temporary")
        let accountService = MockRuntimeAccountStatusProvider(statuses: [
            .available,
            .unavailable(.unknown),
        ])

        runtimeState.refreshCloudAvailabilityIfNeeded(accountService: accountService)
        await waitForRuntimeRefresh(fetchCount: 1, accountService: accountService)

        runtimeState.refreshCloudAvailabilityIfNeeded(accountService: accountService)
        await waitForRuntimeRefresh(fetchCount: 1, accountService: accountService)

        #expect(runtimeState.cloudSyncErrorDescription == nil)
        #expect(accountService.fetchCount == 1)
    }

    @Test
    func brosCloudAvailabilityTurnsOffWhenRuntimeErrorIsSet() {
        resetAppRuntimeState()
        defer { resetAppRuntimeState() }

        AppRuntimeState.shared.updateCloudState(isEnabled: true, errorDescription: nil)
        #expect(AppRuntimeState.shared.isBrosCloudAvailable(cloudContainerAvailable: true))

        AppRuntimeState.shared.updateCloudRuntimeError("CloudKit setup failed.")

        #expect(!AppRuntimeState.shared.isBrosCloudAvailable(cloudContainerAvailable: true))
    }

#if DEBUG
    @Test
    func demoSeedServiceSeedsProfileAndTemplatesIdempotently() throws {
        let context = try makeInMemoryContext()
        let service = DemoSeedService(modelContext: context)

        try service.seedDemoDataIfEmpty()

        let profilesFirstPass = try context.fetch(FetchDescriptor<UserProfile>())
        let foldersFirstPass = try context.fetch(FetchDescriptor<TemplateFolder>())
        let templatesFirstPass = try context.fetch(FetchDescriptor<WorkoutTemplate>())

        #expect(profilesFirstPass.count == 1)
        #expect(profilesFirstPass.first?.displayName == "Demo Lifter")
        #expect(foldersFirstPass.count == 3)
        #expect(templatesFirstPass.count >= 3)

        try service.seedDemoDataIfEmpty()

        let profilesSecondPass = try context.fetch(FetchDescriptor<UserProfile>())
        let foldersSecondPass = try context.fetch(FetchDescriptor<TemplateFolder>())
        let templatesSecondPass = try context.fetch(FetchDescriptor<WorkoutTemplate>())

        #expect(profilesSecondPass.count == profilesFirstPass.count)
        #expect(foldersSecondPass.count == foldersFirstPass.count)
        #expect(templatesSecondPass.count == templatesFirstPass.count)
    }
#endif

    private func makeCloudSyncSummary(
        type: CloudSyncEventType,
        status: CloudSyncEventStatus,
        error: CloudSyncErrorSnapshot? = nil
    ) -> CloudSyncEventSummary {
        CloudSyncEventSummary(
            type: type,
            status: status,
            storeIdentifier: "UserData",
            startedAt: .now,
            endedAt: status == .running ? nil : .now,
            error: error
        )
    }

    private func applyCloudSyncResolution(_ resolution: CloudSyncEventHealthResolution) {
        switch resolution {
        case .noChange:
            break
        case .clearRuntimeError:
            AppRuntimeState.shared.updateCloudRuntimeError(nil)
        case .setRuntimeError(let description):
            AppRuntimeState.shared.updateCloudRuntimeError(description)
        }
    }

    private func resetAppRuntimeState() {
        AppRuntimeState.shared.updateCloudState(isEnabled: false, errorDescription: nil)
        AppRuntimeState.shared.updateLatestCloudSyncEvent(nil)
    }

    private func waitForRuntimeRefresh(
        fetchCount expectedFetchCount: Int,
        accountService: MockRuntimeAccountStatusProvider
    ) async {
        for _ in 0..<20 {
            if accountService.fetchCount >= expectedFetchCount {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await Task.yield()
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
}

private struct MockProfileDefaultDisplayNameProvider: ProfileDefaultDisplayNameProviding {
    let displayName: String?

    func defaultDisplayName() async -> String? {
        displayName
    }
}

private actor CountingProfileDefaultDisplayNameProvider: ProfileDefaultDisplayNameProviding {
    private(set) var callCount = 0
    let displayName: String?

    init(displayName: String?) {
        self.displayName = displayName
    }

    func defaultDisplayName() async -> String? {
        callCount += 1
        return displayName
    }
}

private struct MockCloudAccountStatusClient: CloudAccountStatusClient {
    let status: CKAccountStatus
    let error: Error?

    func accountStatus() async throws -> CKAccountStatus {
        if let error {
            throw error
        }
        return status
    }
}

private struct MockCloudStartupAccountStatusProvider: CloudStartupAccountStatusProviding {
    let status: CloudStartupAccountStatus

    func currentStatus(timeout: TimeInterval) -> CloudStartupAccountStatus {
        _ = timeout
        return status
    }
}

private final class MockRuntimeAccountStatusProvider: AccountStatusProviding {
    private var statuses: [AccountStatus]
    private(set) var fetchCount = 0

    init(statuses: [AccountStatus]) {
        self.statuses = statuses
    }

    func fetchAccountStatus() async -> AccountStatus {
        fetchCount += 1
        guard statuses.count > 1 else {
            return statuses.first ?? .checking
        }

        return statuses.removeFirst()
    }
}
