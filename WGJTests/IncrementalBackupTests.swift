import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class IncrementalBackupTests: XCTestCase {
    func testChunkEncodingPreservesExistingBytesAndDigest() throws {
        let container = try makeContainer(workouts: 2)
        let context = ModelContext(container)
        let profile = UserProfile(displayName: "Åsa / 🏋️ \"training\"")
        profile.avatarImageData = Data([0, 127, 255])
        profile.bodyWeightKilograms = 72.125
        context.insert(profile)
        for name in ["z-custom", "a-custom"] {
            context.insert(ExerciseCatalogItem(remoteUUID: name, displayName: name, sourceName: "custom"))
        }
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "pull-up",
            exerciseNameSnapshot: "Pull-Up", categorySnapshot: "Back", muscleSummarySnapshot: "Back", session: session)
        context.insert(exercise)
        for weight: Double? in [nil, 0, 1.23456789, 100] {
            context.insert(WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 8,
                actualWeight: weight, isCompleted: true, sessionExercise: exercise))
        }
        try context.saveWithRecoveryProtection()
        for sessionID: UUID? in [nil, session.id] {
            var payload = try UserDataCloudBackupPayload(context: context, sessionID: sessionID,
                includeShared: sessionID == nil, includeHistory: sessionID != nil, includeTemplates: false)
            payload.generatedAt = .distantPast
            // Reproduce the shipped encoder, including its redundant first key sort.
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupArchiveCodec.json(payload)) as? [String: Any])
            for (key, value) in legacy {
                if let rows = value as? [[String: Any]] {
                    legacy[key] = rows.sorted {
                        String(describing: $0["id"] ?? $0["remoteUUID"] ?? "") < String(describing: $1["id"] ?? $1["remoteUUID"] ?? "")
                    }
                }
            }
            let expected = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            let (actual, summary) = try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: sessionID)
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(BackupArchiveCodec.digest(actual), BackupArchiveCodec.digest(expected))
            XCTAssertEqual(summary, payload.contentSummary)
        }
    }

    func testRetentionBatchesManifestReadsAndPreservesEveryRetainedChunk() async throws {
        let container = try makeContainer(workouts: 2)
        let plan = try BackupExportPlan.build(container: container, previous: nil)
        defer { plan.cleanUp() }
        let oldest = plan.manifest
        var previous = oldest
        previous.generation = UUID().uuidString
        previous.chunks[0].storageID = UUID().uuidString
        var current = previous
        current.generation = UUID().uuidString
        current.previousGenerations = [previous.generation, oldest.generation]
        var retired = oldest
        retired.generation = UUID().uuidString
        retired.chunks[0].storageID = UUID().uuidString
        let all = [oldest, previous, retired]
        let byName = Dictionary(uniqueKeysWithValues: all.map { ("backup-generation-v3-\($0.generation)", $0) })
        let retiredName = "backup-generation-v3-\(retired.generation)"
        let protected = Set([oldest, previous, current].flatMap { $0.chunks.map(\.recordName) })
        let garbage = protected.union([retiredName, "abandoned-chunk"])
        var reads: [Set<String>] = []
        var deletions: [Set<String>] = []
        try await BackupRetentionCleanup.remove(garbage, retaining: current,
            loadManifests: { names in reads.append(names); return byName },
            delete: { deletions.append($0) })
        XCTAssertEqual(reads, [Set(byName.keys)])
        XCTAssertEqual(deletions, [[retired.chunks[0].recordName, "abandoned-chunk"], [retiredName]])
        XCTAssertTrue(deletions.allSatisfy { $0.isDisjoint(with: protected) })

        // A partial read must not permit even the first deletion phase.
        deletions = []
        do {
            try await BackupRetentionCleanup.remove(garbage, retaining: current,
                loadManifests: { _ in [retiredName: retired] }, delete: { deletions.append($0) })
            XCTFail("Missing retained manifest must stop cleanup")
        } catch BackupArchiveError.missingChunk { }
        XCTAssertTrue(deletions.isEmpty)
    }

    func testRetentionRetryCanRediscoverChunksAfterPartialDeletion() async throws {
        let plan = try BackupExportPlan.build(container: makeContainer(workouts: 1), previous: nil)
        defer { plan.cleanUp() }
        let current = plan.manifest
        var retired = current
        retired.generation = UUID().uuidString
        retired.chunks[0].storageID = UUID().uuidString
        let name = "backup-generation-v3-\(retired.generation)"
        var deleted: [Set<String>] = []
        do {
            try await BackupRetentionCleanup.remove([name], retaining: current,
                loadManifests: { _ in [name: retired] }, delete: { names in
                    deleted.append(names)
                    throw ArchiveTestError.publication
                })
            XCTFail("Expected partial delete failure")
        } catch ArchiveTestError.publication { }
        XCTAssertEqual(deleted, [[retired.chunks[0].recordName]])
        deleted = []
        try await BackupRetentionCleanup.remove([name], retaining: current,
            loadManifests: { _ in [name: retired] }, delete: { deleted.append($0) })
        XCTAssertEqual(deleted, [[retired.chunks[0].recordName], [name]])
    }

    func testLargeRetentionBacklogBoundsReadsAndProtectsLateRetainedVersions() async throws {
        let plan = try BackupExportPlan.build(container: makeContainer(workouts: 1), previous: nil)
        defer { plan.cleanUp() }
        var current = plan.manifest
        // Put retained generations last so retired chunks are seen before their
        // protection is known. Every manifest represents a substantial history.
        current.previousGenerations = ["FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"]
        for _ in 0..<1_000 {
            var chunk = current.chunks[1]
            chunk.key = UUID().uuidString
            chunk.storageID = UUID().uuidString
            current.chunks.append(chunk)
        }
        let retired = Set((0..<129).map { String(format: "backup-generation-v3-00000000-0000-0000-0000-%012d", $0) })
        let retained = Set(current.previousGenerations.map { "backup-generation-v3-\($0)" })
        let uniqueChunks = Dictionary(uniqueKeysWithValues: retired.union(retained).map { ($0, UUID().uuidString) })
        let protected = Set(current.chunks.map(\.recordName))
            .union(retained.map { "backup-chunk-v3-\(uniqueChunks[$0]!)" })
        let expectedDeletedChunks = Set(retired.map { "backup-chunk-v3-\(uniqueChunks[$0]!)" })
        var requests: [Set<String>] = []
        var deletions: [Set<String>] = []
        // Reuse the fixture to check success, a late missing recovery manifest,
        // and a failure after one batch. Neither failed read may delete anything.
        for scenario in 0..<3 {
            requests = []
            deletions = []
            do {
                try await BackupRetentionCleanup.remove(retired.union(protected), retaining: current,
                    loadManifests: { names in
                        XCTAssertLessThanOrEqual(names.count, BackupManifestBatches.limit)
                        requests.append(names)
                        if scenario == 2 && requests.count == 2 { throw ArchiveTestError.publication }
                        var batch: [String: BackupManifest] = [:]
                        for name in names {
                            if scenario == 1 && retained.contains(name) { continue }
                            var manifest = current
                            manifest.generation = String(name.dropFirst("backup-generation-v3-".count))
                            manifest.previousGenerations = []
                            manifest.chunks[0].storageID = uniqueChunks[name]!
                            batch[name] = manifest
                        }
                        return batch
                    }, delete: { deletions.append($0) })
                XCTAssertEqual(scenario, 0, "An incomplete read must stop cleanup")
                XCTAssertEqual(requests.count, 33)
                XCTAssertEqual(requests.reduce(into: Set<String>()) { $0.formUnion($1) }, retired.union(retained))
                XCTAssertEqual(deletions, [expectedDeletedChunks, retired])
            } catch BackupArchiveError.missingChunk {
                XCTAssertEqual(scenario, 1)
            } catch ArchiveTestError.publication {
                XCTAssertEqual(scenario, 2)
            }
            if scenario != 0 { XCTAssertTrue(deletions.isEmpty) }
            XCTAssertTrue(deletions.allSatisfy { $0.isDisjoint(with: protected) })
        }
    }

    func testCorruptOrMissingChunkNeverReplacesLocalData() async throws {
        for missing in [false, true] {
            let store = MemoryArchiveStore()
            let source = try makeContainer(workouts: 3)
            _ = try await UserDataCloudBackupService(localContainer: source, backupStore: store).exportCurrentBackup()
            await store.damageCurrentChunk(removing: missing)
            let target = try makeContainer(workouts: 1)
            let before = try UserDataCloudBackupPayload(context: ModelContext(target))
            do {
                _ = try await UserDataCloudBackupService(localContainer: target, backupStore: store)
                    .restoreLatestBackup(replacingLocalData: true)
                XCTFail("Invalid backup must never replace local data")
            } catch is BackupArchiveError { }
            let after = try UserDataCloudBackupPayload(context: ModelContext(target))
            XCTAssertEqual(try UserDataBackupPayloadCodec.canonicalData(BackupArchiveCodec.json(before)),
                           try UserDataBackupPayloadCodec.canonicalData(BackupArchiveCodec.json(after)))
        }
    }

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
        await waitForCleanup()
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
        await waitForCleanup()
        XCTAssertEqual(try BackupLocalJournal.state(for: container).garbageRecords, garbage)
        await store.restoreManifest(removed)
        _ = try await service.exportCurrentBackup()
        await waitForCleanup()
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
        await waitForCleanup()
        XCTAssertFalse(try BackupLocalJournal.state(for: container).garbageRecords?.isEmpty ?? true)
        let previousCount = await store.publicationCount
        _ = try await service.exportCurrentBackup()
        let count = await store.publicationCount
        XCTAssertEqual(count, previousCount)
        await waitForCleanup()
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

    func testBackupAcknowledgesBeforeCleanupAndSerializesRestore() async throws {
        for changed in [false, true] {
            let store = MemoryArchiveStore()
            let container = try makeContainer(workouts: 1)
            let service = UserDataCloudBackupService(localContainer: container, backupStore: store)
            _ = try await service.exportCurrentBackup()
            await waitForCleanup()
            var state = try BackupLocalJournal.state(for: container)
            let garbage: Set<String> = ["abandoned-chunk"]
            state.garbageRecords = garbage
            try BackupLocalJournal.save(state, for: container)
            if changed {
                let context = ModelContext(container)
                context.insert(UserProfile(displayName: "Changed"))
                try context.saveWithRecoveryProtection()
            }
            try BackupLocalJournal.markPending(for: container)
            let cleanupStarted = expectation(description: "Cleanup started")
            let exported = expectation(description: "Export returns while cleanup is suspended")
            await store.pauseCleanup(started: cleanupStarted)
            let export = Task {
                defer { exported.fulfill() }
                return try await service.exportCurrentBackup()
            }
            await fulfillment(of: [cleanupStarted, exported], timeout: 5)
            let acknowledged = try BackupLocalJournal.state(for: container)
            let remote = try await store.fetchManifest()
            XCTAssertEqual(acknowledged.generation, remote?.generation)
            XCTAssertNil(acknowledged.attemptedManifest)
            XCTAssertNil(try BackupLocalJournal.pending(for: container))
            XCTAssertEqual(acknowledged.garbageRecords, garbage)
            // A new edit must stay pending even when older cleanup finishes.
            try BackupLocalJournal.markPending(for: container)
            let nextTicket = try BackupLocalJournal.pending(for: container)
            let restored = expectation(description: "Restore waits for cleanup")
            restored.isInverted = true
            let restore = Task {
                defer { restored.fulfill() }
                return try await service.restoreLatestBackup(replacingLocalData: true)
            }
            await fulfillment(of: [restored], timeout: 0.1)
            XCTAssertEqual(try BackupLocalJournal.pending(for: container), nextTicket)
            await store.resumeCleanup()
            _ = try await export.value
            _ = try await restore.value
            await waitForCleanup()
            XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        }
    }

    func testCleanupAcknowledgmentPreservesNewWorkAndDoesNotResurrectResetLineage() throws {
        let container = try makeContainer(workouts: 0)
        var state = BackupLocalJournal.State(account: "account-a", generation: "generation-a",
            garbageRecords: ["old", "new"])
        try BackupLocalJournal.save(state, for: container)
        try BackupLocalJournal.markPending(for: container)
        let ticket = try BackupLocalJournal.pending(for: container)
        try BackupLocalJournal.finishCleanup(["old"], account: "account-a", generation: "generation-a", for: container)
        XCTAssertEqual(try BackupLocalJournal.state(for: container).garbageRecords, ["new"])
        XCTAssertEqual(try BackupLocalJournal.pending(for: container), ticket)
        for replacement in [
            BackupLocalJournal.State(),
            BackupLocalJournal.State(account: "account-b", generation: "generation-a", garbageRecords: ["old"]),
            BackupLocalJournal.State(account: "account-a", generation: "generation-b", garbageRecords: ["old"])
        ] {
            state = replacement
            try BackupLocalJournal.save(state, for: container)
            try BackupLocalJournal.finishCleanup(["old"], account: "account-a", generation: "generation-a", for: container)
            let result = try BackupLocalJournal.state(for: container)
            XCTAssertEqual(result.account, state.account)
            XCTAssertEqual(result.generation, state.generation)
            XCTAssertEqual(result.garbageRecords, state.garbageRecords)
        }
    }

    private func waitForCleanup() async {
        await BackupOperationGate.shared.acquire()
        await BackupOperationGate.shared.release()
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
    private var cleanupStarted: XCTestExpectation?
    private var cleanupContinuation: CheckedContinuation<Void, Never>?
    func pauseCleanup(started: XCTestExpectation) { cleanupStarted = started }
    func resumeCleanup() {
        cleanupStarted = nil
        cleanupContinuation?.resume()
        cleanupContinuation = nil
    }
    private var chunks: [String: Data] = [:]
    private var failPublication = false
    private var account = "account-a"
    private(set) var lastUploadedChunkCount = 0
    private(set) var publicationCount = 0

    func accountIdentifier() async throws -> String { account }
    func changeAccount() { account = "account-b" }
    func failNextCleanup() { failCleanup = true }
    func removeOrphanedRecords(_ names: Set<String>, retaining: BackupManifest) async throws {
        if let cleanupStarted {
            await withCheckedContinuation { continuation in
                cleanupContinuation = continuation
                cleanupStarted.fulfill()
            }
        }
        if failCleanup { failCleanup = false; throw ArchiveTestError.publication }
        try await BackupRetentionCleanup.remove(names, retaining: retaining,
            loadManifests: { names in
                names.reduce(into: [:]) { result, name in result[name] = self.manifest(named: name) }
            },
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
    func damageCurrentChunk(removing: Bool) {
        guard let name = current?.chunks.first?.recordName else { return }
        chunks[name] = removing ? nil : Data("{}".utf8)
    }
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
