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
}
