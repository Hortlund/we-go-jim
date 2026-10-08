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
        var otherDistance = 0.0
        var nextOtherDistanceStep = 0
        var trainingSeconds = 0
        var nextTimeStep = 0
        let timeSteps = [10, 24, 50, 100, 168, 250, 500, 1_000]
        var activeDays: Set<Date> = []
        let distanceSteps: [Double] = [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
        var nextDistanceStep = 0
        // Distance thresholds follow the chosen display unit, with meters using km milestones.
        let milestoneUnit: WorkoutDistanceUnit = distanceUnit == .meters ? .kilometers : distanceUnit
        var longestByExercise: [String: Double] = [:]
        for (index, workout) in ordered.enumerated() {
            if thresholds.contains(index + 1) {
                events.append(.init(id: "workouts-\(index + 1)", sessionID: workout.id, date: workout.date,
                    kind: .workouts, title: String(localized: "\(index + 1) workouts completed"),
                    detail: String(localized: "Every session adds up.")))
            }
            let day = calendar.startOfDay(for: workout.date)
            if activeDays.insert(day).inserted, [30, 100, 365, 1_000].contains(activeDays.count) {
                events.append(.init(id: "active-days-\(activeDays.count)", sessionID: workout.id, date: workout.date,
                    kind: .consistency, title: String(localized: "\(activeDays.count) active days"),
                    detail: String(localized: "Days you made time for yourself. Every one counts.")))
            }
            trainingSeconds += max(0, workout.durationSeconds)
            var crossedHours: Int?
            while nextTimeStep < timeSteps.count, trainingSeconds >= timeSteps[nextTimeStep] * 3_600 {
                crossedHours = timeSteps[nextTimeStep]
                nextTimeStep += 1
            }
            if let crossedHours {
                events.append(.init(id: "training-hours-\(crossedHours)", sessionID: workout.id, date: workout.date,
                    kind: .workouts, title: String(localized: "\(crossedHours) hours of training"),
                    detail: String(localized: "Time invested in getting stronger, fitter, and feeling good.")))
            }
            for activity in workout.activities.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let validDistance = activity.distanceMeters.isFinite && activity.distanceMeters > 0
                    && activity.trackingProfile != .timeOnly && activity.trackingProfile != .stairClimber
                let previous = longestByExercise[activity.exerciseID]
                if previous == nil {
                    let detail = validDistance
                        ? "\(JourneyFormatting.distance(activity.distanceMeters, unit: distanceUnit)) · \(JourneyFormatting.time(activity.durationSeconds))"
                        : JourneyFormatting.time(activity.durationSeconds)
                    events.append(.init(id: "first-cardio-\(activity.exerciseID)", sessionID: workout.id, date: workout.date,
                        kind: .cardio, title: String(localized: "Your first \(activity.name.lowercased())"),
                        detail: detail, activityID: activity.isOutdoor ? activity.id : nil))
                }
                longestByExercise[activity.exerciseID] = max(previous ?? 0, validDistance ? activity.distanceMeters : 0)
                guard validDistance else { continue }
                if activity.isWalkRun { distance += activity.distanceMeters }
                else { otherDistance += activity.distanceMeters }
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
            var crossedOther: Double?
            while nextOtherDistanceStep < distanceSteps.count,
                  otherDistance >= milestoneUnit.meters(from: distanceSteps[nextOtherDistanceStep]) {
                crossedOther = distanceSteps[nextOtherDistanceStep]
                nextOtherDistanceStep += 1
            }
            if let crossedOther {
                events.append(.init(id: "other-distance-\(milestoneUnit.rawValue)-\(crossedOther)", sessionID: workout.id,
                    date: workout.date, kind: .cardio,
                    title: String(localized: "\(JourneyFormatting.distance(milestoneUnit.meters(from: crossedOther), unit: milestoneUnit)) beyond walking and running"),
                    detail: String(localized: "Total recorded cycling, rowing, and other distance cardio.")))
            }
        }
        events += CardioPersonalRecordService.milestones(workouts: ordered, unit: distanceUnit)
        for exercise in exercises.sorted(by: { $0.id < $1.id }) {
            let points = exercise.performances.filter {
                visibleIDs.contains($0.sessionID) && $0.value.isFinite && $0.value > 0
            }.sorted { $0.date == $1.date ? $0.sessionID.uuidString < $1.sessionID.uuidString : $0.date < $1.date }
            guard let first = points.first else { continue }
            var record = first.value
            for (index, point) in points.enumerated().dropFirst() {
                guard point.value > record else { continue }
                record = point.value
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
                    }, chartUnit: unit, personalRecord: .init(
                        id: "strength-\(exercise.id)-\(point.sessionID)", exerciseName: exercise.name,
                        performanceText: valueText(point.value),
                        detailText: exercise.isReps ? String(localized: "Most bodyweight reps")
                            : exercise.usesAddedWeight ? String(localized: "Heaviest added weight")
                            : String(localized: "Heaviest weight")), recordKey: "strength-\(exercise.id)"))
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
        events = JourneyCelebrationBuilder.milestones(workouts: ordered, exercises: exercises,
            existing: events, unit: distanceUnit, calendar: calendar, now: now)
        let insights = JourneyInsightsBuilder.build(workouts: ordered, exercises: exercises,
            years: Array(years.reversed()), events: events, unit: distanceUnit, calendar: calendar, now: now)
        var snapshot = TrainingJourneySnapshot(workoutCount: ordered.count, activeDays: days.count,
            durationSeconds: ordered.reduce(0) { $0 + max(0, $1.durationSeconds) },
            walkRunDistanceMeters: distance, firstWorkoutDate: ordered.first?.date, years: Array(years.reversed()),
            milestones: events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }, distanceUnit: distanceUnit,
            otherCardioDistanceMeters: otherDistance, insights: insights)
        snapshot.achievementGoals = JourneyAchievementCatalog.build(snapshot, calendar: calendar)
        return snapshot
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
            guard [4, 10, 12, 26, 52].contains(streak), achieved.insert(streak).inserted,
                  let workout = weeks[week]?.min(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) else { continue }
            events.append(.init(id: "consistency-\(streak)", sessionID: workout.id, date: workout.date, kind: .consistency,
                title: String(localized: "\(streak) consecutive training weeks"),
                detail: String(localized: "At least one workout each week.")))
        }
        return events
    }
}
