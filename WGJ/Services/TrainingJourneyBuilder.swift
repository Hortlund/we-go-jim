import Foundation

/// Reconstructs achievements from recorded history. No persisted badges or cloud writes.
nonisolated enum TrainingJourneyBuilder {
    static func build(workouts: [JourneyWorkout], exercises: [JourneyExercise],
                      distanceUnit: WorkoutDistanceUnit = .kilometers, loadUnit: TemplateLoadUnit = .kg,
                      calendar: Calendar = .current, now: Date = .now) -> TrainingJourneySnapshot {
        let ordered = workouts.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        let visibleIDs = Set(ordered.map(\.id))
        let days = Dictionary(grouping: ordered, by: { calendar.startOfDay(for: $0.date) })
        var events: [JourneyMilestone] = []
        if let first = ordered.first {
            events.append(.init(id: "beginning", sessionID: first.id, date: first.date, kind: .beginning,
                title: String(localized: "Your first workout"), detail: first.name))
        }
        let thresholds = Set([10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000])
        var distance = 0.0
        let distanceSteps: [Double] = [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
        var nextDistanceStep = 0
        // Distance thresholds follow the chosen display unit, with meters using km milestones.
        let milestoneUnit: WorkoutDistanceUnit = distanceUnit == .meters ? .kilometers : distanceUnit
        var longestByExercise: [String: Double] = [:]
        var featuredDistanceByExercise: [String: Double] = [:]
        for (index, workout) in ordered.enumerated() {
            if thresholds.contains(index + 1) {
                events.append(.init(id: "workouts-\(index + 1)", sessionID: workout.id, date: workout.date,
                    kind: .workouts, title: String(localized: "\(index + 1) workouts completed"),
                    detail: String(localized: "Every session adds up.")))
            }
            for activity in workout.activities
                where activity.isWalkRun && activity.distanceMeters.isFinite && activity.distanceMeters > 0 {
                distance += activity.distanceMeters
                let previous = longestByExercise[activity.exerciseID]
                let featured = featuredDistanceByExercise[activity.exerciseID] ?? previous
                if previous == nil {
                    events.append(.init(id: "first-cardio-\(activity.exerciseID)", sessionID: workout.id, date: workout.date,
                        kind: .cardio, title: String(localized: "Your first \(activity.name.lowercased())"),
                        detail: "\(JourneyFormatting.distance(activity.distanceMeters, unit: distanceUnit)) · \(JourneyFormatting.time(activity.durationSeconds))",
                        activityID: activity.isOutdoor ? activity.id : nil))
                }
                if let previous, let featured, activity.distanceMeters > previous,
                   activity.distanceMeters >= featured * 1.05,
                   activity.distanceMeters - featured >= 100 {
                    events.append(.init(id: "distance-\(activity.id)", sessionID: workout.id, date: workout.date,
                        kind: .cardio, title: String(localized: "Longest \(activity.name.lowercased())"),
                        detail: "\(JourneyFormatting.distance(activity.distanceMeters, unit: distanceUnit)) · \(JourneyFormatting.time(activity.durationSeconds))",
                        activityID: activity.isOutdoor ? activity.id : nil))
                    featuredDistanceByExercise[activity.exerciseID] = activity.distanceMeters
                }
                if previous == nil { featuredDistanceByExercise[activity.exerciseID] = activity.distanceMeters }
                longestByExercise[activity.exerciseID] = max(previous ?? 0, activity.distanceMeters)
            }
            // A long outing can cross several thresholds. Feature the highest one reached.
            var crossed: Double?
            while nextDistanceStep < distanceSteps.count,
                  distance >= milestoneUnit.meters(from: distanceSteps[nextDistanceStep]) {
                crossed = distanceSteps[nextDistanceStep]
                nextDistanceStep += 1
            }
            if let crossed {
                events.append(.init(id: "total-distance-\(milestoneUnit.rawValue)-\(crossed)", sessionID: workout.id, date: workout.date,
                    kind: .cardio, title: String(localized: "\(JourneyFormatting.distance(milestoneUnit.meters(from: crossed), unit: milestoneUnit)) on foot"),
                    detail: String(localized: "Total recorded walking and running distance.")))
            }
        }
        for exercise in exercises.sorted(by: { $0.id < $1.id }) {
            let points = exercise.performances.filter {
                visibleIDs.contains($0.sessionID) && $0.value.isFinite && $0.value > 0
            }.sorted { $0.date == $1.date ? $0.sessionID.uuidString < $1.sessionID.uuidString : $0.date < $1.date }
            guard let first = points.first else { continue }
            var record = first.value
            var featured = first.value
            for (index, point) in points.enumerated().dropFirst() {
                guard point.value > record else { continue }
                record = point.value
                let minimumChange = exercise.isReps ? 2.0 : max(2.5, featured * 0.1)
                guard point.value - featured >= minimumChange - 0.0001 else { continue }
                featured = point.value
                func valueText(_ value: Double) -> String {
                    if exercise.isReps { return String(localized: "\(Int(value)) reps") }
                    let displayed = (loadUnit == .lb ? value / 0.45359237 : value)
                    return "\(displayed.formatted(.number.precision(.fractionLength(0...1)))) \(loadUnit.shortLabel)"
                }
                let unit = exercise.isReps ? String(localized: "reps") : loadUnit.shortLabel
                events.append(.init(id: "strength-\(exercise.id)-\(point.sessionID)", sessionID: point.sessionID,
                    date: point.date, kind: .strength,
                    title: "\(exercise.name) · \(valueText(point.value))",
                    detail: exercise.isReps
                        ? String(localized: "Bodyweight sets. First recorded: \(valueText(first.value)).")
                        : exercise.usesAddedWeight
                        ? String(localized: "Added weight. First recorded: \(valueText(first.value)).")
                        : String(localized: "First recorded: \(valueText(first.value))."),
                    chart: chartPoints(points, through: index).map {
                        JourneyPerformance(sessionID: $0.sessionID, date: $0.date,
                            value: exercise.isReps ? $0.value : (loadUnit == .lb ? $0.value / 0.45359237 : $0.value))
                    }, chartUnit: unit))
            }
        }
        events += consistencyEvents(ordered, calendar: calendar)
        let workoutsByMonth = Dictionary(grouping: ordered, by: {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
        })
        // Advance through real calendar intervals: years can change eras and
        // calendars can include a thirteenth or leap month.
        let yearFormatter = DateIntervalFormatter()
        yearFormatter.calendar = calendar
        yearFormatter.locale = calendar.locale ?? .current
        yearFormatter.dateTemplate = calendar.identifier == .japanese ? "Gy" : "y"
        var years: [JourneyYear] = []
        var yearCursor = min(ordered.first?.date ?? now, now)
        let latestDate = max(ordered.last?.date ?? now, now)
        while yearCursor <= latestDate,
              let year = calendar.dateInterval(of: .year, for: yearCursor), year.end > yearCursor {
            var months: [JourneyMonth] = []
            var monthCursor = year.start
            while monthCursor < year.end,
                  let month = calendar.dateInterval(of: .month, for: monthCursor), month.end > monthCursor {
                let start = month.start
                let monthWorkouts = workoutsByMonth[start, default: []]
                var monthDays: [JourneyDay] = []
                var date = start
                while date < month.end {
                    let sessions = days[calendar.startOfDay(for: date), default: []]
                    monthDays.append(JourneyDay(date: date, workoutCount: sessions.count,
                        hasStrength: sessions.contains(where: \.hasStrength), hasCardio: sessions.contains(where: \.hasCardio)))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
                    date = next
                }
                let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
                months.append(JourneyMonth(date: start, leadingDays: offset, days: monthDays, workouts: monthWorkouts))
                monthCursor = month.end
            }
            years.append(JourneyYear(date: year.start,
                title: yearFormatter.string(from: year.start, to: year.end.addingTimeInterval(-1)), months: months))
            yearCursor = year.end
        }
        return TrainingJourneySnapshot(workoutCount: ordered.count, activeDays: days.count,
            durationSeconds: ordered.reduce(0) { $0 + max(0, $1.durationSeconds) },
            walkRunDistanceMeters: distance, firstWorkoutDate: ordered.first?.date, years: Array(years.reversed()),
            milestones: events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }, distanceUnit: distanceUnit)
    }

    private static func chartPoints(_ points: [JourneyPerformance], through lastIndex: Int) -> [JourneyPerformance] {
        guard lastIndex >= 24 else { return Array(points.prefix(lastIndex + 1)) }
        return (0..<24).map { points[Int(Double($0) * Double(lastIndex) / 23)] }
    }

    private static func consistencyEvents(_ workouts: [JourneyWorkout], calendar: Calendar) -> [JourneyMilestone] {
        let weeks = Dictionary(grouping: workouts, by: {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
        })
        var previous: Date?
        var streak = 0
        var achieved: Set<Int> = []
        var events: [JourneyMilestone] = []
        for week in weeks.keys.sorted() {
            streak = previous.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) } == week ? streak + 1 : 1
            previous = week
            guard [4, 12, 26, 52].contains(streak), achieved.insert(streak).inserted,
                  let workout = weeks[week]?.min(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) else { continue }
            events.append(.init(id: "consistency-\(streak)", sessionID: workout.id, date: workout.date, kind: .consistency,
                title: String(localized: "\(streak) consecutive training weeks"),
                detail: String(localized: "At least one workout each week.")))
        }
        return events
    }
}
