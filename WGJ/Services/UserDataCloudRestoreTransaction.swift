import Foundation
import SwiftData

nonisolated enum UserDataCloudRestoreValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(entity: String, identifier: String)
    case missingParent(childEntity: String, childIdentifier: String, parentIdentifier: String)
    case missingCatalogMuscle(exerciseIdentifier: String, muscleIdentifier: Int)
    case invalidCompletedWorkoutStatus(UUID)
    case invalidSupersetMembership(UUID)
}

nonisolated enum UserDataCloudRestoreCheckpoint: CaseIterable, Equatable, Sendable {
    case afterValidation
    case afterDeletionStaged
    case afterGraphMerge
    case afterRelationshipLink
    case afterProjectionRebuild
    case beforeSave
}

nonisolated struct UserDataCloudRestoreDependencies {
    let checkpoint: (UserDataCloudRestoreCheckpoint) throws -> Void
    let save: (ModelContext) throws -> Void

    init(
        checkpoint: @escaping (UserDataCloudRestoreCheckpoint) throws -> Void = { _ in },
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.checkpoint = checkpoint
        self.save = save
    }
}

nonisolated final class UserDataCloudRestoreTransaction {
    private let container: ModelContainer
    private let dependencies: UserDataCloudRestoreDependencies

    init(
        container: ModelContainer,
        dependencies: UserDataCloudRestoreDependencies = UserDataCloudRestoreDependencies()
    ) {
        self.container = container
        self.dependencies = dependencies
    }

    func commit(
        replacingLocalData: Bool,
        mergeDatabaseGraph: (ModelContext) throws -> Void,
        relinkRelationships: (ModelContext) throws -> Void
    ) throws {
        try LocalStoreWriteBarrier.exclusively {
            try commitExclusively(replacingLocalData: replacingLocalData,
                mergeDatabaseGraph: mergeDatabaseGraph, relinkRelationships: relinkRelationships)
        }
    }

    private func commitExclusively(
        replacingLocalData: Bool,
        mergeDatabaseGraph: (ModelContext) throws -> Void,
        relinkRelationships: (ModelContext) throws -> Void
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let recovery = try PersistentRestoreRecovery.prepare(container: container)
        var attemptedSave = false
        do {
            try dependencies.checkpoint(.afterValidation)
            if replacingLocalData {
                try AppDataDeletionService(modelContext: context).stageLocalDataDeletion()
                try dependencies.checkpoint(.afterDeletionStaged)
            }

            try mergeDatabaseGraph(context)
            try dependencies.checkpoint(.afterGraphMerge)
            try relinkRelationships(context)
            try dependencies.checkpoint(.afterRelationshipLink)
            try rebuildCompletedSessionSummariesAndFacts(in: context)
            try dependencies.checkpoint(.afterProjectionRebuild)
            try dependencies.checkpoint(.beforeSave)

            if context.hasChanges {
                attemptedSave = true
                try dependencies.save(context)
            }
            try PersistentRestoreRecovery.complete(recovery)
        } catch {
            context.rollback()
            if attemptedSave, recovery != nil { throw PersistentRestoreRecovery.RecoveryRequired() }
            try? PersistentRestoreRecovery.complete(recovery)
            throw error
        }
    }

    private func rebuildCompletedSessionSummariesAndFacts(in context: ModelContext) throws {
        _ = try HistoryProjectionRepository(modelContext: context).backfillIfNeeded(persistChanges: false)
        _ = try HistoryRecordRebuilder.rebuild(in: context)
    }
}
