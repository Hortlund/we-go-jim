import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
struct UserDataCloudMirrorBridgeTests {
    @Test
    func bridgeExportsNewerLocalProfileToMirror() async throws {
        let profileID = UUID()
        let localContainer = try makeUserDataContainer("LocalProfileExport")
        let mirrorContainer = try makeUserDataContainer("MirrorProfileExport")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserProfile(
            id: profileID,
            displayName: "Local Name",
            weeklyWorkoutGoal: 5,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        mirrorContext.insert(UserProfile(
            id: profileID,
            displayName: "Mirror Name",
            weeklyWorkoutGoal: 3,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 15)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrored = try #require(try fetchProfile(id: profileID, in: ModelContext(mirrorContainer)))
        #expect(mirrored.displayName == "Local Name")
        #expect(mirrored.weeklyWorkoutGoal == 5)
        #expect(mirrored.updatedAt == Date(timeIntervalSinceReferenceDate: 20))
    }

    @Test
    func bridgeImportsNewerMirrorProfileToLocal() async throws {
        let profileID = UUID()
        let localContainer = try makeUserDataContainer("LocalProfileImport")
        let mirrorContainer = try makeUserDataContainer("MirrorProfileImport")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserProfile(
            id: profileID,
            displayName: "Local Name",
            weeklyWorkoutGoal: 5,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        mirrorContext.insert(UserProfile(
            id: profileID,
            displayName: "Mirror Name",
            weeklyWorkoutGoal: 6,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let local = try #require(try fetchProfile(id: profileID, in: ModelContext(localContainer)))
        #expect(local.displayName == "Mirror Name")
        #expect(local.weeklyWorkoutGoal == 6)
        #expect(local.updatedAt == Date(timeIntervalSinceReferenceDate: 30))
    }

    @Test
    func bridgeAppliesProfileTombstoneToMirrorInsteadOfResurrectingDeletedProfile() async throws {
        let profileID = UUID()
        let localContainer = try makeUserDataContainer("LocalProfileDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorProfileDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserDataDeletionTombstone(
            entityName: "UserProfile",
            entityID: profileID,
            deletedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        mirrorContext.insert(UserProfile(
            id: profileID,
            displayName: "Deleted Remote Profile",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let refreshedMirrorContext = ModelContext(mirrorContainer)
        #expect(try fetchProfile(id: profileID, in: refreshedMirrorContext) == nil)
        #expect(try fetchTombstone(entityName: "UserProfile", entityID: profileID, in: refreshedMirrorContext) != nil)
    }

    @Test
    func bridgeImportsNewerMirrorProfileWidgetConfigToLocal() async throws {
        let configID = UUID()
        let localContainer = try makeUserDataContainer("LocalWidgetConfigImport")
        let mirrorContainer = try makeUserDataContainer("MirrorWidgetConfigImport")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(ProfileWidgetConfig(
            id: configID,
            kind: .exerciseVolumeTrend,
            isEnabled: false,
            selectedCatalogExerciseUUID: "local-bench",
            selectedExerciseNameSnapshot: "Local Bench",
            exerciseTrendMetric: .volume,
            sortOrder: 7,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        mirrorContext.insert(ProfileWidgetConfig(
            id: configID,
            kind: .exerciseOneRMTrend,
            isEnabled: true,
            selectedCatalogExerciseUUID: "remote-squat",
            selectedExerciseNameSnapshot: "Remote Squat",
            exerciseTrendMetric: .oneRepMax,
            sortOrder: 2,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let local = try #require(try fetchProfileWidgetConfig(id: configID, in: ModelContext(localContainer)))
        #expect(local.kind == .exerciseOneRMTrend)
        #expect(local.isEnabled)
        #expect(local.selectedCatalogExerciseUUID == "remote-squat")
        #expect(local.selectedExerciseNameSnapshot == "Remote Squat")
        #expect(local.exerciseTrendMetric == .oneRepMax)
        #expect(local.sortOrder == 2)
        #expect(local.updatedAt == Date(timeIntervalSinceReferenceDate: 30))
    }

    @Test
    func bridgeExportsNewerLocalProfileWidgetConfigToMirror() async throws {
        let configID = UUID()
        let localContainer = try makeUserDataContainer("LocalWidgetConfigExport")
        let mirrorContainer = try makeUserDataContainer("MirrorWidgetConfigExport")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(ProfileWidgetConfig(
            id: configID,
            kind: .exerciseVolumeTrend,
            isEnabled: true,
            selectedCatalogExerciseUUID: "local-deadlift",
            selectedExerciseNameSnapshot: "Local Deadlift",
            exerciseTrendMetric: .volume,
            sortOrder: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 40)
        ))
        mirrorContext.insert(ProfileWidgetConfig(
            id: configID,
            kind: .prs,
            isEnabled: false,
            sortOrder: 0,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrored = try #require(try fetchProfileWidgetConfig(id: configID, in: ModelContext(mirrorContainer)))
        #expect(mirrored.kind == .exerciseVolumeTrend)
        #expect(mirrored.isEnabled)
        #expect(mirrored.selectedCatalogExerciseUUID == "local-deadlift")
        #expect(mirrored.selectedExerciseNameSnapshot == "Local Deadlift")
        #expect(mirrored.exerciseTrendMetric == .volume)
        #expect(mirrored.sortOrder == 4)
        #expect(mirrored.updatedAt == Date(timeIntervalSinceReferenceDate: 40))
    }

    @Test
    func bridgeImportsCustomizedMirrorBuiltInWidgetOverFreshLocalDefault() async throws {
        let localConfigID = UUID()
        let mirrorConfigID = UUID()
        let localContainer = try makeUserDataContainer("LocalWidgetDefaultImport")
        let mirrorContainer = try makeUserDataContainer("MirrorWidgetDefaultImport")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(ProfileWidgetConfig(
            id: localConfigID,
            kind: .weeklyGoals,
            isEnabled: true,
            sortOrder: 1,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        mirrorContext.insert(ProfileWidgetConfig(
            id: mirrorConfigID,
            kind: .weeklyGoals,
            isEnabled: false,
            sortOrder: 6,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let local = try #require(try fetchProfileWidgetConfig(id: mirrorConfigID, in: ModelContext(localContainer)))
        #expect(local.kind == .weeklyGoals)
        #expect(!local.isEnabled)
        #expect(local.sortOrder == 6)
        #expect(local.updatedAt == Date(timeIntervalSinceReferenceDate: 20))
    }

    @Test
    func bridgeImportsMirrorBlockedBroToLocal() async throws {
        let blockedID = UUID()
        let localContainer = try makeUserDataContainer("LocalBlockedBroImport")
        let mirrorContainer = try makeUserDataContainer("MirrorBlockedBroImport")
        let mirrorContext = ModelContext(mirrorContainer)

        mirrorContext.insert(BlockedBroCloudRecord(
            id: blockedID,
            userRecordName: "remote-blocked-user",
            displayNameSnapshot: "Remote Blocked",
            blockedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let local = try #require(try fetchBlockedBro(userRecordName: "remote-blocked-user", in: ModelContext(localContainer)))
        #expect(local.id == blockedID)
        #expect(local.displayNameSnapshot == "Remote Blocked")
        #expect(local.blockedAt == Date(timeIntervalSinceReferenceDate: 30))
    }

    @Test
    func bridgeExportsLocalBlockedBroToMirror() async throws {
        let blockedID = UUID()
        let localContainer = try makeUserDataContainer("LocalBlockedBroExport")
        let mirrorContainer = try makeUserDataContainer("MirrorBlockedBroExport")
        let localContext = ModelContext(localContainer)

        localContext.insert(BlockedBro(
            id: blockedID,
            userRecordName: "local-blocked-user",
            displayNameSnapshot: "Local Blocked",
            blockedAt: Date(timeIntervalSinceReferenceDate: 40)
        ))
        try localContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrored = try #require(try fetchBlockedBroCloudRecord(userRecordName: "local-blocked-user", in: ModelContext(mirrorContainer)))
        #expect(mirrored.id == blockedID)
        #expect(mirrored.displayNameSnapshot == "Local Blocked")
        #expect(mirrored.blockedAt == Date(timeIntervalSinceReferenceDate: 40))
    }

    @Test
    func bridgeAppliesBlockedBroTombstoneToMirrorInsteadOfResurrectingUnblockedUser() async throws {
        let blockedID = UUID()
        let localContainer = try makeUserDataContainer("LocalBlockedBroDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorBlockedBroDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserDataDeletionTombstone(
            entityName: "BlockedBro",
            entityID: blockedID,
            deletedAt: Date(timeIntervalSinceReferenceDate: 50)
        ))
        mirrorContext.insert(BlockedBroCloudRecord(
            id: blockedID,
            userRecordName: "deleted-blocked-user",
            displayNameSnapshot: "Deleted Blocked",
            blockedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let refreshedMirrorContext = ModelContext(mirrorContainer)
        #expect(try fetchBlockedBroCloudRecord(userRecordName: "deleted-blocked-user", in: refreshedMirrorContext) == nil)
        #expect(try fetchTombstone(entityName: "BlockedBro", entityID: blockedID, in: refreshedMirrorContext) != nil)
    }

    @Test
    func bridgeImportsMirrorCustomExerciseToLocalCatalog() async throws {
        let localContainer = try makeUserDataContainer("LocalCustomExerciseImport")
        let mirrorContainer = try makeUserDataContainer("MirrorCustomExerciseImport")
        let mirrorContext = ModelContext(mirrorContainer)
        let exercise = CustomExerciseCloudRecord(
            remoteUUID: "custom-remote-press",
            displayName: "Remote Press",
            categoryName: "Chest",
            equipmentSummary: "Cable",
            instructionText: "Press with control.",
            updatedAt: Date(timeIntervalSinceReferenceDate: 30),
            aliasesData: try JSONEncoder().encode(["Cable Remote Press"]),
            primaryMusclesData: try JSONEncoder().encode([
                CustomExerciseCloudMuscleSnapshot(remoteID: 1, name: "Chest", nameEn: "Chest"),
            ]),
            secondaryMusclesData: try JSONEncoder().encode([
                CustomExerciseCloudMuscleSnapshot(remoteID: 2, name: "Triceps", nameEn: "Triceps"),
            ])
        )
        mirrorContext.insert(exercise)
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let local = try #require(try fetchExercise(remoteUUID: "custom-remote-press", in: ModelContext(localContainer)))
        #expect(local.displayName == "Remote Press")
        #expect(local.sourceName == "custom")
        #expect(local.instructionText == "Press with control.")
        #expect(local.primaryMuscles.map { $0.remoteID } == [1])
        #expect(local.secondaryMuscles.map { $0.remoteID } == [2])
        #expect(local.aliases.map { $0.value } == ["Cable Remote Press"])
    }

    @Test
    func bridgeExportsLocalCustomExerciseToMirrorCatalog() async throws {
        let localContainer = try makeUserDataContainer("LocalCustomExerciseExport")
        let mirrorContainer = try makeUserDataContainer("MirrorCustomExerciseExport")
        let localContext = ModelContext(localContainer)
        let legs = MuscleGroup(remoteID: 3, name: "Legs", nameEn: "Legs")
        let exercise = ExerciseCatalogItem(
            remoteUUID: "custom-local-squat",
            displayName: "Local Squat",
            categoryName: "Legs",
            equipmentSummary: "Dumbbell",
            instructionText: "Squat tall.",
            isCurated: false,
            sourceName: "custom",
            updatedAt: Date(timeIntervalSinceReferenceDate: 40)
        )
        localContext.insert(legs)
        localContext.insert(exercise)
        exercise.primaryMuscles.append(legs)
        let alias = ExerciseAlias(value: "DB Squat", exercise: exercise)
        localContext.insert(alias)
        exercise.aliases.append(alias)
        try localContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrored = try #require(try fetchCustomExerciseCloudRecord(remoteUUID: "custom-local-squat", in: ModelContext(mirrorContainer)))
        #expect(mirrored.displayName == "Local Squat")
        #expect(mirrored.instructionText == "Squat tall.")
        let mirroredPrimaryMuscleIDs = try JSONDecoder()
            .decode([CustomExerciseCloudMuscleSnapshot].self, from: try #require(mirrored.primaryMusclesData))
            .map { $0.remoteID }
        #expect(mirroredPrimaryMuscleIDs == [3])
        #expect(try JSONDecoder().decode([String].self, from: try #require(mirrored.aliasesData)) == ["DB Squat"])
    }

    @Test
    func bridgeAppliesCustomExerciseTombstoneToMirrorInsteadOfResurrectingDeletedExercise() async throws {
        let localContainer = try makeUserDataContainer("LocalCustomExerciseDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorCustomExerciseDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserDataDeletionTombstone(
            entityName: "ExerciseCatalogItem",
            entityID: UUID(),
            entityKey: "custom-deleted-row",
            deletedAt: Date(timeIntervalSinceReferenceDate: 50)
        ))
        mirrorContext.insert(CustomExerciseCloudRecord(
            remoteUUID: "custom-deleted-row",
            displayName: "Deleted Row",
            categoryName: "Back",
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let refreshedMirrorContext = ModelContext(mirrorContainer)
        #expect(try fetchCustomExerciseCloudRecord(remoteUUID: "custom-deleted-row", in: refreshedMirrorContext) == nil)
        #expect(try fetchTombstone(entityName: "ExerciseCatalogItem", entityKey: "custom-deleted-row", in: refreshedMirrorContext) != nil)
    }

    @Test
    func bridgeExportsTemplateAggregateToMirror() async throws {
        let templateID = UUID()
        let folderID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let localContainer = try makeUserDataContainer("LocalTemplateExport")
        let mirrorContainer = try makeUserDataContainer("MirrorTemplateExport")
        let localContext = ModelContext(localContainer)

        let template = WorkoutTemplate(
            id: templateID,
            folderID: folderID,
            name: "Push Day",
            notes: "Bench first",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let exercise = TemplateExercise(
            id: exerciseID,
            templateID: templateID,
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            sortOrder: 0,
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let set = TemplateExerciseSet(
            id: setID,
            templateExerciseID: exerciseID,
            sortOrder: 0,
            targetReps: 8,
            targetWeight: 100,
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        localContext.insert(template)
        localContext.insert(exercise)
        localContext.insert(set)
        try localContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrorContext = ModelContext(mirrorContainer)
        let mirroredTemplate = try #require(try fetchTemplate(id: templateID, in: mirrorContext))
        let mirroredExercise = try #require(try fetchTemplateExercise(id: exerciseID, in: mirrorContext))
        let mirroredSet = try #require(try fetchTemplateSet(id: setID, in: mirrorContext))
        #expect(mirroredTemplate.name == "Push Day")
        #expect(mirroredExercise.exerciseNameSnapshot == "Bench Press")
        #expect(mirroredSet.targetReps == 8)
    }

    @Test
    func bridgeUsesNewestTemplateWhenDuplicateIDsExist() async throws {
        let templateID = UUID()
        let localContainer = try makeUserDataContainer("LocalDuplicateTemplateExport")
        let mirrorContainer = try makeUserDataContainer("MirrorDuplicateTemplateExport")
        let localContext = ModelContext(localContainer)

        localContext.insert(WorkoutTemplate(
            id: templateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Older Duplicate",
            updatedAt: Date(timeIntervalSinceReferenceDate: 10)
        ))
        localContext.insert(WorkoutTemplate(
            id: templateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Newer Duplicate",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let mirrorContext = ModelContext(mirrorContainer)
        let mirroredTemplate = try #require(try fetchTemplate(id: templateID, in: mirrorContext))
        #expect(mirroredTemplate.name == "Newer Duplicate")
    }

    @Test
    func bridgeImportsCompletedWorkoutAggregateToLocal() async throws {
        let sessionID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let localContainer = try makeUserDataContainer("LocalWorkoutImport")
        let mirrorContainer = try makeUserDataContainer("MirrorWorkoutImport")
        let mirrorContext = ModelContext(mirrorContainer)

        let session = WorkoutSession(
            id: sessionID,
            name: "Remote Workout",
            status: .completed,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
            endedAt: Date(timeIntervalSinceReferenceDate: 20),
            durationSeconds: 600,
            totalVolume: 800,
            prHitsCount: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )
        let exercise = WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Legs",
            totalSetCount: 1,
            completedSetCount: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )
        let set = WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 5,
            actualWeight: 140,
            isCompleted: true,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )
        mirrorContext.insert(session)
        mirrorContext.insert(exercise)
        mirrorContext.insert(set)
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let localContext = ModelContext(localContainer)
        let localSession = try #require(try fetchWorkoutSession(id: sessionID, in: localContext))
        let localExercise = try #require(try fetchWorkoutExercise(id: exerciseID, in: localContext))
        let localSet = try #require(try fetchWorkoutSet(id: setID, in: localContext))
        #expect(localSession.name == "Remote Workout")
        #expect(localExercise.exerciseNameSnapshot == "Squat")
        #expect(localSet.actualReps == 5)
    }

    @Test
    func bridgeSchedulesHistoryProjectionForImportedCompletedWorkout() async throws {
        let sessionID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let localContainer = try makeUserDataContainer("LocalWorkoutProjectionImport")
        let mirrorContainer = try makeUserDataContainer("MirrorWorkoutProjectionImport")
        let mirrorContext = ModelContext(mirrorContainer)
        let projectionRecorder = ProjectionScheduleRecorder()

        mirrorContext.insert(WorkoutSession(
            id: sessionID,
            name: "Remote Workout",
            status: .completed,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
            endedAt: Date(timeIntervalSinceReferenceDate: 20),
            durationSeconds: 600,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        mirrorContext.insert(WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Legs",
            totalSetCount: 1,
            completedSetCount: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        mirrorContext.insert(WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            sortOrder: 0,
            actualReps: 5,
            actualWeight: 140,
            isCompleted: true,
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer,
            projectionScheduler: { sessionIDs, _ in
                projectionRecorder.record(sessionIDs)
            }
        ).syncLocalChangesToMirror()

        #expect(projectionRecorder.recordedSessionIDs == [sessionID])
    }

    @Test
    func bridgeSchedulesHistoryProjectionCleanupForImportedCompletedWorkoutTombstone() async throws {
        let sessionID = UUID()
        let localContainer = try makeUserDataContainer("LocalSessionProjectionDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorSessionProjectionDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)
        let projectionRecorder = ProjectionScheduleRecorder()

        localContext.insert(WorkoutSession(
            id: sessionID,
            name: "Deleted Session",
            status: .completed,
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        mirrorContext.insert(UserDataDeletionTombstone(
            entityName: "WorkoutSession",
            entityID: sessionID,
            deletedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer,
            projectionScheduler: { sessionIDs, _ in
                projectionRecorder.record(sessionIDs)
            }
        ).syncLocalChangesToMirror()

        #expect(projectionRecorder.recordedSessionIDs == [sessionID])
    }

    @Test
    func bridgeAppliesTemplateTombstoneToMirrorInsteadOfResurrectingDeletedTemplate() async throws {
        let templateID = UUID()
        let localContainer = try makeUserDataContainer("LocalTemplateDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorTemplateDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserDataDeletionTombstone(
            entityName: "WorkoutTemplate",
            entityID: templateID,
            deletedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        mirrorContext.insert(WorkoutTemplate(
            id: templateID,
            folderID: UUID(),
            name: "Deleted Template",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let refreshedMirrorContext = ModelContext(mirrorContainer)
        #expect(try fetchTemplate(id: templateID, in: refreshedMirrorContext) == nil)
        #expect(try fetchTombstone(entityName: "WorkoutTemplate", entityID: templateID, in: refreshedMirrorContext) != nil)
    }

    @Test
    func bridgeAppliesCompletedWorkoutTombstoneToMirrorInsteadOfResurrectingDeletedSession() async throws {
        let sessionID = UUID()
        let localContainer = try makeUserDataContainer("LocalSessionDelete")
        let mirrorContainer = try makeUserDataContainer("MirrorSessionDelete")
        let localContext = ModelContext(localContainer)
        let mirrorContext = ModelContext(mirrorContainer)

        localContext.insert(UserDataDeletionTombstone(
            entityName: "WorkoutSession",
            entityID: sessionID,
            deletedAt: Date(timeIntervalSinceReferenceDate: 30)
        ))
        mirrorContext.insert(WorkoutSession(
            id: sessionID,
            name: "Deleted Session",
            status: .completed,
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try localContext.save()
        try mirrorContext.save()

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()

        let refreshedMirrorContext = ModelContext(mirrorContainer)
        #expect(try fetchWorkoutSession(id: sessionID, in: refreshedMirrorContext) == nil)
        #expect(try fetchTombstone(entityName: "WorkoutSession", entityID: sessionID, in: refreshedMirrorContext) != nil)
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
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { profile in
                profile.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchProfileWidgetConfig(id: UUID, in context: ModelContext) throws -> ProfileWidgetConfig? {
        var descriptor = FetchDescriptor<ProfileWidgetConfig>(
            predicate: #Predicate { config in
                config.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchBlockedBro(userRecordName: String, in context: ModelContext) throws -> BlockedBro? {
        var descriptor = FetchDescriptor<BlockedBro>(
            predicate: #Predicate { item in
                item.userRecordName == userRecordName
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchBlockedBroCloudRecord(
        userRecordName: String,
        in context: ModelContext
    ) throws -> BlockedBroCloudRecord? {
        var descriptor = FetchDescriptor<BlockedBroCloudRecord>(
            predicate: #Predicate { item in
                item.userRecordName == userRecordName
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchExercise(remoteUUID: String, in context: ModelContext) throws -> ExerciseCatalogItem? {
        var descriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { item in
                item.remoteUUID == remoteUUID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchCustomExerciseCloudRecord(
        remoteUUID: String,
        in context: ModelContext
    ) throws -> CustomExerciseCloudRecord? {
        var descriptor = FetchDescriptor<CustomExerciseCloudRecord>(
            predicate: #Predicate { item in
                item.remoteUUID == remoteUUID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTemplate(id: UUID, in context: ModelContext) throws -> WorkoutTemplate? {
        var descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTemplateExercise(id: UUID, in context: ModelContext) throws -> TemplateExercise? {
        var descriptor = FetchDescriptor<TemplateExercise>(predicate: #Predicate { $0.id == id })
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

    private func fetchWorkoutExercise(id: UUID, in context: ModelContext) throws -> WorkoutSessionExercise? {
        var descriptor = FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchWorkoutSet(id: UUID, in context: ModelContext) throws -> WorkoutSessionSet? {
        var descriptor = FetchDescriptor<WorkoutSessionSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTombstone(
        entityName: String,
        entityID: UUID,
        in context: ModelContext
    ) throws -> UserDataDeletionTombstone? {
        var descriptor = FetchDescriptor<UserDataDeletionTombstone>(
            predicate: #Predicate { tombstone in
                tombstone.entityName == entityName && tombstone.entityID == entityID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTombstone(
        entityName: String,
        entityKey: String,
        in context: ModelContext
    ) throws -> UserDataDeletionTombstone? {
        try context.fetch(FetchDescriptor<UserDataDeletionTombstone>()).first {
            $0.entityName == entityName && $0.entityKey == entityKey
        }
    }
}

private final class ProjectionScheduleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionIDs: Set<UUID> = []

    var recordedSessionIDs: Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        return sessionIDs
    }

    func record(_ ids: Set<UUID>) {
        lock.lock()
        defer { lock.unlock() }
        sessionIDs.formUnion(ids)
    }
}
