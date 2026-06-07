import Foundation
import SwiftData

nonisolated struct WorkoutTemplateSyncPreview: Equatable, Identifiable, Sendable {
    let templateID: UUID
    let templateName: String
    let editedWorkoutNotes: WorkoutTemplateSyncEditedWorkoutNotes?
    let addedCardioBlocks: [WorkoutTemplateSyncAddedCardioBlock]
    let removedCardioBlocks: [WorkoutTemplateSyncRemovedCardioBlock]
    let editedCardioBlocks: [WorkoutTemplateSyncEditedCardioBlock]
    let addedExercises: [WorkoutTemplateSyncAddedExercise]
    let removedExercises: [WorkoutTemplateSyncRemovedExercise]
    let reorderedExercises: [WorkoutTemplateSyncReorderedExercise]
    let editedExercises: [WorkoutTemplateSyncEditedExercise]
    let mutation: WorkoutTemplateSyncMutation

    var id: UUID { templateID }

    var totalChangeCount: Int {
        (editedWorkoutNotes == nil ? 0 : 1)
            + addedCardioBlocks.count
            + removedCardioBlocks.count
            + editedCardioBlocks.count
            + addedExercises.count
            + removedExercises.count
            + reorderedExercises.count
            + editedExercises.count
    }

    var summary: String {
        var parts: [String] = []

        if editedWorkoutNotes != nil {
            parts.append("updated workout notes")
        }

        if !addedCardioBlocks.isEmpty {
            parts.append(countText(addedCardioBlocks.count, singular: "added cardio block"))
        }

        if !removedCardioBlocks.isEmpty {
            parts.append(countText(removedCardioBlocks.count, singular: "removed cardio block"))
        }

        if !editedCardioBlocks.isEmpty {
            parts.append(countText(editedCardioBlocks.count, singular: "edited cardio block"))
        }

        if !addedExercises.isEmpty {
            parts.append(countText(addedExercises.count, singular: "added exercise"))
        }

        if !removedExercises.isEmpty {
            parts.append(countText(removedExercises.count, singular: "removed exercise"))
        }

        if !reorderedExercises.isEmpty {
            parts.append(countText(reorderedExercises.count, singular: "reordered exercise"))
        }

        if !editedExercises.isEmpty {
            parts.append(countText(editedExercises.count, singular: "edited exercise"))
        }

        return parts.isEmpty ? "No reusable template changes" : parts.joined(separator: " • ")
    }

    private func countText(_ count: Int, singular: String) -> String {
        "\(count) \(singular)" + (count == 1 ? "" : "s")
    }
}

nonisolated struct WorkoutTemplateSyncEditedWorkoutNotes: Equatable, Sendable {
    let changes: [String]
}

nonisolated struct WorkoutTemplateSyncAddedCardioBlock: Identifiable, Equatable, Sendable {
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let summary: String

    var id: String { phase.rawValue }
}

nonisolated struct WorkoutTemplateSyncRemovedCardioBlock: Identifiable, Equatable, Sendable {
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let summary: String

    var id: String { phase.rawValue }
}

nonisolated struct WorkoutTemplateSyncEditedCardioBlock: Identifiable, Equatable, Sendable {
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let changes: [String]

    var id: String { phase.rawValue }
}

nonisolated struct WorkoutTemplateSyncAddedExercise: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let summary: String

    var id: String { catalogExerciseUUID }
}

nonisolated struct WorkoutTemplateSyncRemovedExercise: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let summary: String

    var id: String { catalogExerciseUUID }
}

nonisolated struct WorkoutTemplateSyncReorderedExercise: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let fromPosition: Int
    let toPosition: Int

    var id: String { catalogExerciseUUID }
}

nonisolated struct WorkoutTemplateSyncEditedExercise: Identifiable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let changes: [String]

    var id: String { catalogExerciseUUID }
}

nonisolated struct WorkoutTemplateSyncMutation: Equatable, Sendable {
    let templateNotes: String
    let cardioBlocks: [WorkoutTemplateSyncCardioMutation]
    let exercises: [WorkoutTemplateSyncExerciseMutation]
}

nonisolated struct WorkoutTemplateSyncCardioMutation: Equatable, Sendable {
    let phase: WorkoutCardioPhase
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetDurationSeconds: Int
}

nonisolated struct WorkoutTemplateSyncExerciseMutation: Equatable, Sendable {
    let templateExerciseID: UUID?
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let setDrafts: [TemplateExerciseSetDraft]
    let components: [TemplateExerciseComponentDraft]
    let superset: ExerciseSupersetMembershipDraft?

    init(
        templateExerciseID: UUID? = nil,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        setDrafts: [TemplateExerciseSetDraft],
        components: [TemplateExerciseComponentDraft] = [],
        superset: ExerciseSupersetMembershipDraft? = nil
    ) {
        self.templateExerciseID = templateExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = restSeconds
        self.setDrafts = setDrafts
        self.components = components
        self.superset = superset
    }
}

nonisolated final class WorkoutTemplateSyncService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func previewTemplateUpdate(forSessionID sessionID: UUID) throws -> WorkoutTemplateSyncPreview? {
        guard let session = try workoutSession(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        guard let templateID = session.templateID else {
            return nil
        }

        guard let template = try workoutTemplate(id: templateID) else {
            return nil
        }

        return WorkoutTemplateSyncPreviewBuilder.buildPreview(template: template, session: session)
    }

    func applyTemplateUpdate(_ preview: WorkoutTemplateSyncPreview) throws {
        let repository = TemplateRepository(modelContext: modelContext)
        try repository.applyWorkoutTemplateSync(
            templateID: preview.templateID,
            templateNotes: preview.mutation.templateNotes,
            exercises: preview.mutation.exercises,
            cardioBlocks: preview.mutation.cardioBlocks
        )
    }

    private func workoutSession(id: UUID) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { session in
            session.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func workoutTemplate(id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { template in
            template.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func makeMutation(
        from sessionExercise: WorkoutSessionExercise,
        templateExercise: TemplateExercise?
    ) -> WorkoutTemplateSyncExerciseMutation {
        let componentDrafts = templateExercise.map(templateComponentDrafts(for:)) ?? [
            TemplateExerciseComponentDraft(
                catalogExerciseUUID: sessionExercise.catalogExerciseUUID,
                exerciseNameSnapshot: sessionExercise.exerciseNameSnapshot,
                categorySnapshot: sessionExercise.categorySnapshot,
                muscleSummarySnapshot: sessionExercise.muscleSummarySnapshot
            ),
        ]
        let primaryComponent = componentDrafts.first
        return WorkoutTemplateSyncExerciseMutation(
            templateExerciseID: sessionExercise.templateExerciseID,
            catalogExerciseUUID: primaryComponent?.catalogExerciseUUID ?? sessionExercise.catalogExerciseUUID,
            exerciseNameSnapshot: primaryComponent?.exerciseNameSnapshot ?? sessionExercise.exerciseNameSnapshot,
            categorySnapshot: primaryComponent?.categorySnapshot ?? sessionExercise.categorySnapshot,
            muscleSummarySnapshot: primaryComponent?.muscleSummarySnapshot ?? sessionExercise.muscleSummarySnapshot,
            notes: sessionExercise.notes,
            targetRepMin: sessionExercise.targetRepMin,
            targetRepMax: sessionExercise.targetRepMax,
            restSeconds: normalizedRest(sessionExercise.restSeconds),
            setDrafts: mappedSetDrafts(from: sessionExercise),
            components: componentDrafts
        )
    }

    private func makeMutation(from cardioBlock: WorkoutSessionCardioBlock) -> WorkoutTemplateSyncCardioMutation {
        WorkoutTemplateSyncCardioMutation(
            phase: cardioBlock.phase,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            targetDurationSeconds: normalizedCardioDuration(cardioBlock.targetDurationSeconds)
        )
    }

    private func mappedSetDrafts(from sessionExercise: WorkoutSessionExercise) -> [TemplateExerciseSetDraft] {
        orderedSets(for: sessionExercise).map { sessionSet in
            TemplateExerciseSetDraft(
                targetReps: sessionSet.targetReps,
                targetWeight: sessionSet.targetWeight,
                loadUnit: sessionSet.targetLoadUnit,
                restSeconds: normalizedRest(sessionExercise.restSeconds),
                isWarmup: sessionSet.isWarmup,
                isLocked: sessionSet.isLocked
            )
        }
    }

    private func templateComponentDrafts(for templateExercise: TemplateExercise) -> [TemplateExerciseComponentDraft] {
        let orderedComponents = (templateExercise.components ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(TemplateExerciseComponentDraft.init(model:))
        if !orderedComponents.isEmpty {
            return orderedComponents
        }

        guard !templateExercise.catalogExerciseUUID.isEmpty else {
            return []
        }

        return [
            TemplateExerciseComponentDraft(
                catalogExerciseUUID: templateExercise.catalogExerciseUUID,
                exerciseNameSnapshot: templateExercise.exerciseNameSnapshot,
                categorySnapshot: templateExercise.categorySnapshot,
                muscleSummarySnapshot: templateExercise.muscleSummarySnapshot
            ),
        ]
    }

    private func matchedTemplateExercise(
        for sessionExercise: WorkoutSessionExercise,
        templateExercisesByID: [UUID: TemplateExercise],
        templateExercisesByUUID: [String: TemplateExercise]
    ) -> TemplateExercise? {
        if let templateExerciseID = sessionExercise.templateExerciseID,
           let matchedByID = templateExercisesByID[templateExerciseID] {
            return matchedByID
        }

        return templateExercisesByUUID[sessionExercise.catalogExerciseUUID]
    }

    private func syncIdentityKey(
        templateExerciseID: UUID?,
        catalogExerciseUUID: String
    ) -> String {
        if let templateExerciseID {
            return "slot:\(templateExerciseID.uuidString.lowercased())"
        }
        return "exercise:\(catalogExerciseUUID.lowercased())"
    }

    private func syncIdentityKey(for sessionExercise: WorkoutSessionExercise) -> String {
        syncIdentityKey(
            templateExerciseID: sessionExercise.templateExerciseID,
            catalogExerciseUUID: sessionExercise.catalogExerciseUUID
        )
    }

    private func editedChangeSummaries(
        templateExercise: TemplateExercise,
        sessionExercise: WorkoutSessionExercise
    ) -> [String] {
        var changes: [String] = []
        let normalizedSessionRest = normalizedRest(sessionExercise.restSeconds)

        if templateExercise.targetRepMin != sessionExercise.targetRepMin
            || templateExercise.targetRepMax != sessionExercise.targetRepMax {
            changes.append(
                "Rep range \(repRangeText(min: templateExercise.targetRepMin, max: templateExercise.targetRepMax)) -> \(repRangeText(min: sessionExercise.targetRepMin, max: sessionExercise.targetRepMax))"
            )
        }

        if templateExercise.restSeconds != normalizedSessionRest {
            changes.append("Rest \(formattedRest(templateExercise.restSeconds)) -> \(formattedRest(normalizedSessionRest))")
        }

        let normalizedTemplateNotes = normalizedExerciseNotes(templateExercise.notes)
        let normalizedSessionNotes = normalizedExerciseNotes(sessionExercise.notes)
        if normalizedTemplateNotes != normalizedSessionNotes {
            switch (normalizedTemplateNotes.isEmpty, normalizedSessionNotes.isEmpty) {
            case (true, false):
                changes.append("Notes added")
            case (false, true):
                changes.append("Notes removed")
            case (false, false):
                changes.append("Notes updated")
            case (true, true):
                break
            }
        }

        let templateSetSnapshots = orderedSets(for: templateExercise).map(TemplateOwnedSetSnapshot.init(templateSet:))
        let sessionSetSnapshots = orderedSets(for: sessionExercise).map(TemplateOwnedSetSnapshot.init(sessionSet:))

        if templateSetSnapshots.count != sessionSetSnapshots.count {
            changes.append("Set count \(templateSetSnapshots.count) -> \(sessionSetSnapshots.count)")
        } else {
            let templateTargetSequence = templateSetSnapshots.map(\.targetIdentity)
            let sessionTargetSequence = sessionSetSnapshots.map(\.targetIdentity)
            if templateTargetSequence != sessionTargetSequence {
                changes.append("Set plan changed")
            }
        }

        if templateSetSnapshots.map(\.isWarmup) != sessionSetSnapshots.map(\.isWarmup) {
            changes.append("Warmup assignments changed")
        }

        if templateSetSnapshots.map(\.isLocked) != sessionSetSnapshots.map(\.isLocked) {
            changes.append("Locked sets changed")
        }

        return changes
    }

    private func editedWorkoutNotesChange(
        templateNotes: String,
        sessionNotes: String
    ) -> WorkoutTemplateSyncEditedWorkoutNotes? {
        let normalizedTemplate = normalizedWorkoutNotes(templateNotes)
        let normalizedSession = normalizedWorkoutNotes(sessionNotes)
        guard normalizedTemplate != normalizedSession else {
            return nil
        }

        var changes: [String] = []
        switch (normalizedTemplate.isEmpty, normalizedSession.isEmpty) {
        case (true, false):
            changes.append("Notes added")
        case (false, true):
            changes.append("Notes removed")
        case (false, false):
            changes.append("Notes updated")
        case (true, true):
            break
        }

        if normalizedSession.isEmpty {
            changes.append("The template workout note will be cleared.")
        } else {
            changes.append(normalizedSession)
        }

        return WorkoutTemplateSyncEditedWorkoutNotes(changes: changes)
    }

    private func editedCardioChangeSummaries(
        templateCardioBlock: TemplateCardioBlock,
        sessionCardioBlock: WorkoutSessionCardioBlock
    ) -> [String] {
        var changes: [String] = []

        if templateCardioBlock.catalogExerciseUUID != sessionCardioBlock.catalogExerciseUUID {
            changes.append(
                "Exercise \(templateCardioBlock.exerciseNameSnapshot) -> \(sessionCardioBlock.exerciseNameSnapshot)"
            )
        }

        let normalizedDuration = normalizedCardioDuration(sessionCardioBlock.targetDurationSeconds)
        if templateCardioBlock.targetDurationSeconds != normalizedDuration {
            changes.append(
                "Duration \(formattedDuration(templateCardioBlock.targetDurationSeconds)) -> \(formattedDuration(normalizedDuration))"
            )
        }

        return changes
    }

    private func reorderedExercisePreviews(
        templateExercises: [TemplateExercise],
        sessionExercises: [WorkoutSessionExercise]
    ) -> [WorkoutTemplateSyncReorderedExercise] {
        let sharedTemplateOrder = templateExercises
            .map { syncIdentityKey(templateExerciseID: $0.id, catalogExerciseUUID: $0.catalogExerciseUUID) }
            .filter { templateKey in
                sessionExercises.contains { syncIdentityKey(for: $0) == templateKey }
            }
        let sharedSessionOrder = sessionExercises
            .map(syncIdentityKey(for:))
            .filter { sessionKey in
                templateExercises.contains {
                    syncIdentityKey(templateExerciseID: $0.id, catalogExerciseUUID: $0.catalogExerciseUUID) == sessionKey
                }
            }

        guard sharedTemplateOrder != sharedSessionOrder else {
            return []
        }

        let sessionIndexByKey = Dictionary(
            sharedSessionOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return sharedTemplateOrder.enumerated().compactMap { index, identityKey in
            guard let destinationIndex = sessionIndexByKey[identityKey], destinationIndex != index else {
                return nil
            }

            let matchedTemplateExercise = templateExercises.first {
                syncIdentityKey(templateExerciseID: $0.id, catalogExerciseUUID: $0.catalogExerciseUUID) == identityKey
            }
            let exerciseName = matchedTemplateExercise?.exerciseNameSnapshot ?? identityKey
            return WorkoutTemplateSyncReorderedExercise(
                catalogExerciseUUID: matchedTemplateExercise?.catalogExerciseUUID ?? identityKey,
                exerciseName: exerciseName,
                fromPosition: index + 1,
                toPosition: destinationIndex + 1
            )
        }
    }

    private func exerciseSummary(
        setCount: Int,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int
    ) -> String {
        [
            "\(setCount) set" + (setCount == 1 ? "" : "s"),
            repRangeText(min: targetRepMin, max: targetRepMax),
            "Rest \(formattedRest(normalizedRest(restSeconds)))",
        ]
        .joined(separator: " • ")
    }

    private func cardioSummary(for cardioBlock: TemplateCardioBlock) -> String {
        [
            cardioBlock.phase.shortTitle,
            formattedDuration(cardioBlock.targetDurationSeconds),
        ]
        .joined(separator: " • ")
    }

    private func cardioSummary(for cardioBlock: WorkoutSessionCardioBlock) -> String {
        [
            cardioBlock.phase.shortTitle,
            formattedDuration(cardioBlock.targetDurationSeconds),
        ]
        .joined(separator: " • ")
    }

    private func repRangeText(min: Int?, max: Int?) -> String {
        switch (min, max) {
        case let (min?, max?):
            return min == max ? "\(min) reps" : "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "Up to \(max)"
        case (nil, nil):
            return "Open reps"
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let mins = safeSeconds / 60
        let secs = safeSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func normalizedRest(_ seconds: Int) -> Int {
        min(3600, max(0, seconds))
    }

    private func normalizedCardioDuration(_ seconds: Int) -> Int {
        min(24 * 60 * 60, max(0, seconds))
    }

    private func normalizedExerciseNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedWorkoutNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func orderedSets(for exercise: TemplateExercise) -> [TemplateExerciseSet] {
        (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated private func orderedSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated private func orderedCardioBlocks(for template: WorkoutTemplate) -> [TemplateCardioBlock] {
        (template.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    nonisolated private func orderedCardioBlocks(for session: WorkoutSession) -> [WorkoutSessionCardioBlock] {
        (session.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }
}

private struct TemplateOwnedSetSnapshot: Equatable {
    struct TargetIdentity: Equatable {
        let targetReps: Int?
        let targetWeight: Double?
        let loadUnit: TemplateLoadUnit
    }

    let targetIdentity: TargetIdentity
    let isWarmup: Bool
    let isLocked: Bool

    nonisolated init(templateSet: TemplateExerciseSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: templateSet.targetReps,
            targetWeight: templateSet.targetWeight,
            loadUnit: templateSet.loadUnit
        )
        self.isWarmup = templateSet.isWarmup
        self.isLocked = templateSet.isLocked
    }

    nonisolated init(sessionSet: WorkoutSessionSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: sessionSet.targetReps,
            targetWeight: sessionSet.targetWeight,
            loadUnit: sessionSet.targetLoadUnit
        )
        self.isWarmup = sessionSet.isWarmup
        self.isLocked = sessionSet.isLocked
    }
}
