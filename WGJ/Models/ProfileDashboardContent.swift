import Foundation

nonisolated struct ProfileDashboardContent: Sendable {
    var enabledWidgets: [ProfileWidgetConfigSnapshot]
    var personalRecords: [WorkoutPRRecord]
    var weeklyProgress: [WeeklyWorkoutProgressPoint]
    var weeklyMuscleHeatmap: ProfileWeeklyMuscleHeatmapSnapshot
    var trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]
    var coachBrief: ProfileCoachPresentation?
    var weeklyGoal: Int
    var overviewStats: ProfileOverviewStats
    var topExercises: [ProfileTopExerciseStat]
    var activityDays: [ProfileActivityDay]
    var activityDayRows: [[ProfileActivityDay]]
    var maxActivityDayWorkoutCount: Int
    var hasActivityDayWorkouts: Bool
    var bodyweightPersonalRecords: [BodyweightExerciseBestRecord] = []

    static let empty = ProfileDashboardContent(
        enabledWidgets: [],
        personalRecords: [],
        weeklyProgress: [],
        weeklyMuscleHeatmap: .empty,
        trendSeriesByWidgetID: [:],
        coachBrief: nil,
        weeklyGoal: 4,
        overviewStats: .empty,
        topExercises: [],
        activityDays: [],
        activityDayRows: [],
        maxActivityDayWorkoutCount: 1,
        hasActivityDayWorkouts: false
    )

    nonisolated static func make(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        dashboard: ProfileDashboardSnapshot,
        trendSeriesByWidgetID: [UUID: ExerciseMetricSeries],
        coachBrief: ProfileCoachPresentation? = nil
    ) -> ProfileDashboardContent {
        let activityDayRows = stride(from: 0, to: dashboard.activityDays.count, by: 7).map { startIndex in
            Array(dashboard.activityDays[startIndex ..< min(startIndex + 7, dashboard.activityDays.count)])
        }
        let maxActivityDayWorkoutCount = max(1, dashboard.activityDays.map(\.workoutCount).max() ?? 0)
        let hasActivityDayWorkouts = dashboard.activityDays.contains { $0.workoutCount > 0 }

        return ProfileDashboardContent(
            enabledWidgets: enabledWidgets,
            personalRecords: Array(dashboard.personalRecords.prefix(5)),
            weeklyProgress: dashboard.weeklyProgress,
            weeklyMuscleHeatmap: dashboard.weeklyMuscleHeatmap,
            trendSeriesByWidgetID: trendSeriesByWidgetID,
            coachBrief: coachBrief,
            weeklyGoal: max(1, dashboard.weeklyGoal),
            overviewStats: dashboard.overviewStats,
            topExercises: Array(dashboard.topExercises.prefix(3)),
            activityDays: dashboard.activityDays,
            activityDayRows: activityDayRows,
            maxActivityDayWorkoutCount: maxActivityDayWorkoutCount,
            hasActivityDayWorkouts: hasActivityDayWorkouts,
            bodyweightPersonalRecords: dashboard.bodyweightPersonalRecords
        )
    }
}
