import Foundation
import SwiftData

struct WorkoutTemplateSyncPreview: Equatable, Identifiable {
    let templateID: UUID
    let templateName: String
    let addedExercises: [WorkoutTemplateSyncAddedExercise]
    let removedExercises: [WorkoutTemplateSyncRemovedExercise]
    let reorderedExercises: [WorkoutTemplateSyncReorderedExercise]
    let editedExercises: [WorkoutTemplateSyncEditedExercise]
    fileprivate let mutation: WorkoutTemplateSyncMutation

    var id: UUID { templateID }

    var totalChangeCount: Int {
        addedExercises.count + removedExercises.count + reorderedExercises.count + editedExercises.count
    }

    var summary: String {
        var parts: [String] = []

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

        return parts.joined(separator: " • ")
    }

    private func countText(_ count: Int, singular: String) -> String {
        "\(count) \(singular)" + (count == 1 ? "" : "s")
    }
}

struct WorkoutTemplateSyncAddedExercise: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let summary: String

    var id: String { catalogExerciseUUID }
}

struct WorkoutTemplateSyncRemovedExercise: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let summary: String

    var id: String { catalogExerciseUUID }
}

struct WorkoutTemplateSyncReorderedExercise: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let fromPosition: Int
    let toPosition: Int

    var id: String { catalogExerciseUUID }
}

struct WorkoutTemplateSyncEditedExercise: Identifiable, Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let changes: [String]

    var id: String { catalogExerciseUUID }
}

struct WorkoutTemplateSyncMutation: Equatable {
    let exercises: [WorkoutTemplateSyncExerciseMutation]
}

struct WorkoutTemplateSyncExerciseMutation: Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let setDrafts: [TemplateExerciseSetDraft]
}

@MainActor
final class WorkoutTemplateSyncService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func previewTemplateUpdate(forSessionID sessionID: UUID) throws -> WorkoutTemplateSyncPreview? {
        guard let session = try workoutSession(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        guard let templateID = session.templateID,
              let template = try workoutTemplate(id: templateID) else {
            return nil
        }

        let orderedTemplateExercises = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let orderedSessionExercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let templateExercisesByUUID = Dictionary(
            uniqueKeysWithValues: orderedTemplateExercises.map { ($0.catalogExerciseUUID, $0) }
        )
        let sessionExercisesByUUID = Dictionary(
            uniqueKeysWithValues: orderedSessionExercises.map { ($0.catalogExerciseUUID, $0) }
        )

        let addedExercises = orderedSessionExercises.compactMap { sessionExercise -> WorkoutTemplateSyncAddedExercise? in
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
            guard sessionExercisesByUUID[templateExercise.catalogExerciseUUID] == nil else {
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
            guard let templateExercise = templateExercisesByUUID[sessionExercise.catalogExerciseUUID] else {
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
            !addedExercises.isEmpty
                || !removedExercises.isEmpty
                || !reorderedExercises.isEmpty
                || !editedExercises.isEmpty
        else {
            return nil
        }

        return WorkoutTemplateSyncPreview(
            templateID: templateID,
            templateName: template.name,
            addedExercises: addedExercises,
            removedExercises: removedExercises,
            reorderedExercises: reorderedExercises,
            editedExercises: editedExercises,
            mutation: WorkoutTemplateSyncMutation(
                exercises: orderedSessionExercises.map(makeMutation(from:))
            )
        )
    }

    func applyTemplateUpdate(_ preview: WorkoutTemplateSyncPreview) throws {
        let repository = TemplateRepository(modelContext: modelContext)
        try repository.applyWorkoutTemplateSync(
            templateID: preview.templateID,
            exercises: preview.mutation.exercises
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

    private func makeMutation(from sessionExercise: WorkoutSessionExercise) -> WorkoutTemplateSyncExerciseMutation {
        WorkoutTemplateSyncExerciseMutation(
            catalogExerciseUUID: sessionExercise.catalogExerciseUUID,
            exerciseNameSnapshot: sessionExercise.exerciseNameSnapshot,
            categorySnapshot: sessionExercise.categorySnapshot,
            muscleSummarySnapshot: sessionExercise.muscleSummarySnapshot,
            targetRepMin: sessionExercise.targetRepMin,
            targetRepMax: sessionExercise.targetRepMax,
            restSeconds: normalizedRest(sessionExercise.restSeconds),
            setDrafts: mappedSetDrafts(from: sessionExercise)
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

        return changes
    }

    private func reorderedExercisePreviews(
        templateExercises: [TemplateExercise],
        sessionExercises: [WorkoutSessionExercise]
    ) -> [WorkoutTemplateSyncReorderedExercise] {
        let sessionCatalogUUIDs = Set(sessionExercises.map(\.catalogExerciseUUID))
        let templateCatalogUUIDs = Set(templateExercises.map(\.catalogExerciseUUID))
        let sharedTemplateOrder = templateExercises
            .map(\.catalogExerciseUUID)
            .filter { sessionCatalogUUIDs.contains($0) }
        let sharedSessionOrder = sessionExercises
            .map(\.catalogExerciseUUID)
            .filter { templateCatalogUUIDs.contains($0) }

        guard sharedTemplateOrder != sharedSessionOrder else {
            return []
        }

        let sessionIndexByUUID = Dictionary(uniqueKeysWithValues: sharedSessionOrder.enumerated().map { ($1, $0) })
        let sessionExercisesByUUID = Dictionary(uniqueKeysWithValues: sessionExercises.map { ($0.catalogExerciseUUID, $0) })

        return sharedTemplateOrder.enumerated().compactMap { index, catalogExerciseUUID in
            guard let destinationIndex = sessionIndexByUUID[catalogExerciseUUID], destinationIndex != index else {
                return nil
            }

            let exerciseName = sessionExercisesByUUID[catalogExerciseUUID]?.exerciseNameSnapshot ?? catalogExerciseUUID
            return WorkoutTemplateSyncReorderedExercise(
                catalogExerciseUUID: catalogExerciseUUID,
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

    private func normalizedRest(_ seconds: Int) -> Int {
        min(3600, max(0, seconds))
    }

    private func orderedSets(for exercise: TemplateExercise) -> [TemplateExerciseSet] {
        (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func orderedSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
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

    init(templateSet: TemplateExerciseSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: templateSet.targetReps,
            targetWeight: templateSet.targetWeight,
            loadUnit: templateSet.loadUnit
        )
        self.isWarmup = templateSet.isWarmup
        self.isLocked = templateSet.isLocked
    }

    init(sessionSet: WorkoutSessionSet) {
        self.targetIdentity = TargetIdentity(
            targetReps: sessionSet.targetReps,
            targetWeight: sessionSet.targetWeight,
            loadUnit: sessionSet.targetLoadUnit
        )
        self.isWarmup = sessionSet.isWarmup
        self.isLocked = sessionSet.isLocked
    }
}
