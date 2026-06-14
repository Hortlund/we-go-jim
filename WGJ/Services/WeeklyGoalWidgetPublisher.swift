import Foundation
import OSLog
import SwiftData
import WidgetKit

nonisolated final class WeeklyGoalWidgetPublisher {
    static let widgetKind = WeeklyGoalWidgetDescriptor.kind
    static let widgetKinds = [WeeklyGoalWidgetDescriptor.kind]
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "WeeklyGoalWidget"
    )

    private let store: WeeklyGoalWidgetStore
    private let reloadTimelines: (String) -> Void

    convenience init?() {
        guard let store = WeeklyGoalWidgetStore() else {
            return nil
        }

        self.init(store: store) { _ in
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        }
    }

    init(
        store: WeeklyGoalWidgetStore,
        reloadTimelines: @escaping (String) -> Void
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
    }

    static func publishBestEffort(modelContext: ModelContext, generatedAt: Date = .now) {
        guard let publisher = WeeklyGoalWidgetPublisher() else {
            logger.debug("Weekly goal widget publish skipped: app group store unavailable")
            return
        }

        do {
            try publisher.publish(modelContext: modelContext, generatedAt: generatedAt)
        } catch {
            logger.error("Weekly goal widget publish failed: \(error.localizedDescription, privacy: .public)")
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
        reloadTimelines(Self.widgetKind)
    }

    func clear() {
        store.clear()
        reloadTimelines(Self.widgetKind)
    }
}
