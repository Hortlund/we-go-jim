import Foundation
import SwiftData

nonisolated enum WorkoutHistoryMutationError: Error, Equatable, Sendable {
    case cardioActivityNotFound
}

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

    func updateCardioResult(
        sessionID: UUID,
        activityID: UUID,
        result: ValidatedWorkoutCardioResult
    ) async throws {
        try await backgroundStore.perform("history.cardio-result.update") { context in
            let repository = WorkoutSessionRepository(
                modelContext: context,
                autoSaveChanges: false
            )
            do {
                guard try repository.session(id: sessionID) != nil else {
                    throw WorkoutSessionRepositoryError.sessionNotFound
                }
                guard let activity = try repository.sessionCardioBlocks(sessionID: sessionID)
                    .first(where: { $0.id == activityID }) else {
                    throw WorkoutHistoryMutationError.cardioActivityNotFound
                }
                guard activity.actualDurationSeconds != result.actualDurationSeconds
                        || activity.actualDistanceMeters != result.actualDistanceMeters
                        || activity.preferredDistanceUnit != result.preferredDistanceUnit
                        || activity.inclinePercent != result.inclinePercent
                        || activity.resistanceLevel != result.resistanceLevel
                        || activity.cardioNotes != result.notes else {
                    return
                }

                let updatedAt = Date()
                activity.actualDurationSeconds = result.actualDurationSeconds
                activity.actualDistanceMeters = result.actualDistanceMeters
                activity.preferredDistanceUnit = result.preferredDistanceUnit
                activity.inclinePercent = result.inclinePercent
                activity.resistanceLevel = result.resistanceLevel
                activity.cardioNotes = result.notes
                activity.updatedAt = updatedAt

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
