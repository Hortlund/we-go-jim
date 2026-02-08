import Foundation
import SwiftData
import Testing
@testable import WoK

@MainActor
struct WorkoutMetricsServiceTests {
    @Test
    func estimatedOneRepMaxUsesEpleyFormula() throws {
        let context = try makeInMemoryContext()
        let metrics = WorkoutMetricsService(modelContext: context)
        let result = metrics.estimatedOneRepMax(weight: 100, reps: 5)
        #expect(abs(result - 116.6666667) < 0.01)
    }

    @Test
    func countPRHitsCountsInSessionImprovements() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "bench-pr",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let first = try sessionRepository.createEmptySession(name: "Session 1")
        try sessionRepository.addExercise(sessionID: first.id, catalogItem: exercise)
        let firstExercise = try sessionRepository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[0].actualWeight = 100
        firstDrafts[0].actualReps = 5
        firstDrafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try sessionRepository.finishSession(sessionID: first.id)

        let second = try sessionRepository.createEmptySession(name: "Session 2")
        try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
        let secondExercise = try sessionRepository.sessionExercises(sessionID: second.id).first!
        var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[0].actualWeight = 102.5
        secondDrafts[0].actualReps = 5
        secondDrafts[0].isCompleted = true
        secondDrafts[1].actualWeight = 90
        secondDrafts[1].actualReps = 10
        secondDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try sessionRepository.finishSession(sessionID: second.id)

        let refreshed = try sessionRepository.session(id: second.id)
        #expect((refreshed?.prHitsCount ?? 0) == 2)
    }

    @Test
    func weeklyWorkoutProgressUsesProfileGoal() throws {
        let context = try makeInMemoryContext()
        let profileRepository = ProfileRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let profile = try profileRepository.loadOrCreateProfile()
        profile.weeklyWorkoutGoal = 5
        try context.save()

        let calendar = Calendar.current
        let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) ?? startOfThisWeek

        let sessionA = WorkoutSession(
            templateID: nil,
            name: "A",
            status: .completed,
            startedAt: lastWeek,
            endedAt: lastWeek.addingTimeInterval(3600),
            durationSeconds: 3600,
            totalVolume: 0,
            prHitsCount: 0
        )
        let sessionB = WorkoutSession(
            templateID: nil,
            name: "B",
            status: .completed,
            startedAt: startOfThisWeek,
            endedAt: startOfThisWeek.addingTimeInterval(1800),
            durationSeconds: 1800,
            totalVolume: 0,
            prHitsCount: 0
        )
        context.insert(sessionA)
        context.insert(sessionB)
        try context.save()

        let points = try metrics.weeklyWorkoutProgress(weeks: 2)
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.goal == 5 })
        #expect(points.map(\.completedWorkouts).reduce(0, +) == 2)
    }

    @Test
    func profileDashboardSnapshotReturnsPRsAndWeeklyDataInOnePass() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let profileRepository = ProfileRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let profile = try profileRepository.loadOrCreateProfile()
        profile.weeklyWorkoutGoal = 3
        try context.save()

        let exercise = ExerciseCatalogItem(
            remoteUUID: "dashboard-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let session = try sessionRepository.createEmptySession(name: "Push")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[0].actualWeight = 100
        drafts[0].actualReps = 5
        drafts[0].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.weeklyGoal == 3)
        #expect(snapshot.personalRecords.count == 1)
        #expect(snapshot.personalRecords.first?.exerciseName == "Bench Press")
        #expect(snapshot.weeklyProgress.count == 4)
        #expect(snapshot.weeklyProgress.allSatisfy { $0.goal == 3 })
        #expect(snapshot.weeklyProgress.map(\.completedWorkouts).reduce(0, +) == 1)
    }

    @Test
    func widgetRepositoryAddRemoveReorderPersists() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        var enabled = try repository.enabledConfigurations()
        #expect(enabled.count == 2)

        try repository.setEnabled(kind: .prs, isEnabled: false)
        enabled = try repository.enabledConfigurations()
        #expect(enabled.count == 1)
        #expect(enabled.first?.kind == .weeklyGoals)

        try repository.setEnabled(kind: .prs, isEnabled: true)
        try repository.moveEnabledWidget(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        enabled = try repository.enabledConfigurations()
        #expect(enabled.count == 2)
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
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
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
