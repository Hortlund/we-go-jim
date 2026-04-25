import Foundation

nonisolated struct WorkoutMetricInputDraftBuffer: Equatable, Sendable {
    enum Metric: Hashable, Sendable {
        case weight
        case reps
    }

    private var weightTextBySetID: [UUID: String] = [:]
    private var repsTextBySetID: [UUID: String] = [:]

    var isEmpty: Bool {
        weightTextBySetID.isEmpty && repsTextBySetID.isEmpty
    }

    mutating func stage(_ text: String, for setID: UUID, metric: Metric) {
        switch metric {
        case .weight:
            weightTextBySetID[setID] = text
        case .reps:
            repsTextBySetID[setID] = text
        }
    }

    func text(for setID: UUID, metric: Metric) -> String? {
        switch metric {
        case .weight:
            weightTextBySetID[setID]
        case .reps:
            repsTextBySetID[setID]
        }
    }

    mutating func clear(for setID: UUID, metric: Metric) {
        switch metric {
        case .weight:
            weightTextBySetID[setID] = nil
        case .reps:
            repsTextBySetID[setID] = nil
        }
    }

    mutating func prune(keeping validSetIDs: Set<UUID>) {
        weightTextBySetID = weightTextBySetID.filter { validSetIDs.contains($0.key) }
        repsTextBySetID = repsTextBySetID.filter { validSetIDs.contains($0.key) }
    }

    mutating func sync(setID: UUID, metric: Metric, draft: WorkoutSessionSetDraft) {
        switch metric {
        case .weight:
            weightTextBySetID[setID] = draft.actualWeight.map(WGJFormatters.decimalString) ?? ""
        case .reps:
            repsTextBySetID[setID] = draft.actualReps.map(String.init) ?? ""
        }
    }

    @discardableResult
    mutating func commit(
        setID: UUID,
        metric: Metric,
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        guard let index = drafts.firstIndex(where: { $0.id == setID }) else {
            clear(for: setID, metric: metric)
            return false
        }

        let changed: Bool
        switch metric {
        case .weight:
            guard let text = weightTextBySetID[setID] else { return false }
            changed = applyWeightText(
                text,
                to: &drafts[index],
                preferredLoadUnit: preferredLoadUnit,
                manualCompletionMode: manualCompletionMode
            )
        case .reps:
            guard let text = repsTextBySetID[setID] else { return false }
            changed = applyRepsText(
                text,
                to: &drafts[index],
                manualCompletionMode: manualCompletionMode
            )
        }

        if clearsText {
            clear(for: setID, metric: metric)
        }
        return changed
    }

    @discardableResult
    mutating func commitAll(
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        let setIDs = Set(weightTextBySetID.keys).union(repsTextBySetID.keys)
        var changed = false

        for setID in setIDs {
            changed = commit(
                setID: setID,
                metric: .weight,
                drafts: &drafts,
                preferredLoadUnit: preferredLoadUnit,
                manualCompletionMode: manualCompletionMode,
                clearsText: clearsText
            ) || changed
            changed = commit(
                setID: setID,
                metric: .reps,
                drafts: &drafts,
                preferredLoadUnit: preferredLoadUnit,
                manualCompletionMode: manualCompletionMode,
                clearsText: clearsText
            ) || changed
        }

        return changed
    }

    private func applyWeightText(
        _ text: String,
        to draft: inout WorkoutSessionSetDraft,
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool
    ) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedWeight: Double?

        if normalized.isEmpty {
            updatedWeight = nil
        } else if let parsed = Self.parseLocalizedDecimal(normalized) {
            updatedWeight = max(0, parsed)
        } else {
            updatedWeight = draft.actualWeight
        }

        var changed = false
        if draft.actualWeight != updatedWeight {
            draft.actualWeight = updatedWeight
            changed = true
        }

        if let updatedWeight, updatedWeight > 0 {
            if draft.actualLoadUnit == .bodyweight {
                draft.actualLoadUnit = resolvedWeightedLoadUnit(for: draft, preferredLoadUnit: preferredLoadUnit)
                changed = true
            }
        } else if updatedWeight == nil,
                  draft.targetLoadUnit == .bodyweight,
                  draft.actualLoadUnit != .bodyweight
        {
            draft.actualLoadUnit = .bodyweight
            changed = true
        }

        if !manualCompletionMode {
            let isCompleted = draft.actualReps != nil || draft.actualWeight != nil
            if draft.isCompleted != isCompleted {
                draft.isCompleted = isCompleted
                changed = true
            }
        }

        return changed
    }

    private func applyRepsText(
        _ text: String,
        to draft: inout WorkoutSessionSetDraft,
        manualCompletionMode: Bool
    ) -> Bool {
        let cleaned = text.filter(\.isNumber)
        let updatedReps = cleaned.isEmpty ? nil : Int(cleaned)
        var changed = false

        if draft.actualReps != updatedReps {
            draft.actualReps = updatedReps
            changed = true
        }

        if !manualCompletionMode {
            let isCompleted = draft.actualReps != nil || draft.actualWeight != nil
            if draft.isCompleted != isCompleted {
                draft.isCompleted = isCompleted
                changed = true
            }
        }

        return changed
    }

    private func resolvedWeightedLoadUnit(
        for draft: WorkoutSessionSetDraft,
        preferredLoadUnit: TemplateLoadUnit
    ) -> TemplateLoadUnit {
        switch draft.targetLoadUnit {
        case .kg, .lb:
            return draft.targetLoadUnit
        case .bodyweight:
            return preferredLoadUnit
        }
    }

    private static func parseLocalizedDecimal(_ text: String) -> Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text
            .replacingOccurrences(of: ",", with: separator)
            .replacingOccurrences(of: ".", with: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        if let parsed = Double(normalized.replacingOccurrences(of: separator, with: ".")) {
            return parsed
        }

        guard normalized.hasSuffix(separator) else { return nil }
        let trimmed = String(normalized.dropLast(separator.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed.replacingOccurrences(of: separator, with: "."))
    }
}
