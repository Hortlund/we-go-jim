import Foundation

nonisolated struct WorkoutMetricInputDraftBuffer: Equatable, Sendable {
    enum Metric: Hashable, Sendable {
        case weight
        case reps
    }

    private var weightTextBySetID: [UUID: String] = [:]
    private var repsTextBySetID: [UUID: String] = [:]
    private var weightTextByDropStageID: [UUID: String] = [:]
    private var repsTextByDropStageID: [UUID: String] = [:]

    var isEmpty: Bool {
        weightTextBySetID.isEmpty
            && repsTextBySetID.isEmpty
            && weightTextByDropStageID.isEmpty
            && repsTextByDropStageID.isEmpty
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

    mutating func stage(_ text: String, forDropStage stageID: UUID, metric: Metric) {
        switch metric {
        case .weight:
            weightTextByDropStageID[stageID] = text
        case .reps:
            repsTextByDropStageID[stageID] = text
        }
    }

    func text(forDropStage stageID: UUID, metric: Metric) -> String? {
        switch metric {
        case .weight:
            weightTextByDropStageID[stageID]
        case .reps:
            repsTextByDropStageID[stageID]
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

    mutating func clear(forDropStage stageID: UUID, metric: Metric) {
        switch metric {
        case .weight:
            weightTextByDropStageID[stageID] = nil
        case .reps:
            repsTextByDropStageID[stageID] = nil
        }
    }

    mutating func prune(keeping validSetIDs: Set<UUID>) {
        weightTextBySetID = weightTextBySetID.filter { validSetIDs.contains($0.key) }
        repsTextBySetID = repsTextBySetID.filter { validSetIDs.contains($0.key) }
    }

    mutating func pruneDropStages(keeping validStageIDs: Set<UUID>) {
        weightTextByDropStageID = weightTextByDropStageID.filter { validStageIDs.contains($0.key) }
        repsTextByDropStageID = repsTextByDropStageID.filter { validStageIDs.contains($0.key) }
    }

    mutating func sync(setID: UUID, metric: Metric, draft: WorkoutSessionSetDraft) {
        switch metric {
        case .weight:
            weightTextBySetID[setID] = draft.actualWeight.map(WGJFormatters.decimalString) ?? ""
        case .reps:
            repsTextBySetID[setID] = draft.actualReps.map(String.init) ?? ""
        }
    }

    mutating func sync(dropStageID: UUID, metric: Metric, draft: WorkoutSessionDropStageDraft) {
        switch metric {
        case .weight:
            weightTextByDropStageID[dropStageID] = draft.actualWeight.map(WGJFormatters.decimalString) ?? ""
        case .reps:
            repsTextByDropStageID[dropStageID] = draft.actualReps.map(String.init) ?? ""
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

    @discardableResult
    mutating func commitDropStage(
        stageID: UUID,
        metric: Metric,
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        guard let location = dropStageLocation(stageID: stageID, drafts: drafts) else {
            clear(forDropStage: stageID, metric: metric)
            return false
        }

        let changed: Bool
        switch metric {
        case .weight:
            guard let text = weightTextByDropStageID[stageID] else { return false }
            changed = applyWeightText(
                text,
                to: &drafts[location.setIndex].dropStages[location.stageIndex],
                preferredLoadUnit: preferredLoadUnit,
                manualCompletionMode: manualCompletionMode
            )
        case .reps:
            guard let text = repsTextByDropStageID[stageID] else { return false }
            changed = applyRepsText(
                text,
                to: &drafts[location.setIndex].dropStages[location.stageIndex],
                manualCompletionMode: manualCompletionMode
            )
        }

        if clearsText {
            clear(forDropStage: stageID, metric: metric)
        }
        return changed
    }

    @discardableResult
    mutating func commitAllDropStages(
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        let stageIDs = Set(weightTextByDropStageID.keys).union(repsTextByDropStageID.keys)
        var changed = false

        for stageID in stageIDs {
            changed = commitDropStage(
                stageID: stageID,
                metric: .weight,
                drafts: &drafts,
                preferredLoadUnit: preferredLoadUnit,
                manualCompletionMode: manualCompletionMode,
                clearsText: clearsText
            ) || changed
            changed = commitDropStage(
                stageID: stageID,
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

    private func applyWeightText(
        _ text: String,
        to draft: inout WorkoutSessionDropStageDraft,
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
        to draft: inout WorkoutSessionDropStageDraft,
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

    private func resolvedWeightedLoadUnit(
        for draft: WorkoutSessionDropStageDraft,
        preferredLoadUnit: TemplateLoadUnit
    ) -> TemplateLoadUnit {
        switch draft.targetLoadUnit {
        case .kg, .lb:
            return draft.targetLoadUnit
        case .bodyweight:
            return preferredLoadUnit
        }
    }

    private func dropStageLocation(
        stageID: UUID,
        drafts: [WorkoutSessionSetDraft]
    ) -> (setIndex: Int, stageIndex: Int)? {
        for (setIndex, draft) in drafts.enumerated() {
            if let stageIndex = draft.dropStages.firstIndex(where: { $0.id == stageID }) {
                return (setIndex, stageIndex)
            }
        }

        return nil
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

@MainActor
final class WorkoutMetricInputDraftStore {
    private var buffer = WorkoutMetricInputDraftBuffer()

    var isEmpty: Bool {
        buffer.isEmpty
    }

    func stage(_ text: String, for setID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) {
        buffer.stage(text, for: setID, metric: metric)
    }

    func text(for setID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) -> String? {
        buffer.text(for: setID, metric: metric)
    }

    func stage(_ text: String, forDropStage stageID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) {
        buffer.stage(text, forDropStage: stageID, metric: metric)
    }

    func text(forDropStage stageID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) -> String? {
        buffer.text(forDropStage: stageID, metric: metric)
    }

    func clear(for setID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) {
        buffer.clear(for: setID, metric: metric)
    }

    func clear(forDropStage stageID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric) {
        buffer.clear(forDropStage: stageID, metric: metric)
    }

    func prune(keeping validSetIDs: Set<UUID>) {
        buffer.prune(keeping: validSetIDs)
    }

    func pruneDropStages(keeping validStageIDs: Set<UUID>) {
        buffer.pruneDropStages(keeping: validStageIDs)
    }

    func sync(setID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric, draft: WorkoutSessionSetDraft) {
        buffer.sync(setID: setID, metric: metric, draft: draft)
    }

    func sync(dropStageID: UUID, metric: WorkoutMetricInputDraftBuffer.Metric, draft: WorkoutSessionDropStageDraft) {
        buffer.sync(dropStageID: dropStageID, metric: metric, draft: draft)
    }

    @discardableResult
    func commit(
        setID: UUID,
        metric: WorkoutMetricInputDraftBuffer.Metric,
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        buffer.commit(
            setID: setID,
            metric: metric,
            drafts: &drafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
    }

    @discardableResult
    func commitAll(
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        buffer.commitAll(
            drafts: &drafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
    }

    @discardableResult
    func commitDropStage(
        stageID: UUID,
        metric: WorkoutMetricInputDraftBuffer.Metric,
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        buffer.commitDropStage(
            stageID: stageID,
            metric: metric,
            drafts: &drafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
    }

    @discardableResult
    func commitAllDropStages(
        drafts: inout [WorkoutSessionSetDraft],
        preferredLoadUnit: TemplateLoadUnit,
        manualCompletionMode: Bool,
        clearsText: Bool = true
    ) -> Bool {
        buffer.commitAllDropStages(
            drafts: &drafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
    }
}
