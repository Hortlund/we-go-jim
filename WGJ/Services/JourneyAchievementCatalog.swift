import Foundation

nonisolated struct JourneyAchievementGoal: Identifiable, Sendable {
    let id: String
    let title: String
    let requirement: String
    let category: String
    let isEarned: Bool
    var progress: Double? = nil
    var progressText: String? = nil
    var seriesID: String? = nil
    var seriesTitle: String? = nil
}

nonisolated struct JourneyAchievementSeries: Identifiable, Sendable {
    let id: String
    let title: String
    let category: String
    let goals: [JourneyAchievementGoal]

    var nextGoal: JourneyAchievementGoal? { goals.first { !$0.isEarned } }
    var latestCleared: JourneyAchievementGoal? { goals.last { $0.isEarned } }
    var currentGoal: JourneyAchievementGoal? { nextGoal ?? goals.last }
    var clearedCount: Int { goals.filter(\.isEarned).count }
}

/// A finite discovery guide for milestone families. Individual, repeatable PRs remain in earned history.
nonisolated enum JourneyAchievementCatalog {
    /// Preserve catalog order: thresholds within a series run from first to last.
    static func series(_ goals: [JourneyAchievementGoal]) -> [JourneyAchievementSeries] {
        let grouped = Dictionary(grouping: goals) { $0.seriesID ?? $0.id }
        var seen = Set<String>()
        return goals.compactMap { goal in
            let id = goal.seriesID ?? goal.id
            guard seen.insert(id).inserted else { return nil }
            return .init(id: id, title: goal.seriesTitle ?? goal.title, category: goal.category,
                goals: grouped[id, default: []])
        }
    }

    static func build(_ snapshot: TrainingJourneySnapshot, calendar: Calendar) -> [JourneyAchievementGoal] {
        let events = snapshot.milestones
        let ids = Set(events.map(\.id))
        let workouts = snapshot.years.flatMap(\.months).flatMap(\.workouts)
        let activities = workouts.flatMap(\.activities).filter {
            $0.distanceMeters.isFinite && $0.distanceMeters > 0 && $0.trackingProfile != .timeOnly && $0.trackingProfile != .stairClimber
        }
        var goals: [JourneyAchievementGoal] = []
        func badge(_ id: String, _ title: String, _ requirement: String, _ category: String, earned: Bool? = nil,
                   series: (id: String, title: String)? = nil) {
            goals.append(.init(id: id, title: title, requirement: requirement, category: category,
                isEarned: earned ?? ids.contains(id), seriesID: series?.id, seriesTitle: series?.title))
        }
        func count(_ id: String, _ title: String, _ category: String, current: Double, target: Double, unit: String,
                   series: (id: String, title: String)? = nil) {
            let value = min(current, target)
            goals.append(.init(id: id, title: title, requirement: String(localized: "Reach \(target.formatted()) \(unit)."),
                category: category, isEarned: current >= target,
                progress: min(1, max(0, current / target)),
                progressText: "\(value.formatted(.number.precision(.fractionLength(0...1)))) / \(target.formatted()) \(unit)",
                seriesID: series?.id, seriesTitle: series?.title))
        }
        let beginnings = String(localized: "Firsts & variety")
        badge("beginning", String(localized: "Your first workout"), String(localized: "Complete a workout."), beginnings)
        badge("first-cardio", String(localized: "Side quest unlocked"), String(localized: "Complete your first cardio activity."), beginnings,
            earned: events.contains { $0.id.hasPrefix("first-cardio-") })
        badge("celebration-mixed", String(localized: "Strength meets stamina"), String(localized: "Complete strength and cardio in one workout."), beginnings)
        badge("celebration-leg-day", String(localized: "Leg day has entered the chat"), String(localized: "Complete a strength exercise with legs or glutes as a known primary muscle group."), beginnings)
        let variety = Set(workouts.flatMap { $0.completedExercises.map(\.id) + $0.activities.map(\.exerciseID) }).count
        for target in [3, 5, 10] {
            count("celebration-variety-\(target)", String(localized: "\(target) different exercises tried"), beginnings,
                current: Double(variety), target: Double(target), unit: String(localized: "exercises"),
                series: ("variety", String(localized: "Exercise explorer")))
        }
        let consistency = String(localized: "Showing up")
        for target in [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000] {
            count("workouts-\(target)", String(localized: "\(target) workouts completed"), consistency,
                current: Double(snapshot.workoutCount), target: Double(target), unit: String(localized: "workouts"),
                series: ("workouts", String(localized: "Showing up")))
        }
        for target in [30, 100, 365, 1_000] {
            count("active-days-\(target)", String(localized: "\(target) active days"), consistency,
                current: Double(snapshot.activeDays), target: Double(target), unit: String(localized: "days"),
                series: ("active-days", String(localized: "Days for you")))
        }
        for target in [10, 24, 50, 100, 168, 250, 500, 1_000] {
            count("training-hours-\(target)", String(localized: "\(target) hours of training"), consistency,
                current: Double(snapshot.durationSeconds) / 3_600, target: Double(target), unit: String(localized: "hours"),
                series: ("training-hours", String(localized: "Time well spent")))
        }
        let weeks = Set(workouts.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start }).sorted()
        var longest = 0, streak = 0
        var previous: Date?
        for week in weeks {
            streak = previous.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) } == week ? streak + 1 : 1
            longest = max(longest, streak)
            previous = week
        }
        for target in [4, 10, 12, 26, 52] {
            count("consistency-\(target)", String(localized: "\(target) consecutive training weeks"), consistency,
                current: Double(longest), target: Double(target), unit: String(localized: "consecutive weeks"),
                series: ("consistency", String(localized: "We go jim. Again.")))
        }
        let monthlyBest = snapshot.years.flatMap(\.months).map(\.activeDays).max() ?? 0
        for target in [5, 10, 15, 20] {
            count("celebration-rhythm-\(target)", String(localized: "\(target) active days in a month"), consistency,
                current: Double(monthlyBest), target: Double(target), unit: String(localized: "days in one month"),
                series: ("rhythm", String(localized: "Finding your rhythm")))
        }
        badge("best-month", String(localized: "Your most active month yet"), String(localized: "Finish a month with more active days than any earlier completed month."), consistency,
            earned: events.contains { $0.id.hasPrefix("celebration-best-month-") })
        let distance = String(localized: "Going places")
        let unit: WorkoutDistanceUnit = snapshot.distanceUnit == .meters ? .kilometers : snapshot.distanceUnit
        for target in [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000] {
            count("foot-distance-\(target)", String(localized: "\(target) \(unit.symbol) on foot"), distance,
                current: unit.value(fromMeters: snapshot.walkRunDistanceMeters), target: Double(target), unit: unit.symbol,
                series: ("foot-distance", String(localized: "On foot")))
            count("other-distance-\(target)", String(localized: "\(target) \(unit.symbol) of other cardio"), distance,
                current: unit.value(fromMeters: snapshot.otherCardioDistanceMeters), target: Double(target), unit: unit.symbol,
                series: ("other-distance", String(localized: "Beyond walking and running")))
        }
        for (meters, title) in [(21_097.5, String(localized: "A half marathon in total")), (42_195.0, String(localized: "A marathon in total"))] {
            count("foot-\(Int(meters))", title, distance, current: snapshot.walkRunDistanceMeters / 1_000,
                target: meters / 1_000, unit: String(localized: "km on foot across workouts"),
                series: ("foot-adventures", String(localized: "Every step adds up")))
        }
        if unit == .miles {
            count("foot-100km", String(localized: "100 km on foot in total"), distance,
                current: snapshot.walkRunDistanceMeters / 1_000, target: 100, unit: String(localized: "km on foot across workouts"),
                series: ("foot-adventures", String(localized: "Every step adds up")))
        }
        count("cycling-100km", String(localized: "Tour de You"), distance,
            current: activities.filter(\.isCycling).reduce(0) { $0 + $1.distanceMeters } / 1_000, target: 100,
            unit: String(localized: "km cycling across workouts"))
        count("rowing-50km", String(localized: "Oar-some behaviour"), distance,
            current: activities.filter { $0.trackingProfile == .rower }.reduce(0) { $0 + $1.distanceMeters } / 1_000, target: 50,
            unit: String(localized: "km rowing across workouts"))
        let records = String(localized: "Breakthroughs")
        badge("strength-pr", String(localized: "Gravity filed a complaint"), String(localized: "Beat your heaviest weight for an exercise."), records,
            earned: events.contains { $0.kind == .strength && $0.recordKey?.hasSuffix("-weight") == true })
        badge("bodyweight-pr", String(localized: "Same human. More horsepower."), String(localized: "Beat your bodyweight-rep record for an exercise."), records,
            earned: events.contains { $0.kind == .strength && $0.recordKey?.hasSuffix("-reps") == true })
        badge("distance-pr", String(localized: "Longest distance"), String(localized: "Beat your distance for the same cardio exercise and tracking type. Your first attempt sets the baseline."), records,
            earned: events.contains { $0.id.hasPrefix("cardio-pr-distance-") })
        badge("speed-pr", String(localized: "Fastest average speed"), String(localized: "Beat your whole-activity average speed for the same exercise and tracking type, over at least 1 km. Your first qualifying attempt sets the baseline."), records,
            earned: events.contains { $0.id.hasPrefix("cardio-pr-speed-") })
        let recordCount = events.filter { $0.personalRecord != nil }.count
        for target in [10, 25, 50, 100] {
            count("records-\(target)", String(localized: "\(target) Journey PRs"), records,
                current: Double(recordCount), target: Double(target), unit: String(localized: "PRs"),
                series: ("records", String(localized: "A collection of breakthroughs")))
        }
        for percent in [25, 50, 100] {
            badge("improvement-\(percent)", String(localized: "\(percent)% above your starting point"),
                String(localized: "Improve an exercise's weight or bodyweight reps by \(percent)% over its first recorded result."), records,
                earned: events.contains { $0.id.hasPrefix("celebration-improvement-") && $0.id.hasSuffix("-\(percent)") },
                series: ("improvements", String(localized: "Look how far you've come")))
        }
        badge("celebration-pr-printer", String(localized: "PR printer goes brrr"), String(localized: "Earn three distinct exercise-and-record-type PRs in one workout."), records)
        badge("celebration-sequel", String(localized: "The sequel was stronger"), String(localized: "Beat a PR again in your next completed session for the same exercise and metric."), records)
        badge("celebration-montage", String(localized: "Main character training montage"), String(localized: "Finish a month containing strength, cardio and a PR."), records)
        let story = String(localized: "Your story")
        for years in [1, 2, 3, 5, 10] {
            badge("celebration-anniversary-\(years)", String(localized: "\(years)-year training anniversary"),
                String(localized: "Complete a workout on or after the \(years)-year anniversary of your first workout."), story,
                series: ("anniversaries", String(localized: "The gains have lore now")))
        }
        badge("new-year", String(localized: "The lore continues"), String(localized: "Log your first workout in a later calendar year."), story,
            earned: events.contains { $0.id.hasPrefix("celebration-new-year-") })
        badge("comeback", String(localized: "Back at it"), String(localized: "A welcome back if you return after 30 days away. No need to take a break to chase this one."), story,
            earned: events.contains { $0.id.hasPrefix("celebration-comeback-") })
        return goals
    }
}
