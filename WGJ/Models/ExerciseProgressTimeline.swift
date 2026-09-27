import Foundation

nonisolated enum ExerciseProgressMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case estimatedOneRepMax
    case heaviestWeight
    case bestSetReps
    case sessionVolume
    case totalReps
    case workoutFrequency
    case duration
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedOneRepMax: "Estimated 1RM"
        case .heaviestWeight: "Heaviest Weight"
        case .bestSetReps: "Best-Set Reps"
        case .sessionVolume: "Session Volume"
        case .totalReps: "Total Reps"
        case .workoutFrequency: "Workout Frequency"
        case .duration: "Duration"
        case .distance: "Distance"
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

nonisolated struct ExerciseProgressSession: Hashable, Sendable {
    let sessionID: UUID
    let completedAt: Date
    let estimatedOneRepMaxKilograms: Double?
    let heaviestWeightKilograms: Double?
    let sessionVolumeKilograms: Double?
    let bestSetReps: Int?
    let totalReps: Int
    let completedSetCount: Int
    let displayUnit: TemplateLoadUnit
    var durationSeconds: Double? = nil
    var distanceMeters: Double? = nil
    var loadContext: ExerciseLoadContext? = nil
}

nonisolated struct ExerciseProgressDataset: Hashable, Sendable {
    let exerciseUUID: String
    let exerciseName: String
    let sessions: [ExerciseProgressSession]
    let preferredLoadUnit: TemplateLoadUnit
    let usesAddedWeight: Bool
    let usesAssistance: Bool

    init(
        exerciseUUID: String,
        exerciseName: String,
        sessions: [ExerciseProgressSession],
        preferredLoadUnit: TemplateLoadUnit,
        usesAddedWeight: Bool = false, usesAssistance: Bool = false
    ) {
        self.exerciseUUID = exerciseUUID
        self.exerciseName = exerciseName
        self.sessions = sessions.sorted {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.sessionID.uuidString < $1.sessionID.uuidString
        }
        self.preferredLoadUnit = preferredLoadUnit
        self.usesAddedWeight = usesAddedWeight
        self.usesAssistance = usesAssistance
    }
}

nonisolated struct ExerciseProgressPoint: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let value: Double
    var context: String? = nil
    var performance: ExerciseSetPerformance? = nil
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
    var context: String? = nil
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
    var usesAddedWeight: Bool = false
    var usesAssistance: Bool = false
}

extension ExerciseProgressDataset {
    func title(for metric: ExerciseProgressMetric) -> String {
        usesAddedWeight && metric == .heaviestWeight ? "Heaviest Added Weight"
            : usesAddedWeight && metric == .sessionVolume ? "Added-Weight Volume" : metric.title
    }

    var preferredMetric: ExerciseProgressMetric {
        usesAddedWeight || usesAssistance ? .bestSetReps : .estimatedOneRepMax
    }
}

extension ExerciseProgressProjection {
    var metricTitle: String {
        usesAddedWeight && metric == .heaviestWeight ? "Heaviest Added Weight"
            : usesAddedWeight && metric == .sessionVolume ? "Added-Weight Volume" : metric.title
    }

    var comparisonNote: String? {
        if metric == .bestSetReps, points.count > 1 {
            guard let first = points.first?.performance, let last = points.last?.performance else {
                return "Compare reps alongside the load used."
            }
            if !first.hasSameLoad(as: last) {
                return usesAssistance ? "Assistance changed. Compare reps at the same assistance on the same machine." : "Load changed. Fewer reps at a heavier load can still be progress."
            }
        }
        if metric == .totalReps { return "Total reps depend on both load and the number of working sets." }
        return nil
    }

    var metricExplanation: String? {
        if usesAssistance { return "Less assistance is harder. Compare reps at the same assistance on the same machine; bodyweight and effort also matter." }
        return switch metric {
        case .bestSetReps: "Your highest-rep working set in each workout, with its logged load. Compare similar technique, range of motion and effort."
        case .totalReps: "Reps across all completed working sets."
        case .sessionVolume: usesAddedWeight
            ? "Added weight × reps across working sets. Bodyweight is not included."
            : "Weight × reps across working sets. This measures training volume, not strength on its own."
        case .estimatedOneRepMax: "An estimate from logged weight and reps, not a tested maximum. Technique, effort and rep range affect the estimate."
        case .heaviestWeight: usesAddedWeight ? "External weight only. Your bodyweight is not included." : nil
        default: nil
        }
    }

    func formattedValue(_ value: Double) -> String {
        switch metric {
        case .estimatedOneRepMax, .heaviestWeight:
            return "\(WGJFormatters.oneDecimalString(value)) \(displayUnit.shortLabel)"
        case .sessionVolume:
            return "\(WGJFormatters.integerString(value)) \(displayUnit.shortLabel)"
        case .bestSetReps, .totalReps:
            return "\(Int(value.rounded())) reps"
        case .duration:
            return "\(WGJFormatters.oneDecimalString(value / 60)) min"
        case .distance:
            return "\(WGJFormatters.oneDecimalString(value / 1000)) km"
        case .workoutFrequency:
            let count = Int(value.rounded())
            return "\(count) workout" + (count == 1 ? "" : "s") + "/week"
        }
    }
}
