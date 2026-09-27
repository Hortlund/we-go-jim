import Foundation

/// An actual logged set, rather than a load taken from another set in the workout.
nonisolated struct ExerciseSetPerformance: Codable, Hashable, Sendable {
    let reps: Int
    let kilograms: Double // Zero means no external load.

    func loadLabel(unit: TemplateLoadUnit, addedWeight: Bool, assistance: Bool = false) -> String {
        if assistance { return kilograms > 0 ? "\(WGJFormatters.decimalString(unit == .lb ? kilograms / 0.45359237 : kilograms)) \(unit == .lb ? "lb" : "kg") assistance" : "No assistance" }
        guard kilograms > 0 else { return addedWeight ? "Bodyweight" : "No added weight" }
        let value = unit == .lb ? kilograms / 0.45359237 : kilograms
        let suffix = unit == .lb ? "lb" : "kg"
        return "\(WGJFormatters.decimalString(value)) \(suffix)"
    }

    func label(unit: TemplateLoadUnit, addedWeight: Bool, assistance: Bool = false) -> String {
        let repsText = "\(reps) \(reps == 1 ? "rep" : "reps")"
        let loadText = loadLabel(unit: unit, addedWeight: addedWeight, assistance: assistance)
        if assistance { return "\(repsText) · \(loadText)" }
        guard kilograms > 0 else { return repsText }
        return "\(loadText) × \(repsText)"
    }

    func hasSameLoad(as other: Self) -> Bool {
        abs(kilograms - other.kilograms) < 0.01
    }
}

/// Derived from completed working sets; persisted in the rebuildable history payload.
nonisolated struct ExerciseLoadContext: Codable, Hashable, Sendable {
    let bestRepsSet: ExerciseSetPerformance
    let heaviestSet: ExerciseSetPerformance
    let strongestSet: ExerciseSetPerformance?
    let minimumKilograms: Double
    let maximumKilograms: Double
    var leastAssistanceSet: ExerciseSetPerformance? = nil
    var bestAssistedRepsSet: ExerciseSetPerformance? = nil

    func set(for metric: ExerciseProgressMetric) -> ExerciseSetPerformance? {
        switch metric {
        case .bestSetReps: bestRepsSet
        case .heaviestWeight: heaviestSet
        case .estimatedOneRepMax: strongestSet
        default: nil
        }
    }

    func assistanceRangeLabel(unit: TemplateLoadUnit) -> String {
        guard let leastAssistanceSet else { return "Assistance not recorded" }
        let low = leastAssistanceSet.loadLabel(unit: unit, addedWeight: false, assistance: true)
        let high = ExerciseSetPerformance(reps: 0, kilograms: maximumKilograms)
            .loadLabel(unit: unit, addedWeight: false, assistance: true)
        return abs(leastAssistanceSet.kilograms - maximumKilograms) < 0.01 ? low : "\(low) – \(high)"
    }

    func rangeLabel(unit: TemplateLoadUnit, addedWeight: Bool) -> String {
        let low = ExerciseSetPerformance(reps: 0, kilograms: minimumKilograms).loadLabel(unit: unit, addedWeight: addedWeight)
        let high = ExerciseSetPerformance(reps: 0, kilograms: maximumKilograms).loadLabel(unit: unit, addedWeight: addedWeight)
        return minimumKilograms == maximumKilograms ? low : "\(low) – \(high)"
    }
}

nonisolated enum ExerciseLoadKind: String, CaseIterable, Codable, Sendable {
    case resistance, addedWeight, assistance

    var title: String {
        switch self {
        case .resistance: "Resistance"
        case .addedWeight: "Added weight"
        case .assistance: "Assistance"
        }
    }
    var explanation: String {
        switch self {
        case .resistance: "Log the weight you lift."
        case .addedWeight: "Log extra weight only. Your bodyweight is not included."
        case .assistance: "Log the machine assistance. Less assistance is harder; compare on the same machine."
        }
    }
}

nonisolated enum ExerciseLoadSemantics {
    static func kind(equipment: String, exerciseName: String, override: String? = nil) -> ExerciseLoadKind {
        if let override, let kind = ExerciseLoadKind(rawValue: override) { return kind }
        if containsAssistedWord(equipment + " " + exerciseName) { return .assistance }
        return usesAddedWeight(equipment: equipment, exerciseName: exerciseName) ? .addedWeight : .resistance
    }

    /// Equipment can contain several comma-separated items. Movement names only
    /// disambiguate bodyweight exercises whose equipment is also used by ordinary lifts.
    /// Do not infer from broad words such as "pull", "press", "bench", or "machine".
    static func usesAddedWeight(equipment: String, exerciseName: String = "") -> Bool {
        let equipment = normalized(equipment)
        let name = normalized(exerciseName)
        guard !containsAssistedWord(equipment), !equipment.contains("machine"),
              !containsAssistedWord(name) else { return false }

        let items = Set(equipment.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let bodyweightEquipment: Set<String> = [
            "bodyweight", "body weight", "pull up bar", "dip station", "dip belt",
            "rings", "gymnastic rings", "ab wheel", "hyperextension bench"
        ]
        return !items.isDisjoint(with: bodyweightEquipment) || bodyweightMovements.contains(name)
    }

    private static let bodyweightMovements: Set<String> = [
        "pull up", "pull ups", "weighted pull up", "neutral grip pull up", "chin up", "chin ups",
        "dip", "dips", "parallel bar dips", "weighted dip", "weighted dips", "chest dip", "bench dip", "bench dips",
        "push up", "push ups", "weighted push up", "ring push up", "close grip push up", "feet elevated push up",
        "inverted row", "ring row", "weighted crunch", "decline sit up", "weighted plank", "copenhagen plank"
    ]

    private static func containsAssistedWord(_ value: String) -> Bool {
        normalized(value).split(whereSeparator: { !$0.isLetter }).contains("assisted")
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "‑", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension TrainingGuidanceCatalogSnapshot {
    nonisolated var loadKind: ExerciseLoadKind {
        ExerciseLoadSemantics.kind(equipment: equipmentSummary, exerciseName: exerciseName, override: loadTrackingRaw)
    }
    nonisolated var usesAssistance: Bool { loadKind == .assistance }
}

extension ExerciseCatalogItem {
    nonisolated var loadKind: ExerciseLoadKind {
        ExerciseLoadSemantics.kind(equipment: equipmentSummary, exerciseName: displayName, override: loadTrackingRaw)
    }
}

extension TrainingGuidanceCatalogSnapshot {
    nonisolated var usesAddedWeight: Bool {
        loadKind == .addedWeight
    }
}

/// A new, easier assistance level establishes a baseline rather than earning a rep PR.
nonisolated struct AssistanceRecordTracker {
    var leastKilograms = Double.infinity
    var repsByLoad: [Int: Int] = [:]

    mutating func consume(kilograms: Double, reps: Int) -> [WorkoutPersonalRecordKind] {
        let key = Int((kilograms * 100).rounded())
        var kinds: [WorkoutPersonalRecordKind] = []
        if kilograms < leastKilograms - 0.01 { kinds.append(.assistance); leastKilograms = kilograms }
        if let prior = repsByLoad[key], reps > prior { kinds.append(.assistedReps) }
        repsByLoad[key] = max(repsByLoad[key, default: 0], reps)
        return kinds
    }
}
