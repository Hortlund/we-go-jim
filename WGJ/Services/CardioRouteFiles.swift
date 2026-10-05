import Foundation

/// Atomic local files shared by the recording actor and the synchronous restore
/// barrier. A restore changes the generation, fencing previously queued GPS writes.
nonisolated struct CardioRouteFiles: Sendable {
    static let defaultDirectory = URL.applicationSupportDirectory.appendingPathComponent("CardioRoutes", isDirectory: true)
    let directory: URL
    private static let lock = NSRecursiveLock()
    private struct Generation {
        let value: UUID
        let restoreTicket: UUID?
    }
    nonisolated(unsafe) private static var generations: [String: Generation] = [:]

    init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    func withAccess<T>(_ operation: () throws -> T) rethrows -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try operation()
    }

    func generation() -> UUID {
        withAccess {
            let key = directory.standardizedFileURL.path
            if let existing = Self.generations[key] { return existing.value }
            let value = UUID()
            Self.generations[key] = Generation(value: value, restoreTicket: nil)
            return value
        }
    }

    @discardableResult
    func advanceGeneration(forRestoreTicket ticket: UUID? = nil) -> UUID {
        withAccess {
            let key = directory.standardizedFileURL.path
            // Replaying one committed restore must not fence a newer workout's
            // recorder that already reopened after the first installation attempt.
            if let ticket, let existing = Self.generations[key], existing.restoreTicket == ticket {
                return existing.value
            }
            let value = UUID()
            Self.generations[key] = Generation(value: value, restoreTicket: ticket)
            return value
        }
    }

    func url(for activityID: UUID) -> URL {
        directory.appendingPathComponent("\(activityID.uuidString).json")
    }

    func read(activityID: UUID) throws -> CardioRoute? {
        try withAccess {
            let url = url(for: activityID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let route = try JSONDecoder().decode(CardioRoute.self, from: Data(contentsOf: url))
            guard route.activityID == activityID else { throw CocoaError(.fileReadCorruptFile) }
            return route
        }
    }

    func write(_ route: CardioRoute) throws {
        try withAccess {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.protect(directory)
            let file = url(for: route.activityID)
            try JSONEncoder().encode(route).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Self.protect(file)
        }
    }

    /// Only completed workout identities are provided here. Live journals and
    /// orphaned files never become cloud data.
    func completedRoutes(for blocks: [WorkoutCardioBlockBackup]) throws -> [CardioRoute] {
        try withAccess {
            try blocks.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { block in
                guard let route = try read(activityID: block.id) else { return nil }
                guard route.sessionID == block.sessionID else { throw BackupArchiveError.corruptChunk }
                guard !route.isRecording, !route.points.isEmpty else { return nil }
                try route.validateForBackup()
                return route
            }
        }
    }

    /// Replayable after the database commit. If any file operation fails, the
    /// durable restore intent remains and must finish before normal local writes.
    func restore(_ restoration: CardioRouteRestoration) throws {
        try withAccess {
            advanceGeneration(forRestoreTicket: restoration.ticket)
            for route in restoration.routes ?? [] { try route.validateForBackup() }
            // A failed read cannot establish which newer routes are safe to remove.
            // Leave the files intact until replay can read it.
            let preserved = try restoration.activeWorkoutSnapshotURL.map {
                try ActiveWorkoutSnapshotStore.routeActivitiesSaved(after: restoration.cleanupBefore, at: $0)
            } ?? []
            let parents = Dictionary(uniqueKeysWithValues: restoration.activities.map { ($0.activityID, $0.sessionID) })
            let incoming = Set((restoration.routes ?? []).map(\.activityID))
            for route in restoration.routes ?? [] {
                guard parents[route.activityID] == route.sessionID else { throw BackupArchiveError.corruptChunk }
                if preserved.contains(route.activityID) { continue }
                try write(route)
            }
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where file.pathExtension == "json" {
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                if let id, incoming.contains(id) || preserved.contains(id) { continue }
                // Old backups didn't contain routes. Preserve an existing route
                // only if both identities still belong to the restored history.
                if restoration.routes == nil, let id, let route = try? read(activityID: id),
                   parents[id] == route.sessionID { continue }
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    static func protect(_ url: URL) throws {
        var file = url
        var values = URLResourceValues()
        // Completed routes use WGJ's explicit cloud backup; live journals must
        // not be swept into the separate system device backup.
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
}

nonisolated struct CardioRouteRestoration: Codable, Sendable {
    struct Activity: Codable, Sendable {
        let activityID: UUID
        let sessionID: UUID
    }
    let ticket: UUID
    let directory: URL
    let routes: [CardioRoute]?
    let activities: [Activity]
    let cleanupBefore: Date
    let activeWorkoutSnapshotURL: URL?

    init(ticket: UUID, files: CardioRouteFiles, payload: UserDataCloudBackupPayload,
         cleanupBefore: Date = .now, activeWorkoutSnapshotURL: URL? = nil) {
        self.ticket = ticket
        directory = files.directory
        routes = payload.cardioRoutes
        activities = payload.workoutCardioBlocks.map { Activity(activityID: $0.id, sessionID: $0.sessionID) }
        self.cleanupBefore = cleanupBefore
        self.activeWorkoutSnapshotURL = activeWorkoutSnapshotURL
            ?? (files.directory == CardioRouteFiles.defaultDirectory ? ActiveWorkoutSnapshotStore.defaultSnapshotURL : nil)
    }
}
