import Foundation

nonisolated struct JourneyWorkout: Identifiable, Sendable {
    let id: UUID
    let name: String
    let date: Date
    let durationSeconds: Int
    let hasStrength: Bool
    let hasCardio: Bool
    let activities: [JourneyActivity]
    var completedExercises: [JourneyCompletedExercise] = []
}

nonisolated struct JourneyCompletedExercise: Sendable {
    let id: String
    let name: String
    var isLegExercise: Bool = false
}

nonisolated struct JourneyActivity: Sendable {
    let id: UUID
    let exerciseID: String
    let name: String
    let distanceMeters: Double
    let durationSeconds: Int
    let isWalkRun: Bool
    let isOutdoor: Bool
    var trackingProfile: WorkoutCardioTrackingProfile = .walkRun
    var isCycling: Bool = false
}

nonisolated struct JourneyPerformance: Identifiable, Sendable {
    var id: UUID { sessionID }
    let sessionID: UUID
    let date: Date
    let value: Double
}

nonisolated struct JourneyExercise: Sendable {
    let id: String
    let name: String
    let isReps: Bool
    let usesAddedWeight: Bool
    let performances: [JourneyPerformance]
}

nonisolated enum JourneyMilestoneKind: String, CaseIterable, Sendable {
    case beginning, workouts, strength, cardio, consistency, celebration

    var systemImage: String {
        switch self {
        case .beginning: "flag.fill"
        case .workouts: "trophy.fill"
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        case .consistency: "flame.fill"
        case .celebration: "sparkles"
        }
    }
}

nonisolated struct JourneyMilestone: Identifiable, Sendable {
    let id: String
    let sessionID: UUID
    let date: Date
    let kind: JourneyMilestoneKind
    let title: String
    let detail: String
    var activityID: UUID? = nil
    var chart: [JourneyPerformance] = []
    var chartUnit: String? = nil
    var personalRecord: WorkoutCompletionPersonalRecord? = nil
    var recordKey: String? = nil
    var playfulTitle: String? = nil
    var unlockedAt: Date? = nil
}

nonisolated struct JourneyDay: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let workoutCount: Int
    let hasStrength: Bool
    let hasCardio: Bool
}

nonisolated struct JourneyMonth: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let leadingDays: Int
    let days: [JourneyDay]
    let workouts: [JourneyWorkout]
    var activeDays: Int { days.filter { $0.workoutCount > 0 }.count }
}

nonisolated struct JourneyYear: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let title: String
    let months: [JourneyMonth]
}

nonisolated struct TrainingJourneySnapshot: Sendable {
    let workoutCount: Int
    let activeDays: Int
    let durationSeconds: Int
    let walkRunDistanceMeters: Double
    let firstWorkoutDate: Date?
    let years: [JourneyYear]
    let milestones: [JourneyMilestone]
    let distanceUnit: WorkoutDistanceUnit
    var otherCardioDistanceMeters: Double = 0
    var insights: JourneyInsights = .init()
    var achievementGoals: [JourneyAchievementGoal] = []
    var celebrationScope: String = "local"

    static let empty = Self(workoutCount: 0, activeDays: 0, durationSeconds: 0,
        walkRunDistanceMeters: 0, firstWorkoutDate: nil, years: [], milestones: [], distanceUnit: .kilometers)
}

nonisolated enum JourneyFormatting {
    static func distance(_ meters: Double, unit: WorkoutDistanceUnit) -> String {
        let value = unit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol)"
    }

    static func time(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 60 { return "\(minutes.formatted()) min" }
        return "\((Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...1)))) h"
    }
}
