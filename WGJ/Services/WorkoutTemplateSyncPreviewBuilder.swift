import Foundation
import SwiftData

nonisolated enum WorkoutTemplateSyncPreviewBuilder {
    static func buildPreview(
        template: WorkoutTemplate,
        session: WorkoutSession
    ) -> WorkoutTemplateSyncPreview? {
        let orderedTemplateExercises = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let orderedSessionExercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let orderedTemplateCardioBlocks = orderedCardioBlocks(for: template)
        let orderedSessionCardioBlocks = orderedCardioBlocks(for: session)
        let editedWorkoutNotes = editedWorkoutNotesChange(
            templateNotes: template.notes,
            sessionNotes: session.notes
        )
        let templateCardioByPhase = Dictionary(
            uniqueKeysWithValues: orderedTemplateCardioBlocks.map { ($0.phase, $0) }
        )
        let sessionCardioByPhase = Dictionary(
            uniqueKeysWithValues: orderedSessionCardioBlocks.map { ($0.phase, $0) }
        )
        let templateExercisesByUUID = Dictionary(
            uniqueKeysWithValues: orderedTemplateExercises.map { ($0.catalogExerciseUUID, $0) }
        )
        let templateExercisesByID = Dictionary(
            uniqueKeysWithValues: orderedTemplateExercises.map { ($0.id, $0) }
        )
        let matchedTemplateIDs = Set<UUID>(
            orderedSessionExercises.compactMap { exercise in
                guard let templateExerciseID = exercise.templateExerciseID,
                      templateExercisesByID[templateExerciseID] != nil else {
                    return nil
                }
                return templateExerciseID
            }
        )
        let sessionExercisesByLegacyCatalogUUID = Dictionary(
            uniqueKeysWithValues: orderedSessionExercises
                .filter { $0.templateExerciseID == nil }
                .map { ($0.catalogExerciseUUID, $0) }
        )

        let addedCardioBlocks = orderedSessionCardioBlocks.compactMap { cardioBlock -> WorkoutTemplateSyncAddedCardioBlock? in
            guard templateCardioByPhase[cardioBlock.phase] == nil else {
                return nil
            }

            return WorkoutTemplateSyncAddedCardioBlock(
                phase: cardioBlock.phase,
                exerciseName: cardioBlock.exerciseNameSnapshot,
                summary: cardioSummary(for: cardioBlock)
            )
        }

        let removedCardioBlocks = orderedTemplateCardioBlocks.compactMap { cardioBlock -> WorkoutTemplateSyncRemovedCardioBlock? in
            guard sessionCardioByPhase[cardioBlock.phase] == nil else {
                return nil
            }

            return WorkoutTemplateSyncRemovedCardioBlock(
                phase: cardioBlock.phase,
                exerciseName: cardioBlock.exerciseNameSnapshot,
                summary: cardioSummary(for: cardioBlock)
            )
        }

        let editedCardioBlocks = orderedSessionCardioBlocks.compactMap { cardioBlock -> WorkoutTemplateSyncEditedCardioBlock? in
            guard let templateCardioBlock = templateCardioByPhase[cardioBlock.phase] else {
                return nil
            }

            let changes = editedCardioChangeSummaries(
                templateCardioBlock: templateCardioBlock,
                sessionCardioBlock: cardioBlock
            )
            guard !changes.isEmpty else {
                return nil
            }

            return WorkoutTemplateSyncEditedCardioBlock(
                phase: cardioBlock.phase,
                exerciseName: cardioBlock.exerciseNameSnapshot,
                changes: changes
            )
        }

        let addedExercises = orderedSessionExercises.compactMap { sessionExercise -> WorkoutTemplateSyncAddedExercise? in
            if let templateExerciseID = sessionExercise.templateExerciseID,
               templateExercisesByID[templateExerciseID] != nil {
                return nil
            }
            guard templateExercisesByUUID[sessionExercise.catalogExerciseUUID] == nil else {
                return nil
            }

            return WorkoutTemplateSyncAddedExercise(
                catalogExerciseUUID: sessionExercise.catalogExerciseUUID,
                exerciseName: sessionExercise.exerciseNameSnapshot,
                summary: exerciseSummary(
                    setCount: orderedSets(for: sessionExercise).count,
                    targetRepMin: sessionExercise.targetRepMin,
                    targetRepMax: sessionExercise.targetRepMax,
                    restSeconds: sessionExercise.restSeconds
                )
            )
        }

        let removedExercises = orderedTemplateExercises.compactMap { templateExercise -> WorkoutTemplateSyncRemovedExercise? in
            if matchedTemplateIDs.contains(templateExercise.id) {
                return nil
            }
            guard sessionExercisesByLegacyCatalogUUID[templateExercise.catalogExerciseUUID] == nil else {
                return nil
            }

            return WorkoutTemplateSyncRemovedExercise(
                catalogExerciseUUID: templateExercise.catalogExerciseUUID,
                exerciseName: templateExercise.exerciseNameSnapshot,
                summary: exerciseSummary(
                    setCount: orderedSets(for: templateExercise).count,
                    targetRepMin: templateExercise.targetRepMin,
                    targetRepMax: templateExercise.targetRepMax,
                    restSeconds: templateExercise.restSeconds
                )
            )
        }

        let reorderedExercises = reorderedExercisePreviews(
            templateExercises: orderedTemplateExercises,
            sessionExercises: orderedSessionExercises
        )

        var editedExercises: [WorkoutTemplateSyncEditedExercise] = []
        for sessionExercise in orderedSessionExercises {
            let templateExercise = matchedTemplateExercise(
                for: sessionExercise,
                templateExercisesByID: templateExercisesByID,
                templateExercisesByUUID: templateExercisesByUUID
            )
            guard let templateExercise else {
                continue
            }

            let changes = editedChangeSummaries(
                templateExercise: templateExercise,
                sessionExercise: sessionExercise
            )
            guard !changes.isEmpty else {
                continue
            }

            editedExercises.append(
                WorkoutTemplateSyncEditedExercise(
                    catalogExerciseUUID: sessionExercise.catalogExerciseUUID,
                    exerciseName: sessionExercise.exerciseNameSnapshot,
                    changes: changes
                )
            )
        }

        guard
            editedWorkoutNotes != nil
                ||
            !addedCardioBlocks.isEmpty
                || !removedCardioBlocks.isEmpty
                || !editedCardioBlocks.isEmpty
                ||
            !addedExercises.isEmpty
                || !removedExercises.isEmpty
                || !reorderedExercises.isEmpty
                || !editedExercises.isEmpty
        else {
            return nil
        }

        return WorkoutTemplateSyncPreview(
            templateID: template.id,
            templateName: template.name,
            editedWorkoutNotes: editedWorkoutNotes,
            addedCardioBlocks: addedCardioBlocks,
            removedCardioBlocks: removedCardioBlocks,
            editedCardioBlocks: editedCardioBlocks,
            addedExercises: addedExercises,
            removedExercises: removedExercises,
            reorderedExercises: reorderedExercises,
            editedExercises: editedExercises,
            mutation: WorkoutTemplateSyncMutation(
                templateNotes: normalizedWorkoutNotes(session.notes),
                cardioBlocks: orderedSessionCardioBlocks.map(makeMutation(from:)),
                exercises: orderedSessionExercises.map { sessionExercise in
                    makeMutation(
                        from: sessionExercise,
                        templateExercise: matchedTemplateExercise(
                            for: sessionExercise,
                            templateExercisesByID: templateExercisesByID,
                            templateExercisesByUUID: templateExercisesByUUID
                        )
                    )
                }
            )
        )
    }

    nonisolated private static func makeMutation(
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
            components: componentDrafts,
            superset: sessionExercise.supersetMembership
        )
    }

    nonisolated private static func makeMutation(from cardioBlock: WorkoutSessionCardioBlock) -> WorkoutTemplateSyncCardioMutation {
        WorkoutTemplateSyncCardioMutation(
            phase: cardioBlock.phase,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            targetDurationSeconds: normalizedCardioDuration(cardioBlock.targetDurationSeconds)
        )
    }

    nonisolated private static func mappedSetDrafts(from sessionExercise: WorkoutSessionExercise) -> [TemplateExerciseSetDraft] {
        orderedSets(for: sessionExercise).map { sessionSet in
            TemplateExerciseSetDraft(
                targetReps: sessionSet.targetReps,
                targetWeight: sessionSet.targetWeight,
                loadUnit: sessionSet.targetLoadUnit,
                restSeconds: normalizedRest(sessionExercise.restSeconds),
                isWarmup: sessionSet.isWarmup,
                isLocked: sessionSet.isLocked,
                dropStages: (sessionSet.dropStages ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { stage in
                        TemplateExerciseDropStageDraft(
                            id: stage.id,
                            targetReps: stage.targetReps,
                            targetWeight: stage.targetWeight,
                            loadUnit: stage.targetLoadUnit
                        )
                    }
            )
        }
    }

    nonisolated private static func templateComponentDrafts(for templateExercise: TemplateExercise) -> [TemplateExerciseComponentDraft] {
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

    private static func matchedTemplateExercise(
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

    private static func syncIdentityKey(
        templateExerciseID: UUID?,
        catalogExerciseUUID: String
    ) -> String {
        if let templateExerciseID {
            return "slot:\(templateExerciseID.uuidString.lowercased())"
        }
        return "exercise:\(catalogExerciseUUID.lowercased())"
    }

    private static func syncIdentityKey(for sessionExercise: WorkoutSessionExercise) -> String {
        syncIdentityKey(
            templateExerciseID: sessionExercise.templateExerciseID,
            catalogExerciseUUID: sessionExercise.catalogExerciseUUID
        )
    }

    private static func editedChangeSummaries(
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

        if templateExercise.supersetMembership != sessionExercise.supersetMembership {
            switch (templateExercise.supersetMembership, sessionExercise.supersetMembership) {
            case (nil, .some):
                changes.append("Superset pairing added")
            case (.some, nil):
                changes.append("Superset pairing removed")
            case let (.some(templateMembership), .some(sessionMembership)):
                if templateMembership.position != sessionMembership.position {
                    changes.append("Superset slot \(templateMembership.position.label) -> \(sessionMembership.position.label)")
                } else if templateMembership.roundRestSeconds != sessionMembership.roundRestSeconds {
                    changes.append(
                        "Superset rest \(formattedRest(templateMembership.roundRestSeconds)) -> \(formattedRest(sessionMembership.roundRestSeconds))"
                    )
                } else {
                    changes.append("Superset pairing updated")
                }
            case (nil, nil):
                break
            }
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
                changes.append("Set layout changed")
            }
        }

        if templateSetSnapshots.map(\.isWarmup) != sessionSetSnapshots.map(\.isWarmup) {
            changes.append("Warmup assignments changed")
        }

        if templateSetSnapshots.map(\.isLocked) != sessionSetSnapshots.map(\.isLocked) {
            changes.append("Locked sets changed")
        }

        if templateSetSnapshots.map(\.dropStageIdentity) != sessionSetSnapshots.map(\.dropStageIdentity) {
            changes.append("Dropset layout changed")
        }

        return changes
    }

    private static func editedWorkoutNotesChange(
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
            changes.append("The reusable workout note will be cleared.")
        } else {
            changes.append(normalizedSession)
        }

        return WorkoutTemplateSyncEditedWorkoutNotes(changes: changes)
    }

    private static func editedCardioChangeSummaries(
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

    private static func reorderedExercisePreviews(
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

        let sessionIndexByKey = Dictionary(uniqueKeysWithValues: sharedSessionOrder.enumerated().map { ($1, $0) })

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

    private static func exerciseSummary(
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

    private static func cardioSummary(for cardioBlock: TemplateCardioBlock) -> String {
        [
            cardioBlock.phase.shortTitle,
            formattedDuration(cardioBlock.targetDurationSeconds),
        ]
        .joined(separator: " • ")
    }

    private static func cardioSummary(for cardioBlock: WorkoutSessionCardioBlock) -> String {
        [
            cardioBlock.phase.shortTitle,
            formattedDuration(cardioBlock.targetDurationSeconds),
        ]
        .joined(separator: " • ")
    }

    private static func repRangeText(min: Int?, max: Int?) -> String {
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

    private static func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let mins = safeSeconds / 60
        let secs = safeSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static func normalizedRest(_ seconds: Int) -> Int {
        min(3600, max(0, seconds))
    }

    nonisolated private static func normalizedCardioDuration(_ seconds: Int) -> Int {
        min(24 * 60 * 60, max(0, seconds))
    }

    nonisolated private static func normalizedExerciseNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizedWorkoutNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func orderedSets(for exercise: TemplateExercise) -> [TemplateExerciseSet] {
        (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated private static func orderedSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated private static func orderedCardioBlocks(for template: WorkoutTemplate) -> [TemplateCardioBlock] {
        (template.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    nonisolated private static func orderedCardioBlocks(for session: WorkoutSession) -> [WorkoutSessionCardioBlock] {
        (session.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }
}

nonisolated private struct TemplateOwnedSetSnapshot: Equatable {
    struct TargetIdentity: Equatable {
        let targetReps: Int?
        let targetWeight: Double?
        let loadUnit: TemplateLoadUnit
    }

    struct DropStageIdentity: Equatable {
        let targetReps: Int?
        let targetWeight: Double?
        let loadUnit: TemplateLoadUnit
    }

    let targetIdentity: TargetIdentity
    let isWarmup: Bool
    let isLocked: Bool
    let dropStageIdentity: [DropStageIdentity]

    nonisolated init(templateSet: TemplateExerciseSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: templateSet.targetReps,
            targetWeight: templateSet.targetWeight,
            loadUnit: templateSet.loadUnit
        )
        self.isWarmup = templateSet.isWarmup
        self.isLocked = templateSet.isLocked
        self.dropStageIdentity = (templateSet.dropStages ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                DropStageIdentity(
                    targetReps: $0.targetReps,
                    targetWeight: $0.targetWeight,
                    loadUnit: $0.loadUnit
                )
            }
    }

    nonisolated init(sessionSet: WorkoutSessionSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: sessionSet.targetReps,
            targetWeight: sessionSet.targetWeight,
            loadUnit: sessionSet.targetLoadUnit
        )
        self.isWarmup = sessionSet.isWarmup
        self.isLocked = sessionSet.isLocked
        self.dropStageIdentity = (sessionSet.dropStages ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                DropStageIdentity(
                    targetReps: $0.targetReps,
                    targetWeight: $0.targetWeight,
                    loadUnit: $0.targetLoadUnit
                )
            }
    }
}
