import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
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
        customExercise.primaryMuscles = [muscle]
        customExercise.aliases = [ExerciseAlias(value: "Backup DB Squat", exercise: customExercise)]
        sourceContext.insert(muscle)
        sourceContext.insert(customExercise)

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
