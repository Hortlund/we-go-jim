import CryptoKit
import Foundation
import OSLog
import SwiftData
import Synchronization

/// The archive envelope evolves independently of the canonical payload and local schema.
nonisolated enum BackupArchiveCodec {
    private static let magic = Data("WGJZ1\0".utf8)

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ data: Data) throws -> Data {
        magic + (try (data as NSData).compressed(using: .lzfse) as Data)
    }

    static func decode(_ data: Data) throws -> Data {
        guard data.starts(with: magic) else { return data } // Legacy JSON assets.
        do { return try (Data(data.dropFirst(magic.count)) as NSData).decompressed(using: .lzfse) as Data }
        catch { throw BackupArchiveError.corruptChunk }
    }

    static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

nonisolated struct BackupChunkReference: Codable, Equatable, Sendable {
    var key: String
    var storageID: String = UUID().uuidString
    var digest: String
    var sourceUpdatedAt: Date
    var sourceFingerprint: String? = nil
    var summary: UserDataCloudBackupContentSummary
    var recordName: String { "backup-chunk-v3-\(storageID)" }
}

nonisolated struct BackupManifest: Codable, Equatable, Sendable {
    var version: Int = 3
    var generation: String
    var updatedAt: Date
    var chunks: [BackupChunkReference]
    var previousGenerations: [String]
    var summary: UserDataCloudBackupContentSummary

    func validate() throws {
        guard version == 3,
              UUID(uuidString: generation) != nil,
              previousGenerations.count <= 2,
              previousGenerations.allSatisfy({ UUID(uuidString: $0) != nil && $0 != generation }),
              Set(previousGenerations).count == previousGenerations.count,
              Set(chunks.map(\.storageID)).count == chunks.count,
              Set(chunks.map(\.key)).count == chunks.count,
              chunks.filter({ $0.key == "shared" }).count == 1,
              chunks.allSatisfy({ UUID(uuidString: $0.storageID) != nil && $0.digest.count == 64 && $0.digest.allSatisfy(\.isHexDigit) })
        else { throw BackupArchiveError.invalidManifest }
    }
}

nonisolated enum BackupArchiveError: LocalizedError {
    case invalidManifest
    case corruptChunk
    case missingChunk

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "This backup format is unsupported or incomplete. Update WGJ before restoring."
        case .corruptChunk: "A backup file failed its integrity check. Your local data was not replaced."
        case .missingChunk: "A required backup file is missing. Your local data was not replaced."
        }
    }
}

nonisolated protocol IncrementalBackupStoring: UserDataCloudBackupStoring {
    func fetchManifest() async throws -> BackupManifest?
    func saveArchive(_ manifest: BackupManifest, chunkFiles: [String: URL], expectedGeneration: String?, expectedAccount: String) async throws
    func removeOrphanedRecords(_ names: Set<String>, retaining: BackupManifest) async throws
}

extension IncrementalBackupStoring {
    nonisolated func removeOrphanedRecords(_ names: Set<String>, retaining: BackupManifest) async throws { }
}

actor BackupOperationGate {
    static let shared = BackupOperationGate()
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().resume() }
    }
}

/// Kept separately from disposable caches; scoped to the actual local store.
/// Tiny pending tickets are written synchronously at committed save boundaries.
nonisolated enum BackupLocalJournal {
    struct State: Codable, Sendable {
        var account: String?
        var generation: String?
        var legacyUpdatedAt: Date?
        var manifest: BackupManifest?
        var attemptedManifest: BackupManifest?
        var garbageRecords: Set<String>? = nil
    }
    struct Pending: Codable, Equatable, Sendable {
        var ticket: UUID = UUID()
        var account: String?
        var attempt: Int = 0
        var retryAfter: Date = .distantPast
    }

    struct RestoreRequest: Codable, Sendable {
        var ticket = UUID()
        var cleanupBefore: Date = .now
        var account: String?
        var replacingLocalData: Bool
        var previousGeneration: Bool
        var head: UserDataCloudBackupRemoteMetadata?
        var pinned = false
        var requiresExplicitRetry: Bool? = nil
        var stateAfterCommit: State?
        var pendingBeforeCommit: Pending?
    }

    private final class WeakContainer: @unchecked Sendable {
        weak var value: ModelContainer?
        init(_ value: ModelContainer) { self.value = value }
    }
    private struct Memory {
        var containers: [ObjectIdentifier: WeakContainer] = [:]
        mutating func prepare(_ container: ModelContainer) {
            let id = ObjectIdentifier(container)
            if containers[id]?.value !== container {
                states[id] = nil
                pending[id] = nil
                restores[id] = nil
                restoreCleanups[id] = nil
                containers[id] = WeakContainer(container)
            }
        }
        var states: [ObjectIdentifier: State] = [:]
        var pending: [ObjectIdentifier: Pending] = [:]
        var restores: [ObjectIdentifier: RestoreRequest] = [:]
        var restoreCleanups: [ObjectIdentifier: Date] = [:]
    }
    private static let lock = Mutex(Memory())
    private static let restoreReconciliationLock = NSLock()

    static func directory(for container: ModelContainer) -> URL? {
        guard let configuration = container.configurations.filter({ !$0.isStoredInMemoryOnly }).sorted(by: { $0.url.path < $1.url.path }).first else { return nil }
        let identity = container.configurations.map { $0.url.path }.sorted().joined(separator: "|")
        return configuration.url.deletingLastPathComponent()
            .appendingPathComponent("BackupJournal", isDirectory: true)
            .appendingPathComponent(BackupArchiveCodec.digest(Data(identity.utf8)), isDirectory: true)
    }

    static func state(for container: ModelContainer) throws -> State {
        try lock.withLock { memory in
            memory.prepare(container)
            guard let directory = directory(for: container) else {
                return memory.states[ObjectIdentifier(container)] ?? State()
            }
            return try read(State.self, at: directory.appendingPathComponent("state.json")) ?? State()
        }
    }

    static func knownRecordNames(for container: ModelContainer) throws -> Set<String> {
        let state = try state(for: container)
        var names = state.garbageRecords ?? []
        for manifest in [state.manifest, state.attemptedManifest].compactMap({ $0 }) {
            names.formUnion(manifest.chunks.map(\.recordName))
            names.insert("backup-generation-v3-\(manifest.generation)")
        }
        return names
    }

    static func save(_ state: State, for container: ModelContainer) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            if let directory = directory(for: container) {
                try write(state, at: directory.appendingPathComponent("state.json"))
            } else { memory.states[ObjectIdentifier(container)] = state }
        }
    }

    /// Clear only completed cleanup work without racing a reset of local lineage.
    static func finishCleanup(
        _ names: Set<String>, account: String?, generation: String, for container: ModelContainer
    ) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            let url = directory(for: container)?.appendingPathComponent("state.json")
            let current = try url.map { try read(State.self, at: $0) }
                ?? memory.states[ObjectIdentifier(container)]
            guard var state = current, state.account == account,
                  state.generation == generation, state.attemptedManifest == nil else { return }
            let remaining = (state.garbageRecords ?? []).subtracting(names)
            state.garbageRecords = remaining.isEmpty ? nil : remaining
            if let url { try write(state, at: url) }
            else { memory.states[ObjectIdentifier(container)] = state }
        }
    }

    static func markPending(for container: ModelContainer) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            if let directory = directory(for: container) {
                // Account binding lives in state.json and is checked before export.
                // Do not decode its growing manifest on the local save path.
                try write(Pending(), at: directory.appendingPathComponent("pending.json"))
            } else {
                memory.pending[ObjectIdentifier(container)] = Pending(account: memory.states[ObjectIdentifier(container)]?.account)
            }
        }
    }

    static func pending(for container: ModelContainer) throws -> Pending? {
        try lock.withLock { memory in
            memory.prepare(container)
            guard let directory = directory(for: container) else { return memory.pending[ObjectIdentifier(container)] }
            return try read(Pending.self, at: directory.appendingPathComponent("pending.json"))
        }
    }

    static func finish(_ pending: Pending, for container: ModelContainer, retryAfter: Date? = nil) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            let url = directory(for: container)?.appendingPathComponent("pending.json")
            let current = try url.map { try read(Pending.self, at: $0) } ?? memory.pending[ObjectIdentifier(container)]
            guard current?.ticket == pending.ticket else { return } // Never acknowledge newer edits.
            var next = pending
            next.attempt += 1
            next.retryAfter = retryAfter ?? .distantPast
            if let url {
                if retryAfter != nil { try write(next, at: url) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else { memory.pending[ObjectIdentifier(container)] = retryAfter == nil ? nil : next }
        }
    }

    static func restoreRequest(for container: ModelContainer) throws -> RestoreRequest? {
        try lock.withLock { memory in
            memory.prepare(container)
            guard let directory = directory(for: container) else { return memory.restores[ObjectIdentifier(container)] }
            if let request = try read(RestoreRequest.self, at: directory.appendingPathComponent("restore.json")) {
                return request
            }
            var paused = try read(RestoreRequest.self, at: directory.appendingPathComponent("restore-paused.json"))
            paused?.requiresExplicitRetry = true
            return paused
        }
    }

    static func saveRestore(_ request: RestoreRequest?, for container: ModelContainer) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            if let directory = directory(for: container) {
                let url = directory.appendingPathComponent("restore.json")
                if let request { try write(request, at: url) }
                // A newly written explicit request takes precedence over a paused
                // one, even if termination interrupts removal of the old file.
                let paused = directory.appendingPathComponent("restore-paused.json")
                if FileManager.default.fileExists(atPath: paused.path) { try FileManager.default.removeItem(at: paused) }
                if request == nil, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else { memory.restores[ObjectIdentifier(container)] = request }
        }
    }

    /// Called under the write barrier. Rename the already durable intent rather
    /// than allocating an atomic rewrite after a possibly disk-full save failure.
    /// The rollback snapshots remain untouched until startup recovery completes.
    static func pauseRestore(_ ticket: UUID, for container: ModelContainer) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            guard let directory = directory(for: container) else {
                let id = ObjectIdentifier(container)
                if memory.restores[id]?.ticket == ticket { memory.restores[id]?.requiresExplicitRetry = true }
                return
            }
            let url = directory.appendingPathComponent("restore.json")
            guard try read(RestoreRequest.self, at: url)?.ticket == ticket else { return }
            let paused = directory.appendingPathComponent("restore-paused.json")
            if FileManager.default.fileExists(atPath: paused.path) { try FileManager.default.removeItem(at: paused) }
            try FileManager.default.moveItem(at: url, to: paused)
        }
    }

    /// Called under the local write barrier, including before ordinary writes.
    /// A committed receipt is replayable until its lineage acknowledgment is durable.
    static func reconcileRestore(for container: ModelContainer) throws {
        restoreReconciliationLock.lock()
        defer { restoreReconciliationLock.unlock() }
        guard let request = try restoreRequest(for: container),
              try PersistentRestoreRecovery.committedTicket(container: container) == request.ticket,
              let state = request.stateAfterCommit else { return }
        try save(state, for: container)
        if let pending = request.pendingBeforeCommit { try finish(pending, for: container) }
        try saveRestoreCleanup(request.cleanupBefore, for: container)
        try saveRestore(nil, for: container)
        try? PersistentRestoreRecovery.acknowledge(container: container)
    }

    static func restoreCleanup(for container: ModelContainer) throws -> Date? {
        try lock.withLock { memory in
            memory.prepare(container)
            guard let directory = directory(for: container) else { return memory.restoreCleanups[ObjectIdentifier(container)] }
            return try read(Date.self, at: directory.appendingPathComponent("restore-cleanup.json"))
        }
    }

    static func saveRestoreCleanup(_ cutoff: Date?, for container: ModelContainer) throws {
        try lock.withLock { memory in
            memory.prepare(container)
            if let directory = directory(for: container) {
                let url = directory.appendingPathComponent("restore-cleanup.json")
                if let cutoff { try write(cutoff, at: url) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else { memory.restoreCleanups[ObjectIdentifier(container)] = cutoff }
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private static func write<T: Encodable>(_ value: T, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try BackupArchiveCodec.json(value).write(to: url, options: .atomic)
    }
}

/// Stable binary partitions keep cloud assets bounded while allowing small
/// histories to use one asset. An insertion only rewrites its partition (or its
/// two children when it splits), never every workout in the archive.
nonisolated struct BackupHistoryBatch {
    static let maximumWorkouts = 64
    struct Entry: Codable {
        let id: UUID
        let updatedAt: Date
        var bytes: [UInt8] { withUnsafeBytes(of: id.uuid) { Array($0) } }
    }
    let key: String
    let entries: [Entry]
    let fingerprint: String
    var updatedAt: Date { entries.map(\.updatedAt).max() ?? .distantPast }

    static func make(_ sessions: [WorkoutSession]) throws -> [Self] {
        let entries = sessions.map { Entry(id: $0.id, updatedAt: $0.updatedAt) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard Set(entries.map(\.id)).count == entries.count else { throw BackupArchiveError.invalidManifest }
        var result: [Self] = []
        func partition(_ rows: [Entry], prefix: String, bit: Int) throws {
            guard !rows.isEmpty else { return }
            if rows.count <= maximumWorkouts {
                result.append(Self(key: "history-v1-" + (prefix.isEmpty ? "all" : prefix), entries: rows,
                    fingerprint: BackupArchiveCodec.digest(try BackupArchiveCodec.json(rows))))
                return
            }
            guard bit < 128 else { throw BackupArchiveError.invalidManifest }
            var zero: [Entry] = []
            var one: [Entry] = []
            for row in rows {
                if row.bytes[bit / 8] & (1 << (7 - bit % 8)) == 0 { zero.append(row) }
                else { one.append(row) }
            }
            try partition(zero, prefix: prefix + "0", bit: bit + 1)
            try partition(one, prefix: prefix + "1", bit: bit + 1)
        }
        try partition(entries, prefix: "", bit: 0)
        return result
    }
}

nonisolated struct BackupExportPlan {
    let manifest: BackupManifest
    let chunkFiles: [String: URL]
    let temporaryDirectory: URL
    let rawChunkBytes: Int
    let compressedChunkBytes: Int

    func cleanUp() { BackupTemporaryFiles.remove(temporaryDirectory) }

    static func build(container: ModelContainer, previous: BackupManifest?, attempted: BackupManifest? = nil, progress: CloudBackupProgressReporter = .init()) throws -> Self {
        try WGJPerformance.measure("backup.plan") {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            if previous == nil {
                try TemplateRepository(modelContext: context, autoSaveChanges: false).pruneOrphanedTemplateGraphs()
            }
            let directory = try BackupTemporaryFiles.makeArchiveDirectory()
            do {
                let old = Dictionary(uniqueKeysWithValues: (previous?.chunks ?? []).map { ($0.key, $0) })
                let attempts = Dictionary(uniqueKeysWithValues: (attempted?.chunks ?? []).map { ($0.key, $0) })
                var chunks: [BackupChunkReference] = []
                var files: [String: URL] = [:]
                var rawBytes = 0
                var compressedBytes = 0
                let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).sorted(by: { $0.id.uuidString < $1.id.uuidString })
                let completed = WorkoutSessionStatus.completed.rawValue
                let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == completed }))
                let historyBatches = try BackupHistoryBatch.make(sessions)
                let totalParts = 1 + templates.count + historyBatches.count
                progress(.preparing, completed: 0, total: totalParts)
                func append(key: String, updatedAt: Date, fingerprint: String? = nil, payload: () throws -> (Data, UserDataCloudBackupContentSummary)) throws {
                    defer { progress(.preparing, completed: chunks.count, total: totalParts) }
                    if key != "shared", let cached = old[key],
                       fingerprint.map({ cached.sourceFingerprint == $0 }) ?? (cached.sourceUpdatedAt == updatedAt) {
                        chunks.append(cached)
                        return
                    }
                    let (data, summary) = try payload()
                    let digest = BackupArchiveCodec.digest(data)
                    if let cached = old[key], cached.digest == digest {
                        var reused = cached
                        reused.sourceUpdatedAt = updatedAt
                        reused.sourceFingerprint = fingerprint
                        chunks.append(reused)
                        return
                    }
                    var reference = BackupChunkReference(key: key, digest: digest, sourceUpdatedAt: updatedAt, sourceFingerprint: fingerprint, summary: summary)
                    if let attempt = attempts[key], attempt.digest == digest { reference.storageID = attempt.storageID }
                    chunks.append(reference)
                    if old[key]?.digest != digest {
                        let url = directory.appendingPathComponent(reference.recordName)
                        let compressed = try BackupArchiveCodec.encode(data)
                        try compressed.write(to: url, options: .atomic)
                        rawBytes += data.count
                        compressedBytes += compressed.count
                        files[reference.recordName] = url
                    }
                }
                try append(key: "shared", updatedAt: .distantPast) {
                    try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: nil)
                }
                for template in templates {
                    try append(key: "template-\(template.id.uuidString)", updatedAt: template.updatedAt) {
                        try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: nil, templateID: template.id)
                    }
                }
                for batch in historyBatches {
                    try append(key: batch.key, updatedAt: batch.updatedAt, fingerprint: batch.fingerprint) {
                        try UserDataBackupPayloadCodec.makeHistoryChunk(context: context, sessionIDs: Set(batch.entries.map(\.id)))
                    }
                }
                let summary = UserDataBackupPayloadCodec.combinedSummary(chunks.map(\.summary))
                let manifest = BackupManifest(
                    generation: UUID().uuidString, updatedAt: .now, chunks: chunks,
                    previousGenerations: previous.map { Array(([$0.generation] + $0.previousGenerations).prefix(2)) } ?? [],
                    summary: summary
                )
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "WGJ", category: "Backup").info(
                    "Planned \(chunks.count) chunks, changed \(files.count), raw bytes \(rawBytes), compressed bytes \(compressedBytes)"
                )
                return Self(manifest: manifest, chunkFiles: files, temporaryDirectory: directory,
                            rawChunkBytes: rawBytes, compressedChunkBytes: compressedBytes)
            } catch {
                BackupTemporaryFiles.remove(directory)
                throw error
            }
        }
    }
}

/// A manifest contains the full workout index, so bound decoded histories as well
/// as network requests. Consumers keep record IDs, never the decoded manifests.
nonisolated enum BackupManifestBatches {
    static let limit = 4

    static func forEach(
        _ names: Set<String>,
        load: (Set<String>) async throws -> [String: BackupManifest],
        consume: (String, BackupManifest) throws -> Void
    ) async throws {
        let ordered = names.sorted()
        for offset in stride(from: 0, to: ordered.count, by: limit) {
            try Task.checkCancellation()
            let batch = Set(ordered[offset..<min(offset + limit, ordered.count)])
            let manifests = try await load(batch)
            for (name, manifest) in manifests {
                try manifest.validate()
                guard batch.contains(name), name == "backup-generation-v3-\(manifest.generation)" else {
                    throw BackupArchiveError.invalidManifest
                }
                try consume(name, manifest)
            }
        }
    }
}

/// Shared by the CloudKit transport and deterministic retention tests. A cleanup
/// succeeds only when every retained manifest was read and both delete phases finish.
nonisolated enum BackupRetentionCleanup {
    static func remove(
        _ names: Set<String>, retaining current: BackupManifest,
        loadManifests: (Set<String>) async throws -> [String: BackupManifest],
        delete: (Set<String>) async throws -> Void
    ) async throws {
        guard !names.isEmpty else { return }
        try current.validate()
        let retainedGenerations = Set(current.previousGenerations.map { "backup-generation-v3-\($0)" })
        let currentName = "backup-generation-v3-\(current.generation)"
        let retiredGenerations = names.filter { $0.hasPrefix("backup-generation-v3-") }
            .subtracting(retainedGenerations).subtracting([currentName])
        var retained = Set(current.chunks.map(\.recordName))
        retained.insert(currentName)
        var foundRetained: Set<String> = []
        var candidates = names
        // Reduce each batch to record IDs before fetching the next. Even a large
        // retry backlog must not keep every full workout index alive at once.
        try await BackupManifestBatches.forEach(retainedGenerations.union(retiredGenerations), load: loadManifests) { name, manifest in
            if retainedGenerations.contains(name) {
                foundRetained.insert(name)
                retained.formUnion(manifest.chunks.map(\.recordName))
                retained.insert(name)
            } else {
                candidates.formUnion(manifest.chunks.map(\.recordName))
            }
        }
        // Retained manifests can arrive in any batch. Validate all of them before
        // subtracting their chunks or permitting either deletion phase.
        guard foundRetained == retainedGenerations else { throw BackupArchiveError.missingChunk }
        candidates.subtract(retained)
        let generations = candidates.filter { $0.hasPrefix("backup-generation-v3-") }
        // Keep each retired manifest until its chunks are removed. The durable local
        // journal can then rediscover and retry every deletion after a partial failure.
        try await delete(candidates.subtracting(generations))
        try await delete(generations)
    }
}
