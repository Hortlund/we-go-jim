import Foundation
import SwiftData
import WidgetKit

nonisolated final class WeeklyGoalWidgetPublisher {
    static let widgetKind = WeeklyGoalWidgetDescriptor.kind

    private let store: WeeklyGoalWidgetStore
    private let reloadTimeline: (String) -> Void

    convenience init?() {
        guard let store = WeeklyGoalWidgetStore() else {
            return nil
        }

        self.init(store: store) { kind in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    init(
        store: WeeklyGoalWidgetStore,
        reloadTimeline: @escaping (String) -> Void
    ) {
        self.store = store
        self.reloadTimeline = reloadTimeline
    }

    func publish(modelContext: ModelContext, generatedAt: Date = .now) throws {
        let dashboard = try WorkoutMetricsService(modelContext: modelContext)
            .profileDashboardSnapshot(prLimit: 1, weeks: 6)
        let currentWeek = dashboard.weeklyProgress.last
        let hasActiveWorkout = (try? WorkoutSessionRepository(modelContext: modelContext).activeSession()) != nil
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: currentWeek?.completedWorkouts ?? 0,
            weeklyGoal: dashboard.weeklyGoal,
            weekStart: currentWeek?.weekStart ?? generatedAt,
            recentWeeks: dashboard.weeklyProgress.map { point in
                WeeklyGoalWidgetWeek(
                    weekStart: point.weekStart,
                    completedWorkouts: point.completedWorkouts,
                    goal: point.goal
                )
            },
            hasActiveWorkout: hasActiveWorkout,
            generatedAt: generatedAt
        )

        try store.save(snapshot)
        reloadTimeline(Self.widgetKind)
    }

    func clear() {
        store.clear()
        reloadTimeline(Self.widgetKind)
    }
}
