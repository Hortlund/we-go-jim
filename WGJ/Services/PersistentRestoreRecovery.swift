import Foundation
import SQLite3
import SwiftData

/// A restore spans several SQLite stores. Keep a durable rollback generation until
/// every store has committed; recover it before opening SwiftData after a crash.
nonisolated enum PersistentRestoreRecovery {
    private struct FileSnapshot: Codable {
        let destination: URL
        let snapshot: URL
    }
    struct RecoveryRequired: LocalizedError {
        var reason: String = "A local store did not commit."
        var errorDescription: String? {
            "Restore could not finish. Restart WGJ to recover the previous local data, then try restoring again."
        }
    }

    static func requireHealthyStore(_ container: ModelContainer) throws {
        guard let directory = directory(configurations: Array(container.configurations)) else { return }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path) {
            throw RecoveryRequired()
        }
    }

    static func prepare(container: ModelContainer, ticket: UUID? = nil) throws -> URL? {
        let configurations = Array(container.configurations)
        guard let directory = directory(configurations: configurations) else { return nil }
        let marker = directory.appendingPathComponent("pending.json")
        guard !FileManager.default.fileExists(atPath: marker.path) else { throw RecoveryRequired() }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var snapshots: [FileSnapshot] = []
        for config in configurations where !config.isStoredInMemoryOnly {
            guard FileManager.default.fileExists(atPath: config.url.path) else { continue }
            let destination = directory.appendingPathComponent("\(snapshots.count).sqlite")
            try copyDatabase(from: config.url, to: destination, standalone: true)
            snapshots.append(FileSnapshot(destination: config.url, snapshot: destination))
        }
        if let ticket {
            try BackupArchiveCodec.json(ticket).write(to: directory.appendingPathComponent("ticket.json"), options: .atomic)
        }
        try BackupArchiveCodec.json(snapshots).write(to: marker, options: .atomic)
        return directory
    }

    static func complete(_ directory: URL?, committed: Bool = false) throws {
        guard let directory else { return }
        let marker = directory.appendingPathComponent("pending.json")
        if committed, FileManager.default.fileExists(atPath: directory.appendingPathComponent("ticket.json").path) {
            // Atomic rename is the transaction commit point. Keep its receipt
            // until the backup journal has acknowledged it, even across termination.
            try FileManager.default.moveItem(at: marker, to: directory.appendingPathComponent("committed.json"))
            return
        }
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        // The marker is the commit point; leftover copies are disposable after it is removed.
        try? FileManager.default.removeItem(at: directory)
    }

    static func committedTicket(container: ModelContainer) throws -> UUID? {
        guard let directory = directory(configurations: Array(container.configurations)),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("committed.json").path) else { return nil }
        return try JSONDecoder().decode(UUID.self, from: Data(contentsOf: directory.appendingPathComponent("ticket.json")))
    }

    static func acknowledge(container: ModelContainer) throws {
        guard let directory = directory(configurations: Array(container.configurations)) else { return }
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path) else { throw RecoveryRequired() }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    static func recoverIfNeeded(configurations: [ModelConfiguration]) throws {
        guard let directory = directory(configurations: configurations) else { return }
        let marker = directory.appendingPathComponent("pending.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let snapshots = try JSONDecoder().decode([FileSnapshot].self, from: Data(contentsOf: marker))
        let allowed = Set(configurations.map { $0.url.standardizedFileURL.path })
        guard snapshots.allSatisfy({ allowed.contains($0.destination.standardizedFileURL.path)
            && $0.snapshot.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path }) else {
            throw RecoveryRequired(reason: "Snapshot paths do not match the configured stores.")
        }
        for snapshot in snapshots { try copyDatabase(from: snapshot.snapshot, to: snapshot.destination) }
        try complete(directory)
    }

    private static func directory(configurations: [ModelConfiguration]) -> URL? {
        guard let config = configurations.filter({ !$0.isStoredInMemoryOnly }).sorted(by: { $0.url.path < $1.url.path }).first else { return nil }
        let key = BackupArchiveCodec.digest(Data(configurations.map { $0.url.path }.sorted().joined(separator: "|").utf8))
        return config.url.deletingLastPathComponent().appendingPathComponent("RestoreRecovery-\(key)", isDirectory: true)
    }

    private static func copyDatabase(from sourceURL: URL, to destinationURL: URL, standalone: Bool = false) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let source { sqlite3_close(source) }
            throw RecoveryRequired()
        }
        defer { sqlite3_close(source) }
        guard sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let destination { sqlite3_close(destination) }
            throw RecoveryRequired()
        }
        defer { sqlite3_close(destination) }
        sqlite3_busy_timeout(source, 5_000)
        sqlite3_busy_timeout(destination, 5_000)
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw RecoveryRequired(reason: "SQLite backup initialization: \(String(cString: sqlite3_errmsg(destination)))")
        }
        var result: Int32 = SQLITE_OK
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        repeat {
            result = sqlite3_backup_step(backup, 256)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                sqlite3_sleep(10)
            }
        } while result == SQLITE_OK || ((result == SQLITE_BUSY || result == SQLITE_LOCKED) && ContinuousClock.now < deadline)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE && finished == SQLITE_OK else {
            throw RecoveryRequired(reason: "SQLite backup step \(result), finish \(finished), source: \(String(cString: sqlite3_errmsg(source))), destination: \(String(cString: sqlite3_errmsg(destination)))")
        }
        if standalone {
            // A portable snapshot must not depend on a WAL or shared-memory sidecar.
            guard sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
                throw RecoveryRequired(reason: "Could not finalize the standalone rollback snapshot.")
            }
        }
    }
}
