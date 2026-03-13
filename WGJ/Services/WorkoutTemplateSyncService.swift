import Foundation
import SwiftData

struct WorkoutTemplateSyncPreview: Equatable {
    let templateID: UUID
    let changedExerciseCount: Int
    let summary: String
    fileprivate let updates: [WorkoutTemplateExerciseUpdate]
}

private struct WorkoutTemplateExerciseUpdate: Equatable {
    let templateExerciseID: UUID
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

        let templateExercisesByUUID = Dictionary(
            uniqueKeysWithValues: (template.exercises ?? []).map { ($0.catalogExerciseUUID, $0) }
        )
        let orderedSessionExercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }

        var updates: [WorkoutTemplateExerciseUpdate] = []
        for sessionExercise in orderedSessionExercises {
            guard let templateExercise = templateExercisesByUUID[sessionExercise.catalogExerciseUUID] else {
                continue
            }

            let comparisonDrafts = mappedSetDrafts(
                from: sessionExercise,
                templateExercise: templateExercise,
                prefersActualValues: false
            )
            guard hasTemplateOwnedChanges(
                templateExercise: templateExercise,
                sessionExercise: sessionExercise,
                comparisonDrafts: comparisonDrafts
            ) else {
                continue
            }

            let updateDrafts = mappedSetDrafts(
                from: sessionExercise,
                templateExercise: templateExercise,
                prefersActualValues: true
            )
            updates.append(
                WorkoutTemplateExerciseUpdate(
                    templateExerciseID: templateExercise.id,
                    targetRepMin: sessionExercise.targetRepMin,
                    targetRepMax: sessionExercise.targetRepMax,
                    restSeconds: min(3600, max(0, sessionExercise.restSeconds)),
                    setDrafts: updateDrafts
                )
            )
        }

        guard !updates.isEmpty else { return nil }

        let count = updates.count
        let noun = count == 1 ? "exercise" : "exercises"
        return WorkoutTemplateSyncPreview(
            templateID: templateID,
            changedExerciseCount: count,
            summary: "\(count) \(noun) changed. Update the template with the new workout settings?",
            updates: updates
        )
    }

    func applyTemplateUpdate(_ preview: WorkoutTemplateSyncPreview) throws {
        let repository = TemplateRepository(modelContext: modelContext)
        for update in preview.updates {
            try repository.updateExerciseRepRange(
                templateExerciseID: update.templateExerciseID,
                minReps: update.targetRepMin,
                maxReps: update.targetRepMax
            )
            try repository.updateExerciseRestSeconds(
                templateExerciseID: update.templateExerciseID,
                restSeconds: update.restSeconds
            )
            try repository.saveSetDrafts(
                templateExerciseID: update.templateExerciseID,
                drafts: update.setDrafts
            )
        }
    }

    private func mappedSetDrafts(
        from sessionExercise: WorkoutSessionExercise,
        templateExercise: TemplateExercise,
        prefersActualValues: Bool
    ) -> [TemplateExerciseSetDraft] {
        let sessionSets = (sessionExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let templateSets = (templateExercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }

        return sessionSets.enumerated().map { index, sessionSet in
            let templateID = templateSets.indices.contains(index) ? templateSets[index].id : UUID()
            let shouldUseActualValues = prefersActualValues
                && (sessionSet.actualReps != nil || sessionSet.actualWeight != nil)

            return TemplateExerciseSetDraft(
                id: templateID,
                targetReps: shouldUseActualValues ? sessionSet.actualReps : sessionSet.targetReps,
                targetWeight: shouldUseActualValues ? sessionSet.actualWeight : sessionSet.targetWeight,
                loadUnit: shouldUseActualValues ? sessionSet.actualLoadUnit : sessionSet.targetLoadUnit,
                restSeconds: min(3600, max(0, sessionExercise.restSeconds)),
                isWarmup: sessionSet.isWarmup,
                isLocked: sessionSet.isLocked
            )
        }
    }

    private func hasTemplateOwnedChanges(
        templateExercise: TemplateExercise,
        sessionExercise: WorkoutSessionExercise,
        comparisonDrafts: [TemplateExerciseSetDraft]
    ) -> Bool {
        if templateExercise.targetRepMin != sessionExercise.targetRepMin
            || templateExercise.targetRepMax != sessionExercise.targetRepMax
            || templateExercise.restSeconds != min(3600, max(0, sessionExercise.restSeconds)) {
            return true
        }

        let templateDrafts = (templateExercise.prescribedSets ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(TemplateExerciseSetDraft.init(model:))

        guard templateDrafts.count == comparisonDrafts.count else {
            return true
        }

        for (templateDraft, sessionDraft) in zip(templateDrafts, comparisonDrafts) {
            if templateDraft.targetReps != sessionDraft.targetReps
                || templateDraft.targetWeight != sessionDraft.targetWeight
                || templateDraft.loadUnit != sessionDraft.loadUnit
                || templateDraft.isWarmup != sessionDraft.isWarmup
                || templateDraft.isLocked != sessionDraft.isLocked {
                return true
            }
        }

        return false
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
