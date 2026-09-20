import Foundation
import SwiftData

/// Scalar ownership IDs are authoritative; relationship faults are never required here.
nonisolated enum WorkoutCommitPreparation {
    static func stampChangedWorkouts(in context: ModelContext) throws {
        let changed = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        let deletedSessions = Set(context.deletedModelsArray.compactMap { ($0 as? WorkoutSession)?.id })
        var sessionIDs: Set<UUID> = []
        var exerciseIDs: Set<UUID> = []
        var setIDs: Set<UUID> = []
        for model in changed {
            switch model {
            case let exercise as WorkoutSessionExercise: sessionIDs.insert(exercise.sessionID)
            case let set as WorkoutSessionSet: exerciseIDs.insert(set.sessionExerciseID)
            case let stage as WorkoutSessionDropStage: setIDs.insert(stage.sessionSetID)
            case let activity as WorkoutSessionCardioBlock: sessionIDs.insert(activity.sessionID)
            case let group as WorkoutSessionSupersetGroup: sessionIDs.insert(group.sessionID)
            default: break
            }
        }
        if !setIDs.isEmpty {
            for set in try context.fetch(FetchDescriptor<WorkoutSessionSet>(predicate: #Predicate { setIDs.contains($0.id) })) {
                exerciseIDs.insert(set.sessionExerciseID)
            }
        }
        if !exerciseIDs.isEmpty {
            for exercise in try context.fetch(FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate { exerciseIDs.contains($0.id) })) {
                sessionIDs.insert(exercise.sessionID)
            }
        }
        sessionIDs.subtract(deletedSessions)
        guard !sessionIDs.isEmpty else { return }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { sessionIDs.contains($0.id) })) {
            session.updatedAt = .now
        }
    }
    static func stampChangedTemplates(in context: ModelContext) throws {
        let changed = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        var templateIDs: Set<UUID> = []
        var exerciseIDs: Set<UUID> = []
        var setIDs: Set<UUID> = []
        for model in changed {
            switch model {
            case let exercise as TemplateExercise: templateIDs.insert(exercise.templateID)
            case let component as TemplateExerciseComponent: exerciseIDs.insert(component.templateExerciseID)
            case let set as TemplateExerciseSet: exerciseIDs.insert(set.templateExerciseID)
            case let stage as TemplateExerciseDropStage: setIDs.insert(stage.templateExerciseSetID)
            case let block as TemplateCardioBlock: templateIDs.insert(block.templateID)
            case let group as TemplateSupersetGroup: templateIDs.insert(group.templateID)
            default: break
            }
        }
        if !setIDs.isEmpty {
            for set in try context.fetch(FetchDescriptor<TemplateExerciseSet>(predicate: #Predicate { setIDs.contains($0.id) })) {
                exerciseIDs.insert(set.templateExerciseID)
            }
        }
        if !exerciseIDs.isEmpty {
            for exercise in try context.fetch(FetchDescriptor<TemplateExercise>(predicate: #Predicate { exerciseIDs.contains($0.id) })) {
                templateIDs.insert(exercise.templateID)
            }
        }
        guard !templateIDs.isEmpty else { return }
        for template in try context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { templateIDs.contains($0.id) })) {
            template.updatedAt = .now
        }
    }

}
