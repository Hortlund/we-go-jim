import Foundation
import SwiftData
import WidgetKit

nonisolated final class WeeklyGoalWidgetPublisher {
    static let widgetKind = WeeklyGoalWidgetDescriptor.kind

    private let store: WeeklyGoalWidgetStore
    private let reloadTimelines: () -> Void

    convenience init?() {
        guard let store = WeeklyGoalWidgetStore() else {
            return nil
        }

        self.init(store: store) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init(
        store: WeeklyGoalWidgetStore,
        reloadTimelines: @escaping () -> Void
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
    }

    static func publishBestEffort(modelContext: ModelContext, generatedAt: Date = .now) {
        guard let publisher = WeeklyGoalWidgetPublisher() else {
            #if DEBUG
            print("Weekly goal widget publish skipped: app group store unavailable")
            #endif
            return
        }

        do {
            try publisher.publish(modelContext: modelContext, generatedAt: generatedAt)
        } catch {
            #if DEBUG
            print("Weekly goal widget publish failed: \(error)")
            #endif
        }
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
        reloadTimelines()
    }

    func clear() {
        store.clear()
        reloadTimelines()
    }
}
