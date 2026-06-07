import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
@MainActor
struct UserDataCloudBackupServiceTests {
    @Test
    func backupRestoresDurableUserDataIntoFreshLocalStores() async throws {
        let sourceLocalContainer = try makeUserDataContainer("BackupSourceLocal")
        let sourceMirrorContainer = try makeUserDataContainer("BackupSourceMirror")
        let sourceContext = ModelContext(sourceLocalContainer)
        let now = Date(timeIntervalSinceReferenceDate: 600)
        let profileID = UUID()
        let folderID = UUID()
        let templateID = UUID()
        let templateExerciseID = UUID()
        let templateSetID = UUID()
        let sessionID = UUID()
        let sessionExerciseID = UUID()
        let sessionSetID = UUID()

        sourceContext.insert(UserProfile(
            id: profileID,
            displayName: "Backup Bro",
            weeklyWorkoutGoal: 6,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now
        ))

        let muscle = MuscleGroup(remoteID: 77, name: "Quads", nameEn: "Quads")
        let customExercise = ExerciseCatalogItem(
            remoteUUID: "backup-custom-squat",
            displayName: "Backup Custom Squat",
            categoryName: "Legs",
            equipmentSummary: "Dumbbell",
            instructionText: "Squat with control.",
            sourceName: "custom",
            updatedAt: now
        )
        sourceContext.insert(muscle)
        sourceContext.insert(customExercise)
        customExercise.primaryMuscles.append(muscle)
        let alias = ExerciseAlias(value: "Backup DB Squat", exercise: customExercise)
        sourceContext.insert(alias)
        customExercise.aliases.append(alias)

        sourceContext.insert(ProfileWidgetConfig(
            id: UUID(),
            kind: .exerciseOneRMTrend,
            isEnabled: true,
            selectedCatalogExerciseUUID: "backup-custom-squat",
            selectedExerciseNameSnapshot: "Backup Custom Squat",
            exerciseTrendMetric: .oneRepMax,
            sortOrder: 3,
            createdAt: now,
            updatedAt: now
        ))

        sourceContext.insert(BlockedBro(
            id: UUID(),
            userRecordName: "blocked-backup-user",
            displayNameSnapshot: "Blocked Backup",
            blockedAt: now
        ))

        let folder = TemplateFolder(
            id: folderID,
            name: "Backup Folder",
            sortOrder: 1,
            createdAt: now,
            updatedAt: now
        )
        sourceContext.insert(folder)
        let template = WorkoutTemplate(
            id: templateID,
            folderID: folderID,
            name: "Backup Template",
            notes: "Template notes",
            createdAt: now,
            updatedAt: now,
            folder: folder
        )
        sourceContext.insert(template)
        sourceContext.insert(TemplateCardioBlock(
            id: UUID(),
            templateID: templateID,
            phase: .preWorkout,
            catalogExerciseUUID: "backup-cardio",
            exerciseNameSnapshot: "Backup Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Cardio",
            targetDurationSeconds: 420,
            createdAt: now,
            updatedAt: now,
            template: template
        ))
        let templateExercise = TemplateExercise(
            id: templateExerciseID,
            templateID: templateID,
            catalogExerciseUUID: "backup-custom-squat",
            exerciseNameSnapshot: "Backup Custom Squat",
            categorySnapshot: "Legs",
            muscleSummarySnapshot: "Quads",
            notes: "Template exercise notes",
            restSeconds: 90,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            template: template
        )
        sourceContext.insert(templateExercise)
        let templateSet = TemplateExerciseSet(
            id: templateSetID,
            templateExerciseID: templateExerciseID,
            sortOrder: 0,
            targetReps: 8,
            targetWeight: 42.5,
            loadUnit: .kg,
            restSeconds: 90,
            createdAt: now,
            updatedAt: now,
            templateExercise: templateExercise
        )
        sourceContext.insert(templateSet)
        sourceContext.insert(TemplateExerciseDropStage(
            id: UUID(),
            templateExerciseSetID: templateSetID,
            sortOrder: 0,
            targetReps: 6,
            targetWeight: 35,
            loadUnit: .kg,
            createdAt: now,
            updatedAt: now,
            templateExerciseSet: templateSet
        ))

        let session = WorkoutSession(
            id: sessionID,
            templateID: templateID,
            name: "Backup Workout",
            status: .completed,
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            durationSeconds: 3600,
            totalVolume: 850,
            prHitsCount: 1,
            notes: "Completed notes",
            createdAt: now,
            updatedAt: now
        )
        sourceContext.insert(session)
        sourceContext.insert(WorkoutSessionCardioBlock(
            id: UUID(),
            sessionID: sessionID,
            phase: .postWorkout,
            catalogExerciseUUID: "backup-cardio",
            exerciseNameSnapshot: "Backup Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Cardio",
            targetDurationSeconds: 300,
            isCompleted: true,
            createdAt: now,
            updatedAt: now,
            session: session
        ))
        let sessionExercise = WorkoutSessionExercise(
            id: sessionExerciseID,
            sessionID: sessionID,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: "backup-custom-squat",
            exerciseNameSnapshot: "Backup Custom Squat",
            categorySnapshot: "Legs",
            muscleSummarySnapshot: "Quads",
            notes: "Session exercise notes",
            restSeconds: 90,
            totalSetCount: 1,
            completedSetCount: 1,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            session: session
        )
        sourceContext.insert(sessionExercise)
        let sessionSet = WorkoutSessionSet(
            id: sessionSetID,
            sessionExerciseID: sessionExerciseID,
            sortOrder: 0,
            targetReps: 8,
            targetWeight: 42.5,
            targetLoadUnit: .kg,
            actualReps: 10,
            actualWeight: 45,
            actualLoadUnit: .kg,
            isCompleted: true,
            createdAt: now,
            updatedAt: now,
            sessionExercise: sessionExercise
        )
        sourceContext.insert(sessionSet)
        sourceContext.insert(WorkoutSessionDropStage(
            id: UUID(),
            sessionSetID: sessionSetID,
            sortOrder: 0,
            targetReps: 6,
            targetWeight: 35,
            targetLoadUnit: .kg,
            actualReps: 7,
            actualWeight: 30,
            actualLoadUnit: .kg,
            isCompleted: true,
            createdAt: now,
            updatedAt: now,
            sessionSet: sessionSet
        ))
        try sourceContext.save()

        let backupStore = FakeUserDataCloudBackupStore()
        try await UserDataCloudBackupService(
            localContainer: sourceLocalContainer,
            mirrorContainer: sourceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()
        #expect(await backupStore.savedRecord() != nil)

        let restoredLocalContainer = try makeUserDataContainer("BackupRestoredLocal")
        let restoredMirrorContainer = try makeUserDataContainer("BackupRestoredMirror")
        let didRestore = try await UserDataCloudBackupService(
            localContainer: restoredLocalContainer,
            mirrorContainer: restoredMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).restoreLatestBackup()

        #expect(didRestore)
        let restoredContext = ModelContext(restoredLocalContainer)
        let restoredProfile = try #require(try fetchProfile(id: profileID, in: restoredContext))
        #expect(restoredProfile.displayName == "Backup Bro")
        #expect(restoredProfile.weeklyWorkoutGoal == 6)
        let restoredExercise = try #require(try fetchExercise(remoteUUID: "backup-custom-squat", in: restoredContext))
        #expect(restoredExercise.displayName == "Backup Custom Squat")
        #expect(restoredExercise.primaryMuscles.map { $0.remoteID } == [77])
        #expect(restoredExercise.aliases.map { $0.value } == ["Backup DB Squat"])
        #expect(try fetchBlockedBro(userRecordName: "blocked-backup-user", in: restoredContext) != nil)
        #expect(try fetchWidget(exerciseUUID: "backup-custom-squat", in: restoredContext) != nil)
        #expect(try fetchTemplate(id: templateID, in: restoredContext)?.name == "Backup Template")
        #expect(try fetchTemplateSet(id: templateSetID, in: restoredContext)?.targetWeight == 42.5)
        #expect(try fetchWorkoutSession(id: sessionID, in: restoredContext)?.totalVolume == 850)
        let restoredSet = try #require(try fetchWorkoutSessionSet(id: sessionSetID, in: restoredContext))
        #expect(restoredSet.actualReps == 10)
        #expect(restoredSet.actualWeight == 45)
        #expect(try fetchWorkoutCardioBlock(sessionID: sessionID, in: restoredContext)?.isCompleted == true)
    }

    @Test
    func staleDirectBackupDoesNotReplaceFresherMirrorData() async throws {
        let sourceLocalContainer = try makeUserDataContainer("StaleBackupSourceLocal")
        let sourceMirrorContainer = try makeUserDataContainer("StaleBackupSourceMirror")
        let sourceContext = ModelContext(sourceLocalContainer)
        let staleProfileID = UUID()
        sourceContext.insert(UserProfile(
            id: staleProfileID,
            displayName: "Stale Backup Profile",
            weeklyWorkoutGoal: 3,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        try sourceContext.save()

        let backupStore = FakeUserDataCloudBackupStore()
        try await UserDataCloudBackupService(
            localContainer: sourceLocalContainer,
            mirrorContainer: sourceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()
        let savedRecordCandidate = await backupStore.savedRecord()
        let savedRecord = try #require(savedRecordCandidate)

        let restoredLocalContainer = try makeUserDataContainer("StaleBackupRestoredLocal")
        let restoredMirrorContainer = try makeUserDataContainer("StaleBackupRestoredMirror")
        let restoredMirrorContext = ModelContext(restoredMirrorContainer)
        let freshProfileID = UUID()
        restoredMirrorContext.insert(UserProfile(
            id: freshProfileID,
            displayName: "Fresh Mirror Profile",
            weeklyWorkoutGoal: 7,
            createdAt: savedRecord.updatedAt.addingTimeInterval(30),
            updatedAt: savedRecord.updatedAt.addingTimeInterval(30)
        ))
        try restoredMirrorContext.save()

        let didRestore = try await UserDataCloudBackupService(
            localContainer: restoredLocalContainer,
            mirrorContainer: restoredMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).restoreLatestBackup()

        #expect(didRestore)
        let restoredLocalContext = ModelContext(restoredLocalContainer)
        #expect(try fetchProfile(id: freshProfileID, in: restoredLocalContext)?.displayName == "Fresh Mirror Profile")
        #expect(try fetchProfile(id: staleProfileID, in: restoredLocalContext) == nil)
    }

    @Test
    func exportMergesExistingDirectBackupBeforeSavingSnapshot() async throws {
        let firstDeviceLocalContainer = try makeUserDataContainer("FirstDeviceLocal")
        let firstDeviceMirrorContainer = try makeUserDataContainer("FirstDeviceMirror")
        let firstDeviceContext = ModelContext(firstDeviceLocalContainer)
        let firstTemplateID = UUID()
        firstDeviceContext.insert(WorkoutTemplate(
            id: firstTemplateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "First Device Template",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        try firstDeviceContext.save()

        let backupStore = FakeUserDataCloudBackupStore()
        try await UserDataCloudBackupService(
            localContainer: firstDeviceLocalContainer,
            mirrorContainer: firstDeviceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()

        let secondDeviceLocalContainer = try makeUserDataContainer("SecondDeviceLocal")
        let secondDeviceMirrorContainer = try makeUserDataContainer("SecondDeviceMirror")
        let secondDeviceContext = ModelContext(secondDeviceLocalContainer)
        let secondTemplateID = UUID()
        secondDeviceContext.insert(WorkoutTemplate(
            id: secondTemplateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Second Device Template",
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        ))
        try secondDeviceContext.save()

        try await UserDataCloudBackupService(
            localContainer: secondDeviceLocalContainer,
            mirrorContainer: secondDeviceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()

        let restoredLocalContainer = try makeUserDataContainer("MergedBackupLocal")
        let restoredMirrorContainer = try makeUserDataContainer("MergedBackupMirror")
        _ = try await UserDataCloudBackupService(
            localContainer: restoredLocalContainer,
            mirrorContainer: restoredMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).restoreLatestBackup()

        let restoredContext = ModelContext(restoredLocalContainer)
        #expect(try fetchTemplate(id: firstTemplateID, in: restoredContext)?.name == "First Device Template")
        #expect(try fetchTemplate(id: secondTemplateID, in: restoredContext)?.name == "Second Device Template")
    }

    @Test
    func restoredProfileBeatsFreshUntouchedLocalDefaultProfile() async throws {
        let localContainer = try makeUserDataContainer("DefaultProfileLocal")
        let mirrorContainer = try makeUserDataContainer("DefaultProfileMirror")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)
        let realProfileID = UUID()

        localContext.insert(UserProfile(
            displayName: "Athlete",
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        ))
        mirrorContext.insert(UserProfile(
            id: realProfileID,
            displayName: "Cloud Bro",
            athleteType: .powerlifting,
            weeklyWorkoutGoal: 6,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer,
            projectionScheduler: { _, _ in }
        ).syncLocalChangesToMirror()

        let syncedLocalContext = ModelContext(localContainer)
        let syncedProfile = try #require(try fetchProfile(id: realProfileID, in: syncedLocalContext))
        #expect(syncedProfile.displayName == "Cloud Bro")
        #expect(syncedProfile.athleteType == .powerlifting)
        #expect(syncedProfile.weeklyWorkoutGoal == 6)
    }

    @Test
    func backupProfileBeatsFreshUntouchedMirrorDefaultProfile() async throws {
        let sourceLocalContainer = try makeUserDataContainer("BackupProfileSourceLocal")
        let sourceMirrorContainer = try makeUserDataContainer("BackupProfileSourceMirror")
        let sourceContext = ModelContext(sourceLocalContainer)
        let realProfileID = UUID()
        sourceContext.insert(UserProfile(
            id: realProfileID,
            displayName: "Real Backup Profile",
            athleteType: .hybridAthlete,
            weeklyWorkoutGoal: 6,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        try sourceContext.save()

        let backupStore = FakeUserDataCloudBackupStore()
        try await UserDataCloudBackupService(
            localContainer: sourceLocalContainer,
            mirrorContainer: sourceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()

        let restoredLocalContainer = try makeUserDataContainer("BackupProfileRestoredLocal")
        let restoredMirrorContainer = try makeUserDataContainer("BackupProfileRestoredMirror")
        let restoredMirrorContext = ModelContext(restoredMirrorContainer)
        restoredMirrorContext.insert(UserProfile(
            displayName: "Athlete",
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        ))
        try restoredMirrorContext.save()

        _ = try await UserDataCloudBackupService(
            localContainer: restoredLocalContainer,
            mirrorContainer: restoredMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).restoreLatestBackup()

        let restoredLocalContext = ModelContext(restoredLocalContainer)
        let restoredProfile = try #require(try fetchProfile(id: realProfileID, in: restoredLocalContext))
        #expect(restoredProfile.displayName == "Real Backup Profile")
        #expect(restoredProfile.athleteType == .hybridAthlete)
        #expect(restoredProfile.weeklyWorkoutGoal == 6)
    }

    @Test
    func backupMergeUsesNewestFolderWhenDuplicateFolderIDsExist() async throws {
        let sourceLocalContainer = try makeUserDataContainer("BackupDuplicateFolderSourceLocal")
        let sourceMirrorContainer = try makeUserDataContainer("BackupDuplicateFolderSourceMirror")
        let sourceContext = ModelContext(sourceLocalContainer)
        let folderID = UUID()
        let templateID = UUID()
        sourceContext.insert(TemplateFolder(
            id: folderID,
            name: "Backup Folder",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        sourceContext.insert(WorkoutTemplate(
            id: templateID,
            folderID: folderID,
            name: "Backup Template In Folder",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        try sourceContext.save()

        let backupStore = FakeUserDataCloudBackupStore()
        try await UserDataCloudBackupService(
            localContainer: sourceLocalContainer,
            mirrorContainer: sourceMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).exportCurrentBackup()

        let restoredLocalContainer = try makeUserDataContainer("BackupDuplicateFolderRestoredLocal")
        let restoredMirrorContainer = try makeUserDataContainer("BackupDuplicateFolderRestoredMirror")
        let restoredMirrorContext = ModelContext(restoredMirrorContainer)
        restoredMirrorContext.insert(TemplateFolder(
            id: folderID,
            name: "Older Duplicate Folder",
            updatedAt: Date(timeIntervalSinceReferenceDate: 10)
        ))
        restoredMirrorContext.insert(TemplateFolder(
            id: folderID,
            name: "Newer Duplicate Folder",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try restoredMirrorContext.save()

        _ = try await UserDataCloudBackupService(
            localContainer: restoredLocalContainer,
            mirrorContainer: restoredMirrorContainer,
            backupStore: backupStore,
            projectionScheduler: { _, _ in }
        ).restoreLatestBackup()

        let restoredLocalContext = ModelContext(restoredLocalContainer)
        #expect(try fetchTemplate(id: templateID, in: restoredLocalContext)?.name == "Backup Template In Folder")
    }

    private func makeUserDataContainer(_ name: String) throws -> ModelContainer {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseAlias.self,
            CustomExerciseCloudRecord.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            BlockedBro.self,
            BlockedBroCloudRecord.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            UserDataDeletionTombstone.self,
        ])
        let configuration = ModelConfiguration(
            "\(name)-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchProfile(id: UUID, in context: ModelContext) throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchExercise(remoteUUID: String, in context: ModelContext) throws -> ExerciseCatalogItem? {
        var descriptor = FetchDescriptor<ExerciseCatalogItem>(predicate: #Predicate { $0.remoteUUID == remoteUUID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchBlockedBro(userRecordName: String, in context: ModelContext) throws -> BlockedBro? {
        var descriptor = FetchDescriptor<BlockedBro>(predicate: #Predicate { $0.userRecordName == userRecordName })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchWidget(exerciseUUID: String, in context: ModelContext) throws -> ProfileWidgetConfig? {
        var descriptor = FetchDescriptor<ProfileWidgetConfig>(
            predicate: #Predicate { $0.selectedCatalogExerciseUUID == exerciseUUID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTemplate(id: UUID, in context: ModelContext) throws -> WorkoutTemplate? {
        var descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTemplateSet(id: UUID, in context: ModelContext) throws -> TemplateExerciseSet? {
        var descriptor = FetchDescriptor<TemplateExerciseSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchWorkoutSession(id: UUID, in context: ModelContext) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchWorkoutSessionSet(id: UUID, in context: ModelContext) throws -> WorkoutSessionSet? {
        var descriptor = FetchDescriptor<WorkoutSessionSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchWorkoutCardioBlock(sessionID: UUID, in context: ModelContext) throws -> WorkoutSessionCardioBlock? {
        var descriptor = FetchDescriptor<WorkoutSessionCardioBlock>(predicate: #Predicate { $0.sessionID == sessionID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

actor FakeUserDataCloudBackupStore: UserDataCloudBackupStoring {
    private var record: UserDataCloudBackupRemoteRecord?

    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws {
        self.record = record
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        record
    }

    func savedRecord() -> UserDataCloudBackupRemoteRecord? {
        record
    }
}
