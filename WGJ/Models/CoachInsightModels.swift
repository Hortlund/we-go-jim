import Foundation

nonisolated enum CoachFollowUpKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case whatImproved
    case whyFlat
    case whatChanged
}

nonisolated enum CoachNarrativeAvailabilityMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case generated
    case fallback
}

nonisolated struct WeeklyCoachSignal: Identifiable, Equatable, Sendable {
    let id: String
    let catalogExerciseUUID: String
    let exerciseName: String
    let deltaPercentage: Double
    let summary: String
}

nonisolated struct WeeklyCoachInsightSnapshot: Equatable, Sendable {
    let weekStart: Date
    let revisionKey: String
    let baselineWeekCount: Int
    let completedWorkoutCount: Int
    let totalVolumeDelta: Double
    let consistencyDelta: Double
    let topRisingSignals: [WeeklyCoachSignal]
    let topWatchSignals: [WeeklyCoachSignal]
    let fallbackSummary: String?
    let followUpKinds: [CoachFollowUpKind]
}
