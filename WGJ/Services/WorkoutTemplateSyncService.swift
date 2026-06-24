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

    func applyTemplateUpdate(
        _ preview: WorkoutTemplateSyncPreview,
        backupReason: BoundaryCloudBackupReason = .templateSaved
    ) throws {
        let repository = TemplateRepository(
            modelContext: modelContext,
            userDataChangeBackupReason: backupReason
        )
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
}
