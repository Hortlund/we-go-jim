import Foundation

nonisolated enum ExerciseProgressMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case estimatedOneRepMax
    case heaviestWeight
    case bestSetReps
    case sessionVolume
    case totalReps
    case workoutFrequency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedOneRepMax: "Estimated 1RM"
        case .heaviestWeight: "Heaviest Weight"
        case .bestSetReps: "Best-Set Reps"
        case .sessionVolume: "Session Volume"
        case .totalReps: "Total Reps"
        case .workoutFrequency: "Workout Frequency"
        }
    }

    var isWeighted: Bool {
        self == .estimatedOneRepMax || self == .heaviestWeight || self == .sessionVolume
    }
}

nonisolated enum ExerciseProgressRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        case .allTime: "All"
        }
    }
}

nonisolated struct ExerciseProgressSession: Equatable, Sendable {
    let sessionID: UUID
    let completedAt: Date
    let estimatedOneRepMaxKilograms: Double?
    let heaviestWeightKilograms: Double?
    let sessionVolumeKilograms: Double?
    let bestSetReps: Int?
    let totalReps: Int
    let completedSetCount: Int
    let displayUnit: TemplateLoadUnit
}

nonisolated struct ExerciseProgressDataset: Equatable, Sendable {
    let exerciseUUID: String
    let exerciseName: String
    let sessions: [ExerciseProgressSession]
    let preferredLoadUnit: TemplateLoadUnit

    init(
        exerciseUUID: String,
        exerciseName: String,
        sessions: [ExerciseProgressSession],
        preferredLoadUnit: TemplateLoadUnit
    ) {
        self.exerciseUUID = exerciseUUID
        self.exerciseName = exerciseName
        self.sessions = sessions.sorted {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.sessionID.uuidString < $1.sessionID.uuidString
        }
        self.preferredLoadUnit = preferredLoadUnit
    }
}

nonisolated struct ExerciseProgressPoint: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let value: Double
}

nonisolated struct ExerciseProgressAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let reason: String?
}

nonisolated struct ExerciseProgressSummary: Equatable, Sendable {
    let first: Double
    let latest: Double
    let best: Double
    let absoluteChange: Double
    let percentageChange: Double?
    let sessionCount: Int
    let totalSets: Int
    let totalReps: Int
}

nonisolated enum ExerciseProgressMilestoneKind: String, Equatable, Sendable {
    case firstPerformance
    case personalRecord
    case materialChange
    case latestPerformance
}

nonisolated struct ExerciseProgressMilestone: Identifiable, Equatable, Sendable {
    let id: String
    let pointID: String
    let date: Date
    let value: Double
    let kind: ExerciseProgressMilestoneKind
}

nonisolated struct ExerciseProgressProjection: Equatable, Sendable {
    let metric: ExerciseProgressMetric
    let range: ExerciseProgressRange
    let availability: ExerciseProgressAvailability
    let displayUnit: TemplateLoadUnit
    let points: [ExerciseProgressPoint]
    let chartPoints: [ExerciseProgressPoint]
    let summary: ExerciseProgressSummary?
    let milestones: [ExerciseProgressMilestone]
    let accessibilitySummary: String
}
