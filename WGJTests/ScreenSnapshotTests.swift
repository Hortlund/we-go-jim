import Foundation
import Testing
@testable import WGJ

@MainActor
struct ScreenSnapshotTests {
    @Test
    func exercisesCatalogViewModelBuildsFilteredSections() {
        let chest = MuscleGroup(remoteID: 1, name: "Chest", nameEn: "Chest")
        let legs = MuscleGroup(remoteID: 2, name: "Legs", nameEn: "Legs")

        let bench = ExerciseCatalogItem(
            remoteUUID: "bench",
            displayName: "Bench Press",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        bench.primaryMuscles = [chest]
        bench.aliases = [ExerciseAlias(value: "Barbell Bench", exercise: bench)]

        let squat = ExerciseCatalogItem(
            remoteUUID: "squat",
            displayName: "Back Squat",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            isCurated: true
        )
        squat.primaryMuscles = [legs]

        let hidden = ExerciseCatalogItem(
            remoteUUID: "hidden",
            displayName: "Hidden Curl",
            categoryName: "Accessories",
            equipmentSummary: "Cable",
            isHidden: true
        )
        hidden.primaryMuscles = [chest]

        let viewModel = ExercisesCatalogViewModel()
        viewModel.rebuildCatalog(from: [bench, squat, hidden])

        #expect(viewModel.availableCategories == ["Strength"])
        #expect(viewModel.availableMuscles.map(\.name) == ["Chest", "Legs"])

        viewModel.recomputeSections(
            query: "bench",
            selectedPrimaryMuscleID: chest.remoteID,
            selectedCategory: "Strength",
            sortDescending: false
        )

        #expect(viewModel.sections.count == 1)
        #expect(viewModel.sections.first?.title == "B")
        #expect(viewModel.sections.first?.rows.map(\.displayName) == ["Bench Press"])
    }

    @Test
    func historyOverviewSnapshotBuilderGroupsSessionsAndCountsDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let januarySession = WorkoutSession(
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_736_035_200),
            endedAt: Date(timeIntervalSince1970: 1_736_038_800),
            durationSeconds: 3600,
            totalVolume: 1200,
            prHitsCount: 1
        )
        let januaryExercise = WorkoutSessionExercise(
            sessionID: januarySession.id,
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            sortOrder: 0,
            session: januarySession
        )
        let januarySet = WorkoutSessionSet(
            sessionExerciseID: januaryExercise.id,
            sortOrder: 0,
            targetReps: 8,
            targetWeight: 100,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: januaryExercise
        )
        januaryExercise.sets = [januarySet]
        januarySession.exercises = [januaryExercise]

        let februarySession = WorkoutSession(
            name: "Leg Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_738_886_400),
            endedAt: Date(timeIntervalSince1970: 1_738_890_000),
            durationSeconds: 3600,
            totalVolume: 1800,
            prHitsCount: 0
        )

        let snapshot = HistoryOverviewSnapshotBuilder.build(
            sessions: [januarySession, februarySession],
            selectedDayFilter: nil,
            calendar: calendar
        )

        #expect(snapshot.sections.count == 2)
        #expect(snapshot.sections.first?.cards.first?.name == "Leg Day")
        #expect(
            snapshot.workoutCountsByDay[calendar.startOfDay(for: januarySession.endedAt ?? januarySession.startedAt)] == 1
        )

        let filtered = HistoryOverviewSnapshotBuilder.build(
            sessions: [januarySession, februarySession],
            selectedDayFilter: januarySession.endedAt,
            calendar: calendar
        )

        #expect(filtered.sections.count == 1)
        #expect(filtered.sections.first?.cards.map(\.name) == ["Push Day"])
    }

    @Test
    func profileDashboardContentBuildsStableSnapshot() {
        let widgetConfigs = [
            ProfileWidgetConfig(kind: .prs, sortOrder: 0),
            ProfileWidgetConfig(kind: .weeklyGoals, sortOrder: 1),
        ]
        let dashboard = ProfileDashboardSnapshot(
            personalRecords: [
                WorkoutPRRecord(
                    id: "bench",
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    estimatedOneRepMax: 110,
                    weight: 100,
                    reps: 3,
                    loadUnit: .kg,
                    achievedAt: .now
                ),
            ],
            weeklyProgress: [
                WeeklyWorkoutProgressPoint(
                    id: "week-1",
                    weekStart: Date(timeIntervalSince1970: 1_736_035_200),
                    completedWorkouts: 3,
                    goal: 0
                ),
            ],
            weeklyGoal: 0,
            overviewStats: ProfileOverviewStats(
                totalWorkouts: 6,
                totalPRHits: 4,
                totalDurationSeconds: 7_200,
                currentStreakDays: 2,
                longestStreakDays: 4,
                activeDaysThisMonth: 3,
                firstWorkoutDate: Date(timeIntervalSince1970: 1_735_430_400)
            ),
            topExercises: [
                ProfileTopExerciseStat(
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    sessionCount: 4,
                    lastPerformedAt: Date(timeIntervalSince1970: 1_736_035_200)
                ),
            ],
            activityDays: [
                ProfileActivityDay(
                    date: Date(timeIntervalSince1970: 1_736_035_200),
                    workoutCount: 1
                ),
            ]
        )

        let trendSeries = [
            ProfileWidgetKind.exerciseOneRMTrend: ExerciseMetricSeries(
                catalogExerciseUUID: "bench",
                exerciseName: "Bench Press",
                loadUnit: .kg,
                points: [
                    ExerciseMetricPoint(
                        id: "point-1",
                        completedAt: Date(timeIntervalSince1970: 1_736_035_200),
                        value: 105
                    ),
                ]
            ),
        ]

        let content = ProfileDashboardContent.make(
            enabledWidgets: widgetConfigs,
            dashboard: dashboard,
            trendSeriesByKind: trendSeries
        )

        #expect(content.enabledWidgets.count == 2)
        #expect(content.personalRecords.map(\.exerciseName) == ["Bench Press"])
        #expect(content.weeklyProgress.first?.completedWorkouts == 3)
        #expect(content.weeklyGoal == 1)
        #expect(content.overviewStats.totalWorkouts == 6)
        #expect(content.topExercises.first?.sessionCount == 4)
        #expect(content.activityDays.first?.workoutCount == 1)
        #expect(content.trendSeriesByKind[.exerciseOneRMTrend]?.points.first?.value == 105)
    }
}
