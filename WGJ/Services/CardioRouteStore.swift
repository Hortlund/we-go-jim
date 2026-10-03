import Foundation

actor CardioRouteStore {
    static let shared = CardioRouteStore()

    private let files: CardioRouteFiles
    private var directory: URL { files.directory }
    private var generation: UUID
    private var activityGenerations: [UUID: UUID] = [:]
    private var deletedSessions: Set<UUID> = []
    private var deletedActivities: Set<UUID> = []
    private var latestRevisions: [UUID: UInt64] = [:]

    init(directory: URL = CardioRouteFiles.defaultDirectory) {
        let files = CardioRouteFiles(directory: directory)
        self.files = files
        generation = files.generation()
    }

    func writeGeneration() -> UUID {
        refreshGeneration()
        return generation
    }

    func prepareWrite(activityID: UUID) -> UUID {
        refreshGeneration()
        if deletedActivities.remove(activityID) != nil { latestRevisions[activityID] = nil }
        return activityGenerations[activityID] ?? generation
    }

    func prepareRecording(activityID: UUID) throws -> (route: CardioRoute?, generation: UUID) {
        try files.withAccess {
            let route = try load(activityID: activityID)
            let generation = prepareWrite(activityID: activityID)
            return (route, generation)
        }
    }

    func load(activityID: UUID) throws -> CardioRoute? {
        try files.withAccess {
            refreshGeneration()
            guard !deletedActivities.contains(activityID) else { return nil }
            guard let route = try files.read(activityID: activityID) else { return nil }
            guard !deletedSessions.contains(route.sessionID) else { return nil }
            latestRevisions[activityID] = max(latestRevisions[activityID] ?? 0, route.revision)
            return route
        }
    }

    func save(_ route: CardioRoute, generation expectedGeneration: UUID) throws {
        try files.withAccess {
            guard generation == files.generation(),
                  expectedGeneration == (activityGenerations[route.activityID] ?? generation),
                  !deletedSessions.contains(route.sessionID),
                  !deletedActivities.contains(route.activityID),
                  route.revision >= (latestRevisions[route.activityID] ?? 0) else { return }
            try files.write(route)
            latestRevisions[route.activityID] = route.revision
        }
    }

    func delete(activityID: UUID) throws {
        try files.withAccess {
            refreshGeneration()
            activityGenerations[activityID] = UUID()
            deletedActivities.insert(activityID)
            let url = fileURL(activityID)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func delete(sessionID: UUID, activityIDs: Set<UUID> = []) throws {
        try files.withAccess {
            refreshGeneration()
            deletedSessions.insert(sessionID)
            // Known identities also remove damaged routes without decoding their contents.
            var identitiesToDelete = activityIDs
            if FileManager.default.fileExists(atPath: directory.path) {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.pathExtension == "json" {
                    guard let route = try? JSONDecoder().decode(CardioRoute.self, from: Data(contentsOf: url)),
                          route.sessionID == sessionID else { continue }
                    identitiesToDelete.insert(route.activityID)
                }
            }
            var firstFailure: Error?
            for activityID in identitiesToDelete {
                do { try delete(activityID: activityID) }
                catch { if firstFailure == nil { firstFailure = error } }
            }
            if let firstFailure { throw firstFailure }
        }
    }

    func deleteAll() throws {
        try files.withAccess {
            // Fence tasks which captured a route before deletion, even if they arrive later.
            generation = files.advanceGeneration()
            activityGenerations = [:]
            latestRevisions = [:]
            deletedSessions = []
            deletedActivities = []
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func refreshGeneration() {
        let current = files.generation()
        guard current != generation else { return }
        generation = current
        activityGenerations = [:]
        latestRevisions = [:]
        deletedSessions = []
        deletedActivities = []
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }
}
