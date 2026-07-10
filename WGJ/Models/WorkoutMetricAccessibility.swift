import Foundation

nonisolated struct WorkoutMetricAccessibilityDescriptor: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String?
}

nonisolated enum WorkoutMetricAccessibilityPolicy {
    static func field(
        exerciseName: String,
        setNumber: Int,
        dropStageNumber: Int?,
        metric: WorkoutMetricInputDraftBuffer.Metric,
        value: String?,
        unit: String?,
        isWarmup: Bool = false
    ) -> WorkoutMetricAccessibilityDescriptor {
        let trimmedExercise = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercise = trimmedExercise.isEmpty ? "Exercise" : trimmedExercise
        let setContext = isWarmup ? "warmup set \(setNumber)" : "working set \(setNumber)"
        let stageContext = dropStageNumber.map { ", drop stage \($0)" } ?? ""
        let metricName = metric == .weight ? "weight" : "reps"
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let spokenValue: String
        switch metric {
        case .weight:
            let spokenUnit = spokenWeightUnit(unit)
            if spokenUnit == "bodyweight" {
                spokenValue = trimmedValue.isEmpty ? "Bodyweight" : "\(trimmedValue) bodyweight"
            } else if trimmedValue.isEmpty {
                spokenValue = "No weight entered"
            } else if let spokenUnit {
                spokenValue = "\(trimmedValue) \(spokenUnit)"
            } else {
                spokenValue = trimmedValue
            }
        case .reps:
            spokenValue = trimmedValue.isEmpty ? "No reps entered" : "\(trimmedValue) reps"
        }

        return WorkoutMetricAccessibilityDescriptor(
            label: "\(exercise), \(setContext)\(stageContext), \(metricName)",
            value: spokenValue,
            hint: "Double tap to edit."
        )
    }

    static func warmupControl(
        exerciseName: String,
        setNumber: Int,
        isWarmup: Bool
    ) -> WorkoutMetricAccessibilityDescriptor {
        WorkoutMetricAccessibilityDescriptor(
            label: "\(exerciseName), set \(setNumber), set type",
            value: isWarmup ? "Warmup" : "Working set",
            hint: isWarmup ? "Double tap to mark as a working set." : "Double tap to mark as warmup."
        )
    }

    private static func spokenWeightUnit(_ unit: String?) -> String? {
        switch unit?.lowercased() {
        case "kg", "kilogram", "kilograms":
            return "kilograms"
        case "lb", "lbs", "pound", "pounds":
            return "pounds"
        case "bw", "bodyweight", "body weight":
            return "bodyweight"
        default:
            return unit
        }
    }
}
