import Foundation
import SwiftData

nonisolated struct TemplateEditorInitialSnapshot: Sendable, Equatable {
    let preferredLoadUnit: TemplateLoadUnit
    let preferredDistanceUnit: WorkoutDistanceUnit
    let isTrainingGuidanceEnabled: Bool
    let template: TemplateEditorLoadedTemplate?
}

nonisolated struct TemplateEditorLoadedTemplate: Sendable, Equatable {
    let name: String
    let notes: String
    let exerciseDrafts: [TemplateExerciseDraft]
    let cardioDrafts: [TemplateCardioBlockDraft]
}

nonisolated enum TemplateEditorSnapshotLoader {
    static func load(
        templateID: UUID?,
        modelContext: ModelContext
    ) throws -> TemplateEditorInitialSnapshot {
        let profile = try ProfileRepository(modelContext: modelContext).currentProfile()
        let preferredLoadUnit = profile?.preferredLoadUnit ?? .kg
        let preferredDistanceUnit = profile?.preferredDistanceUnit ?? .regionalDefault(locale: .current)
        let isTrainingGuidanceEnabled = profile?.isTrainingGuidanceEnabled ?? true

        guard let templateID else {
            return TemplateEditorInitialSnapshot(
                preferredLoadUnit: preferredLoadUnit,
                preferredDistanceUnit: preferredDistanceUnit,
                isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
                template: nil
            )
        }

        let repository = TemplateRepository(modelContext: modelContext)
        let loadedTemplate: TemplateEditorLoadedTemplate?
        if let template = try repository.template(id: templateID) {
            loadedTemplate = TemplateEditorLoadedTemplate(
                name: template.name,
                notes: template.notes,
                exerciseDrafts: try repository.exercises(in: templateID).map {
                    TemplateExerciseDraft(model: $0, preferredLoadUnit: preferredLoadUnit)
                },
                cardioDrafts: try repository.cardioActivities(templateID: templateID).map {
                    TemplateCardioBlockDraft(model: $0)
                }
            )
        } else {
            loadedTemplate = nil
        }

        return TemplateEditorInitialSnapshot(
            preferredLoadUnit: preferredLoadUnit,
            preferredDistanceUnit: preferredDistanceUnit,
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
            template: loadedTemplate
        )
    }
}

nonisolated struct TemplateEditorSaveRequest: Sendable {
    let folderID: UUID?
    let templateID: UUID?
    let name: String
    let notes: String
    let exerciseDrafts: [TemplateExerciseDraft]
    let cardioDrafts: [TemplateCardioBlockDraft]
}

nonisolated enum TemplateEditorSaveOperationResult: Sendable, Equatable {
    case saved(TemplateEditorSaveResult)
}

nonisolated enum TemplateEditorPersistence {
    static func save(
        _ request: TemplateEditorSaveRequest,
        modelContext: ModelContext,
        boundaryEffects: TemplateSaveBoundaryEffects = .live
    ) throws -> TemplateEditorSaveOperationResult {
        let repository = TemplateRepository(
            modelContext: modelContext,
            autoSaveChanges: false,
            boundaryEffects: boundaryEffects
        )
        let savedTemplateID: UUID

        if let templateID = request.templateID {
            try repository.updateTemplateContents(
                id: templateID,
                name: request.name,
                notes: request.notes,
                exerciseDrafts: request.exerciseDrafts,
                cardioDrafts: request.cardioDrafts
            )
            savedTemplateID = templateID
        } else {
            let created = try repository.createTemplate(
                folderID: request.folderID,
                name: request.name,
                notes: request.notes
            )
            try repository.setExercises(templateID: created.id, drafts: request.exerciseDrafts)
            try repository.setCardioActivities(templateID: created.id, drafts: request.cardioDrafts)
            savedTemplateID = created.id
        }

        try repository.finalizeDeferredUserDataChangesIfNeeded()

        return .saved(TemplateEditorSaveResult(
            templateID: savedTemplateID,
            name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }
}

nonisolated struct TemplateEditorSaveResult: Sendable, Equatable {
    let templateID: UUID
    let name: String
    let notes: String
}
