import Foundation

nonisolated struct WorkoutMetricAccessibilityDescriptor: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String?
}

nonisolated enum WorkoutMetricAccessibilityPolicy {
    enum CardioAction: Equatable, Sendable {
        case start
        case pause
        case resume
        case finish
        case editResult
    }

    enum CardioMetricSemantic: Equatable, Sendable {
        case plain
        case distance(WorkoutDistanceUnit)
        case speed(WorkoutDistanceUnit)
        case pace(WorkoutDistanceUnit)
        case rowingPace
        case incline
    }

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

    static func cardioAction(_ action: CardioAction, activityName: String) -> String {
        CardioLocalizedCopy.actionAccessibilityLabel(action.localizedCopyAction, activityName: activityName)
    }

    /// Formats semantic cardio units for unambiguous, localized VoiceOver speech.
    static func cardioMetricValue(
        _ value: String,
        semantic: CardioMetricSemantic
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch semantic {
        case .plain:
            return trimmed
        case .distance(.kilometers):
            return String(localized: "\(trimmed) kilometers")
        case .distance(.miles):
            return String(localized: "\(trimmed) miles")
        case .distance(.meters):
            return String(localized: "\(trimmed) meters")
        case .speed(.kilometers):
            return String(localized: "\(trimmed) kilometers per hour")
        case .speed(.miles):
            return String(localized: "\(trimmed) miles per hour")
        case .speed(.meters):
            return String(localized: "\(trimmed) meters per hour")
        case .pace(.kilometers):
            return String(localized: "\(trimmed) per kilometer")
        case .pace(.miles):
            return String(localized: "\(trimmed) per mile")
        case .pace(.meters):
            return String(localized: "\(trimmed) per meter")
        case .rowingPace:
            return String(localized: "\(trimmed) per 500 meters")
        case .incline:
            return String(localized: "\(trimmed) percent incline")
        }
    }

    static func cardioMetric(
        label: String,
        value: String,
        semantic: CardioMetricSemantic
    ) -> String {
        String(localized: "\(label), \(cardioMetricValue(value, semantic: semantic))")
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

private extension WorkoutMetricAccessibilityPolicy.CardioAction {
    nonisolated var localizedCopyAction: CardioLocalizedCopy.Action {
        switch self {
        case .start: return .start
        case .pause: return .pause
        case .resume: return .resume
        case .finish: return .finish
        case .editResult: return .editResult
        }
    }
}
