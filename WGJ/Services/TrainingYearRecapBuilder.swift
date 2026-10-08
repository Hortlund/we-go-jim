import Foundation

/// Uses the same visible history as Journey. Sharing never writes to the store.
nonisolated enum TrainingYearRecapBuilder {
    static func build(_ snapshot: TrainingJourneySnapshot, calendar: Calendar = .current,
                      now: Date = .now) -> [TrainingYearRecap] {
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = calendar.locale ?? .current
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        let fullMonthFormatter = DateFormatter()
        fullMonthFormatter.calendar = calendar
        fullMonthFormatter.locale = calendar.locale ?? .current
        fullMonthFormatter.timeZone = calendar.timeZone
        fullMonthFormatter.setLocalizedDateFormatFromTemplate("MMMM")

        return snapshot.years.compactMap { year in
            let workouts = year.months.flatMap(\.workouts)
            guard !workouts.isEmpty else { return nil }
            let sessionIDs = Set(workouts.map(\.id))
            let milestones = snapshot.milestones.filter { sessionIDs.contains($0.sessionID) }
            let highlight = milestones.first { $0.kind == .strength }
                ?? milestones.first { $0.kind == .cardio && $0.personalRecord != nil }
                ?? milestones.first
            // First month wins ties, keeping the recap deterministic.
            let busiest = year.months.reduce(nil as JourneyMonth?) { best, month in
                guard month.workouts.count > (best?.workouts.count ?? 0) else { return best }
                return month
            }
            let weeks = Set(workouts.map {
                calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
            })
            let distance = workouts.flatMap(\.activities).filter {
                $0.isWalkRun && $0.distanceMeters.isFinite && $0.distanceMeters > 0
            }.reduce(0) { $0 + $1.distanceMeters }
            let yearInterval = calendar.dateInterval(of: .year, for: year.date)
            return TrainingYearRecap(yearStart: year.date, yearTitle: year.title,
                isYearInProgress: yearInterval.map { now >= $0.start && now < $0.end } ?? false,
                workoutCount: workouts.count,
                activeDays: Set(workouts.map { calendar.startOfDay(for: $0.date) }).count,
                durationSeconds: workouts.reduce(0) { $0 + max(0, $1.durationSeconds) },
                walkRunDistanceMeters: distance, distanceUnit: snapshot.distanceUnit,
                trainingWeeks: weeks.count, milestoneCount: milestones.count,
                months: year.months.map {
                    .init(date: $0.date, label: monthFormatter.string(from: $0.date), workoutCount: $0.workouts.count)
                },
                busiestMonth: busiest.map { fullMonthFormatter.string(from: $0.date) },
                busiestMonthWorkoutCount: busiest?.workouts.count ?? 0, highlight: highlight?.title)
        }
    }
}
