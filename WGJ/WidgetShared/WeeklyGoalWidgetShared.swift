import Foundation

nonisolated struct WeeklyGoalWidgetWeek: Codable, Equatable, Identifiable, Sendable {
    let weekStart: Date
    let completedWorkouts: Int
    let goal: Int

    var id: Date { weekStart }

    var progressFraction: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(completedWorkouts) / Double(goal))
    }
}

nonisolated struct WeeklyGoalWidgetSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let completedWorkouts: Int
    let weeklyGoal: Int
    let weekStart: Date
    let weekEnd: Date
    let generatedAt: Date
    let hasActiveWorkout: Bool
    let recentWeeks: [WeeklyGoalWidgetWeek]

    init(
        schemaVersion: Int = Self.schemaVersion,
        completedWorkouts: Int,
        weeklyGoal: Int,
        weekStart: Date,
        weekEnd: Date,
        generatedAt: Date,
        hasActiveWorkout: Bool = false,
        recentWeeks: [WeeklyGoalWidgetWeek] = []
    ) {
        self.schemaVersion = schemaVersion
        self.completedWorkouts = completedWorkouts
        self.weeklyGoal = weeklyGoal
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.generatedAt = generatedAt
        self.hasActiveWorkout = hasActiveWorkout
        self.recentWeeks = recentWeeks
    }

    var remainingWorkouts: Int {
        max(0, weeklyGoal - completedWorkouts)
    }

    var progressFraction: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, Double(completedWorkouts) / Double(weeklyGoal))
    }

    var statusText: String {
        WeeklyGoalWidgetContentPolicy.statusText(
            completedWorkouts: completedWorkouts,
            weeklyGoal: weeklyGoal
        )
    }

    var progressText: String {
        "\(completedWorkouts) / \(weeklyGoal)"
    }

    var chartMaximumWorkouts: Int {
        max(
            weeklyGoal,
            recentWeeks
                .flatMap { [$0.goal, $0.completedWorkouts] }
                .max() ?? weeklyGoal
        )
    }
}

nonisolated enum WeeklyGoalWidgetContentPolicy {
    static let defaultGoal = 4
    static let minimumGoal = 1
    static let maximumGoal = 14

    static func snapshot(
        completedWorkouts: Int,
        weeklyGoal: Int,
        weekStart: Date,
        recentWeeks: [WeeklyGoalWidgetWeek] = [],
        calendar: Calendar = .current,
        hasActiveWorkout: Bool = false,
        generatedAt: Date = .now
    ) -> WeeklyGoalWidgetSnapshot {
        let normalizedGoal = normalizedGoal(weeklyGoal)
        let normalizedCompleted = max(0, completedWorkouts)
        let resolvedWeekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let normalizedWeeks = recentWeeks.map { week in
            WeeklyGoalWidgetWeek(
                weekStart: week.weekStart,
                completedWorkouts: max(0, week.completedWorkouts),
                goal: WeeklyGoalWidgetContentPolicy.normalizedGoal(week.goal)
            )
        }
        let resolvedWeeks = normalizedWeeks.isEmpty
            ? [
                WeeklyGoalWidgetWeek(
                    weekStart: weekStart,
                    completedWorkouts: normalizedCompleted,
                    goal: normalizedGoal
                ),
            ]
            : normalizedWeeks

        return WeeklyGoalWidgetSnapshot(
            completedWorkouts: normalizedCompleted,
            weeklyGoal: normalizedGoal,
            weekStart: weekStart,
            weekEnd: resolvedWeekEnd,
            generatedAt: generatedAt,
            hasActiveWorkout: hasActiveWorkout,
            recentWeeks: resolvedWeeks
        )
    }

    static func placeholder(generatedAt: Date = .now) -> WeeklyGoalWidgetSnapshot {
        snapshot(
            completedWorkouts: 0,
            weeklyGoal: defaultGoal,
            weekStart: generatedAt,
            generatedAt: generatedAt
        )
    }

    static func normalizedGoal(_ goal: Int) -> Int {
        max(minimumGoal, min(maximumGoal, goal))
    }

    static func statusText(completedWorkouts: Int, weeklyGoal: Int) -> String {
        let normalizedGoal = normalizedGoal(weeklyGoal)
        let normalizedCompleted = max(0, completedWorkouts)
        if normalizedCompleted > normalizedGoal {
            return "Goal beaten"
        }
        if normalizedCompleted == normalizedGoal {
            return "Goal hit"
        }

        let remaining = normalizedGoal - normalizedCompleted
        return "\(remaining) to go"
    }
}

nonisolated enum WeeklyGoalWidgetDeepLink {
    static let profileWeeklyGoalURL = URL(string: "wgj://profile/weekly-goal")!
}

nonisolated enum WeeklyGoalWidgetDescriptor {
    static let kind = "WeeklyGoalWidget"
}

nonisolated struct WeeklyGoalWidgetStore {
    static let appGroupIdentifier = "group.se.highball.WeGoJim"
    static let snapshotDefaultsKey = "weeklyGoalWidget.snapshot.v2"
    static let legacySnapshotDefaultsKey = "weeklyGoalWidget.snapshot.v1"

    private let defaults: UserDefaults

    init?(appGroupIdentifier: String = Self.appGroupIdentifier) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        self.defaults = defaults
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() throws -> WeeklyGoalWidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotDefaultsKey) else {
            return nil
        }

        return try? decoder.decode(WeeklyGoalWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WeeklyGoalWidgetSnapshot) throws {
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: Self.snapshotDefaultsKey)
        defaults.removeObject(forKey: Self.legacySnapshotDefaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.snapshotDefaultsKey)
        defaults.removeObject(forKey: Self.legacySnapshotDefaultsKey)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
