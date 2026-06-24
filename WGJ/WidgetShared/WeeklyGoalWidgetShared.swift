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

nonisolated enum WeeklyGoalWeekPolicy {
    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func nextWeekStart(after date: Date = .now, calendar: Calendar = calendar()) -> Date {
        let currentWeekStart = weekStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart)
            ?? date.addingTimeInterval(7 * 24 * 3_600)
    }

    static func weekStart(for date: Date, calendar: Calendar = calendar()) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = calendar.firstWeekday
        guard let weekStart = calendar.date(from: components) else {
            return calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: weekStart)
    }
}

nonisolated enum WeeklyGoalWidgetContentPolicy {
    static let defaultGoal = 4
    static let minimumGoal = 1
    static let maximumGoal = 14
    static let recentWeekLimit = 6

    static func snapshot(
        completedWorkouts: Int,
        weeklyGoal: Int,
        weekStart: Date,
        recentWeeks: [WeeklyGoalWidgetWeek] = [],
        calendar: Calendar = WeeklyGoalWeekPolicy.calendar(),
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
        let calendar = WeeklyGoalWeekPolicy.calendar()
        return snapshot(
            completedWorkouts: 0,
            weeklyGoal: defaultGoal,
            weekStart: WeeklyGoalWeekPolicy.weekStart(for: generatedAt, calendar: calendar),
            calendar: calendar,
            generatedAt: generatedAt
        )
    }

    static func preview(generatedAt: Date = .now, calendar: Calendar = WeeklyGoalWeekPolicy.calendar()) -> WeeklyGoalWidgetSnapshot {
        let weekStart = WeeklyGoalWeekPolicy.weekStart(for: generatedAt, calendar: calendar)
        let completedByOffset = [1, 3, 2, 4, 1, 3]
        let recentWeeks = completedByOffset.enumerated().compactMap { index, completed -> WeeklyGoalWidgetWeek? in
            guard let week = calendar.date(byAdding: .weekOfYear, value: index - 5, to: weekStart) else {
                return nil
            }
            return WeeklyGoalWidgetWeek(
                weekStart: week,
                completedWorkouts: completed,
                goal: defaultGoal
            )
        }

        return snapshot(
            completedWorkouts: 3,
            weeklyGoal: defaultGoal,
            weekStart: weekStart,
            recentWeeks: recentWeeks,
            calendar: calendar,
            generatedAt: generatedAt
        )
    }

    static func resolvedSnapshot(
        _ snapshot: WeeklyGoalWidgetSnapshot,
        asOf date: Date = .now,
        calendar: Calendar = WeeklyGoalWeekPolicy.calendar()
    ) -> WeeklyGoalWidgetSnapshot {
        let currentWeekStart = WeeklyGoalWeekPolicy.weekStart(for: date, calendar: calendar)
        let snapshotWeekStart = WeeklyGoalWeekPolicy.weekStart(for: snapshot.weekStart, calendar: calendar)
        guard currentWeekStart > snapshotWeekStart else {
            return snapshot
        }

        var weeksByStart: [Date: WeeklyGoalWidgetWeek] = [:]
        for week in snapshot.recentWeeks {
            let normalizedWeekStart = WeeklyGoalWeekPolicy.weekStart(for: week.weekStart, calendar: calendar)
            weeksByStart[normalizedWeekStart] = WeeklyGoalWidgetWeek(
                weekStart: normalizedWeekStart,
                completedWorkouts: max(0, week.completedWorkouts),
                goal: normalizedGoal(week.goal)
            )
        }
        weeksByStart[snapshotWeekStart] = WeeklyGoalWidgetWeek(
            weekStart: snapshotWeekStart,
            completedWorkouts: max(0, snapshot.completedWorkouts),
            goal: normalizedGoal(snapshot.weeklyGoal)
        )

        var weeksAdvanced = 0
        var rolloverWeekStart = snapshotWeekStart
        while let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: rolloverWeekStart),
              nextWeekStart <= currentWeekStart {
            weeksAdvanced += 1
            weeksByStart[nextWeekStart] = weeksByStart[nextWeekStart] ?? WeeklyGoalWidgetWeek(
                weekStart: nextWeekStart,
                completedWorkouts: 0,
                goal: normalizedGoal(snapshot.weeklyGoal)
            )
            rolloverWeekStart = nextWeekStart
        }

        let recentWeeks = weeksByStart.values
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(min(recentWeekLimit, max(snapshot.recentWeeks.count, weeksAdvanced + 1)))

        return WeeklyGoalWidgetSnapshot(
            completedWorkouts: 0,
            weeklyGoal: normalizedGoal(snapshot.weeklyGoal),
            weekStart: currentWeekStart,
            weekEnd: calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart,
            generatedAt: date,
            hasActiveWorkout: snapshot.hasActiveWorkout,
            recentWeeks: Array(recentWeeks)
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
    static let profileWeeklyGoalURL: URL = {
        var components = URLComponents()
        components.scheme = "wgj"
        components.host = "profile"
        components.path = "/weekly-goal"
        return components.url ?? URL(fileURLWithPath: "/profile/weekly-goal")
    }()
}

nonisolated enum WeeklyGoalWidgetDescriptor {
    static let kind = "WeeklyGoalWidget"
}

nonisolated struct WeeklyGoalWidgetStore {
    static let appGroupIdentifier = "group.se.highball.WeGoJim"
    static let snapshotDefaultsKey = "weeklyGoalWidget.snapshot.current"
    static let legacySnapshotDefaultsKeys = [
        "weeklyGoalWidget.snapshot.v1",
        "weeklyGoalWidget.snapshot.v2",
        "weeklyGoalWidget.snapshot.v3",
        "weeklyGoalWidget.snapshot.v4",
        "weeklyGoalWidget.snapshot.v5",
        "weeklyGoalWidget.snapshot.v6",
        "weeklyGoalWidget.snapshot.v7",
        "weeklyGoalWidget.snapshot.v8",
        "weeklyGoalWidget.snapshot.v9",
        "weeklyGoalWidget.snapshot.v10",
        "weeklyGoalWidget.snapshot.v11",
    ]

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
        clearLegacySnapshots()
    }

    func clear() {
        defaults.removeObject(forKey: Self.snapshotDefaultsKey)
        clearLegacySnapshots()
    }

    private func clearLegacySnapshots() {
        for key in Self.legacySnapshotDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
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
