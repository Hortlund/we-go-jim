import Foundation

nonisolated struct TrainingYearRecap: Identifiable, Equatable, Sendable {
    var id: Date { yearStart }
    let yearStart: Date
    let yearTitle: String
    let isYearInProgress: Bool
    let workoutCount: Int
    let activeDays: Int
    let durationSeconds: Int
    let walkRunDistanceMeters: Double
    let distanceUnit: WorkoutDistanceUnit
    let trainingWeeks: Int
    let milestoneCount: Int
    let months: [Month]
    let busiestMonth: String?
    let busiestMonthWorkoutCount: Int
    let highlight: String?

    nonisolated struct Month: Identifiable, Equatable, Sendable {
        var id: Date { date }
        let date: Date
        let label: String
        let workoutCount: Int
    }

    var periodLabel: String {
        isYearInProgress ? String(localized: "Year so far") : String(localized: "Year in training")
    }

    var accessibilitySummary: String {
        var summary = String(localized: "\(yearTitle), \(periodLabel). \(workoutCount) workouts, \(activeDays) active days, \(JourneyFormatting.time(durationSeconds)) training, \(JourneyFormatting.distance(walkRunDistanceMeters, unit: distanceUnit)) walking and running. \(trainingWeeks) training weeks, \(milestoneCount) milestones.")
        if let busiestMonth {
            summary += " " + String(localized: "Busiest month: \(busiestMonth), \(busiestMonthWorkoutCount) workouts.")
        }
        if let highlight { summary += " " + highlight }
        return summary
    }
}
