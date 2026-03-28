import Foundation

enum WorkoutSetProgressTone: Equatable {
    case accent
    case success
    case caution
}

struct WorkoutSetProgressReference: Equatable {
    let lastValue: String
    let aimValue: String
    let statusText: String?
    let statusTone: WorkoutSetProgressTone
    let canReusePrevious: Bool

    static func make(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        formatWeight: (Double) -> String = { WGJFormatters.decimalString($0) }
    ) -> WorkoutSetProgressReference? {
        guard let previous else { return nil }

        let lastValue = performanceText(
            weight: previous.weight,
            reps: previous.reps,
            unit: previous.unit,
            formatWeight: formatWeight
        )
        let aimValue = aimText(
            draft: draft,
            previous: previous,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            formatWeight: formatWeight
        )
        let status = statusPresentation(
            draft: draft,
            previous: previous,
            formatWeight: formatWeight
        )

        return WorkoutSetProgressReference(
            lastValue: lastValue,
            aimValue: aimValue,
            statusText: status?.text,
            statusTone: status?.tone ?? .accent,
            canReusePrevious: hasReusableValues(in: previous) && !matchesPrevious(draft: draft, previous: previous)
        )
    }

    private static func performanceText(
        weight: Double?,
        reps: Int?,
        unit: TemplateLoadUnit,
        formatWeight: (Double) -> String
    ) -> String {
        if unit == .bodyweight {
            if let reps {
                return "BW x \(reps)"
            }

            return "Bodyweight"
        }

        if let weight, let reps {
            return "\(formatWeight(weight)) \(unit.shortLabel) x \(reps)"
        }

        if let weight {
            return "\(formatWeight(weight)) \(unit.shortLabel)"
        }

        if let reps {
            return "\(reps) reps"
        }

        return "No log"
    }

    private static func aimText(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot,
        targetRepMin: Int?,
        targetRepMax: Int?,
        formatWeight: (Double) -> String
    ) -> String {
        let weightText = previous.weight.map { "\(formatWeight($0)) \(previous.unit.shortLabel)" }

        if draft.isWarmup {
            return "Match the ramp"
        }

        if previous.unit == .bodyweight {
            if let reps = previous.reps, let targetRepMax {
                if reps < targetRepMax {
                    return "Aim for \(reps + 1) reps"
                }

                return "Beat \(reps) reps"
            }

            if let reps = previous.reps {
                return "Aim for \(reps + 1) reps"
            }

            return "Match last set"
        }

        if let weightText, let reps = previous.reps {
            if let targetRepMin, let targetRepMax, targetRepMin <= targetRepMax {
                if reps < targetRepMin {
                    return "\(weightText) x \(targetRepMin)-\(targetRepMax)"
                }

                if reps < targetRepMax {
                    return "\(weightText) x \(reps + 1)"
                }

                return "Small jump above \(weightText)"
            }

            if let targetReps = draft.targetReps, reps < targetReps {
                return "\(weightText) x \(targetReps)"
            }

            return "\(weightText) x \(reps + 1)"
        }

        if let weightText {
            if let targetReps = draft.targetReps {
                return "\(weightText) x \(targetReps)"
            }

            if let targetRepMin, let targetRepMax, targetRepMin <= targetRepMax {
                return "\(weightText) x \(targetRepMin)-\(targetRepMax)"
            }

            return "Match \(weightText)"
        }

        if let reps = previous.reps {
            if let targetRepMax {
                let nextRepGoal = min(reps + 1, targetRepMax)
                return nextRepGoal > reps ? "Aim for \(nextRepGoal) reps" : "Own \(reps) reps again"
            }

            return "Aim for \(reps + 1) reps"
        }

        return "Fill the set"
    }

    private static func statusPresentation(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot,
        formatWeight: (Double) -> String
    ) -> (text: String, tone: WorkoutSetProgressTone)? {
        let hasCurrentWeight = draft.actualWeight != nil
        let hasCurrentReps = draft.actualReps != nil
        guard hasCurrentWeight || hasCurrentReps else { return nil }

        let unitsMatch = draft.actualLoadUnit == previous.unit
        let weightDelta = weightDelta(draft: draft, previous: previous, unitsMatch: unitsMatch)
        let repDelta = repDelta(draft: draft, previous: previous)

        if let delta = weightDelta {
            if delta > 0.01 {
                if let repDelta, repDelta > 0 {
                    return ("\(positiveWeightDeltaText(delta, unit: previous.unit, formatWeight: formatWeight)) and \(positiveRepDeltaText(repDelta)) vs last", .success)
                }

                if let repDelta, repDelta < 0 {
                    let repGap = abs(repDelta)
                    return ("Heavier, but \(repGap) rep\(repGap == 1 ? "" : "s") under last", .accent)
                }

                return ("\(positiveWeightDeltaText(delta, unit: previous.unit, formatWeight: formatWeight)) vs last", .success)
            }

            if delta < -0.01 {
                if let repDelta, repDelta > 0 {
                    return ("\(positiveRepDeltaText(repDelta)) at lighter load", .accent)
                }

                if let repDelta, repDelta < 0 {
                    let deficit = abs(repDelta)
                    return ("Lighter and \(deficit) rep\(deficit == 1 ? "" : "s") under last", .caution)
                }

                return ("Below last load", .caution)
            }
        }

        if let repDelta {
            if repDelta > 0 {
                return ("\(positiveRepDeltaText(repDelta)) vs last", .success)
            }

            if repDelta < 0 {
                let deficit = abs(repDelta)
                return ("\(deficit) rep\(deficit == 1 ? "" : "s") under last", .caution)
            }
        }

        if let delta = weightDelta {
            if abs(delta) <= 0.01, draft.actualReps == previous.reps {
                return ("Matched last session", .accent)
            }

            if abs(delta) <= 0.01 {
                return ("Matched last load", .accent)
            }
        }

        if draft.actualReps == previous.reps, draft.actualReps != nil {
            return ("Matched last reps", .accent)
        }

        return nil
    }

    private static func weightDelta(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot,
        unitsMatch: Bool
    ) -> Double? {
        guard unitsMatch, let currentWeight = draft.actualWeight, let previousWeight = previous.weight else {
            return nil
        }

        return currentWeight - previousWeight
    }

    private static func repDelta(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot
    ) -> Int? {
        guard let currentReps = draft.actualReps, let previousReps = previous.reps else {
            return nil
        }

        return currentReps - previousReps
    }

    private static func positiveWeightDeltaText(
        _ delta: Double,
        unit: TemplateLoadUnit,
        formatWeight: (Double) -> String
    ) -> String {
        "+\(formatWeight(delta)) \(unit.shortLabel)"
    }

    private static func positiveRepDeltaText(_ delta: Int) -> String {
        "+\(delta) rep\(delta == 1 ? "" : "s")"
    }

    private static func hasReusableValues(in previous: WorkoutPreviousSetSnapshot) -> Bool {
        previous.weight != nil || previous.reps != nil
    }

    private static func matchesPrevious(draft: WorkoutSessionSetDraft, previous: WorkoutPreviousSetSnapshot) -> Bool {
        let weightsMatch: Bool
        switch (draft.actualWeight, previous.weight) {
        case (nil, nil):
            weightsMatch = true
        case let (lhs?, rhs?):
            weightsMatch = abs(lhs - rhs) <= 0.01
        default:
            weightsMatch = false
        }

        return weightsMatch
            && draft.actualReps == previous.reps
            && draft.actualLoadUnit == previous.unit
    }
}
