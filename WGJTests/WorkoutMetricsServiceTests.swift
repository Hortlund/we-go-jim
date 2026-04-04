import Foundation
import SwiftData
import Testing
@testable import WGJ

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
        firstDrafts[1].actualWeight = 100
        firstDrafts[1].actualReps = 5
        firstDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try sessionRepository.finishSession(sessionID: first.id)

        let second = try sessionRepository.createEmptySession(name: "Session 2")
        try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
        let secondExercise = try sessionRepository.sessionExercises(sessionID: second.id).first!
        var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[1].actualWeight = 102.5
        secondDrafts[1].actualReps = 5
        secondDrafts[1].isCompleted = true
        secondDrafts[2].actualWeight = 90
        secondDrafts[2].actualReps = 10
        secondDrafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try sessionRepository.finishSession(sessionID: second.id)

        let refreshed = try sessionRepository.session(id: second.id)
        #expect((refreshed?.prHitsCount ?? 0) == 2)
    }

    @Test
    func countPRHitsNormalizesMixedUnitsForSameExercise() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "bench-mixed-units",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseline = try sessionRepository.createEmptySession(name: "Baseline")
        try sessionRepository.addExercise(sessionID: baseline.id, catalogItem: exercise)
        let baselineExercise = try sessionRepository.sessionExercises(sessionID: baseline.id).first!
        var baselineDrafts = try sessionRepository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].actualWeight = 200
        baselineDrafts[1].actualReps = 5
        baselineDrafts[1].actualLoadUnit = .lb
        baselineDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try sessionRepository.finishSession(sessionID: baseline.id)

        let current = try sessionRepository.createEmptySession(name: "Current")
        try sessionRepository.addExercise(sessionID: current.id, catalogItem: exercise)
        let currentExercise = try sessionRepository.sessionExercises(sessionID: current.id).first!
        var currentDrafts = try sessionRepository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[1].actualWeight = 100
        currentDrafts[1].actualReps = 5
        currentDrafts[1].actualLoadUnit = .kg
        currentDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try sessionRepository.finishSession(sessionID: current.id)

        let refreshed = try sessionRepository.session(id: current.id)
        #expect((refreshed?.prHitsCount ?? 0) == 1)
    }

    @Test
    func sessionPRAchievementsReturnsOneBestResultPerExercise() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "bench-social-pr",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseline = try sessionRepository.createEmptySession(name: "Baseline")
        try sessionRepository.addExercise(sessionID: baseline.id, catalogItem: exercise)
        let baselineExercise = try sessionRepository.sessionExercises(sessionID: baseline.id).first!
        var baselineDrafts = try sessionRepository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].actualWeight = 100
        baselineDrafts[1].actualReps = 5
        baselineDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try sessionRepository.finishSession(sessionID: baseline.id)

        let current = try sessionRepository.createEmptySession(name: "Push")
        try sessionRepository.addExercise(sessionID: current.id, catalogItem: exercise)
        let currentExercise = try sessionRepository.sessionExercises(sessionID: current.id).first!
        var currentDrafts = try sessionRepository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[1].actualWeight = 102.5
        currentDrafts[1].actualReps = 5
        currentDrafts[1].isCompleted = true
        currentDrafts[2].actualWeight = 90
        currentDrafts[2].actualReps = 10
        currentDrafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try sessionRepository.finishSession(sessionID: current.id)

        let achievements = try metrics.sessionPRAchievements(sessionID: current.id)
        #expect(achievements.count == 1)
        #expect(achievements.first?.catalogExerciseUUID == exercise.remoteUUID)
        #expect(achievements.first?.weight == 90)
        #expect(achievements.first?.reps == 10)
    }

    @Test
    func sessionSetPRAchievementsMarksExactSetsAndKinds() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "bench-set-prs",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseline = try sessionRepository.createEmptySession(name: "Baseline")
        try sessionRepository.addExercise(sessionID: baseline.id, catalogItem: exercise)
        let baselineExercise = try sessionRepository.sessionExercises(sessionID: baseline.id).first!
        var baselineDrafts = try sessionRepository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].actualWeight = 100
        baselineDrafts[1].actualReps = 5
        baselineDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try sessionRepository.finishSession(sessionID: baseline.id)

        let current = try sessionRepository.createEmptySession(name: "Push")
        try sessionRepository.addExercise(sessionID: current.id, catalogItem: exercise)
        let currentExercise = try sessionRepository.sessionExercises(sessionID: current.id).first!
        var currentDrafts = try sessionRepository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[1].actualWeight = 102.5
        currentDrafts[1].actualReps = 5
        currentDrafts[1].isCompleted = true
        currentDrafts[2].actualWeight = 100
        currentDrafts[2].actualReps = 6
        currentDrafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try sessionRepository.finishSession(sessionID: current.id)

        let achievements = try metrics.sessionSetPRAchievements(sessionID: current.id)
        let achievementsBySetID = Dictionary(
            uniqueKeysWithValues: achievements.map { ($0.setID, $0) }
        )

        #expect(achievements.count == 2)
        #expect(achievementsBySetID[currentDrafts[1].id]?.kinds == [.strength, .weight, .volume])
        #expect(achievementsBySetID[currentDrafts[2].id]?.kinds == [.strength, .reps, .volume])
    }

    @Test
    func sessionSummaryExcludesWarmupsAndNormalizesMixedUnitsForVolume() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "summary-mixed-volume",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let session = try sessionRepository.createEmptySession(name: "Push")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[0].actualWeight = 225
        drafts[0].actualReps = 1
        drafts[0].actualLoadUnit = .lb
        drafts[0].isCompleted = true
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        drafts[2].actualWeight = 100
        drafts[2].actualReps = 5
        drafts[2].actualLoadUnit = .lb
        drafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let summary = try metrics.sessionSummary(sessionID: session.id)
        let expectedVolume = 100 * 5 + (100 * 0.45359237 * 5)

        #expect(abs(summary.totalVolume - expectedVolume) < 0.01)
        #expect(summary.prHitsCount == 1)
    }

    @Test
    func bodyweightSetsCanCreateRepPRsWithoutAddingVolume() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "bodyweight-pr-pullup",
            displayName: "Pull Up",
            categoryName: "Back",
            equipmentSummary: "Bodyweight",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseline = try sessionRepository.createEmptySession(name: "Baseline")
        try sessionRepository.addExercise(sessionID: baseline.id, catalogItem: exercise)
        let baselineExercise = try #require(try sessionRepository.sessionExercises(sessionID: baseline.id).first)
        var baselineDrafts = try sessionRepository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].actualReps = 10
        baselineDrafts[1].actualLoadUnit = .bodyweight
        baselineDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try sessionRepository.finishSession(sessionID: baseline.id)

        let current = try sessionRepository.createEmptySession(name: "Current")
        try sessionRepository.addExercise(sessionID: current.id, catalogItem: exercise)
        let currentExercise = try #require(try sessionRepository.sessionExercises(sessionID: current.id).first)
        var currentDrafts = try sessionRepository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[0].actualReps = 15
        currentDrafts[0].actualLoadUnit = .bodyweight
        currentDrafts[0].isCompleted = true
        currentDrafts[1].actualReps = 12
        currentDrafts[1].actualLoadUnit = .bodyweight
        currentDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try sessionRepository.finishSession(sessionID: current.id)

        let achievements = try metrics.sessionSetPRAchievements(sessionID: current.id)
        let refreshed = try sessionRepository.session(id: current.id)

        #expect(achievements.count == 1)
        #expect(achievements.first?.kinds == [.reps])
        #expect(achievements.first?.weight == nil)
        #expect((refreshed?.totalVolume ?? -1) == 0)
        #expect((refreshed?.prHitsCount ?? 0) == 1)
        #expect(try metrics.sessionPRAchievements(sessionID: current.id).isEmpty)
    }

    @Test
    func targetOnlyCompletedSetsDoNotCreateMetrics() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "target-only-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let session = try sessionRepository.createEmptySession(name: "Target Only")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[1].targetWeight = 100
        drafts[1].targetReps = 8
        drafts[1].isCompleted = true
        drafts[2].targetWeight = 110
        drafts[2].targetReps = 6
        drafts[2].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let summary = try metrics.sessionSummary(sessionID: session.id)

        #expect(summary.totalVolume == 0)
        #expect(summary.prHitsCount == 0)
        #expect(try metrics.sessionSetPRAchievements(sessionID: session.id).isEmpty)
        #expect(try metrics.sessionPRAchievements(sessionID: session.id).isEmpty)
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
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.weeklyGoal == 3)
        #expect(snapshot.personalRecords.count == 1)
        #expect(snapshot.personalRecords.first?.exerciseName == "Bench Press")
        #expect(snapshot.weeklyProgress.count == 4)
        #expect(snapshot.weeklyProgress.allSatisfy { $0.goal == 3 })
        #expect(snapshot.weeklyProgress.map(\.completedWorkouts).reduce(0, +) == 1)
        #expect(snapshot.overviewStats.totalWorkouts == 1)
        #expect(snapshot.topExercises.first?.catalogExerciseUUID == exercise.remoteUUID)
        #expect(snapshot.activityDays.count == 42)
    }

    @Test
    func profileDashboardSnapshotCountsCompletedWorkoutsWithoutProjectedSetFacts() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "dashboard-no-facts",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let session = try sessionRepository.createEmptySession(name: "Target Only")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[1].targetWeight = 100
        drafts[1].targetReps = 8
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.overviewStats.totalWorkouts == 1)
        #expect(snapshot.personalRecords.isEmpty)
        #expect(snapshot.topExercises.isEmpty)
        #expect(snapshot.activityDays.count == 42)
    }

    @Test
    func profileDashboardSnapshotChoosesBestPRAcrossMixedUnits() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "dashboard-mixed-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let first = try sessionRepository.createEmptySession(name: "LB Day")
        try sessionRepository.addExercise(sessionID: first.id, catalogItem: exercise)
        let firstExercise = try sessionRepository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[1].actualWeight = 200
        firstDrafts[1].actualReps = 5
        firstDrafts[1].actualLoadUnit = .lb
        firstDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try sessionRepository.finishSession(sessionID: first.id)

        let second = try sessionRepository.createEmptySession(name: "KG Day")
        try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
        let secondExercise = try sessionRepository.sessionExercises(sessionID: second.id).first!
        var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[1].actualWeight = 100
        secondDrafts[1].actualReps = 5
        secondDrafts[1].actualLoadUnit = .kg
        secondDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try sessionRepository.finishSession(sessionID: second.id)

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.personalRecords.count == 1)
        #expect(snapshot.personalRecords.first?.loadUnit == .kg)
        #expect(snapshot.personalRecords.first?.weight == 100)
    }

    @Test
    func profileDashboardSnapshotBuildsOverviewStatsTopExercisesAndActivityDays() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "overview-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let squat = ExerciseCatalogItem(
            remoteUUID: "overview-squat",
            displayName: "Back Squat",
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(squat)

        let baseDay = Calendar.current.startOfDay(for: Date())
        try makeCompletedSession(
            named: "Bench 1",
            exercise: bench,
            start: Calendar.current.date(byAdding: .day, value: -2, to: baseDay) ?? baseDay,
            durationSeconds: 3_600,
            prHitsCount: 1,
            sessionRepository: sessionRepository,
            context: context
        )
        try makeCompletedSession(
            named: "Bench 2",
            exercise: bench,
            start: Calendar.current.date(byAdding: .day, value: -1, to: baseDay) ?? baseDay,
            durationSeconds: 2_400,
            prHitsCount: 2,
            sessionRepository: sessionRepository,
            context: context
        )
        try makeCompletedSession(
            named: "Squat Day",
            exercise: squat,
            start: baseDay,
            durationSeconds: 1_800,
            prHitsCount: 0,
            sessionRepository: sessionRepository,
            context: context
        )

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.overviewStats.totalWorkouts == 3)
        #expect(snapshot.overviewStats.totalPRHits == 3)
        #expect(snapshot.overviewStats.totalDurationSeconds == 7_800)
        #expect(snapshot.overviewStats.currentStreakDays == 3)
        #expect(snapshot.overviewStats.longestStreakDays == 3)
        #expect(snapshot.topExercises.first?.catalogExerciseUUID == bench.remoteUUID)
        #expect(snapshot.topExercises.first?.sessionCount == 2)
        #expect(snapshot.activityDays.count == 42)
        #expect(snapshot.activityDays.last?.workoutCount == 1)
    }

    @Test
    func profileDashboardSnapshotResetsCurrentStreakWhenLatestWorkoutIsOlderThanYesterday() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "streak-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)

        let baseDay = Calendar.current.startOfDay(for: Date())
        try makeCompletedSession(
            named: "Old 1",
            exercise: bench,
            start: Calendar.current.date(byAdding: .day, value: -4, to: baseDay) ?? baseDay,
            durationSeconds: 1_800,
            prHitsCount: 0,
            sessionRepository: sessionRepository,
            context: context
        )
        try makeCompletedSession(
            named: "Old 2",
            exercise: bench,
            start: Calendar.current.date(byAdding: .day, value: -3, to: baseDay) ?? baseDay,
            durationSeconds: 1_800,
            prHitsCount: 0,
            sessionRepository: sessionRepository,
            context: context
        )

        let snapshot = try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4)
        #expect(snapshot.overviewStats.currentStreakDays == 0)
        #expect(snapshot.overviewStats.longestStreakDays == 2)
    }

    @Test
    func widgetRepositoryAddRemoveReorderPersists() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        let allConfigs = try repository.configurations()
        #expect(allConfigs.count == 7)
        #expect(allConfigs.contains { $0.kind == .streaks })
        #expect(allConfigs.contains { $0.kind == .topExercises })
        #expect(allConfigs.contains { $0.kind == .consistencyCalendar })

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

    @Test
    func widgetRepositoryGraphWidgetsStartDisabledUntilConfigured() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        let configs = try repository.configurations()
        let oneRMConfig = try #require(configs.first { $0.kind == .exerciseOneRMTrend })
        let volumeConfig = try #require(configs.first { $0.kind == .exerciseVolumeTrend })

        #expect(!oneRMConfig.isEnabled)
        #expect(oneRMConfig.selectedCatalogExerciseUUID == nil)
        #expect(!volumeConfig.isEnabled)
        #expect(volumeConfig.selectedCatalogExerciseUUID == nil)
    }

    @Test
    func widgetRepositoryPersistsExerciseSelectionForGraphWidgets() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        try repository.updateExerciseSelection(
            kind: .exerciseOneRMTrend,
            catalogExerciseUUID: "bench-history",
            exerciseName: "Bench Press"
        )
        try repository.setEnabled(kind: .exerciseOneRMTrend, isEnabled: true)

        let configs = try repository.configurations()
        let config = try #require(configs.first { $0.kind == .exerciseOneRMTrend })
        #expect(config.selectedCatalogExerciseUUID == "bench-history")
        #expect(config.selectedExerciseNameSnapshot == "Bench Press")
        #expect(config.isEnabled)
    }

    @Test
    func widgetRepositoryRejectsEnablingGraphWidgetWithoutExerciseSelection() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        #expect(throws: ProfileWidgetRepositoryError.self) {
            try repository.setEnabled(kind: .exerciseOneRMTrend, isEnabled: true)
        }
    }

    @Test
    func exerciseOneRepMaxTrendReturnsLastEightPointsOldestToNewest() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "trend-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

        for offset in 0..<9 {
            let session = try sessionRepository.createEmptySession(name: "Session \(offset)")
            try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
            let sessionExercise = try sessionRepository.sessionExercises(sessionID: session.id).first!
            var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
            drafts[1].actualWeight = 80 + Double(offset)
            drafts[1].actualReps = 5
            drafts[1].actualLoadUnit = .kg
            drafts[1].isCompleted = true
            try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
            try sessionRepository.finishSession(sessionID: session.id)

            let stored = try #require(try sessionRepository.session(id: session.id))
            stored.startedAt = baseDate.addingTimeInterval(Double(offset) * 86_400)
            stored.endedAt = stored.startedAt.addingTimeInterval(1_800)
            try context.save()
        }

        let series = try metrics.exerciseOneRepMaxTrend(for: exercise.remoteUUID, limit: 8)
        #expect(series.points.count == 8)
        #expect(series.points == series.points.sorted { $0.completedAt < $1.completedAt })
        #expect(abs(series.points.first!.value - metrics.estimatedOneRepMax(weight: 81, reps: 5)) < 0.01)
        #expect(abs(series.points.last!.value - metrics.estimatedOneRepMax(weight: 88, reps: 5)) < 0.01)
    }

    @Test
    func exerciseVolumeTrendUsesMostRecentUnitAndIgnoresBodyweightSets() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "volume-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let first = try sessionRepository.createEmptySession(name: "KG Day")
        try sessionRepository.addExercise(sessionID: first.id, catalogItem: exercise)
        let firstExercise = try sessionRepository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[1].actualWeight = 100
        firstDrafts[1].actualReps = 5
        firstDrafts[1].actualLoadUnit = .kg
        firstDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try sessionRepository.finishSession(sessionID: first.id)

        let second = try sessionRepository.createEmptySession(name: "Bodyweight Day")
        try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
        let secondExercise = try sessionRepository.sessionExercises(sessionID: second.id).first!
        var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[1].actualWeight = 1
        secondDrafts[1].actualReps = 12
        secondDrafts[1].actualLoadUnit = .bodyweight
        secondDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try sessionRepository.finishSession(sessionID: second.id)

        let third = try sessionRepository.createEmptySession(name: "LB Day")
        try sessionRepository.addExercise(sessionID: third.id, catalogItem: exercise)
        let thirdExercise = try sessionRepository.sessionExercises(sessionID: third.id).first!
        var thirdDrafts = try sessionRepository.setDrafts(sessionExerciseID: thirdExercise.id)
        thirdDrafts[1].actualWeight = 220
        thirdDrafts[1].actualReps = 5
        thirdDrafts[1].actualLoadUnit = .lb
        thirdDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: thirdExercise.id, drafts: thirdDrafts)
        try sessionRepository.finishSession(sessionID: third.id)

        let series = try metrics.exerciseVolumeTrend(for: exercise.remoteUUID, limit: 8)
        #expect(series.points.count == 2)
        #expect(series.loadUnit == .lb)
        #expect(abs(series.points.last!.value - 1_100) < 0.01)
        #expect(abs(series.points.first!.value - (500 / 0.45359237)) < 0.1)
    }

    @Test
    func exerciseHistoryOptionsReturnsLatestWeightedExercises() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let metrics = WorkoutMetricsService(modelContext: context)

        let bench = ExerciseCatalogItem(
            remoteUUID: "history-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let pullUp = ExerciseCatalogItem(
            remoteUUID: "history-pullup",
            displayName: "Pull Up",
            categoryName: "Back",
            equipmentSummary: "Bodyweight",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(pullUp)

        let first = try sessionRepository.createEmptySession(name: "Weighted")
        try sessionRepository.addExercise(sessionID: first.id, catalogItem: bench)
        let firstExercise = try sessionRepository.sessionExercises(sessionID: first.id).first!
        var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
        firstDrafts[1].actualWeight = 90
        firstDrafts[1].actualReps = 5
        firstDrafts[1].actualLoadUnit = .kg
        firstDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
        try sessionRepository.finishSession(sessionID: first.id)

        let second = try sessionRepository.createEmptySession(name: "Bodyweight")
        try sessionRepository.addExercise(sessionID: second.id, catalogItem: pullUp)
        let secondExercise = try sessionRepository.sessionExercises(sessionID: second.id).first!
        var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
        secondDrafts[1].actualWeight = 1
        secondDrafts[1].actualReps = 10
        secondDrafts[1].actualLoadUnit = .bodyweight
        secondDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
        try sessionRepository.finishSession(sessionID: second.id)

        let options = try metrics.exerciseHistoryOptions()
        #expect(options.count == 1)
        #expect(options.first?.catalogExerciseUUID == bench.remoteUUID)
    }

    @Test
    func archivedSessionsAreIgnoredByMetricsAndPreviousSetLookupUntilRestored() throws {
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "archived-metrics-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(exercise)

        let baseline = try sessionRepository.createEmptySession(name: "Baseline")
        try sessionRepository.addExercise(sessionID: baseline.id, catalogItem: exercise)
        let baselineExercise = try #require(try sessionRepository.sessionExercises(sessionID: baseline.id).first)
        var baselineDrafts = try sessionRepository.setDrafts(sessionExerciseID: baselineExercise.id)
        baselineDrafts[1].actualWeight = 100
        baselineDrafts[1].actualReps = 5
        baselineDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: baselineExercise.id, drafts: baselineDrafts)
        try sessionRepository.finishSession(sessionID: baseline.id)

        let current = try sessionRepository.createEmptySession(name: "Current")
        try sessionRepository.addExercise(sessionID: current.id, catalogItem: exercise)
        let currentExercise = try #require(try sessionRepository.sessionExercises(sessionID: current.id).first)
        var currentDrafts = try sessionRepository.setDrafts(sessionExerciseID: currentExercise.id)
        currentDrafts[1].actualWeight = 110
        currentDrafts[1].actualReps = 5
        currentDrafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: currentExercise.id, drafts: currentDrafts)
        try sessionRepository.finishSession(sessionID: current.id)

        var metrics = WorkoutMetricsService(modelContext: context)
        #expect(try metrics.exerciseOneRepMaxTrend(for: exercise.remoteUUID, limit: 8).points.count == 2)
        #expect(try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4).overviewStats.totalWorkouts == 2)
        #expect(try sessionRepository.previousSet(
            for: exercise.remoteUUID,
            setIndex: 1,
            before: .distantFuture,
            excludingSessionID: nil
        )?.actualWeight == 110)

        try sessionRepository.archiveSession(id: current.id)

        metrics = WorkoutMetricsService(modelContext: context)
        #expect(try metrics.exerciseOneRepMaxTrend(for: exercise.remoteUUID, limit: 8).points.count == 1)
        #expect(try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4).overviewStats.totalWorkouts == 1)
        #expect(try sessionRepository.previousSet(
            for: exercise.remoteUUID,
            setIndex: 1,
            before: .distantFuture,
            excludingSessionID: nil
        )?.actualWeight == 100)

        try sessionRepository.restoreArchivedSession(id: current.id)

        metrics = WorkoutMetricsService(modelContext: context)
        #expect(try metrics.exerciseOneRepMaxTrend(for: exercise.remoteUUID, limit: 8).points.count == 2)
        #expect(try metrics.profileDashboardSnapshot(prLimit: 5, weeks: 4).overviewStats.totalWorkouts == 2)
        #expect(try sessionRepository.previousSet(
            for: exercise.remoteUUID,
            setIndex: 1,
            before: .distantFuture,
            excludingSessionID: nil
        )?.actualWeight == 110)
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
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
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

    private func makeCompletedSession(
        named name: String,
        exercise: ExerciseCatalogItem,
        start: Date,
        durationSeconds: Int,
        prHitsCount: Int,
        sessionRepository: WorkoutSessionRepository,
        context: ModelContext
    ) throws {
        let session = try sessionRepository.createEmptySession(name: name)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: exercise)
        let sessionExercise = try #require(try sessionRepository.sessionExercises(sessionID: session.id).first)
        var drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExercise.id)
        drafts[1].actualWeight = 100
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExercise.id, drafts: drafts)
        try sessionRepository.finishSession(sessionID: session.id)

        let stored = try #require(try sessionRepository.session(id: session.id))
        stored.startedAt = start
        stored.endedAt = start.addingTimeInterval(TimeInterval(durationSeconds))
        stored.durationSeconds = durationSeconds
        stored.prHitsCount = prHitsCount
        try context.save()
    }
}
