import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class IncrementalBackupTests: XCTestCase {
    func testExplicitReplacementRecreatesBackupDeletedByAnotherDevice() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let old = try XCTUnwrap(BackupLocalJournal.state(for: container).manifest)
        try await store.deleteBackup() // A different device leaves this installation's journal intact.
        do { _ = try await service.exportCurrentBackup(); XCTFail("Automatic recreation must remain blocked") }
        catch UserDataCloudBackupSafetyError.remoteChanged { }
        _ = try await service.exportCurrentBackup(replacingRemote: true)
        let recreated = try XCTUnwrap(BackupLocalJournal.state(for: container).manifest)
        XCTAssertTrue(recreated.previousGenerations.isEmpty)
        XCTAssertTrue(Set(old.chunks.map(\.storageID)).isDisjoint(with: recreated.chunks.map(\.storageID)))
        let backup = try await store.fetchBackup()
        XCTAssertEqual(backup?.contentSummary?.completedWorkoutCount, 2)
    }

    func testRestorePreservesFailedUploadAndRetiredRecordCleanup() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Unpublished edit"))
        try context.save()
        await store.failNextPublication()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected publication failure") }
        catch ArchiveTestError.publication { }
        var state = try BackupLocalJournal.state(for: container)
        let abandoned = try XCTUnwrap(state.attemptedManifest)
        let committed = try XCTUnwrap(state.manifest)
        let abandonedChunks = Set(abandoned.chunks.map(\.recordName)).subtracting(committed.chunks.map(\.recordName))
        XCTAssertFalse(abandonedChunks.isEmpty)
        let orphan = "backup-chunk-v3-\(UUID())"
        state.garbageRecords = [orphan]
        try BackupLocalJournal.save(state, for: container)
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        let restored = try BackupLocalJournal.state(for: container)
        XCTAssertNil(restored.attemptedManifest)
        XCTAssertTrue(restored.garbageRecords?.contains(orphan) == true)
        XCTAssertTrue(restored.garbageRecords?.contains("backup-generation-v3-\(abandoned.generation)") == true)
        XCTAssertTrue(Set(abandoned.chunks.map(\.recordName)).isSubset(of: restored.garbageRecords ?? []))
        _ = try await service.exportCurrentBackup()
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
        let remaining = await store.storedChunkNames()
        XCTAssertTrue(remaining.isDisjoint(with: abandonedChunks))
        let backup = try await store.fetchBackup()
        XCTAssertEqual(backup?.contentSummary?.completedWorkoutCount, 2)
    }

    func testRestoreDoesNotCarryCleanupIntoAnotherAccount() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        var state = try BackupLocalJournal.state(for: container)
        state.garbageRecords = ["backup-chunk-v3-\(UUID())"]
        try BackupLocalJournal.save(state, for: container)
        await store.changeAccount()
        _ = try await service.restoreLatestBackup(replacingLocalData: true)
        let restored = try BackupLocalJournal.state(for: container)
        XCTAssertEqual(restored.account, "account-b")
        XCTAssertNil(restored.garbageRecords)
    }

    func testMissingRetainedManifestKeepsCleanupQueuedUntilRetry() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Second generation"))
        try context.save()
        _ = try await service.exportCurrentBackup()
        let removed = try await store.removePreviousManifest()
        var state = try BackupLocalJournal.state(for: container)
        let garbage: Set<String> = ["backup-chunk-v3-\(UUID())"]
        state.garbageRecords = garbage
        try BackupLocalJournal.save(state, for: container)
        _ = try await service.exportCurrentBackup()
        XCTAssertEqual(try BackupLocalJournal.state(for: container).garbageRecords, garbage)
        await store.restoreManifest(removed)
        _ = try await service.exportCurrentBackup()
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
        let previous = try await store.fetchPreviousBackup()
        XCTAssertNotNil(previous)
    }

    func testOlderNonemptyDeviceCannotReplaceNewGeneration() async throws {
        let store = MemoryArchiveStore()
        let owner = try makeContainer(workouts: 10)
        _ = try await UserDataCloudBackupService(localContainer: owner, backupStore: store).exportCurrentBackup()
        let before = try await store.fetchManifest()
        let stale = try makeContainer(workouts: 1)
        do {
            _ = try await UserDataCloudBackupService(localContainer: stale, backupStore: store).exportCurrentBackup()
            XCTFail("Stale device replaced another lineage")
        } catch UserDataCloudBackupSafetyError.unrelatedDevice { }
        let after = try await store.fetchManifest()
        XCTAssertEqual(after, before)
    }

    func testFailedPublicationKeepsPreviousBackupAndRetryReusesUnchangedWorkouts() async throws {
        let store = MemoryArchiveStore()
        let owner = try makeContainer(workouts: 12)
        let service = UserDataCloudBackupService(localContainer: owner, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let before = try await store.fetchManifest()
        let context = ModelContext(owner)
        context.insert(UserProfile(displayName: "New name"))
        try context.save()
        await store.failNextPublication()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected failure") }
        catch ArchiveTestError.publication { }
        let unchanged = try await store.fetchManifest()
        XCTAssertEqual(unchanged, before)
        _ = try await service.exportCurrentBackup()
        let count = await store.lastUploadedChunkCount
        XCTAssertEqual(count, 1)
        let record = try await store.fetchBackup()
        XCTAssertEqual(record?.contentSummary?.completedWorkoutCount, 12)
    }

    func testRestoredDeviceCanContinueLineageAndRoundTripAllChunks() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 3)
        _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
        let target = try makeContainer(workouts: 0)
        let targetService = UserDataCloudBackupService(localContainer: target, backupStore: store)
        let result = try await targetService.restoreLatestBackup()
        XCTAssertNotNil(result)
        XCTAssertEqual(try ModelContext(target).fetchCount(FetchDescriptor<WorkoutSession>()), 3)
        _ = try await targetService.exportCurrentBackup()
        let uploaded = await store.lastUploadedChunkCount
        // Restore recalculates derived summaries, so changed summaries may re-upload once.
        XCTAssertLessThanOrEqual(uploaded, 4)
        let beforeNoOp = try await store.fetchManifest()
        let publications = await store.publicationCount
        _ = try await targetService.exportCurrentBackup()
        let afterNoOp = try await store.fetchManifest()
        let afterPublications = await store.publicationCount
        XCTAssertEqual(beforeNoOp, afterNoOp)
        XCTAssertEqual(publications, afterPublications)
    }

    func testAccountSwitchDoesNotSendExistingLocalHistoryToNewAccount() async throws {
        let store = MemoryArchiveStore()
        let source = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: source, backupStore: store)
        _ = try await service.exportCurrentBackup()
        await store.changeAccount()
        do { _ = try await service.exportCurrentBackup(); XCTFail("Expected account protection") }
        catch UserDataCloudBackupSafetyError.accountChanged { }
    }

    func testExplicitReplacementKeepsPreviousGenerationRestorable() async throws {
        let store = MemoryArchiveStore()
        let first = try makeContainer(workouts: 3)
        _ = try await UserDataCloudBackupService(localContainer: first, backupStore: store).exportCurrentBackup()
        let second = try makeContainer(workouts: 1)
        let service = UserDataCloudBackupService(localContainer: second, backupStore: store)
        _ = try await service.exportCurrentBackup(replacingRemote: true)
        let result = try await service.restoreLatestBackup(replacingLocalData: true, previousGeneration: true)
        XCTAssertNotNil(result)
        XCTAssertEqual(try ModelContext(second).fetchCount(FetchDescriptor<WorkoutSession>()), 3)
    }

    func testPublicationAcknowledgmentCanRecoverAfterProcessExit() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        let remote = try await store.fetchManifest()
        let manifest = try XCTUnwrap(remote)
        try BackupLocalJournal.save(.init(account: "account-a", attemptedManifest: manifest), for: container)
        _ = try await service.exportCurrentBackup()
        XCTAssertEqual(try BackupLocalJournal.state(for: container).generation, manifest.generation)
        XCTAssertNil(try BackupLocalJournal.state(for: container).attemptedManifest)
    }

    func testFailedRetentionCleanupRetriesWithoutPublishingAnotherGeneration() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 1)
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Profile")
        context.insert(profile)
        try context.save()
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        for index in 0..<4 {
            profile.displayName = "Profile \(index)"
            try context.save()
            if index == 3 { await store.failNextCleanup() }
            _ = try await service.exportCurrentBackup()
        }
        XCTAssertFalse(try BackupLocalJournal.state(for: container).garbageRecords?.isEmpty ?? true)
        let previousCount = await store.publicationCount
        _ = try await service.exportCurrentBackup()
        let count = await store.publicationCount
        XCTAssertEqual(count, previousCount)
        XCTAssertNil(try BackupLocalJournal.state(for: container).garbageRecords)
    }

    func testCloudDeletionClearsLocalLineageAndPendingBackupTicket() async throws {
        let store = MemoryArchiveStore()
        let container = try makeContainer(workouts: 2)
        let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
        _ = try await service.exportCurrentBackup()
        try BackupLocalJournal.markPending(for: container)
        XCTAssertFalse(try BackupLocalJournal.knownRecordNames(for: container).isEmpty)
        try await service.deleteRemoteBackup()
        XCTAssertNil(try BackupLocalJournal.pending(for: container))
        XCTAssertNil(try BackupLocalJournal.state(for: container).generation)
        XCTAssertTrue(try BackupLocalJournal.knownRecordNames(for: container).isEmpty)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        _ = try await service.exportCurrentBackup()
        let recreated = try await store.fetchManifest()
        XCTAssertEqual(recreated?.summary.completedWorkoutCount, 2)
    }

    private func makeContainer(workouts: Int) throws -> ModelContainer {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let context = ModelContext(container)
        for index in 0..<workouts { context.insert(WorkoutSession(name: "Workout \(index)", status: .completed, endedAt: .now)) }
        try context.save()
        return container
    }
}

private enum ArchiveTestError: Error { case publication }

private actor MemoryArchiveStore: IncrementalBackupStoring {
    private var current: BackupManifest?
    private var generations: [String: BackupManifest] = [:]
    private var failCleanup = false
    private var chunks: [String: Data] = [:]
    private var failPublication = false
    private var account = "account-a"
    private(set) var lastUploadedChunkCount = 0
    private(set) var publicationCount = 0

    func accountIdentifier() async throws -> String { account }
    func changeAccount() { account = "account-b" }
    func failNextCleanup() { failCleanup = true }
    func removeOrphanedRecords(_ names: Set<String>, retaining: BackupManifest) async throws {
        if failCleanup { failCleanup = false; throw ArchiveTestError.publication }
        try await BackupRetentionCleanup.remove(names, retaining: retaining,
            loadManifest: { self.manifest(named: $0) },
            delete: { self.deleteRecords($0) })
    }
    private func manifest(named name: String) -> BackupManifest? {
        generations[String(name.dropFirst("backup-generation-v3-".count))]
    }
    private func deleteRecords(_ names: Set<String>) {
        for name in names {
            chunks[name] = nil
            if name.hasPrefix("backup-generation-v3-") {
                generations[String(name.dropFirst("backup-generation-v3-".count))] = nil
            }
        }
    }
    func removePreviousManifest() throws -> BackupManifest {
        let id = try XCTUnwrap(current?.previousGenerations.first)
        return try XCTUnwrap(generations.removeValue(forKey: id))
    }
    func restoreManifest(_ manifest: BackupManifest) { generations[manifest.generation] = manifest }
    func storedChunkNames() -> Set<String> { Set(chunks.keys) }
    func failNextPublication() { failPublication = true }
    func fetchManifest() async throws -> BackupManifest? { current }
    func saveArchive(_ manifest: BackupManifest, chunkFiles: [String: URL], expectedGeneration: String?, expectedAccount: String) async throws {
        guard account == expectedAccount else { throw UserDataCloudBackupSafetyError.accountChanged }
        guard expectedGeneration == current?.generation else { throw UserDataCloudBackupSafetyError.remoteChanged }
        lastUploadedChunkCount = chunkFiles.count
        for (name, url) in chunkFiles { chunks[name] = try Data(contentsOf: url) }
        if failPublication { failPublication = false; throw ArchiveTestError.publication }
        current = manifest
        generations[manifest.generation] = manifest
        publicationCount += 1
    }
    func fetchBackupMetadata() async throws -> UserDataCloudBackupRemoteMetadata? {
        current.map { .init(updatedAt: $0.updatedAt, contentSummary: $0.summary, generation: $0.generation) }
    }
    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard let current else { return nil }
        return try record(current)
    }
    func fetchPreviousBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        guard let previous = current?.previousGenerations.first, let manifest = generations[previous] else { return nil }
        return try record(manifest)
    }
    private func record(_ current: BackupManifest) throws -> UserDataCloudBackupRemoteRecord {
        let parts = try current.chunks.map { reference in
            guard let data = chunks[reference.recordName] else { throw BackupArchiveError.missingChunk }
            let decoded = try BackupArchiveCodec.decode(data)
            guard BackupArchiveCodec.digest(decoded) == reference.digest else { throw BackupArchiveError.corruptChunk }
            return decoded
        }
        return try UserDataCloudBackupRemoteRecord(updatedAt: current.updatedAt,
                payloadData: UserDataBackupPayloadCodec.combine(parts, generatedAt: current.updatedAt),
                contentSummary: current.summary, generation: current.generation)
    }
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord, expectedUpdatedAt: Date?) async throws { XCTFail("Incremental export used legacy upload") }
    func deleteBackup() async throws { current = nil; chunks = [:] }
}
