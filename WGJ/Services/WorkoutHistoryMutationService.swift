import Foundation
import SwiftData

nonisolated struct WorkoutHistoryMutationService: Sendable {
    let backgroundStore: AppBackgroundStore
    let beforeSave: @Sendable () throws -> Void

    init(
        backgroundStore: AppBackgroundStore,
        beforeSave: @escaping @Sendable () throws -> Void = {}
    ) {
        self.backgroundStore = backgroundStore
        self.beforeSave = beforeSave
    }

    func removeExercise(sessionID: UUID, exerciseID: UUID) async throws {
        try await backgroundStore.perform("history.exercise.remove") { context in
            let repository = WorkoutSessionRepository(
                modelContext: context,
                autoSaveChanges: false
            )
            do {
                try repository.removeExercise(
                    sessionID: sessionID,
                    sessionExerciseID: exerciseID
                )
                try repository.recalculateSessionSummary(sessionID: sessionID)
                try beforeSave()
                try repository.finalizeDeferredUserDataChangesIfNeeded()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func addExercise(
        sessionID: UUID,
        selection: ExerciseCatalogSelection
    ) async throws {
        try await backgroundStore.perform("history.exercise.add") { context in
            let repository = WorkoutSessionRepository(
                modelContext: context,
                autoSaveChanges: false
            )
            do {
                try repository.addExercise(
                    sessionID: sessionID,
                    selection: selection
                )
                try repository.recalculateSessionSummary(sessionID: sessionID)
                try beforeSave()
                try repository.finalizeDeferredUserDataChangesIfNeeded()
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
