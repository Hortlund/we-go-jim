import CloudKit
import Foundation
import SwiftData

struct UserDataCloudBackupRemoteRecord: Equatable, Sendable {
    var updatedAt: Date
    var payloadData: Data
}

protocol UserDataCloudBackupStoring: Sendable {
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord?
}

nonisolated enum UserDataCloudBackupDescriptor {
    static let recordType = "WGJUserDataBackup"
    static let recordName = "current-user-data-backup-v1"

    enum Field {
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let payloadAsset = "payloadAsset"
        static let payloadData = "payloadData"
        static let payloadCompression = "payloadCompression"
    }
}

@MainActor
final class UserDataCloudBackupService {
    private let localContainer: ModelContainer
    private let mirrorContainer: ModelContainer
    private let backupStore: any UserDataCloudBackupStoring
    private let projectionScheduler: UserDataCloudMirrorBridge.ProjectionScheduler
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        localContainer: ModelContainer,
        mirrorContainer: ModelContainer,
        backupStore: any UserDataCloudBackupStoring,
        projectionScheduler: @escaping UserDataCloudMirrorBridge.ProjectionScheduler = { _, _ in }
    ) {
        self.localContainer = localContainer
        self.mirrorContainer = mirrorContainer
        self.backupStore = backupStore
        self.projectionScheduler = projectionScheduler
        encoder.outputFormatting = [.sortedKeys]
    }

    func exportCurrentBackup() async throws {
        try await mergeLatestBackupIntoMirrorIfAvailable()
        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer,
            projectionScheduler: projectionScheduler
        ).syncLocalChangesToMirror()

        let mirrorContext = ModelContext(mirrorContainer)
        let payload = try UserDataCloudBackupPayload(context: mirrorContext)
        let payloadData = try encoder.encode(payload)
        try await backupStore.saveBackup(UserDataCloudBackupRemoteRecord(
            updatedAt: payload.generatedAt,
            payloadData: payloadData
        ))
    }

    @discardableResult
    func restoreLatestBackup() async throws -> Bool {
        guard let record = try await backupStore.fetchBackup() else {
            return false
        }

        let payload = try decoder.decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        let mirrorContext = ModelContext(mirrorContainer)
        try payload.mergeIntoMirrorContents(in: mirrorContext)
        if mirrorContext.hasChanges {
            try mirrorContext.save()
        }

        try await UserDataCloudMirrorBridge(
            localContainer: localContainer,
            mirrorContainer: mirrorContainer,
            projectionScheduler: projectionScheduler
        ).syncLocalChangesToMirror()
        return true
    }

    private func mergeLatestBackupIntoMirrorIfAvailable() async throws {
        guard let record = try await backupStore.fetchBackup() else {
            return
        }

        let payload = try decoder.decode(UserDataCloudBackupPayload.self, from: record.payloadData)
        let mirrorContext = ModelContext(mirrorContainer)
        try payload.mergeIntoMirrorContents(in: mirrorContext)
        if mirrorContext.hasChanges {
            try mirrorContext.save()
        }
    }
}

struct CloudKitUserDataCloudBackupStore: UserDataCloudBackupStoring {
    private static let inlinePayloadFallbackLimitBytes = 900_000
    private static let lzfsePayloadCompression = "lzfse"

    private let database: CKDatabase?
    private let fileManager: FileManager

    init(container: CKContainer? = nil, fileManager: FileManager = .default) {
        self.database = (container ?? AppRuntimeConfig.makeCloudKitContainer())?.privateCloudDatabase
        self.fileManager = fileManager
    }

    func saveBackup(_ backup: UserDataCloudBackupRemoteRecord) async throws {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        let record = try await existingRecord(recordID: recordID)
            ?? CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: recordID)
        let payloadURL = try writeTemporaryPayload(backup.payloadData)
        defer {
            try? fileManager.removeItem(at: payloadURL)
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

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        let recordID = CKRecord.ID(recordName: UserDataCloudBackupDescriptor.recordName)
        guard let record = try await existingRecord(recordID: recordID) else {
            return nil
        }

        let updatedAt = record[UserDataCloudBackupDescriptor.Field.updatedAt] as? Date ?? .distantPast
        if let asset = record[UserDataCloudBackupDescriptor.Field.payloadAsset] as? CKAsset,
           let fileURL = asset.fileURL,
           let payloadData = try? Data(contentsOf: fileURL) {
            return UserDataCloudBackupRemoteRecord(
                updatedAt: updatedAt,
                payloadData: payloadData
            )
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
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WGJUserDataCloudBackups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func requireDatabase() throws -> CKDatabase {
        guard let database else {
            throw CloudKitContainerAvailabilityError.unavailable
        }
        return database
    }
}

@MainActor
private struct UserDataCloudBackupPayload: Codable {
    static let schemaVersion = 1

    var schemaVersion: Int = Self.schemaVersion
    var generatedAt: Date = Date()
    var profiles: [Profile]
    var tombstones: [Tombstone]
    var customExercises: [CustomExercise]
    var profileWidgets: [ProfileWidget]
    var blockedBros: [BlockedBroBackup]
    var templateFolders: [TemplateFolderBackup]
    var workoutTemplates: [WorkoutTemplateBackup]
    var templateSupersetGroups: [TemplateSupersetGroupBackup]
    var templateCardioBlocks: [TemplateCardioBlockBackup]
    var templateExercises: [TemplateExerciseBackup]
    var templateComponents: [TemplateComponentBackup]
    var templateSets: [TemplateSetBackup]
    var templateDropStages: [TemplateDropStageBackup]
    var workoutSessions: [WorkoutSessionBackup]
    var workoutSupersetGroups: [WorkoutSupersetGroupBackup]
    var workoutCardioBlocks: [WorkoutCardioBlockBackup]
    var workoutExercises: [WorkoutExerciseBackup]
    var workoutSets: [WorkoutSetBackup]
    var workoutDropStages: [WorkoutDropStageBackup]

    init(context: ModelContext) throws {
        profiles = try context.fetch(FetchDescriptor<UserProfile>()).map { Profile($0) }
        tombstones = try context.fetch(FetchDescriptor<UserDataDeletionTombstone>()).map { Tombstone($0) }
        customExercises = try context.fetch(FetchDescriptor<CustomExerciseCloudRecord>()).map { CustomExercise($0) }
        profileWidgets = try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).map { ProfileWidget($0) }
        blockedBros = try context.fetch(FetchDescriptor<BlockedBroCloudRecord>()).map { BlockedBroBackup($0) }
        templateFolders = try context.fetch(FetchDescriptor<TemplateFolder>()).map { TemplateFolderBackup($0) }
        workoutTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).map { WorkoutTemplateBackup($0) }
        templateSupersetGroups = try context.fetch(FetchDescriptor<TemplateSupersetGroup>())
            .map { TemplateSupersetGroupBackup($0) }
        templateCardioBlocks = try context.fetch(FetchDescriptor<TemplateCardioBlock>())
            .map { TemplateCardioBlockBackup($0) }
        templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>()).map { TemplateExerciseBackup($0) }
        templateComponents = try context.fetch(FetchDescriptor<TemplateExerciseComponent>())
            .map { TemplateComponentBackup($0) }
        templateSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>()).map { TemplateSetBackup($0) }
        templateDropStages = try context.fetch(FetchDescriptor<TemplateExerciseDropStage>())
            .map { TemplateDropStageBackup($0) }
        workoutSessions = try context.fetch(FetchDescriptor<WorkoutSession>()).map { WorkoutSessionBackup($0) }
        workoutSupersetGroups = try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>())
            .map { WorkoutSupersetGroupBackup($0) }
        workoutCardioBlocks = try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>())
            .map { WorkoutCardioBlockBackup($0) }
        workoutExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
            .map { WorkoutExerciseBackup($0) }
        workoutSets = try context.fetch(FetchDescriptor<WorkoutSessionSet>()).map { WorkoutSetBackup($0) }
        workoutDropStages = try context.fetch(FetchDescriptor<WorkoutSessionDropStage>())
            .map { WorkoutDropStageBackup($0) }
        compactInPlace()
    }

    private static func latestByKey<Item, Key: Hashable>(
        _ items: [Item],
        key: (Item) -> Key,
        isNewer: (Item, Item) -> Bool
    ) -> [Item] {
        Array(items.reduce(into: [Key: Item]()) { result, item in
            let itemKey = key(item)
            guard let existing = result[itemKey] else {
                result[itemKey] = item
                return
            }
            if isNewer(item, existing) {
                result[itemKey] = item
            }
        }.values)
    }

    func mergeIntoMirrorContents(in context: ModelContext) throws {
        let payload = compacted()
        if try payload.isMirrorEmpty(in: context) {
            try payload.replaceMirrorContents(in: context)
            return
        }

        try payload.mergeSimpleRecords(in: context)
        try payload.mergeTemplateAggregates(in: context)
        try payload.mergeWorkoutSessionAggregates(in: context)
    }

    private func compacted() -> Self {
        var copy = self
        copy.compactInPlace()
        return copy
    }

    private mutating func compactInPlace() {
        profiles = Self.latestByKey(
            profiles,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        tombstones = Self.latestByKey(
            tombstones,
            key: \.key,
            isNewer: { $0.deletedAt > $1.deletedAt }
        ).sorted { $0.key < $1.key }
        customExercises = Self.latestByKey(
            customExercises,
            key: \.remoteUUID,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.remoteUUID < $1.remoteUUID }
        profileWidgets = Self.latestByKey(
            profileWidgets,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        blockedBros = Self.latestByKey(
            blockedBros,
            key: \.userRecordName,
            isNewer: { $0.blockedAt > $1.blockedAt }
        ).sorted { $0.userRecordName < $1.userRecordName }
        templateFolders = Self.latestByKey(
            templateFolders,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutTemplates = Self.latestByKey(
            workoutTemplates,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateSupersetGroups = Self.latestByKey(
            templateSupersetGroups,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateCardioBlocks = Self.latestByKey(
            templateCardioBlocks,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateExercises = Self.latestByKey(
            templateExercises,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateComponents = Self.latestByKey(
            templateComponents,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateSets = Self.latestByKey(
            templateSets,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        templateDropStages = Self.latestByKey(
            templateDropStages,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutSessions = Self.latestByKey(
            workoutSessions,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutSupersetGroups = Self.latestByKey(
            workoutSupersetGroups,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutCardioBlocks = Self.latestByKey(
            workoutCardioBlocks,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutExercises = Self.latestByKey(
            workoutExercises,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutSets = Self.latestByKey(
            workoutSets,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
        workoutDropStages = Self.latestByKey(
            workoutDropStages,
            key: \.id,
            isNewer: { $0.updatedAt > $1.updatedAt }
        ).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func replaceMirrorContents(in context: ModelContext) throws {
        try clearMirrorContents(in: context)

        for item in customExercises {
            context.insert(item.model)
        }
        for item in blockedBros {
            context.insert(item.model)
        }
        for item in profiles {
            context.insert(item.model)
        }
        for item in profileWidgets {
            context.insert(item.model)
        }
        for item in tombstones {
            context.insert(item.model)
        }

        var folders: [UUID: TemplateFolder] = [:]
        for item in templateFolders {
            let model = item.model
            context.insert(model)
            folders[item.id] = model
        }

        var templates: [UUID: WorkoutTemplate] = [:]
        for item in workoutTemplates {
            let model = item.model(folder: folders[item.folderID])
            context.insert(model)
            templates[item.id] = model
        }

        var templateGroups: [UUID: TemplateSupersetGroup] = [:]
        for item in templateSupersetGroups {
            let model = item.model(template: templates[item.templateID])
            context.insert(model)
            templateGroups[item.id] = model
        }

        for item in templateCardioBlocks {
            context.insert(item.model(template: templates[item.templateID]))
        }

        var templateExerciseModels: [UUID: TemplateExercise] = [:]
        for item in templateExercises {
            let model = item.model(
                template: templates[item.templateID],
                supersetGroup: item.supersetGroupID.flatMap { templateGroups[$0] }
            )
            context.insert(model)
            templateExerciseModels[item.id] = model
        }

        for item in templateComponents {
            context.insert(item.model(templateExercise: templateExerciseModels[item.templateExerciseID]))
        }

        var templateSetModels: [UUID: TemplateExerciseSet] = [:]
        for item in templateSets {
            let model = item.model(templateExercise: templateExerciseModels[item.templateExerciseID])
            context.insert(model)
            templateSetModels[item.id] = model
        }

        for item in templateDropStages {
            context.insert(item.model(templateExerciseSet: templateSetModels[item.templateExerciseSetID]))
        }

        var sessions: [UUID: WorkoutSession] = [:]
        for item in workoutSessions {
            let model = item.model
            context.insert(model)
            sessions[item.id] = model
        }

        var workoutGroups: [UUID: WorkoutSessionSupersetGroup] = [:]
        for item in workoutSupersetGroups {
            let model = item.model(session: sessions[item.sessionID])
            context.insert(model)
            workoutGroups[item.id] = model
        }

        for item in workoutCardioBlocks {
            context.insert(item.model(session: sessions[item.sessionID]))
        }

        var workoutExerciseModels: [UUID: WorkoutSessionExercise] = [:]
        for item in workoutExercises {
            let model = item.model(
                session: sessions[item.sessionID],
                supersetGroup: item.supersetGroupID.flatMap { workoutGroups[$0] }
            )
            context.insert(model)
            workoutExerciseModels[item.id] = model
        }

        var workoutSetModels: [UUID: WorkoutSessionSet] = [:]
        for item in workoutSets {
            let model = item.model(sessionExercise: workoutExerciseModels[item.sessionExerciseID])
            context.insert(model)
            workoutSetModels[item.id] = model
        }

        for item in workoutDropStages {
            context.insert(item.model(sessionSet: workoutSetModels[item.sessionSetID]))
        }
    }

    private func mergeSimpleRecords(in context: ModelContext) throws {
        try mergeCustomExercises(in: context)
        try mergeBlockedBros(in: context)
        try mergeProfiles(in: context)
        try mergeProfileWidgets(in: context)
        try mergeTombstones(in: context)
        try mergeTemplateFolders(in: context)
    }

    private func mergeCustomExercises(in context: ModelContext) throws {
        let existingRecords = try context.fetch(FetchDescriptor<CustomExerciseCloudRecord>())
        for item in customExercises {
            if let existing = existingRecords.first(where: { $0.remoteUUID == item.remoteUUID }) {
                guard item.updatedAt > existing.updatedAt else { continue }
                context.delete(existing)
            }
            context.insert(item.model)
        }
    }

    private func mergeBlockedBros(in context: ModelContext) throws {
        let existingRecords = try context.fetch(FetchDescriptor<BlockedBroCloudRecord>())
        for item in blockedBros {
            if let existing = existingRecords.first(where: { $0.userRecordName == item.userRecordName }) {
                guard item.blockedAt > existing.blockedAt else { continue }
                context.delete(existing)
            }
            context.insert(item.model)
        }
    }

    private func mergeProfiles(in context: ModelContext) throws {
        let existingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        for item in profiles {
            let model = item.model
            if let existing = existingProfiles.first {
                guard shouldPreferProfile(model, over: existing) else { continue }
                for profile in existingProfiles {
                    context.delete(profile)
                }
            }
            context.insert(model)
        }
    }

    private func mergeProfileWidgets(in context: ModelContext) throws {
        let existingConfigs = try context.fetch(FetchDescriptor<ProfileWidgetConfig>())
        for item in profileWidgets {
            if let existing = existingConfigs.first(where: { $0.id == item.id }) {
                guard item.updatedAt > existing.updatedAt else { continue }
                context.delete(existing)
            }
            context.insert(item.model)
        }
    }

    private func mergeTombstones(in context: ModelContext) throws {
        let existingTombstones = try context.fetch(FetchDescriptor<UserDataDeletionTombstone>())
        for item in tombstones {
            if let existing = existingTombstones.first(where: { tombstoneKey($0) == item.key }) {
                guard item.deletedAt > existing.deletedAt else { continue }
                context.delete(existing)
            }
            context.insert(item.model)
        }
    }

    private func mergeTemplateFolders(in context: ModelContext) throws {
        let existingFolders = try context.fetch(FetchDescriptor<TemplateFolder>())
        for item in templateFolders {
            if let existing = existingFolders.first(where: { $0.id == item.id }) {
                guard item.updatedAt > existing.updatedAt else { continue }
                context.delete(existing)
            }
            context.insert(item.model)
        }
    }

    private func mergeTemplateAggregates(in context: ModelContext) throws {
        let existingTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        for item in workoutTemplates {
            if let existing = existingTemplates.first(where: { $0.id == item.id }) {
                guard item.updatedAt > existing.updatedAt else { continue }
                try deleteTemplateAggregate(id: item.id, in: context)
            }
            try insertTemplateAggregate(item, in: context)
        }
    }

    private func insertTemplateAggregate(_ item: WorkoutTemplateBackup, in context: ModelContext) throws {
        let folders = newestFolderByID(try context.fetch(FetchDescriptor<TemplateFolder>()))
        let model = item.model(folder: folders[item.folderID])
        context.insert(model)
        var templateGroups: [UUID: TemplateSupersetGroup] = [:]
        for groupItem in templateSupersetGroups where groupItem.templateID == item.id {
            let group = groupItem.model(template: model)
            context.insert(group)
            templateGroups[groupItem.id] = group
        }
        for cardioItem in templateCardioBlocks where cardioItem.templateID == item.id {
            context.insert(cardioItem.model(template: model))
        }
        var exercises: [UUID: TemplateExercise] = [:]
        for exerciseItem in templateExercises where exerciseItem.templateID == item.id {
            let exercise = exerciseItem.model(
                template: model,
                supersetGroup: exerciseItem.supersetGroupID.flatMap { templateGroups[$0] }
            )
            context.insert(exercise)
            exercises[exerciseItem.id] = exercise
        }
        for componentItem in templateComponents where exercises[componentItem.templateExerciseID] != nil {
            context.insert(componentItem.model(templateExercise: exercises[componentItem.templateExerciseID]))
        }
        var sets: [UUID: TemplateExerciseSet] = [:]
        for setItem in templateSets where exercises[setItem.templateExerciseID] != nil {
            let set = setItem.model(templateExercise: exercises[setItem.templateExerciseID])
            context.insert(set)
            sets[setItem.id] = set
        }
        for stageItem in templateDropStages where sets[stageItem.templateExerciseSetID] != nil {
            context.insert(stageItem.model(templateExerciseSet: sets[stageItem.templateExerciseSetID]))
        }
    }

    private func mergeWorkoutSessionAggregates(in context: ModelContext) throws {
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        for item in workoutSessions {
            if let existing = existingSessions.first(where: { $0.id == item.id }) {
                guard item.updatedAt > existing.updatedAt else { continue }
                try deleteWorkoutSessionAggregate(id: item.id, in: context)
            }
            try insertWorkoutSessionAggregate(item, in: context)
        }
    }

    private func insertWorkoutSessionAggregate(_ item: WorkoutSessionBackup, in context: ModelContext) throws {
        let model = item.model
        context.insert(model)
        var workoutGroups: [UUID: WorkoutSessionSupersetGroup] = [:]
        for groupItem in workoutSupersetGroups where groupItem.sessionID == item.id {
            let group = groupItem.model(session: model)
            context.insert(group)
            workoutGroups[groupItem.id] = group
        }
        for cardioItem in workoutCardioBlocks where cardioItem.sessionID == item.id {
            context.insert(cardioItem.model(session: model))
        }
        var exercises: [UUID: WorkoutSessionExercise] = [:]
        for exerciseItem in workoutExercises where exerciseItem.sessionID == item.id {
            let exercise = exerciseItem.model(
                session: model,
                supersetGroup: exerciseItem.supersetGroupID.flatMap { workoutGroups[$0] }
            )
            context.insert(exercise)
            exercises[exerciseItem.id] = exercise
        }
        var sets: [UUID: WorkoutSessionSet] = [:]
        for setItem in workoutSets where exercises[setItem.sessionExerciseID] != nil {
            let set = setItem.model(sessionExercise: exercises[setItem.sessionExerciseID])
            context.insert(set)
            sets[setItem.id] = set
        }
        for stageItem in workoutDropStages where sets[stageItem.sessionSetID] != nil {
            context.insert(stageItem.model(sessionSet: sets[stageItem.sessionSetID]))
        }
    }

    private func isMirrorEmpty(in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<UserProfile>()).isEmpty
            && context.fetch(FetchDescriptor<UserDataDeletionTombstone>()).isEmpty
            && context.fetch(FetchDescriptor<CustomExerciseCloudRecord>()).isEmpty
            && context.fetch(FetchDescriptor<ProfileWidgetConfig>()).isEmpty
            && context.fetch(FetchDescriptor<BlockedBroCloudRecord>()).isEmpty
            && context.fetch(FetchDescriptor<TemplateFolder>()).isEmpty
            && context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty
            && context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty
    }

    private func clearMirrorContents(in context: ModelContext) throws {
        try deleteAll(WorkoutSessionDropStage.self, in: context)
        try deleteAll(WorkoutSessionSet.self, in: context)
        try deleteAll(WorkoutSessionExercise.self, in: context)
        try deleteAll(WorkoutSessionCardioBlock.self, in: context)
        try deleteAll(WorkoutSessionSupersetGroup.self, in: context)
        try deleteAll(WorkoutSession.self, in: context)
        try deleteAll(TemplateExerciseDropStage.self, in: context)
        try deleteAll(TemplateExerciseSet.self, in: context)
        try deleteAll(TemplateExerciseComponent.self, in: context)
        try deleteAll(TemplateExercise.self, in: context)
        try deleteAll(TemplateCardioBlock.self, in: context)
        try deleteAll(TemplateSupersetGroup.self, in: context)
        try deleteAll(WorkoutTemplate.self, in: context)
        try deleteAll(TemplateFolder.self, in: context)
        try deleteAll(ProfileWidgetConfig.self, in: context)
        try deleteAll(UserProfile.self, in: context)
        try deleteAll(BlockedBroCloudRecord.self, in: context)
        try deleteAll(CustomExerciseCloudRecord.self, in: context)
        try deleteAll(UserDataDeletionTombstone.self, in: context)
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }

    private func shouldPreferProfile(_ candidate: UserProfile, over other: UserProfile) -> Bool {
        let candidateIsUntouchedBootstrap = isUntouchedBootstrapProfile(candidate)
        let otherIsUntouchedBootstrap = isUntouchedBootstrapProfile(other)

        if candidateIsUntouchedBootstrap != otherIsUntouchedBootstrap {
            return !candidateIsUntouchedBootstrap
        }

        return candidate.updatedAt >= other.updatedAt
    }

    private func isUntouchedBootstrapProfile(_ profile: UserProfile) -> Bool {
        abs(profile.updatedAt.timeIntervalSince(profile.createdAt)) <= 1
            && profile.athleteTypeRaw == nil
            && profile.avatarImageData == nil
            && profile.preferredWeightUnitRaw == PreferredWeightUnit.kg.rawValue
            && profile.workoutNotificationStyleRaw == WorkoutNotificationStyle.timeSensitive.rawValue
            && profile.weeklyWorkoutGoal == 4
            && profile.isTrainingGuidanceEnabled
            && !profile.keepsScreenAwake
            && !profile.isBozarModeEnabled
            && profile.brosCircleID == nil
            && profile.brosMembershipID == nil
            && profile.brosUserRecordName == nil
            && profile.brosJoinedAt == nil
            && profile.brosRoleRaw == nil
    }

    private func newestFolderByID(_ folders: [TemplateFolder]) -> [UUID: TemplateFolder] {
        folders.reduce(into: [:]) { result, folder in
            guard let existing = result[folder.id] else {
                result[folder.id] = folder
                return
            }
            if folder.updatedAt > existing.updatedAt {
                result[folder.id] = folder
            }
        }
    }

    private func deleteTemplateAggregate(id: UUID, in context: ModelContext) throws {
        for template in try context.fetch(FetchDescriptor<WorkoutTemplate>()) where template.id == id {
            context.delete(template)
        }
    }

    private func deleteWorkoutSessionAggregate(id: UUID, in context: ModelContext) throws {
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) where session.id == id {
            context.delete(session)
        }
    }

    private func tombstoneKey(_ tombstone: UserDataDeletionTombstone) -> String {
        if let entityKey = tombstone.entityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityKey.isEmpty {
            return "\(tombstone.entityName):\(entityKey)"
        }
        return "\(tombstone.entityName):\(tombstone.entityID.uuidString)"
    }
}

private struct Profile: Codable {
    var id: UUID
    var displayName: String
    var athleteTypeRaw: String?
    var avatarImageData: Data?
    var preferredWeightUnitRaw: String
    var workoutNotificationStyleRaw: String
    var weeklyWorkoutGoal: Int
    var isTrainingGuidanceEnabled: Bool
    var keepsScreenAwake: Bool
    var isBozarModeEnabled: Bool
    var brosCircleID: String?
    var brosMembershipID: String?
    var brosUserRecordName: String?
    var brosJoinedAt: Date?
    var brosRoleRaw: String?
    var createdAt: Date
    var updatedAt: Date

    init(_ model: UserProfile) {
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
        brosCircleID = model.brosCircleID
        brosMembershipID = model.brosMembershipID
        brosUserRecordName = model.brosUserRecordName
        brosJoinedAt = model.brosJoinedAt
        brosRoleRaw = model.brosRoleRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    var model: UserProfile {
        let profile = UserProfile(
            id: id,
            displayName: displayName,
            athleteType: athleteTypeRaw.flatMap(ProfileAthleteType.init(rawValue:)),
            avatarImageData: avatarImageData,
            preferredWeightUnit: PreferredWeightUnit(rawValue: preferredWeightUnitRaw) ?? .kg,
            workoutNotificationStyle: WorkoutNotificationStyle(rawValue: workoutNotificationStyleRaw) ?? .timeSensitive,
            weeklyWorkoutGoal: weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
            keepsScreenAwake: keepsScreenAwake,
            isBozarModeEnabled: isBozarModeEnabled,
            brosCircleID: brosCircleID,
            brosMembershipID: brosMembershipID,
            brosUserRecordName: brosUserRecordName,
            brosJoinedAt: brosJoinedAt,
            brosRole: brosRoleRaw.flatMap(BroMembershipRole.init(rawValue:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        profile.athleteTypeRaw = athleteTypeRaw
        profile.preferredWeightUnitRaw = preferredWeightUnitRaw
        profile.workoutNotificationStyleRaw = workoutNotificationStyleRaw
        profile.brosRoleRaw = brosRoleRaw
        return profile
    }
}

private struct Tombstone: Codable {
    var id: UUID
    var entityName: String
    var entityID: UUID
    var entityKey: String?
    var deletedAt: Date
    var key: String { entityKey.map { "\(entityName):\($0)" } ?? "\(entityName):\(entityID.uuidString)" }

    init(_ model: UserDataDeletionTombstone) {
        id = model.id
        entityName = model.entityName
        entityID = model.entityID
        entityKey = model.entityKey
        deletedAt = model.deletedAt
    }

    var model: UserDataDeletionTombstone {
        UserDataDeletionTombstone(
            id: id,
            entityName: entityName,
            entityID: entityID,
            entityKey: entityKey,
            deletedAt: deletedAt
        )
    }
}

private struct CustomExercise: Codable {
    var id: UUID
    var remoteUUID: String
    var remoteID: Int?
    var displayName: String
    var categoryName: String
    var equipmentSummary: String
    var instructionText: String?
    var isHidden: Bool
    var lastUpdateGlobal: Date?
    var updatedAt: Date
    var aliasesData: Data?
    var primaryMusclesData: Data?
    var secondaryMusclesData: Data?

    init(_ model: CustomExerciseCloudRecord) {
        id = model.id
        remoteUUID = model.remoteUUID
        remoteID = model.remoteID
        displayName = model.displayName
        categoryName = model.categoryName
        equipmentSummary = model.equipmentSummary
        instructionText = model.instructionText
        isHidden = model.isHidden
        lastUpdateGlobal = model.lastUpdateGlobal
        updatedAt = model.updatedAt
        aliasesData = model.aliasesData
        primaryMusclesData = model.primaryMusclesData
        secondaryMusclesData = model.secondaryMusclesData
    }

    var model: CustomExerciseCloudRecord {
        CustomExerciseCloudRecord(
            id: id,
            remoteUUID: remoteUUID,
            remoteID: remoteID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            instructionText: instructionText,
            isHidden: isHidden,
            lastUpdateGlobal: lastUpdateGlobal,
            updatedAt: updatedAt,
            aliasesData: aliasesData,
            primaryMusclesData: primaryMusclesData,
            secondaryMusclesData: secondaryMusclesData
        )
    }
}

private struct ProfileWidget: Codable {
    var id: UUID
    var kindRaw: String
    var isEnabled: Bool
    var selectedCatalogExerciseUUID: String?
    var selectedExerciseNameSnapshot: String?
    var exerciseTrendMetricRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: ProfileWidgetConfig) {
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

    var model: ProfileWidgetConfig {
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
}

private struct BlockedBroBackup: Codable {
    var id: UUID
    var userRecordName: String
    var displayNameSnapshot: String
    var blockedAt: Date

    init(_ model: BlockedBroCloudRecord) {
        id = model.id
        userRecordName = model.userRecordName
        displayNameSnapshot = model.displayNameSnapshot
        blockedAt = model.blockedAt
    }

    var model: BlockedBroCloudRecord {
        BlockedBroCloudRecord(
            id: id,
            userRecordName: userRecordName,
            displayNameSnapshot: displayNameSnapshot,
            blockedAt: blockedAt
        )
    }
}

private struct TemplateFolderBackup: Codable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TemplateFolder) {
        id = model.id
        name = model.name
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    var model: TemplateFolder {
        TemplateFolder(id: id, name: name, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }
}

private struct WorkoutTemplateBackup: Codable {
    var id: UUID
    var folderID: UUID
    var name: String
    var notes: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: WorkoutTemplate) {
        id = model.id
        folderID = model.folderID
        name = model.name
        notes = model.notes
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func model(folder: TemplateFolder?) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            folderID: folderID,
            name: name,
            notes: notes,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            folder: folder
        )
    }
}

private struct TemplateSupersetGroupBackup: Codable {
    var id: UUID
    var templateID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TemplateSupersetGroup) {
        id = model.id
        templateID = model.templateID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func model(template: WorkoutTemplate?) -> TemplateSupersetGroup {
        TemplateSupersetGroup(
            id: id,
            templateID: templateID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt,
            template: template
        )
    }
}

private struct TemplateCardioBlockBackup: Codable {
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

    init(_ model: TemplateCardioBlock) {
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

    func model(template: WorkoutTemplate?) -> TemplateCardioBlock {
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
            updatedAt: updatedAt,
            template: template
        )
    }
}

private struct TemplateExerciseBackup: Codable {
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

    init(_ model: TemplateExercise) {
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

    func model(template: WorkoutTemplate?, supersetGroup: TemplateSupersetGroup?) -> TemplateExercise {
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
            updatedAt: updatedAt,
            template: template,
            supersetGroup: supersetGroup
        )
    }
}

private struct TemplateComponentBackup: Codable {
    var id: UUID
    var templateExerciseID: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TemplateExerciseComponent) {
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

    func model(templateExercise: TemplateExercise?) -> TemplateExerciseComponent {
        TemplateExerciseComponent(
            id: id,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            templateExercise: templateExercise
        )
    }
}

private struct TemplateSetBackup: Codable {
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

    init(_ model: TemplateExerciseSet) {
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

    func model(templateExercise: TemplateExercise?) -> TemplateExerciseSet {
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
            updatedAt: updatedAt,
            templateExercise: templateExercise
        )
    }
}

private struct TemplateDropStageBackup: Codable {
    var id: UUID
    var templateExerciseSetID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TemplateExerciseDropStage) {
        id = model.id
        templateExerciseSetID = model.templateExerciseSetID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        loadUnitRaw = model.loadUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func model(templateExerciseSet: TemplateExerciseSet?) -> TemplateExerciseDropStage {
        TemplateExerciseDropStage(
            id: id,
            templateExerciseSetID: templateExerciseSetID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            loadUnit: TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg,
            createdAt: createdAt,
            updatedAt: updatedAt,
            templateExerciseSet: templateExerciseSet
        )
    }
}

private struct WorkoutSessionBackup: Codable {
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

    init(_ model: WorkoutSession) {
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

    var model: WorkoutSession {
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
}

private struct WorkoutSupersetGroupBackup: Codable {
    var id: UUID
    var sessionID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: WorkoutSessionSupersetGroup) {
        id = model.id
        sessionID = model.sessionID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func model(session: WorkoutSession?) -> WorkoutSessionSupersetGroup {
        WorkoutSessionSupersetGroup(
            id: id,
            sessionID: sessionID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt,
            session: session
        )
    }
}

private struct WorkoutCardioBlockBackup: Codable {
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

    init(_ model: WorkoutSessionCardioBlock) {
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

    func model(session: WorkoutSession?) -> WorkoutSessionCardioBlock {
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
            updatedAt: updatedAt,
            session: session
        )
    }
}

private struct WorkoutExerciseBackup: Codable {
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

    init(_ model: WorkoutSessionExercise) {
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

    func model(session: WorkoutSession?, supersetGroup: WorkoutSessionSupersetGroup?) -> WorkoutSessionExercise {
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
            updatedAt: updatedAt,
            session: session,
            supersetGroup: supersetGroup
        )
    }
}

private struct WorkoutSetBackup: Codable {
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

    init(_ model: WorkoutSessionSet) {
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

    func model(sessionExercise: WorkoutSessionExercise?) -> WorkoutSessionSet {
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
            updatedAt: updatedAt,
            sessionExercise: sessionExercise
        )
    }
}

private struct WorkoutDropStageBackup: Codable {
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

    init(_ model: WorkoutSessionDropStage) {
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

    func model(sessionSet: WorkoutSessionSet?) -> WorkoutSessionDropStage {
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
            updatedAt: updatedAt,
            sessionSet: sessionSet
        )
    }
}
