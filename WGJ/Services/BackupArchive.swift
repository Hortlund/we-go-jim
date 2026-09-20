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
        return try (Data(data.dropFirst(magic.count)) as NSData).decompressed(using: .lzfse) as Data
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
                containers[id] = WeakContainer(container)
            }
        }
        var states: [ObjectIdentifier: State] = [:]
        var pending: [ObjectIdentifier: Pending] = [:]
    }
    private static let lock = Mutex(Memory())

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

    private static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private static func write<T: Encodable>(_ value: T, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try BackupArchiveCodec.json(value).write(to: url, options: .atomic)
    }
}

nonisolated struct BackupExportPlan {
    let manifest: BackupManifest
    let chunkFiles: [String: URL]
    let temporaryDirectory: URL
    let rawChunkBytes: Int
    let compressedChunkBytes: Int

    func cleanUp() { BackupTemporaryFiles.remove(temporaryDirectory) }

    static func build(container: ModelContainer, previous: BackupManifest?, attempted: BackupManifest? = nil) throws -> Self {
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
                func append(key: String, updatedAt: Date, payload: () throws -> (Data, UserDataCloudBackupContentSummary)) throws {
                    if key != "shared", let cached = old[key], cached.sourceUpdatedAt == updatedAt {
                        chunks.append(cached)
                        return
                    }
                    let (data, summary) = try payload()
                    let digest = BackupArchiveCodec.digest(data)
                    if let cached = old[key], cached.digest == digest {
                        var reused = cached
                        reused.sourceUpdatedAt = updatedAt
                        chunks.append(reused)
                        return
                    }
                    var reference = BackupChunkReference(key: key, digest: digest, sourceUpdatedAt: updatedAt, summary: summary)
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
                for template in try context.fetch(FetchDescriptor<WorkoutTemplate>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    try append(key: "template-\(template.id.uuidString)", updatedAt: template.updatedAt) {
                        try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: nil, templateID: template.id)
                    }
                }
                let completed = WorkoutSessionStatus.completed.rawValue
                let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == completed }))
                for session in sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    try append(key: session.id.uuidString, updatedAt: session.updatedAt) {
                        try UserDataBackupPayloadCodec.makeChunk(context: context, sessionID: session.id)
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

/// Shared by the CloudKit transport and deterministic retention tests. A cleanup
/// succeeds only when every retained manifest was read and both delete phases finish.
nonisolated enum BackupRetentionCleanup {
    static func remove(
        _ names: Set<String>, retaining current: BackupManifest,
        loadManifest: (String) async throws -> BackupManifest?,
        delete: (Set<String>) async throws -> Void
    ) async throws {
        var retained = Set(current.chunks.map(\.recordName))
        retained.insert("backup-generation-v3-\(current.generation)")
        for generation in current.previousGenerations {
            guard let previous = try await loadManifest("backup-generation-v3-\(generation)") else {
                throw BackupArchiveError.missingChunk
            }
            retained.formUnion(previous.chunks.map(\.recordName))
            retained.insert("backup-generation-v3-\(generation)")
        }
        var candidates = names.subtracting(retained)
        let generations = candidates.filter { $0.hasPrefix("backup-generation-v3-") }
        for name in generations {
            if let retired = try await loadManifest(name) {
                candidates.formUnion(Set(retired.chunks.map(\.recordName)).subtracting(retained))
            }
        }
        // Keep each retired manifest until its chunks are removed. The durable local
        // journal can then rediscover and retry every deletion after a partial failure.
        try await delete(candidates.subtracting(generations))
        try await delete(generations)
    }
}
