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
        let snapshot = try Self.makeSnapshot(modelContext: modelContext, generatedAt: generatedAt)

        try store.save(snapshot)
        reloadTimelines(Self.widgetKind)
    }

    static func makeSnapshot(modelContext: ModelContext, generatedAt: Date) throws -> WeeklyGoalWidgetSnapshot {
        let calendar = WeeklyGoalWeekPolicy.calendar()
        let currentWeekStart = WeeklyGoalWeekPolicy.weekStart(for: generatedAt, calendar: calendar)
        var profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        profileDescriptor.fetchLimit = 1
        let goal = try modelContext.fetch(profileDescriptor).first?.weeklyWorkoutGoal
            ?? WeeklyGoalWidgetContentPolicy.defaultGoal
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        var weeks: [WeeklyGoalWidgetWeek] = []
        // Only count saved session headers. Widget refresh must not build PRs,
        // exercise histories, muscle mappings, or derived set projections.
        for offset in (0..<WeeklyGoalWidgetContentPolicy.recentWeekLimit).reversed() {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { session in
                session.statusRaw == completedStatus && session.archivedAt == nil
                    && (session.endedAt ?? session.startedAt) >= start
                    && (session.endedAt ?? session.startedAt) < end
            })
            weeks.append(WeeklyGoalWidgetWeek(
                weekStart: start, completedWorkouts: try modelContext.fetchCount(descriptor), goal: goal
            ))
        }
        let hasActiveWorkout = (try? WorkoutSessionRepository(modelContext: modelContext).activeSession()) != nil
        return WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: weeks.last?.completedWorkouts ?? 0,
            weeklyGoal: goal,
            weekStart: currentWeekStart,
            recentWeeks: weeks,
            calendar: calendar,
            hasActiveWorkout: hasActiveWorkout,
            generatedAt: generatedAt
        )
    }

    func clear() {
        store.clear()
        reloadTimelines(Self.widgetKind)
    }
}
