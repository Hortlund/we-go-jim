import Foundation

/// Builds display-ready insights off the main actor alongside the Journey snapshot.
nonisolated enum JourneyInsightsBuilder {
    static func build(workouts: [JourneyWorkout], exercises: [JourneyExercise], years: [JourneyYear],
                      events: [JourneyMilestone], unit: WorkoutDistanceUnit, calendar: Calendar, now: Date) -> JourneyInsights {
        guard !workouts.isEmpty else { return .init() }
        let weeks = Set(workouts.map { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }).sorted()
        var longest = 0
        var streak = 0
        var previous: Date?
        for week in weeks {
            streak = previous.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) } == week ? streak + 1 : 1
            longest = max(longest, streak)
            previous = week
        }
        let months = years.flatMap(\.months).sorted { $0.date < $1.date }
        let bestMonth = months.reduce(nil as JourneyMonth?) { best, month in
            month.activeDays > (best?.activeDays ?? 0) ? month : best
        }
        var facts: [JourneyFact] = [
            .init(id: "streak", title: String(localized: "Longest weekly streak"), value: longest == 1 ? String(localized: "1 week") : String(localized: "\(longest) weeks")),
            .init(id: "average", title: String(localized: "Workouts per active week"),
                value: (Double(workouts.count) / Double(max(1, weeks.count))).formatted(.number.precision(.fractionLength(0...1))))
        ]
        if let bestMonth {
            facts.append(.init(id: "month", title: String(localized: "Most active month"),
                value: String(localized: "\(bestMonth.date.formatted(.dateTime.month(.abbreviated).year())) · \(bestMonth.activeDays) days")))
        }
        if let currentYear = calendar.dateInterval(of: .year, for: now),
           let previousDate = calendar.date(byAdding: .year, value: -1, to: now),
           let previousYear = calendar.dateInterval(of: .year, for: previousDate),
           let previousCutoff = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previousDate)) {
            let current = Set(workouts.filter { $0.date >= currentYear.start && $0.date <= now }.map { calendar.startOfDay(for: $0.date) }).count
            let previous = Set(workouts.filter { $0.date >= previousYear.start && $0.date < min(previousCutoff, previousYear.end) }
                .map { calendar.startOfDay(for: $0.date) }).count
            facts.append(.init(id: "year-comparison", title: String(localized: "Active days · this year / last year"),
                value: String(localized: "\(current) / \(previous) through \(now.formatted(.dateTime.month(.abbreviated).day()))")))
        }
        let records = events.filter { $0.personalRecord != nil }
        let activeDays = Set(workouts.map { calendar.startOfDay(for: $0.date) }).count
        let hours = Double(workouts.reduce(0) { $0 + max(0, $1.durationSeconds) }) / 3_600
        let foot = workouts.flatMap(\.activities).filter { $0.isWalkRun && $0.distanceMeters.isFinite && $0.distanceMeters > 0 }
            .reduce(0) { $0 + $1.distanceMeters }
        var candidates: [JourneyNextMilestone] = []
        func next(_ id: String, current: Double, thresholds: [Double], title: (Int) -> String, remaining: (Int) -> String) {
            guard let target = thresholds.first(where: { $0 > current }) else { return }
            candidates.append(.init(id: id, title: title(Int(target)), detail: remaining(Int(ceil(target - current))),
                progress: min(1, max(0, current / target))))
        }
        next("workouts", current: Double(workouts.count), thresholds: [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
            title: { String(localized: "\($0) workouts") }, remaining: { String(localized: "\($0) more sessions. Every one counts.") })
        next("days", current: Double(activeDays), thresholds: [30, 100, 365, 1_000],
            title: { String(localized: "\($0) active days") }, remaining: { String(localized: "\($0) more active days. Your pace, your journey.") })
        next("hours", current: hours, thresholds: [10, 24, 50, 100, 168, 250, 500, 1_000],
            title: { String(localized: "\($0) training hours") }, remaining: { String(localized: "About \($0) more hours, one workout at a time.") })
        next("records", current: Double(records.count), thresholds: [10, 25, 50, 100],
            title: { String(localized: "\($0) Journey PRs") }, remaining: { String(localized: "\($0) more breakthroughs. No deadline.") })
        if foot > 0 {
            let milestoneUnit: WorkoutDistanceUnit = unit == .meters ? .kilometers : unit
            next("distance", current: milestoneUnit.value(fromMeters: foot), thresholds: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
                title: { String(localized: "\($0) \(milestoneUnit.symbol) on foot") },
                remaining: { String(localized: "About \($0) \(milestoneUnit.symbol) to go across your workouts.") })
        }
        let recordsBySession = Dictionary(grouping: records, by: \.sessionID)
        let eventsBySession = Dictionary(grouping: events, by: \.sessionID)
        let highlights = years.compactMap { year -> JourneyYearHighlights? in
            let sessions = year.months.flatMap(\.workouts).sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            guard !sessions.isEmpty else { return nil }
            let ids = Set(sessions.map(\.id))
            var frequency: [String: (name: String, count: Int)] = [:]
            for session in sessions {
                var names: [String: String] = [:]
                for exercise in session.completedExercises { names[exercise.id] = exercise.name }
                for activity in session.activities { names[activity.exerciseID] = activity.name }
                for (id, name) in names {
                    frequency[id] = (name, (frequency[id]?.count ?? 0) + 1)
                }
            }
            let favorite = frequency.sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }.first
            let mostActive = year.months.reduce(nil as JourneyMonth?) { best, month in
                month.activeDays > (best?.activeDays ?? 0) ? month : best
            }
            let yearEvents = sessions.flatMap { eventsBySession[$0.id, default: []] }
            var yearFacts: [JourneyFact] = [
                .init(id: "moments", title: String(localized: "Milestones earned"), value: yearEvents.count.formatted()),
                .init(id: "prs", title: String(localized: "Journey PRs"), value: sessions.reduce(0) { $0 + recordsBySession[$1.id, default: []].count }.formatted())
            ]
            if let favorite {
                yearFacts.append(.init(id: "favorite", title: String(localized: "Favourite exercise · most sessions"),
                    value: String(localized: "\(favorite.value.name) · \(favorite.value.count) sessions")))
            }
            if let mostActive {
                yearFacts.append(.init(id: "month", title: String(localized: "Most active month"),
                    value: String(localized: "\(mostActive.date.formatted(.dateTime.month(.wide))) · \(mostActive.activeDays) days")))
            }
            // Compare each metric's first result of this year with its best later result.
            var improvements: [(id: String, name: String, metric: String, percent: Double)] = []
            for exercise in exercises {
                let points = exercise.performances.filter { ids.contains($0.sessionID) && $0.value.isFinite && $0.value > 0 }
                    .sorted { $0.date == $1.date ? $0.sessionID.uuidString < $1.sessionID.uuidString : $0.date < $1.date }
                if let first = points.first, let best = points.dropFirst().map(\.value).max(), best > first.value {
                    improvements.append((exercise.id, exercise.name, exercise.isReps ? String(localized: "bodyweight reps") : String(localized: "weight"),
                        (best / first.value - 1) * 100))
                }
            }
            var cardioBaselines: [String: Double] = [:]
            var cardioImprovements: [String: (String, String, Double)] = [:]
            for session in sessions {
                var sessionBest: [String: (String, String, Double)] = [:]
                for activity in session.activities where activity.distanceMeters.isFinite && activity.distanceMeters > 0
                    && activity.trackingProfile != .timeOnly && activity.trackingProfile != .stairClimber {
                    let key = "\(activity.exerciseID)-\(activity.trackingProfile.rawValue)"
                    let distanceKey = "\(key)-distance"
                    if activity.distanceMeters > (sessionBest[distanceKey]?.2 ?? 0) {
                        sessionBest[distanceKey] = (activity.name, String(localized: "distance"), activity.distanceMeters)
                    }
                    if activity.distanceMeters >= 1_000 && activity.durationSeconds > 0 {
                        let speed = activity.distanceMeters / Double(activity.durationSeconds)
                        let speedKey = "\(key)-speed"
                        if speed > (sessionBest[speedKey]?.2 ?? 0) {
                            sessionBest[speedKey] = (activity.name, String(localized: "average speed"), speed)
                        }
                    }
                }
                for (key, value) in sessionBest {
                    if let baseline = cardioBaselines[key] {
                        let percent = (value.2 / baseline - 1) * 100
                        if percent > (cardioImprovements[key]?.2 ?? 0) { cardioImprovements[key] = (value.0, value.1, percent) }
                    } else { cardioBaselines[key] = value.2 }
                }
            }
            improvements += cardioImprovements.map { ($0.key, $0.value.0, $0.value.1, $0.value.2) }
            for item in improvements.filter({ $0.percent.isFinite }).sorted(by: { $0.percent == $1.percent ? $0.id < $1.id : $0.percent > $1.percent }).prefix(3) {
                yearFacts.append(.init(id: "improvement-\(item.id)", title: String(localized: "\(item.name) · \(item.metric)"),
                    value: String(localized: "+\(item.percent.formatted(.number.precision(.significantDigits(1...3))))% from your first result this year")))
            }
            let moments = yearEvents.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
                .prefix(5).map { event in event.playfulTitle.map { "\($0) · \(event.title)" } ?? event.title }
            return .init(id: year.id, title: year.title, facts: yearFacts, moments: moments)
        }
        return .init(facts: facts, nextMilestones: Array(candidates.sorted { $0.progress == $1.progress ? $0.id < $1.id : $0.progress > $1.progress }.prefix(3)), years: highlights)
    }
}
