import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class UserDataCloudBackupServiceTests: XCTestCase {
    func testDuplicateTemplatePreservesPreviousSetTargets() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let template = WorkoutTemplate(
            id: templateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Upper",
            notes: "Original"
        )
        let exercise = TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            template: template
        )
        let set = TemplateExerciseSet(
            id: setID,
            templateExerciseID: exerciseID,
            targetReps: 8,
            targetWeight: 100,
            loadUnit: .kg,
            previousTargetReps: 7,
            previousTargetWeight: 95,
            previousLoadUnit: .kg,
            templateExercise: exercise
        )
        template.exercises = [exercise]
        exercise.prescribedSets = [set]

        context.insert(template)
        context.insert(exercise)
        context.insert(set)
        try context.save()

        let copied = try TemplateRepository(modelContext: context)
            .duplicateTemplate(id: templateID, name: "Upper Copy")

        let copiedExercise = try XCTUnwrap(copied.exercises?.first)
        let copiedSet = try XCTUnwrap(copiedExercise.prescribedSets?.first)
        XCTAssertNotEqual(copiedSet.id, setID)
        XCTAssertEqual(copiedSet.targetReps, 8)
        XCTAssertEqual(copiedSet.targetWeight, 100)
        XCTAssertEqual(copiedSet.previousTargetReps, 7)
        XCTAssertEqual(copiedSet.previousTargetWeight, 95)
        XCTAssertEqual(copiedSet.previousLoadUnit, .kg)
    }

    func testRemoveExerciseRejectsExerciseFromDifferentSession() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let firstSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let firstExerciseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let secondExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let firstSession = WorkoutSession(
            id: firstSessionID,
            name: "Push",
            status: .completed
        )
        let secondSession = WorkoutSession(
            id: secondSessionID,
            name: "Pull",
            status: .completed
        )
        let firstExercise = WorkoutSessionExercise(
            id: firstExerciseID,
            sessionID: firstSessionID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            session: firstSession
        )
        let secondExercise = WorkoutSessionExercise(
            id: secondExerciseID,
            sessionID: secondSessionID,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            session: secondSession
        )
        firstSession.exercises = [firstExercise]
        secondSession.exercises = [secondExercise]

        for model in [
            firstSession,
            secondSession,
            firstExercise,
            secondExercise,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        XCTAssertThrowsError(
            try WorkoutSessionRepository(modelContext: context)
                .removeExercise(sessionID: firstSessionID, sessionExerciseID: secondExerciseID)
        ) { error in
            XCTAssertEqual(error as? WorkoutSessionRepositoryError, .sessionExerciseNotFound)
        }

        let remainingExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
        XCTAssertEqual(Set(remainingExercises.map(\.id)), [firstExerciseID, secondExerciseID])
    }

    func testRestoreLatestBackupPreservesTemplateSupersetGroups() async throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false

        let folder = TemplateFolder(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Folder"
        )
        let template = WorkoutTemplate(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            folderID: folder.id,
            name: "Superset Template",
            folder: folder
        )
        let group = TemplateSupersetGroup(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            templateID: template.id,
            roundRestSeconds: 180,
            template: template
        )
        let firstExercise = TemplateExercise(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            templateID: template.id,
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            supersetGroupID: group.id,
            supersetPosition: .first,
            sortOrder: 0,
            template: template,
            supersetGroup: group
        )
        let secondExercise = TemplateExercise(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            templateID: template.id,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            supersetGroupID: group.id,
            supersetPosition: .second,
            sortOrder: 1,
            template: template,
            supersetGroup: group
        )
        folder.templates = [template]
        template.supersetGroups = [group]
        template.exercises = [firstExercise, secondExercise]
        group.exercises = [firstExercise, secondExercise]

        for model in [
            folder,
            template,
            group,
            firstExercise,
            secondExercise,
        ] as [any PersistentModel] {
            sourceContext.insert(model)
        }
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let restoredContainer = try makeInMemoryContainer()
        _ = try await UserDataCloudBackupService(
            localContainer: restoredContainer,
            backupStore: backupStore
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restoredContainer)
        let restoredGroups = try restoredContext.fetch(FetchDescriptor<TemplateSupersetGroup>())
        XCTAssertEqual(restoredGroups.count, 1)
        XCTAssertEqual(restoredGroups.first?.id, group.id)
        XCTAssertEqual(restoredGroups.first?.templateID, template.id)
        XCTAssertEqual(restoredGroups.first?.roundRestSeconds, 180)

        let restoredExercises = try restoredContext.fetch(FetchDescriptor<TemplateExercise>())
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(restoredExercises.first?.supersetMembership?.roundRestSeconds, 180)
        XCTAssertEqual(restoredExercises.last?.supersetMembership?.roundRestSeconds, 180)
    }

    func testRestoreLatestBackupPreservesAllProfileSettings() async throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        sourceContext.insert(UserProfile(
            displayName: "Peter",
            athleteType: .powerlifting,
            preferredWeightUnit: .lb,
            workoutNotificationStyle: .standard,
            weeklyWorkoutGoal: 5,
            isTrainingGuidanceEnabled: false,
            keepsScreenAwake: true,
            isBozarModeEnabled: true
        ))
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let restoredContainer = try makeInMemoryContainer()
        let restoreResult = try await UserDataCloudBackupService(
            localContainer: restoredContainer,
            backupStore: backupStore
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restoredContainer)
        let profiles = try restoredContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertNotNil(restoreResult)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.displayName, "Peter")
        XCTAssertEqual(profiles.first?.preferredWeightUnit, .lb)
        XCTAssertEqual(profiles.first?.workoutNotificationStyle, .standard)
        XCTAssertEqual(profiles.first?.weeklyWorkoutGoal, 5)
        XCTAssertEqual(profiles.first?.isTrainingGuidanceEnabled, false)
        XCTAssertEqual(profiles.first?.keepsScreenAwake, true)
        XCTAssertEqual(profiles.first?.isBozarModeEnabled, true)
    }

    func testRestoreLatestBackupCanReplaceBrokenLocalTemplates() async throws {
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let exerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let folderID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        sourceContext.autosaveEnabled = false
        let sourceFolder = TemplateFolder(id: folderID, name: "Bro Split")
        let sourceTemplate = WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1 - Upper A", folder: sourceFolder)
        let sourceExercise = TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0,
            template: sourceTemplate
        )
        sourceFolder.templates = [sourceTemplate]
        sourceTemplate.exercises = [sourceExercise]
        sourceContext.insert(sourceFolder)
        sourceContext.insert(sourceTemplate)
        sourceContext.insert(sourceExercise)
        try sourceContext.save()

        let backupStore = CapturingBackupStore()
        _ = try await UserDataCloudBackupService(
            localContainer: sourceContainer,
            backupStore: backupStore
        ).exportCurrentBackup()

        let brokenContainer = try makeInMemoryContainer()
        let brokenContext = ModelContext(brokenContainer)
        brokenContext.autosaveEnabled = false
        brokenContext.insert(WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1 - Upper A"))
        try brokenContext.save()

        let restoreResult = try await UserDataCloudBackupService(
            localContainer: brokenContainer,
            backupStore: backupStore
        ).restoreLatestBackup(replacingLocalData: true)

        let restoredContext = ModelContext(brokenContainer)
        let restoredTemplates = try restoredContext.fetch(FetchDescriptor<WorkoutTemplate>())
        let restoredExercises = try restoredContext.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertNotNil(restoreResult)
        XCTAssertEqual(restoredTemplates.count, 1)
        XCTAssertEqual(restoredExercises.count, 1)
        XCTAssertEqual(restoredExercises.first?.exerciseNameSnapshot, "Lat Pulldown")
    }

    func testDeletingFolderRemovesTemplateRowsFromNextBackup() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let folderID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let exerciseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let setID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

        for model in [
            TemplateFolder(id: folderID, name: "Bro Split"),
            WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1"),
            TemplateCardioBlock(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                templateID: templateID,
                phase: .preWorkout,
                catalogExerciseUUID: "crosstrainer",
                exerciseNameSnapshot: "Crosstrainer",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Quads",
                targetDurationSeconds: 300
            ),
            TemplateSupersetGroup(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                templateID: templateID,
                roundRestSeconds: 120
            ),
            TemplateExercise(
                id: exerciseID,
                templateID: templateID,
                catalogExerciseUUID: "lat-pulldown",
                exerciseNameSnapshot: "Lat Pulldown",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Back"
            ),
            TemplateExerciseComponent(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                templateExerciseID: exerciseID,
                catalogExerciseUUID: "lat-pulldown",
                exerciseNameSnapshot: "Lat Pulldown",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Back"
            ),
            TemplateExerciseSet(
                id: setID,
                templateExerciseID: exerciseID,
                targetReps: 10,
                targetWeight: 60
            ),
            TemplateExerciseDropStage(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                templateExerciseSetID: setID,
                targetReps: 8,
                targetWeight: 40
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        try TemplateRepository(modelContext: context).deleteFolder(id: folderID)
        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: CapturingBackupStore()
        ).exportCurrentBackup()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExerciseSet>()).count, 0)
        XCTAssertEqual(snapshot.contentSummary.templateFolderCount, 0)
        XCTAssertEqual(snapshot.contentSummary.workoutTemplateCount, 0)
        XCTAssertEqual(snapshot.contentSummary.templateExerciseCount, 0)
    }

    func testExportCurrentBackupPrunesOrphanedTemplateRows() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let missingFolderID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let templateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutTemplate(id: templateID, folderID: missingFolderID, name: "Deleted Folder Template"))
        context.insert(TemplateExercise(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back"
        ))
        try context.save()

        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: CapturingBackupStore()
        ).exportCurrentBackup()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).count, 0)
        XCTAssertEqual(snapshot.contentSummary.workoutTemplateCount, 0)
        XCTAssertEqual(snapshot.contentSummary.templateExerciseCount, 0)
    }

    func testHistoryOverviewSummaryUsesSessionExerciseIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            totalVolume: 600
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            totalSetCount: 1,
            completedSetCount: 1,
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 10,
            actualWeight: 60,
            isCompleted: true
        ))
        try context.save()

        let loaded = try HistoryOverviewSnapshotLoader.load(
            modelContext: context,
            selectedDayFilter: nil,
            pageSize: 10
        )

        let row = try XCTUnwrap(loaded.completedSessions.first?.summaryRows.first)
        XCTAssertEqual(row.exercise, "1 x Lat Pulldown")
        XCTAssertNotEqual(row.bestSet, "-")
    }

    func testHistoryProjectionUsesSessionExerciseIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 10,
            actualWeight: 60,
            isCompleted: true
        ))
        try context.save()

        XCTAssertEqual(try HistoryProjectionRepository(modelContext: context).backfillIfNeeded(), 1)
        let facts = try context.fetch(FetchDescriptor<CompletedSetFact>())
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.catalogExerciseUUID, "lat-pulldown")
        XCTAssertEqual(facts.first?.exerciseNameSnapshot, "Lat Pulldown")
    }

    func testWorkoutMetricsUseSessionExerciseIDsForPRsAndVolume() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let olderSessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderExerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: olderSessionID,
            name: "Older Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: olderExerciseID,
            sessionID: olderSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: olderExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true
        ))

        let newerSessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let newerExerciseID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        context.insert(WorkoutSession(
            id: newerSessionID,
            name: "Newer Lower",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400)
        ))
        context.insert(WorkoutSessionExercise(
            id: newerExerciseID,
            sessionID: newerSessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            sortOrder: 0
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            sessionExerciseID: newerExerciseID,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded()

        let metrics = WorkoutMetricsService(modelContext: context)
        let sessionPRs = try metrics.sessionPRAchievements(sessionID: newerSessionID)
        let setPRs = try metrics.sessionSetPRAchievements(sessionID: newerSessionID)
        let summary = try metrics.sessionSummary(sessionID: newerSessionID)

        XCTAssertEqual(sessionPRs.map(\.exerciseName), ["Leg Press"])
        XCTAssertEqual(setPRs.count, 1)
        XCTAssertEqual(Set(setPRs[0].kinds), Set([.strength, .weight, .volume]))
        XCTAssertEqual(summary.totalVolume, 960)
        XCTAssertEqual(summary.prHitsCount, 1)
    }

    func testHistoryDetailUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            totalSetCount: 1,
            completedSetCount: 1
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: sessionID
        )

        let drafts = snapshot.localState.setDraftsByExerciseID[exerciseID]
        XCTAssertEqual(drafts?.count, 1)
        XCTAssertEqual(drafts?.first?.actualReps, 7)
        XCTAssertEqual(drafts?.first?.actualWeight, 120)
    }

    func testPreviousValuesUseSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps"
        ))
        context.insert(WorkoutSessionSet(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            isCompleted: true
        ))
        try context.save()

        let previousMaps = try WorkoutSessionRepository(modelContext: context).previousSetMaps(
            forExercises: ["leg-press"],
            before: Date(timeIntervalSince1970: 300),
            excludingSessionID: nil
        )

        XCTAssertEqual(previousMaps["leg-press"]?[0]?.reps, 7)
        XCTAssertEqual(previousMaps["leg-press"]?[0]?.weight, 120)
    }

    func testActiveWorkoutTemplateStartUsesTemplateChildIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        context.insert(WorkoutTemplate(
            id: templateID,
            folderID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Day 1 - Upper A"
        ))
        context.insert(TemplateCardioBlock(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            templateID: templateID,
            phase: .preWorkout,
            catalogExerciseUUID: "crosstrainer",
            exerciseNameSnapshot: "Crosstrainer",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Quadriceps",
            targetDurationSeconds: 300
        ))
        context.insert(TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "lat-pulldown",
            exerciseNameSnapshot: "Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            targetRepMin: 8,
            targetRepMax: 12,
            restSeconds: 120
        ))
        context.insert(TemplateExerciseComponent(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            templateExerciseID: exerciseID,
            catalogExerciseUUID: "lat-pulldown-wide",
            exerciseNameSnapshot: "Wide Lat Pulldown",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Back",
            sortOrder: 0
        ))
        context.insert(TemplateExerciseSet(
            id: setID,
            templateExerciseID: exerciseID,
            targetReps: 10,
            targetWeight: 60,
            loadUnit: .kg
        ))
        context.insert(TemplateExerciseDropStage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateExerciseSetID: setID,
            targetReps: 8,
            targetWeight: 45,
            loadUnit: .kg
        ))
        try context.save()

        let session = try ActiveWorkoutSessionFactory(modelContext: context)
            .createSessionFromTemplate(templateID: templateID)

        XCTAssertEqual(session.cardioBlocks.count, 1)
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(session.exercises.first?.components.count, 1)
        XCTAssertEqual(session.exercises.first?.exerciseNameSnapshot, "Wide Lat Pulldown")
        XCTAssertEqual(session.exercises.first?.setDrafts.count, 1)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.targetReps, 10)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.targetWeight, 60)
        XCTAssertEqual(session.exercises.first?.setDrafts.first?.dropStages.first?.targetWeight, 45)
    }

    func testCreateTemplateFromWorkoutUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Day 4 - Lower B",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        ))
        context.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "leg-press",
            exerciseNameSnapshot: "Leg Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Quadriceps",
            restSeconds: 150
        ))
        context.insert(WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            actualReps: 7,
            actualWeight: 120,
            actualLoadUnit: .kg,
            isCompleted: true
        ))
        context.insert(WorkoutSessionDropStage(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            sessionSetID: setID,
            actualReps: 5,
            actualWeight: 90,
            actualLoadUnit: .kg,
            isCompleted: true
        ))
        try context.save()

        _ = try TemplateRepository(modelContext: context)
            .createTemplate(fromSessionID: sessionID, name: "Copied Lower")

        let templateSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>())
        let templateDropStages = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
        XCTAssertEqual(templateSets.count, 1)
        XCTAssertEqual(templateSets.first?.targetReps, 7)
        XCTAssertEqual(templateSets.first?.targetWeight, 120)
        XCTAssertEqual(templateDropStages.first?.targetReps, 5)
        XCTAssertEqual(templateDropStages.first?.targetWeight, 90)
    }

    func testProgressComparisonUsesSessionChildIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let templateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderSessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let newerSessionID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let olderExerciseID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let newerExerciseID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!

        for model in [
            WorkoutSession(
                id: olderSessionID,
                templateID: templateID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200)
            ),
            WorkoutSession(
                id: newerSessionID,
                templateID: templateID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 300),
                endedAt: Date(timeIntervalSince1970: 400)
            ),
            WorkoutSessionExercise(
                id: olderExerciseID,
                sessionID: olderSessionID,
                catalogExerciseUUID: "leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionExercise(
                id: newerExerciseID,
                sessionID: newerSessionID,
                catalogExerciseUUID: "leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionSet(
                sessionExerciseID: olderExerciseID,
                actualReps: 8,
                actualWeight: 100,
                isCompleted: true
            ),
            WorkoutSessionSet(
                sessionExerciseID: newerExerciseID,
                actualReps: 8,
                actualWeight: 120,
                isCompleted: true
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let snapshot = try WorkoutProgressSnapshotLoader.load(
            modelContext: context,
            selectedPreviousSessionID: olderSessionID,
            selectedCurrentSessionID: newerSessionID
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected progress comparison")
        }
        XCTAssertEqual(comparison.exerciseComparisons.count, 1)
        XCTAssertEqual(comparison.exerciseComparisons.first?.exerciseName, "Leg Press")
        XCTAssertEqual(comparison.exerciseComparisons.first?.direction, .up)
        XCTAssertEqual(comparison.currentWorkout.completedSetCount, 1)
    }

    func testHistoryDetailMuscleHeatmapUsesSessionSetIDs() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        for model in [
            WorkoutSession(
                id: sessionID,
                name: "Day 4 - Lower B",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200)
            ),
            WorkoutSessionExercise(
                id: exerciseID,
                sessionID: sessionID,
                catalogExerciseUUID: "custom-leg-press",
                exerciseNameSnapshot: "Leg Press",
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Quadriceps"
            ),
            WorkoutSessionSet(
                sessionExerciseID: exerciseID,
                actualReps: 8,
                actualWeight: 120,
                isCompleted: true
            ),
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let snapshot = try HistoryDetailSnapshotBuilder.load(
            modelContext: context,
            sessionID: sessionID
        )

        XCTAssertFalse(snapshot.muscleHeatmap.entries.isEmpty)
        XCTAssertTrue(snapshot.muscleHeatmap.topRegionNames.contains("Quadriceps"))
    }

    func testExportCurrentBackupIncludesOnlyCompletedWorkoutChildren() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let completedSession = WorkoutSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Completed",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let completedExercise = WorkoutSessionExercise(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sessionID: completedSession.id,
            catalogExerciseUUID: "completed-bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 1,
            completedSetCount: 1,
            session: completedSession
        )
        let completedSet = WorkoutSessionSet(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sessionExerciseID: completedExercise.id,
            sortOrder: 0,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: completedExercise
        )

        let activeSession = WorkoutSession(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Active",
            status: .active,
            startedAt: Date(timeIntervalSince1970: 300)
        )
        let activeExercise = WorkoutSessionExercise(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            sessionID: activeSession.id,
            catalogExerciseUUID: "active-squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Legs",
            totalSetCount: 1,
            completedSetCount: 0,
            session: activeSession
        )
        let activeSet = WorkoutSessionSet(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            sessionExerciseID: activeExercise.id,
            sortOrder: 0,
            actualReps: 5,
            actualWeight: 120,
            isCompleted: false,
            sessionExercise: activeExercise
        )

        for model in [
            completedSession,
            completedExercise,
            completedSet,
            activeSession,
            activeExercise,
            activeSet,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        let backupStore = CapturingBackupStore()
        let snapshot = try await UserDataCloudBackupService(
            localContainer: container,
            backupStore: backupStore
        ).exportCurrentBackup()

        let summary = snapshot.contentSummary
        let completedWorkoutCount = summary.completedWorkoutCount
        let workoutExerciseCount = summary.workoutExerciseCount
        let workoutSetCount = summary.workoutSetCount
        XCTAssertEqual(completedWorkoutCount, 1)
        XCTAssertEqual(workoutExerciseCount, 1)
        XCTAssertEqual(workoutSetCount, 1)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            UserDataDeletionTombstone.self,
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
        ])

        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }
}

private actor CapturingBackupStore: UserDataCloudBackupStoring {
    private var record: UserDataCloudBackupRemoteRecord?

    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws {
        self.record = record
    }

    func deleteBackup() async throws {
        record = nil
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        record
    }

    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        nil
    }
}
