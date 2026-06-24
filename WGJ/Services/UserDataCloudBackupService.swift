import CloudKit
import Foundation
import SwiftData

struct UserDataCloudBackupRemoteRecord: Equatable, Sendable {
    var updatedAt: Date
    var payloadData: Data
}

struct UserDataCloudBackupRemoteMetadata: Equatable, Sendable {
    var updatedAt: Date
}

struct UserDataCloudBackupRemoteSnapshot: Equatable, Sendable {
    var updatedAt: Date
    var contentSummary: UserDataCloudBackupContentSummary
}

struct UserDataCloudBackupRestoreResult: Equatable, Sendable {
    var restoredAt: Date
}

struct UserDataCloudBackupContentSummary: Equatable, Sendable {
    var profileCount: Int
    var profileWidgetCount: Int
    var customExerciseCount: Int
    var templateFolderCount: Int
    var workoutTemplateCount: Int
    var templateCardioBlockCount: Int
    var templateExerciseCount: Int
    var templateComponentCount: Int
    var templateSetCount: Int
    var templateDropStageCount: Int
    var completedWorkoutCount: Int
    var workoutCardioBlockCount: Int
    var workoutExerciseCount: Int
    var workoutSetCount: Int
    var workoutDropStageCount: Int
}

protocol UserDataCloudBackupStoring: Sendable {
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws
    func deleteBackup() async throws
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord?
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata?
}

nonisolated enum UserDataCloudBackupDescriptor {
    static let recordType = "WGJUserDataBackup"
    static let recordName = "current-user-data-backup-v2"

    enum Field {
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let payloadAsset = "payloadAsset"
        static let payloadData = "payloadData"
        static let payloadCompression = "payloadCompression"
    }
}

nonisolated enum BoundaryCloudBackupReason: String, Sendable {
    case workoutCompleted
    case workoutCompletionTemplateSaved
    case workoutDeleted
    case templateSaved

    var failureDescription: String {
        switch self {
        case .workoutCompleted:
            return "workout completion"
        case .workoutCompletionTemplateSaved:
            return "workout completion template update"
        case .workoutDeleted:
            return "workout delete"
        case .templateSaved:
            return "template save"
        }
    }
}

nonisolated enum BoundaryCloudBackupScheduler {
    static let workoutCompletionSettleDelay: Duration = .seconds(2)

    static func enqueueDelay(for reason: BoundaryCloudBackupReason) -> Duration {
        switch reason {
        case .workoutCompleted, .workoutCompletionTemplateSaved:
            return workoutCompletionSettleDelay
        case .workoutDeleted, .templateSaved:
            return .zero
        }
    }

    static func exportBestEffort(container: ModelContainer, reason: BoundaryCloudBackupReason) {
        guard AppRuntimeConfig.canUseConfiguredCloudKitContainer else { return }

        Task.detached(priority: .utility) {
            let delay = enqueueDelay(for: reason)
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            await BoundaryCloudBackupExportQueue.shared.enqueue(container: container, reason: reason)
        }
    }
}

private struct BoundaryCloudBackupRequest {
    let container: ModelContainer
    let reason: BoundaryCloudBackupReason
}

private actor BoundaryCloudBackupExportQueue {
    static let shared = BoundaryCloudBackupExportQueue()

    private var isProcessing = false
    private var pendingRequest: BoundaryCloudBackupRequest?

    func enqueue(container: ModelContainer, reason: BoundaryCloudBackupReason) {
        pendingRequest = BoundaryCloudBackupRequest(container: container, reason: reason)
        guard !isProcessing else { return }

        isProcessing = true
        Task(priority: .utility) {
            await processPendingRequests()
        }
    }

    private func processPendingRequests() async {
        while let request = pendingRequest {
            pendingRequest = nil
            await export(request)
        }
        isProcessing = false
    }

    private func export(_ request: BoundaryCloudBackupRequest) async {
        do {
            await MainActor.run {
                AppRuntimeState.shared.updateUserDataSyncStatus(.pending())
            }
            let exportedSnapshot = try await UserDataCloudBackupService(
                localContainer: request.container,
                backupStore: CloudKitUserDataCloudBackupStore()
            ).exportCurrentBackup()
            await MainActor.run {
                AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp(at: exportedSnapshot.updatedAt))
            }
        } catch {
            await MainActor.run {
                AppRuntimeState.shared.updateUserDataSyncStatus(.degraded("Cloud backup failed after \(request.reason.failureDescription): \(error.localizedDescription)"))
            }
        }
    }
}

nonisolated final class UserDataCloudBackupService {
    private let localContainer: ModelContainer
    private let backupStore: any UserDataCloudBackupStoring

    init(
        localContainer: ModelContainer,
        backupStore: any UserDataCloudBackupStoring
    ) {
        self.localContainer = localContainer
        self.backupStore = backupStore
    }

    @discardableResult
    func exportCurrentBackup() async throws -> UserDataCloudBackupRemoteSnapshot {
        let context = ModelContext(localContainer)
        context.autosaveEnabled = false
        try TemplateRepository(modelContext: context, autoSaveChanges: false).pruneOrphanedTemplateGraphs()
        let payload = try UserDataCloudBackupPayload(context: context)
        let payloadData = try Self.makeEncoder().encode(payload)
        try await backupStore.saveBackup(UserDataCloudBackupRemoteRecord(
            updatedAt: payload.generatedAt,
            payloadData: payloadData
        ))
        return UserDataCloudBackupRemoteSnapshot(
            updatedAt: payload.generatedAt,
            contentSummary: payload.contentSummary
        )
    }

    func latestBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        try await backupStore.fetchBackupMetadata()
    }

    func deleteRemoteBackup() async throws {
        try await backupStore.deleteBackup()
    }

    func latestBackupSnapshot() async throws -> UserDataCloudBackupRemoteSnapshot? {
        guard let record = try await backupStore.fetchBackup() else {
            return nil
        }

        let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        return UserDataCloudBackupRemoteSnapshot(
            updatedAt: record.updatedAt,
            contentSummary: payload.contentSummary
        )
    }

    func restoreLatestBackup(replacingLocalData: Bool = false) async throws -> UserDataCloudBackupRestoreResult? {
        guard let record = try await backupStore.fetchBackup() else {
            return nil
        }

        let payload = try Self.makeDecoder().decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        let context = ModelContext(localContainer)
        context.autosaveEnabled = false

        if replacingLocalData {
            try await AppDataDeletionService(
                modelContext: context,
                deleteCloudBackup: {},
                clearActiveWorkoutSnapshot: {
                    try await ActiveWorkoutSnapshotStore.shared.delete()
                }
            ).deleteLocalDeviceData()
        } else {
            guard try Self.isLocalUserDataEmpty(context: context) else {
                return nil
            }
        }

        try payload.mergeIntoLocalStore(in: context)
        if context.hasChanges {
            try context.save()
        }
        return UserDataCloudBackupRestoreResult(restoredAt: record.updatedAt)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func isLocalUserDataEmpty(context: ModelContext) throws -> Bool {
        let customExercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
            .filter(\.isCustomExercise)
        return try context.fetch(FetchDescriptor<UserProfile>()).isEmpty
            && context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty
            && context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty
            && customExercises.isEmpty
    }
}

nonisolated struct CloudKitUserDataCloudBackupStore: UserDataCloudBackupStoring {
    private static let inlinePayloadFallbackLimitBytes = 900_000
    private static let lzfsePayloadCompression = "lzfse"
    private static let temporaryPayloadDirectoryName = "WGJUserDataCloudBackups"

    private let database: CKDatabase?

    init(container: CKContainer? = nil) {
        self.database = (container ?? AppRuntimeConfig.makeCloudKitContainer())?.privateCloudDatabase
    }

    static func removeExpiredTemporaryPayloads(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let directory = temporaryPayloadDirectoryURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path),
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
              )
        else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-age)
        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
            ]),
                values.isRegularFile == true,
                (values.contentModificationDate ?? .distantPast) < expirationDate
            else {
                continue
            }

            try? fileManager.removeItem(at: fileURL)
        }
    }

    func saveBackup(_ backup: UserDataCloudBackupRemoteRecord) async throws {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        let record = try await existingRecord(recordID: recordID)
            ?? CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: recordID)
        let payloadURL = try writeTemporaryPayload(backup.payloadData)
        defer {
            try? FileManager.default.removeItem(at: payloadURL)
        }

        record[UserDataCloudBackupDescriptor.Field.updatedAt] = backup.updatedAt as CKRecordValue
        record[UserDataCloudBackupDescriptor.Field.schemaVersion] = NSNumber(value: UserDataCloudBackupPayload.schemaVersion)
        record[UserDataCloudBackupDescriptor.Field.payloadAsset] = CKAsset(fileURL: payloadURL)
        if let inlinePayload = Self.inlinePayloadFallback(for: backup.payloadData) {
            record[UserDataCloudBackupDescriptor.Field.payloadData] = inlinePayload.data as CKRecordValue
            record[UserDataCloudBackupDescriptor.Field.payloadCompression] = inlinePayload.compression as CKRecordValue?
        } else {
            record[UserDataCloudBackupDescriptor.Field.payloadData] = nil
            record[UserDataCloudBackupDescriptor.Field.payloadCompression] = nil
        }

        _ = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
    }

    func deleteBackup() async throws {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard try await existingRecord(recordID: recordID) != nil else {
            return
        }

        _ = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .allKeys,
            atomically: true
        )
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard let record = try await existingRecord(recordID: recordID) else {
            return nil
        }

        let updatedAt = record[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast
        if let asset = record[UserDataCloudBackupDescriptor.Field.payloadAsset] as? CKAsset,
           let fileURL = asset.fileURL,
           let payloadData = try? Data(contentsOf: fileURL) {
            return UserDataCloudBackupRemoteRecord(updatedAt: updatedAt, payloadData: payloadData)
        }
        if let payloadData = record[UserDataCloudBackupDescriptor.Field.payloadData] as? Data {
            let compression = record[UserDataCloudBackupDescriptor.Field.payloadCompression] as? String
            guard let decodedPayloadData = Self.decodedInlinePayload(payloadData, compression: compression) else {
                return nil
            }
            return UserDataCloudBackupRemoteRecord(updatedAt: updatedAt, payloadData: decodedPayloadData)
        }
        return nil
    }

    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard let record = try await existingRecord(recordID: recordID) else {
            return nil
        }

        let updatedAt = record[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast
        return UserDataCloudBackupRemoteMetadata(updatedAt: updatedAt)
    }

    private static func inlinePayloadFallback(for payloadData: Data) -> (data: Data, compression: String?)? {
        if payloadData.count <= inlinePayloadFallbackLimitBytes {
            return (payloadData, nil)
        }

        guard let compressedPayload = try? (payloadData as NSData).compressed(using: .lzfse) as Data,
              compressedPayload.count <= inlinePayloadFallbackLimitBytes
        else {
            return nil
        }
        return (compressedPayload, lzfsePayloadCompression)
    }

    private static func decodedInlinePayload(_ payloadData: Data, compression: String?) -> Data? {
        guard let compression else {
            return payloadData
        }

        guard compression == lzfsePayloadCompression else {
            return nil
        }
        return try? (payloadData as NSData).decompressed(using: .lzfse) as Data
    }

    private func existingRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        let database = try requireDatabase()
        do {
            let results = try await database.records(for: [recordID])
            guard let result = results[recordID] else {
                return nil
            }

            switch result {
            case .success(let record):
                return record
            case .failure(let error as CKError) where error.code == .unknownItem:
                return nil
            case .failure(let error):
                throw error
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func writeTemporaryPayload(_ data: Data) throws -> URL {
        let directory = Self.temporaryPayloadDirectoryURL(fileManager: .default)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func temporaryPayloadDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(temporaryPayloadDirectoryName, isDirectory: true)
    }

    private func requireDatabase() throws -> CKDatabase {
        guard let database else {
            throw CloudKitContainerAvailabilityError.unavailable
        }
        return database
    }
}

nonisolated private struct UserDataCloudBackupPayload: Codable {
    static let schemaVersion = 2

    var schemaVersion: Int = Self.schemaVersion
    var generatedAt: Date = Date()
    var profiles: [Profile]
    var profileWidgets: [ProfileWidget]
    var customExercises: [CustomExercise]
    var templateFolders: [TemplateFolderBackup]
    var workoutTemplates: [WorkoutTemplateBackup]
    var templateCardioBlocks: [TemplateCardioBlockBackup]
    var templateExercises: [TemplateExerciseBackup]
    var templateComponents: [TemplateComponentBackup]
    var templateSets: [TemplateSetBackup]
    var templateSupersetGroups: [TemplateSupersetGroupBackup]?
    var templateDropStages: [TemplateDropStageBackup]
    var workoutSessions: [WorkoutSessionBackup]
    var workoutSupersetGroups: [WorkoutSupersetGroupBackup]?
    var workoutCardioBlocks: [WorkoutCardioBlockBackup]
    var workoutExercises: [WorkoutExerciseBackup]
    var workoutSets: [WorkoutSetBackup]
    var workoutDropStages: [WorkoutDropStageBackup]

    init(context: ModelContext) throws {
        profiles = try context.fetch(FetchDescriptor<UserProfile>()).map(Profile.init)
        profileWidgets = try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).map(ProfileWidget.init)
        customExercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>()).filter(\.isCustomExercise).map(CustomExercise.init)
        templateFolders = try context.fetch(FetchDescriptor<TemplateFolder>()).map(TemplateFolderBackup.init)
        workoutTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(WorkoutTemplateBackup.init)
        templateCardioBlocks = try context.fetch(FetchDescriptor<TemplateCardioBlock>()).map(TemplateCardioBlockBackup.init)
        templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>()).map(TemplateExerciseBackup.init)
        templateComponents = try context.fetch(FetchDescriptor<TemplateExerciseComponent>()).map(TemplateComponentBackup.init)
        templateSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>()).map(TemplateSetBackup.init)
        templateSupersetGroups = try context.fetch(FetchDescriptor<TemplateSupersetGroup>()).map(TemplateSupersetGroupBackup.init)
        templateDropStages = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>()).map(TemplateDropStageBackup.init)
        let completedSessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.status == .completed }
        let completedSessionIDs = Set(completedSessions.map(\.id))
        let completedExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
            .filter { completedSessionIDs.contains($0.sessionID) }
        let completedExerciseIDs = Set(completedExercises.map(\.id))
        let completedSets = try context.fetch(FetchDescriptor<WorkoutSessionSet>())
            .filter { completedExerciseIDs.contains($0.sessionExerciseID) }
        let completedSetIDs = Set(completedSets.map(\.id))

        workoutSessions = completedSessions.map(WorkoutSessionBackup.init)
        workoutSupersetGroups = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
            .filter { completedSessionIDs.contains($0.sessionID) }
            .map(WorkoutSupersetGroupBackup.init)
        workoutCardioBlocks = try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>())
            .filter { completedSessionIDs.contains($0.sessionID) }
            .map(WorkoutCardioBlockBackup.init)
        workoutExercises = completedExercises.map(WorkoutExerciseBackup.init)
        workoutSets = completedSets.map(WorkoutSetBackup.init)
        workoutDropStages = try context.fetch(FetchDescriptor<WorkoutSessionDropStage>())
            .filter { completedSetIDs.contains($0.sessionSetID) }
            .map(WorkoutDropStageBackup.init)
    }

    var contentSummary: UserDataCloudBackupContentSummary {
        UserDataCloudBackupContentSummary(
            profileCount: profiles.count,
            profileWidgetCount: profileWidgets.count,
            customExerciseCount: customExercises.count,
            templateFolderCount: templateFolders.count,
            workoutTemplateCount: workoutTemplates.count,
            templateCardioBlockCount: templateCardioBlocks.count,
            templateExerciseCount: templateExercises.count,
            templateComponentCount: templateComponents.count,
            templateSetCount: templateSets.count,
            templateDropStageCount: templateDropStages.count,
            completedWorkoutCount: workoutSessions.count,
            workoutCardioBlockCount: workoutCardioBlocks.count,
            workoutExerciseCount: workoutExercises.count,
            workoutSetCount: workoutSets.count,
            workoutDropStageCount: workoutDropStages.count
        )
    }

    func mergeIntoLocalStore(in context: ModelContext) throws {
        try upsertProfiles(in: context)
        try upsertProfileWidgets(in: context)
        try upsertCustomExercises(in: context)
        try upsertTemplateFolders(in: context)
        try upsertWorkoutTemplates(in: context)
        try upsertTemplateCardioBlocks(in: context)
        try upsertTemplateExercises(in: context)
        try upsertTemplateComponents(in: context)
        try upsertTemplateSets(in: context)
        try upsertTemplateSupersetGroups(in: context)
        try upsertTemplateDropStages(in: context)
        try upsertWorkoutSessions(in: context)
        try upsertWorkoutSupersetGroups(in: context)
        try upsertWorkoutCardioBlocks(in: context)
        try upsertWorkoutExercises(in: context)
        try upsertWorkoutSets(in: context)
        try upsertWorkoutDropStages(in: context)
        try relinkSupersetRelationships(in: context)
    }

    private func upsertProfiles(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<UserProfile>()).map { ($0.id, $0) })
        for item in profiles {
            if let model = existing[item.id] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertProfileWidgets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).map { ($0.id, $0) })
        for item in profileWidgets {
            if let model = existing[item.id] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertCustomExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExerciseCatalogItem>()).map { ($0.remoteUUID, $0) })
        for item in customExercises {
            if let model = existing[item.remoteUUID] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertTemplateFolders(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateFolder>()).map { ($0.id, $0) })
        for item in templateFolders {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutTemplates(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map { ($0.id, $0) })
        for item in workoutTemplates {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateCardioBlocks(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateCardioBlock>()).map { ($0.id, $0) })
        for item in templateCardioBlocks {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExercise>()).map { ($0.id, $0) })
        for item in templateExercises {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateComponents(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseComponent>()).map { ($0.id, $0) })
        for item in templateComponents {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateSets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseSet>()).map { ($0.id, $0) })
        for item in templateSets {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateSupersetGroups(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateSupersetGroup>()).map { ($0.id, $0) })
        for item in templateSupersetGroups ?? [] {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateDropStages(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseDropStage>()).map { ($0.id, $0) })
        for item in templateDropStages {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSessions(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.id, $0) })
        for item in workoutSessions {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSupersetGroups(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>()).map { ($0.id, $0) })
        for item in workoutSupersetGroups ?? [] {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutCardioBlocks(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>()).map { ($0.id, $0) })
        for item in workoutCardioBlocks {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionExercise>()).map { ($0.id, $0) })
        for item in workoutExercises {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSet>()).map { ($0.id, $0) })
        for item in workoutSets {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutDropStages(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionDropStage>()).map { ($0.id, $0) })
        for item in workoutDropStages {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func relinkSupersetRelationships(in context: ModelContext) throws {
        let templatesByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map { ($0.id, $0) })
        let templateGroupsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateSupersetGroup>()).map { ($0.id, $0) })
        for group in templateGroupsByID.values {
            group.template = templatesByID[group.templateID]
        }
        for exercise in try context.fetch(FetchDescriptor<TemplateExercise>()) {
            exercise.supersetGroup = exercise.supersetGroupID.flatMap { templateGroupsByID[$0] }
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.id, $0) })
        let workoutGroupsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>()).map { ($0.id, $0) })
        for group in workoutGroupsByID.values {
            group.session = sessionsByID[group.sessionID]
        }
        for exercise in try context.fetch(FetchDescriptor<WorkoutSessionExercise>()) {
            exercise.supersetGroup = exercise.supersetGroupID.flatMap { workoutGroupsByID[$0] }
        }
    }
}

private protocol BackupModel {
    associatedtype Model
    nonisolated var model: Model { get }
    nonisolated func apply(to model: Model)
}

private struct Profile: Codable, BackupModel {
    var id: UUID
    var displayName: String
    var athleteTypeRaw: String?
    var avatarImageData: Data?
    var preferredWeightUnitRaw: String
    var workoutNotificationStyleRaw: String
    var weeklyWorkoutGoal: Int
    var isTrainingGuidanceEnabled: Bool
    var keepsScreenAwake: Bool
    var isBozarModeEnabled: Bool?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: UserProfile) {
        id = model.id
        displayName = model.displayName
        athleteTypeRaw = model.athleteTypeRaw
        avatarImageData = model.avatarImageData
        preferredWeightUnitRaw = model.preferredWeightUnitRaw
        workoutNotificationStyleRaw = model.workoutNotificationStyleRaw
        weeklyWorkoutGoal = model.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = model.isTrainingGuidanceEnabled
        keepsScreenAwake = model.keepsScreenAwake
        isBozarModeEnabled = model.isBozarModeEnabled
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            athleteType: athleteTypeRaw.flatMap(ProfileAthleteType.init(rawValue:)),
            avatarImageData: avatarImageData,
            preferredWeightUnit: PreferredWeightUnit(rawValue: preferredWeightUnitRaw) ?? .kg,
            workoutNotificationStyle: WorkoutNotificationStyle(rawValue: workoutNotificationStyleRaw) ?? .timeSensitive,
            weeklyWorkoutGoal: weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
            keepsScreenAwake: keepsScreenAwake,
            isBozarModeEnabled: isBozarModeEnabled ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: UserProfile) {
        model.displayName = displayName
        model.athleteTypeRaw = athleteTypeRaw
        model.avatarImageData = avatarImageData
        model.preferredWeightUnitRaw = preferredWeightUnitRaw
        model.workoutNotificationStyleRaw = workoutNotificationStyleRaw
        model.weeklyWorkoutGoal = weeklyWorkoutGoal
        model.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        model.keepsScreenAwake = keepsScreenAwake
        model.isBozarModeEnabled = isBozarModeEnabled ?? false
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct ProfileWidget: Codable, BackupModel {
    var id: UUID
    var kindRaw: String
    var isEnabled: Bool
    var selectedCatalogExerciseUUID: String?
    var selectedExerciseNameSnapshot: String?
    var exerciseTrendMetricRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: ProfileWidgetConfig) {
        id = model.id
        kindRaw = model.kindRaw
        isEnabled = model.isEnabled
        selectedCatalogExerciseUUID = model.selectedCatalogExerciseUUID
        selectedExerciseNameSnapshot = model.selectedExerciseNameSnapshot
        exerciseTrendMetricRaw = model.exerciseTrendMetricRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: ProfileWidgetConfig {
        ProfileWidgetConfig(
            id: id,
            kind: ProfileWidgetKind(rawValue: kindRaw) ?? .prs,
            isEnabled: isEnabled,
            selectedCatalogExerciseUUID: selectedCatalogExerciseUUID,
            selectedExerciseNameSnapshot: selectedExerciseNameSnapshot,
            exerciseTrendMetric: exerciseTrendMetricRaw.flatMap(ProfileExerciseTrendMetric.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: ProfileWidgetConfig) {
        model.kindRaw = kindRaw
        model.isEnabled = isEnabled
        model.selectedCatalogExerciseUUID = selectedCatalogExerciseUUID
        model.selectedExerciseNameSnapshot = selectedExerciseNameSnapshot
        model.exerciseTrendMetricRaw = exerciseTrendMetricRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct CustomExercise: Codable, BackupModel {
    var remoteUUID: String
    var remoteID: Int?
    var displayName: String
    var categoryName: String
    var equipmentSummary: String
    var instructionText: String?
    var isHidden: Bool
    var lastUpdateGlobal: Date?
    var updatedAt: Date

    nonisolated init(_ model: ExerciseCatalogItem) {
        remoteUUID = model.remoteUUID
        remoteID = model.remoteID
        displayName = model.displayName
        categoryName = model.categoryName
        equipmentSummary = model.equipmentSummary
        instructionText = model.instructionText
        isHidden = model.isHidden
        lastUpdateGlobal = model.lastUpdateGlobal
        updatedAt = model.updatedAt
    }

    nonisolated var model: ExerciseCatalogItem {
        ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            remoteID: remoteID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            instructionText: instructionText,
            isCurated: false,
            isHidden: isHidden,
            sourceName: "custom",
            lastUpdateGlobal: lastUpdateGlobal,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: ExerciseCatalogItem) {
        model.remoteID = remoteID
        model.displayName = displayName
        model.categoryName = categoryName
        model.equipmentSummary = equipmentSummary
        model.instructionText = instructionText
        model.isHidden = isHidden
        model.lastUpdateGlobal = lastUpdateGlobal
        model.updatedAt = updatedAt
    }
}

private struct TemplateFolderBackup: Codable, BackupModel {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateFolder) {
        id = model.id
        name = model.name
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateFolder {
        TemplateFolder(id: id, name: name, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    nonisolated func apply(to model: TemplateFolder) {
        model.name = name
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutTemplateBackup: Codable, BackupModel {
    var id: UUID
    var folderID: UUID
    var name: String
    var notes: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutTemplate) {
        id = model.id
        folderID = model.folderID
        name = model.name
        notes = model.notes
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutTemplate {
        WorkoutTemplate(id: id, folderID: folderID, name: name, notes: notes, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    nonisolated func apply(to model: WorkoutTemplate) {
        model.folderID = folderID
        model.name = name
        model.notes = notes
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateCardioBlockBackup: Codable, BackupModel {
    var id: UUID
    var templateID: UUID
    var phaseRaw: String
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetDurationSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateCardioBlock) {
        id = model.id
        templateID = model.templateID
        phaseRaw = model.phaseRaw
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        targetDurationSeconds = model.targetDurationSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateCardioBlock {
        TemplateCardioBlock(
            id: id,
            templateID: templateID,
            phase: WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            targetDurationSeconds: targetDurationSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateCardioBlock) {
        model.templateID = templateID
        model.phaseRaw = phaseRaw
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.targetDurationSeconds = targetDurationSeconds
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateExerciseBackup: Codable, BackupModel {
    var id: UUID
    var templateID: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExercise) {
        id = model.id
        templateID = model.templateID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        notes = model.notes
        targetRepMin = model.targetRepMin
        targetRepMax = model.targetRepMax
        restSeconds = model.restSeconds
        supersetGroupID = model.supersetGroupID
        supersetPositionRaw = model.supersetPositionRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExercise {
        TemplateExercise(
            id: id,
            templateID: templateID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            supersetGroupID: supersetGroupID,
            supersetPosition: supersetPositionRaw.flatMap(SupersetExercisePosition.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExercise) {
        model.templateID = templateID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.notes = notes
        model.targetRepMin = targetRepMin
        model.targetRepMax = targetRepMax
        model.restSeconds = restSeconds
        model.supersetGroupID = supersetGroupID
        model.supersetPositionRaw = supersetPositionRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateComponentBackup: Codable, BackupModel {
    var id: UUID
    var templateExerciseID: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseComponent) {
        id = model.id
        templateExerciseID = model.templateExerciseID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseComponent {
        TemplateExerciseComponent(
            id: id,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseComponent) {
        model.templateExerciseID = templateExerciseID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateSetBackup: Codable, BackupModel {
    var id: UUID
    var templateExerciseID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String
    var restSeconds: Int
    var isWarmup: Bool
    var isLocked: Bool
    var previousTargetReps: Int?
    var previousTargetWeight: Double?
    var previousLoadUnitRaw: String
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseSet) {
        id = model.id
        templateExerciseID = model.templateExerciseID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        loadUnitRaw = model.loadUnitRaw
        restSeconds = model.restSeconds
        isWarmup = model.isWarmup
        isLocked = model.isLocked
        previousTargetReps = model.previousTargetReps
        previousTargetWeight = model.previousTargetWeight
        previousLoadUnitRaw = model.previousLoadUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseSet {
        TemplateExerciseSet(
            id: id,
            templateExerciseID: templateExerciseID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            loadUnit: TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            isLocked: isLocked,
            previousTargetReps: previousTargetReps,
            previousTargetWeight: previousTargetWeight,
            previousLoadUnit: TemplateLoadUnit(rawValue: previousLoadUnitRaw) ?? .kg,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseSet) {
        model.templateExerciseID = templateExerciseID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.loadUnitRaw = loadUnitRaw
        model.restSeconds = restSeconds
        model.isWarmup = isWarmup
        model.isLocked = isLocked
        model.previousTargetReps = previousTargetReps
        model.previousTargetWeight = previousTargetWeight
        model.previousLoadUnitRaw = previousLoadUnitRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateSupersetGroupBackup: Codable, BackupModel {
    var id: UUID
    var templateID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateSupersetGroup) {
        id = model.id
        templateID = model.templateID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateSupersetGroup {
        TemplateSupersetGroup(
            id: id,
            templateID: templateID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateSupersetGroup) {
        model.templateID = templateID
        model.roundRestSeconds = roundRestSeconds
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct TemplateDropStageBackup: Codable, BackupModel {
    var id: UUID
    var templateExerciseSetID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseDropStage) {
        id = model.id
        templateExerciseSetID = model.templateExerciseSetID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        loadUnitRaw = model.loadUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseDropStage {
        TemplateExerciseDropStage(
            id: id,
            templateExerciseSetID: templateExerciseSetID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            loadUnit: TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseDropStage) {
        model.templateExerciseSetID = templateExerciseSetID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.loadUnitRaw = loadUnitRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutSessionBackup: Codable, BackupModel {
    var id: UUID
    var templateID: UUID?
    var name: String
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var totalVolume: Double
    var prHitsCount: Int
    var summaryMetricsVersion: Int
    var notes: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSession) {
        id = model.id
        templateID = model.templateID
        name = model.name
        statusRaw = model.statusRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        durationSeconds = model.durationSeconds
        totalVolume = model.totalVolume
        prHitsCount = model.prHitsCount
        summaryMetricsVersion = model.summaryMetricsVersion
        notes = model.notes
        archivedAt = model.archivedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSession {
        WorkoutSession(
            id: id,
            templateID: templateID,
            name: name,
            status: WorkoutSessionStatus(rawValue: statusRaw) ?? .completed,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalVolume: totalVolume,
            prHitsCount: prHitsCount,
            summaryMetricsVersion: summaryMetricsVersion,
            notes: notes,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSession) {
        model.templateID = templateID
        model.name = name
        model.statusRaw = statusRaw
        model.startedAt = startedAt
        model.endedAt = endedAt
        model.durationSeconds = durationSeconds
        model.totalVolume = totalVolume
        model.prHitsCount = prHitsCount
        model.summaryMetricsVersion = summaryMetricsVersion
        model.notes = notes
        model.archivedAt = archivedAt
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutSupersetGroupBackup: Codable, BackupModel {
    var id: UUID
    var sessionID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionSupersetGroup) {
        id = model.id
        sessionID = model.sessionID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionSupersetGroup {
        WorkoutSessionSupersetGroup(
            id: id,
            sessionID: sessionID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionSupersetGroup) {
        model.sessionID = sessionID
        model.roundRestSeconds = roundRestSeconds
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutCardioBlockBackup: Codable, BackupModel {
    var id: UUID
    var sessionID: UUID
    var phaseRaw: String
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetDurationSeconds: Int
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionCardioBlock) {
        id = model.id
        sessionID = model.sessionID
        phaseRaw = model.phaseRaw
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        targetDurationSeconds = model.targetDurationSeconds
        isCompleted = model.isCompleted
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionCardioBlock {
        WorkoutSessionCardioBlock(
            id: id,
            sessionID: sessionID,
            phase: WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            targetDurationSeconds: targetDurationSeconds,
            isCompleted: isCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionCardioBlock) {
        model.sessionID = sessionID
        model.phaseRaw = phaseRaw
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.targetDurationSeconds = targetDurationSeconds
        model.isCompleted = isCompleted
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutExerciseBackup: Codable, BackupModel {
    var id: UUID
    var sessionID: UUID
    var templateExerciseID: UUID?
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var totalSetCount: Int
    var completedSetCount: Int
    var hasDropsets: Bool
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionExercise) {
        id = model.id
        sessionID = model.sessionID
        templateExerciseID = model.templateExerciseID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        notes = model.notes
        targetRepMin = model.targetRepMin
        targetRepMax = model.targetRepMax
        restSeconds = model.restSeconds
        totalSetCount = model.totalSetCount
        completedSetCount = model.completedSetCount
        hasDropsets = model.hasDropsets
        supersetGroupID = model.supersetGroupID
        supersetPositionRaw = model.supersetPositionRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionExercise {
        WorkoutSessionExercise(
            id: id,
            sessionID: sessionID,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            totalSetCount: totalSetCount,
            completedSetCount: completedSetCount,
            hasDropsets: hasDropsets,
            supersetGroupID: supersetGroupID,
            supersetPosition: supersetPositionRaw.flatMap(SupersetExercisePosition.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionExercise) {
        model.sessionID = sessionID
        model.templateExerciseID = templateExerciseID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.notes = notes
        model.targetRepMin = targetRepMin
        model.targetRepMax = targetRepMax
        model.restSeconds = restSeconds
        model.updateSetSummary(totalSetCount: totalSetCount, completedSetCount: completedSetCount, hasDropsets: hasDropsets)
        model.supersetGroupID = supersetGroupID
        model.supersetPositionRaw = supersetPositionRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutSetBackup: Codable, BackupModel {
    var id: UUID
    var sessionExerciseID: UUID
    var sortOrder: Int
    var isWarmup: Bool
    var restSeconds: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String
    var isCompleted: Bool
    var isLocked: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionSet) {
        id = model.id
        sessionExerciseID = model.sessionExerciseID
        sortOrder = model.sortOrder
        isWarmup = model.isWarmup
        restSeconds = model.restSeconds
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        targetLoadUnitRaw = model.targetLoadUnitRaw
        actualReps = model.actualReps
        actualWeight = model.actualWeight
        actualLoadUnitRaw = model.actualLoadUnitRaw
        isCompleted = model.isCompleted
        isLocked = model.isLocked
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionSet {
        WorkoutSessionSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            sortOrder: sortOrder,
            isWarmup: isWarmup,
            restSeconds: restSeconds,
            targetReps: targetReps,
            targetWeight: targetWeight,
            targetLoadUnit: TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg,
            actualReps: actualReps,
            actualWeight: actualWeight,
            actualLoadUnit: TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg,
            isCompleted: isCompleted,
            isLocked: isLocked,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionSet) {
        model.sessionExerciseID = sessionExerciseID
        model.sortOrder = sortOrder
        model.isWarmup = isWarmup
        model.restSeconds = restSeconds
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.targetLoadUnitRaw = targetLoadUnitRaw
        model.actualReps = actualReps
        model.actualWeight = actualWeight
        model.actualLoadUnitRaw = actualLoadUnitRaw
        model.isCompleted = isCompleted
        model.isLocked = isLocked
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

private struct WorkoutDropStageBackup: Codable, BackupModel {
    var id: UUID
    var sessionSetID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionDropStage) {
        id = model.id
        sessionSetID = model.sessionSetID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        targetLoadUnitRaw = model.targetLoadUnitRaw
        actualReps = model.actualReps
        actualWeight = model.actualWeight
        actualLoadUnitRaw = model.actualLoadUnitRaw
        isCompleted = model.isCompleted
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionDropStage {
        WorkoutSessionDropStage(
            id: id,
            sessionSetID: sessionSetID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            targetLoadUnit: TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg,
            actualReps: actualReps,
            actualWeight: actualWeight,
            actualLoadUnit: TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg,
            isCompleted: isCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionDropStage) {
        model.sessionSetID = sessionSetID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.targetLoadUnitRaw = targetLoadUnitRaw
        model.actualReps = actualReps
        model.actualWeight = actualWeight
        model.actualLoadUnitRaw = actualLoadUnitRaw
        model.isCompleted = isCompleted
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}
