import Foundation

nonisolated enum WorkoutPerformanceMath {
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    static func normalizedLoadInKilograms(
        _ value: Double,
        unit: TemplateLoadUnit
    ) -> Double {
        switch unit {
        case .kg:
            return value
        case .lb:
            return value * 0.45359237
        case .bodyweight:
            return value
        }
    }

    static func weightedVolumeInKilograms(
        weight: Double,
        reps: Int,
        unit: TemplateLoadUnit
    ) -> Double {
        guard unit != .bodyweight else { return 0 }
        return normalizedLoadInKilograms(weight, unit: unit) * Double(max(0, reps))
    }
}
