import CloudKit
import Foundation

extension CloudKitUserDataCloudBackupStore {
    nonisolated static let archiveHeadName = "current-user-data-backup-v3"
    private nonisolated static let deletionJournalName = "backup-deletion-v3"

    nonisolated func accountIdentifier() async throws -> String {
        guard let cloudContainer else { throw CloudKitContainerAvailabilityError.unavailable }
        return try await WGJPerformance.measureAsync("backup.cloud.account") {
            try await cloudContainer.userRecordID().recordName
        }
    }

    nonisolated func fetchManifest() async throws -> BackupManifest? {
        guard let head = try await existingRecord(
            recordID: CKRecord.ID(recordName: Self.archiveHeadName),
            desiredKeys: UserDataCloudBackupDescriptor.metadataFieldKeys
        ), let generation = try generation(in: head) else { return nil }
        guard let result = try await manifest(named: "backup-generation-v3-\(generation)") else {
            throw BackupArchiveError.missingChunk
        }
        guard result.generation == generation else { throw BackupArchiveError.invalidManifest }
        return result
    }

    nonisolated func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        guard let record = try await existingRecord(
            recordID: CKRecord.ID(recordName: Self.archiveHeadName),
            desiredKeys: UserDataCloudBackupDescriptor.metadataFieldKeys
        ) else { return try await fetchLegacyBackupMetadata() }
        guard let bytes = record[UserDataCloudBackupDescriptor.Field.contentSummary] as? Data else {
            throw BackupArchiveError.invalidManifest
        }
        return try JSONDecoder().decode(UserDataCloudBackupRemoteMetadata.self, from: bytes)
    }

    nonisolated func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard let manifest = try await fetchManifest() else { return try await fetchLegacyBackup() }
        return try await restoreRecord(manifest)
    }

    nonisolated func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard let current = try await fetchManifest() else { return nil }
        guard let previous = current.previousGenerations.first else { return try await fetchLegacyBackup() }
        guard let snapshot = try await manifest(named: "backup-generation-v3-\(previous)") else { throw BackupArchiveError.missingChunk }
        return try await restoreRecord(snapshot)
    }

    nonisolated func restoreRecord(_ manifest: BackupManifest) async throws -> UserDataCloudBackupRemoteRecord {
        try manifest.validate()
        let combiner = UserDataBackupPayloadCodec.Combiner()
        let database = try requireDatabase()
        progress(.downloading, completed: 0, total: manifest.chunks.count)
        for offset in stride(from: 0, to: manifest.chunks.count, by: 50) {
            try Task.checkCancellation()
            let references = manifest.chunks[offset..<min(offset + 50, manifest.chunks.count)]
            let ids = references.map { CKRecord.ID(recordName: $0.recordName) }
            let records = try await Self.requiredArchiveRecords(recordIDs: ids) {
                try await database.records(for: ids, desiredKeys: [UserDataCloudBackupDescriptor.Field.payloadAsset])
            }
            for reference in references {
                guard let record = records[CKRecord.ID(recordName: reference.recordName)] else { throw BackupArchiveError.missingChunk }
                let data = try BackupArchiveCodec.decode(assetData(record))
                guard BackupArchiveCodec.digest(data) == reference.digest else { throw BackupArchiveError.corruptChunk }
                try combiner.append(data)
            }
            progress(.downloading, completed: min(offset + 50, manifest.chunks.count), total: manifest.chunks.count)
        }
        return UserDataCloudBackupRemoteRecord(
            updatedAt: manifest.updatedAt,
            payloadData: try combiner.finish(generatedAt: manifest.updatedAt),
            contentSummary: manifest.summary, generation: manifest.generation
        )
    }

    /// Every referenced chunk is required. Unlike a head lookup, an absent chunk
    /// is a broken archive, not a transport failure to retry on each foreground.
    nonisolated static func requiredArchiveRecords(
        recordIDs: [CKRecord.ID],
        fetch: () async throws -> [CKRecord.ID: Result<CKRecord, Error>]
    ) async throws -> [CKRecord.ID: CKRecord] {
        do {
            let records = try resolveRecords(await fetch(), requestedIDs: recordIDs)
            guard recordIDs.allSatisfy({ records[$0] != nil }) else { throw BackupArchiveError.missingChunk }
            return records
        } catch let error as CKError where error.code == .unknownItem {
            throw BackupArchiveError.missingChunk
        }
    }

    /// Uses only fields already present on WGJUserDataBackup. No new server indexes or subscriptions.
    nonisolated func saveArchive(
        _ manifest: BackupManifest,
        chunkFiles: [String: URL],
        expectedGeneration: String?,
        expectedAccount: String
    ) async throws {
        try manifest.validate()
        guard try await accountIdentifier() == expectedAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
        let database = try requireDatabase()
        let headID = CKRecord.ID(recordName: Self.archiveHeadName)
        let deletionID = CKRecord.ID(recordName: Self.deletionJournalName)
        let pointers = try await existingRecords(
            recordIDs: [headID, deletionID], desiredKeys: UserDataCloudBackupDescriptor.metadataFieldKeys
        )
        guard pointers[deletionID] == nil else { throw UserDataCloudBackupSafetyError.deletionPending }
        let head = pointers[headID]
        let currentGeneration = try generation(in: head)
        guard currentGeneration == expectedGeneration else { throw UserDataCloudBackupSafetyError.remoteChanged }

        // Files are bounded to changed aggregates and uploaded in small batches.
        let files = chunkFiles.sorted { $0.key < $1.key }
        progress(.uploading, completed: 0, total: files.count)
        for offset in stride(from: 0, to: files.count, by: 50) {
            try Task.checkCancellation()
            guard try await accountIdentifier() == expectedAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
            let records = files[offset..<min(offset + 50, files.count)].map { name, url in
                let record = CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: CKRecord.ID(recordName: name))
                record[UserDataCloudBackupDescriptor.Field.payloadAsset] = CKAsset(fileURL: url)
                record[UserDataCloudBackupDescriptor.Field.updatedAt] = manifest.updatedAt as CKRecordValue
                record[UserDataCloudBackupDescriptor.Field.schemaVersion] = 3 as CKRecordValue
                return record
            }
            let results = try await WGJPerformance.measureAsync("backup.cloud.chunks") {
                try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            }
            for record in records {
                guard let result = results.saveResults[record.recordID] else { throw BackupArchiveError.missingChunk }
                _ = try result.get()
            }
            progress(.uploading, completed: min(offset + 50, files.count), total: files.count)
        }

        progress(.finishing)
        let url = try BackupTemporaryFiles.write(BackupArchiveCodec.encode(BackupArchiveCodec.json(manifest)), prefix: "WGJManifest-")
        defer { BackupTemporaryFiles.remove(url) }
        let generationRecord = CKRecord(
            recordType: UserDataCloudBackupDescriptor.recordType,
            recordID: CKRecord.ID(recordName: "backup-generation-v3-\(manifest.generation)")
        )
        let nextHead = head ?? CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: headID)
        let metadata = UserDataCloudBackupRemoteMetadata(
            updatedAt: manifest.updatedAt, contentSummary: manifest.summary, generation: manifest.generation
        )
        let metadataData = try BackupArchiveCodec.json(metadata)
        for record in [generationRecord, nextHead] {
            record[UserDataCloudBackupDescriptor.Field.updatedAt] = manifest.updatedAt as CKRecordValue
            record[UserDataCloudBackupDescriptor.Field.schemaVersion] = 3 as CKRecordValue
            record[UserDataCloudBackupDescriptor.Field.contentSummary] = metadataData as CKRecordValue
        }
        generationRecord[UserDataCloudBackupDescriptor.Field.payloadAsset] = CKAsset(fileURL: url)
        // The head is a small conditional pointer; do not upload a second manifest asset.
        nextHead[UserDataCloudBackupDescriptor.Field.payloadAsset] = nil
        guard try await accountIdentifier() == expectedAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
        try await requireNoPendingDeletion()
        // Save immutable recovery manifest first; CAS publication is the commit point.
        _ = try await WGJPerformance.measureAsync("backup.cloud.manifest") {
            try await database.save(generationRecord)
        }
        let results = try await WGJPerformance.measureAsync("backup.cloud.commit") {
            try await database.modifyRecords(saving: [nextHead], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        }
        guard let result = results.saveResults[headID] else { throw UserDataCloudBackupSafetyError.remoteChanged }
        _ = try result.get()
    }

    nonisolated func deleteBackup() async throws {
        try await deleteBackup(additionalRecordNames: [])
    }

    nonisolated func deleteBackup(additionalRecordNames: Set<String>) async throws {
        await BackupOperationGate.shared.acquire()
        defer { Task { await BackupOperationGate.shared.release() } }
        let database = try requireDatabase()
        let journalID = CKRecord.ID(recordName: Self.deletionJournalName)
        let existingJournal = try await existingRecord(recordID: journalID)
        var names = additionalRecordNames.union([Self.archiveHeadName, UserDataCloudBackupDescriptor.recordName])
        if let existingJournal {
            names.formUnion(try JSONDecoder().decode([String].self, from: BackupArchiveCodec.decode(assetData(existingJournal))))
        } else if let current = try await fetchManifest() {
            names.formUnion(current.chunks.map(\.recordName))
            names.insert("backup-generation-v3-\(current.generation)")
            names.formUnion(current.previousGenerations.map { "backup-generation-v3-\($0)" })
        }
        // Include retired/abandoned manifests remembered by this installation too.
        try await BackupManifestBatches.forEach(
            names.filter { $0.hasPrefix("backup-generation-v3-") },
            load: { try await manifests(named: $0) }
        ) { _, old in
            names.formUnion(old.chunks.map(\.recordName))
        }
        let url = try BackupTemporaryFiles.write(BackupArchiveCodec.encode(BackupArchiveCodec.json(names.sorted())), prefix: "WGJDeletion-")
        defer { BackupTemporaryFiles.remove(url) }
        let journal = existingJournal ?? CKRecord(recordType: UserDataCloudBackupDescriptor.recordType, recordID: journalID)
        journal[UserDataCloudBackupDescriptor.Field.payloadAsset] = CKAsset(fileURL: url)
        _ = try await database.save(journal)
        // Remove pointers first. The separate journal survives partial deletion and
        // permits an idempotent retry even when no current backup remains.
        let pointers: Set<String> = [Self.archiveHeadName, UserDataCloudBackupDescriptor.recordName]
        try await deleteRecords(named: names.intersection(pointers))
        try await deleteRecords(named: names.subtracting(pointers))
        try await deleteRecords(named: [Self.deletionJournalName])
    }

    private nonisolated func requireNoPendingDeletion() async throws {
        if try await existingRecord(recordID: CKRecord.ID(recordName: Self.deletionJournalName), desiredKeys: []) != nil {
            throw UserDataCloudBackupSafetyError.deletionPending
        }
    }

    nonisolated func removeOrphanedRecords(_ names: Set<String>, retaining current: BackupManifest) async throws {
        let trace = WGJPerformance.begin("backup.cloud.cleanup")
        defer { WGJPerformance.end(trace) }
        try await BackupRetentionCleanup.remove(names, retaining: current,
            loadManifests: { try await manifests(named: $0) },
            delete: { try await deleteRecords(named: $0) })
    }

    private nonisolated func deleteRecords(named names: Set<String>) async throws {
        let names = Array(names)
        let database = try requireDatabase()
        for offset in stride(from: 0, to: names.count, by: 100) {
            let ids = names[offset..<min(offset + 100, names.count)].map { CKRecord.ID(recordName: $0) }
            let result = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
            for id in ids {
                guard let deletion = result.deleteResults[id] else { throw BackupArchiveError.missingChunk }
                do { _ = try deletion.get() }
                catch let error as CKError where error.code == .unknownItem { continue }
            }
        }
    }

    private nonisolated func manifest(named name: String) async throws -> BackupManifest? {
        try await manifests(named: [name])[name]
    }

    private nonisolated func manifests(named names: Set<String>) async throws -> [String: BackupManifest] {
        guard !names.isEmpty else { return [:] }
        let records = try await existingRecords(
            recordIDs: names.sorted().map { CKRecord.ID(recordName: $0) },
            desiredKeys: [UserDataCloudBackupDescriptor.Field.payloadAsset]
        )
        var manifests: [String: BackupManifest] = [:]
        for (id, record) in records {
            let manifest = try JSONDecoder().decode(BackupManifest.self, from: BackupArchiveCodec.decode(assetData(record)))
            try manifest.validate()
            guard id.recordName == "backup-generation-v3-\(manifest.generation)" else {
                throw BackupArchiveError.invalidManifest
            }
            manifests[id.recordName] = manifest
        }
        return manifests
    }

    private nonisolated func generation(in record: CKRecord?) throws -> String? {
        guard let record else { return nil }
        guard let bytes = record[UserDataCloudBackupDescriptor.Field.contentSummary] as? Data,
              let generation = try JSONDecoder().decode(UserDataCloudBackupRemoteMetadata.self, from: bytes).generation
        else { throw BackupArchiveError.invalidManifest }
        return generation
    }

    private nonisolated func assetData(_ record: CKRecord) throws -> Data {
        guard let asset = record[UserDataCloudBackupDescriptor.Field.payloadAsset] as? CKAsset,
              let url = asset.fileURL else { throw BackupArchiveError.missingChunk }
        return try Data(contentsOf: url)
    }
}
