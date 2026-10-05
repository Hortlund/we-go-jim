import Foundation
import SwiftData

nonisolated enum UserDataCloudRestoreValidationError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(entity: String, identifier: String)
    case missingParent(childEntity: String, childIdentifier: String, parentIdentifier: String)
    case missingCatalogMuscle(exerciseIdentifier: String, muscleIdentifier: Int)
    case invalidCompletedWorkoutStatus(UUID)
    case invalidSupersetMembership(UUID)

    var errorDescription: String? {
        let detail: String
        switch self {
        case .unsupportedSchemaVersion(let version):
            detail = "The backup uses an unsupported data format (version \(version)). Update WGJ before trying again."
        case .duplicateIdentifier(let entity, let identifier):
            detail = "The backup contains duplicate \(entity) records.\nRecord ID: \(identifier)"
        case .missingParent(let entity, let identifier, let parentIdentifier):
            detail = "A \(entity) record in the backup refers to a missing parent.\nRecord ID: \(identifier)\nParent ID: \(parentIdentifier)"
        case .missingCatalogMuscle(let exerciseIdentifier, let muscleIdentifier):
            detail = "A custom exercise in the backup refers to a missing catalog muscle.\nExercise ID: \(exerciseIdentifier)\nMuscle ID: \(muscleIdentifier)"
        case .invalidCompletedWorkoutStatus(let identifier):
            detail = "The backup contains a workout that is not completed.\nWorkout ID: \(identifier.uuidString)"
        case .invalidSupersetMembership(let identifier):
            detail = "An exercise in the backup has an invalid superset relationship.\nExercise ID: \(identifier.uuidString)"
        }
        return "\(detail)\n\nYour existing data has not been replaced."
    }
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
        restoreTicket: UUID? = nil,
        replacementPayload: UserDataCloudBackupPayload? = nil,
        progress: CloudBackupProgressReporter = .init(),
        mergeDatabaseGraph: (ModelContext) throws -> Void,
        relinkRelationships: (ModelContext) throws -> Void
    ) throws {
        try LocalStoreWriteBarrier.exclusively {
            try commitExclusively(replacingLocalData: replacingLocalData, restoreTicket: restoreTicket, replacementPayload: replacementPayload, progress: progress,
                mergeDatabaseGraph: mergeDatabaseGraph, relinkRelationships: relinkRelationships)
        }
    }

    private func commitExclusively(
        replacingLocalData: Bool,
        restoreTicket: UUID? = nil,
        replacementPayload: UserDataCloudBackupPayload? = nil,
        progress: CloudBackupProgressReporter,
        mergeDatabaseGraph: (ModelContext) throws -> Void,
        relinkRelationships: (ModelContext) throws -> Void
    ) throws {
        if let restoreTicket {
            guard try BackupLocalJournal.restoreRequest(for: container)?.ticket == restoreTicket else {
                throw CancellationError()
            }
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let recovery = try PersistentRestoreRecovery.prepare(container: container, ticket: restoreTicket)
        var attemptedSave = false
        do {
            try dependencies.checkpoint(.afterValidation)
            if replacingLocalData {
                try AppDataDeletionService(modelContext: context).stageLocalDataDeletion(preservingHistory: replacementPayload)
                try dependencies.checkpoint(.afterDeletionStaged)
            }

            try mergeDatabaseGraph(context)
            try dependencies.checkpoint(.afterGraphMerge)
            try relinkRelationships(context)
            try dependencies.checkpoint(.afterRelationshipLink)
            progress(.rebuilding)
            try rebuildCompletedSessionSummariesAndFacts(in: context)
            try dependencies.checkpoint(.afterProjectionRebuild)
            try dependencies.checkpoint(.beforeSave)

            if context.hasChanges {
                progress(.saving)
                attemptedSave = true
                try dependencies.save(context)
            }
            try PersistentRestoreRecovery.complete(recovery, committed: true)
        } catch {
            context.rollback()
            if attemptedSave, recovery != nil { throw PersistentRestoreRecovery.RecoveryRequired() }
            try? PersistentRestoreRecovery.complete(recovery)
            throw error
        }
    }

    private func rebuildCompletedSessionSummariesAndFacts(in context: ModelContext) throws {
        try HistoryProjectionRepository(modelContext: context).rebuildAllForRestore()
        _ = try HistoryRecordRebuilder.rebuild(in: context)
    }
}
