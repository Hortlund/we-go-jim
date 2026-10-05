import Foundation
import SwiftData

/// Runs before local hydration, on an isolated context. Relationships identify
/// the real owner; no workout, exercise, or logged value is removed.
nonisolated enum LocalCopiedIdentityRepair {
    static func repair(in container: ModelContainer) throws {
        guard try BackupLocalJournal.restoreRequest(for: container) == nil else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = Date.now
        let templates = try context.fetch(FetchDescriptor<TemplateSupersetGroup>())
        let templateDuplicates = duplicates(templates, id: \.id)
        if !templateDuplicates.isEmpty {
            let exercises = try context.fetch(FetchDescriptor<TemplateExercise>())
            for groups in templateDuplicates {
                let oldID = groups[0].id
                guard exercises.filter({ $0.supersetGroupID == oldID }).allSatisfy({ $0.supersetGroup != nil }) else { continue }
                for group in groups {
                    group.id = UUID()
                    group.updatedAt = now
                    group.template?.updatedAt = now
                    for exercise in group.exercises ?? [] {
                        exercise.supersetGroupID = group.id
                        exercise.updatedAt = now
                    }
                }
            }
        }
        let workouts = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
        let workoutDuplicates = duplicates(workouts, id: \.id)
        if !workoutDuplicates.isEmpty {
            let exercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
            for groups in workoutDuplicates {
                let oldID = groups[0].id
                guard exercises.filter({ $0.supersetGroupID == oldID }).allSatisfy({ $0.supersetGroup != nil }) else { continue }
                for group in groups {
                    group.id = UUID()
                    group.updatedAt = now
                    group.session?.updatedAt = now
                    for exercise in group.exercises ?? [] {
                        exercise.supersetGroupID = group.id
                        exercise.updatedAt = now
                    }
                }
            }
        }
        let stages = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
        for copies in duplicates(stages, id: \.id) {
            guard Set(copies.map(\.templateExerciseSetID)).count == copies.count else { continue }
            for stage in copies {
                stage.id = UUID()
                stage.updatedAt = now
                stage.templateExerciseSet?.templateExercise?.template?.updatedAt = now
            }
        }
        if context.hasChanges { try context.saveWithRecoveryProtection(purpose: .maintenance) }
    }

    private static func duplicates<Row>(_ rows: [Row], id: KeyPath<Row, UUID>) -> [[Row]] {
        Dictionary(grouping: rows, by: { $0[keyPath: id] }).values.filter { $0.count > 1 }
    }
}
