import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class UserDataCloudBackupServiceTests: XCTestCase {
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
        let sourceTemplate = WorkoutTemplate(id: templateID, folderID: folderID, name: "Day 1 - Upper A")
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
        sourceTemplate.exercises = [sourceExercise]
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
