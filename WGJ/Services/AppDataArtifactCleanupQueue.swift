import Foundation

nonisolated enum AppDataArtifact: String, CaseIterable, Codable, Hashable, Sendable {
    case activeWorkoutSnapshot
    case weeklyGoalWidgetSnapshot
    case exerciseImageCache
}

nonisolated struct AppDataArtifactCleanupWarning: Equatable, Sendable {
    let artifact: AppDataArtifact
    let description: String
}

actor AppDataArtifactCleanupQueue {
    static let shared = AppDataArtifactCleanupQueue(datedCleanup: { artifact, cutoff in
        switch artifact {
        case .activeWorkoutSnapshot:
            try await ActiveWorkoutSnapshotStore.shared.invalidateSnapshotsSavedBefore(cutoff)
        case .weeklyGoalWidgetSnapshot:
            WeeklyGoalWidgetPublisher()?.clear()
        case .exerciseImageCache:
            AppDataDeletionService.removeExerciseImageCacheDirectory()
        }
    })

    private let defaults: UserDefaults
    private let cleanup: @Sendable (AppDataArtifact, Date) async throws -> Void
    private let snapshotDeletion: @Sendable (UUID) async throws -> Void
    private var pendingRun: Task<[AppDataArtifactCleanupWarning], Never>?
    private var runGeneration: UInt64 = 0
    private var artifactRevisions: [AppDataArtifact: UInt64] = [:]
    private let pendingDefaultsKey = "appDataArtifactCleanupQueue.pendingArtifacts"
    nonisolated static let deletedSessionsDefaultsKey = "appDataArtifactCleanupQueue.deletedActiveWorkoutSessions"

    init(
        defaults: UserDefaults = .standard,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void,
        snapshotDeletion: @escaping @Sendable (UUID) async throws -> Void = {
            try ActiveWorkoutSnapshotStore.shared.invalidateSession($0)
        }
    ) {
        self.defaults = defaults
        self.cleanup = { artifact, _ in try await cleanup(artifact) }
        self.snapshotDeletion = snapshotDeletion
    }

    init(
        defaultsSuiteName: String,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void,
        snapshotDeletion: @escaping @Sendable (UUID) async throws -> Void = {
            try ActiveWorkoutSnapshotStore.shared.invalidateSession($0)
        }
    ) {
        self.defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.cleanup = { artifact, _ in try await cleanup(artifact) }
        self.snapshotDeletion = snapshotDeletion
    }

    init(defaults: UserDefaults = .standard,
         datedCleanup: @escaping @Sendable (AppDataArtifact, Date) async throws -> Void,
         snapshotDeletion: @escaping @Sendable (UUID) async throws -> Void = {
             try ActiveWorkoutSnapshotStore.shared.invalidateSession($0)
         }) {
        self.defaults = defaults
        self.cleanup = datedCleanup
        self.snapshotDeletion = snapshotDeletion
    }

    func enqueueSnapshotDeletion(sessionIDs: Set<UUID>) async -> [AppDataArtifactCleanupWarning] {
        setDeletedSessionIDs(deletedSessionIDs().union(sessionIDs))
        return await scheduleRetry()
    }

    func enqueue(_ artifacts: Set<AppDataArtifact>, before cutoff: Date = .now) async -> [AppDataArtifactCleanupWarning] {
        var cutoffs = defaults.dictionary(forKey: "appDataArtifactCleanupQueue.cutoffs") as? [String: Double] ?? [:]
        for artifact in artifacts {
            cutoffs[artifact.rawValue] = max(cutoffs[artifact.rawValue] ?? -Double.greatestFiniteMagnitude, cutoff.timeIntervalSince1970)
        }
        defaults.set(cutoffs, forKey: "appDataArtifactCleanupQueue.cutoffs")
        for artifact in artifacts { artifactRevisions[artifact, default: 0] &+= 1 }
        setPendingArtifacts(pendingArtifacts().union(artifacts))
        return await scheduleRetry()
    }

    func retryPending() async -> [AppDataArtifactCleanupWarning] {
        await scheduleRetry()
    }

    private func scheduleRetry() async -> [AppDataArtifactCleanupWarning] {
        let previous = pendingRun
        runGeneration &+= 1
        let generation = runGeneration
        // Actor methods can interleave at cleanup's await. Serialize entire runs
        // so an old pending-set snapshot cannot overwrite a newly queued artifact.
        let task = Task {
            _ = await previous?.value
            return await processPending()
        }
        pendingRun = task
        let warnings = await task.value
        if runGeneration == generation { pendingRun = nil }
        return warnings
    }

    private func processPending() async -> [AppDataArtifactCleanupWarning] {
        let pending = pendingArtifacts()
        var warnings: [AppDataArtifactCleanupWarning] = []

        // A user deletion targets a workout, independent of wall-clock changes.
        // Restore cleanup keeps its separate timestamp boundary below.
        for id in deletedSessionIDs() {
            do {
                try await snapshotDeletion(id)
                setDeletedSessionIDs(deletedSessionIDs().subtracting([id]))
            } catch {
                warnings.append(AppDataArtifactCleanupWarning(
                    artifact: .activeWorkoutSnapshot, description: String(describing: error)
                ))
            }
        }

        for artifact in AppDataArtifact.allCases where pending.contains(artifact) {
            let revision = artifactRevisions[artifact, default: 0]
            do {
                let cutoffs = defaults.dictionary(forKey: "appDataArtifactCleanupQueue.cutoffs") as? [String: Double] ?? [:]
                let cutoff = Date(timeIntervalSince1970: cutoffs[artifact.rawValue] ?? Date.now.timeIntervalSince1970)
                try await cleanup(artifact, cutoff)
                if artifactRevisions[artifact, default: 0] == revision {
                    var remaining = pendingArtifacts()
                    remaining.remove(artifact)
                    setPendingArtifacts(remaining)
                }
            } catch {
                warnings.append(AppDataArtifactCleanupWarning(
                    artifact: artifact,
                    description: String(describing: error)
                ))
            }
        }

        return warnings
    }

    private func pendingArtifacts() -> Set<AppDataArtifact> {
        Set(
            (defaults.stringArray(forKey: pendingDefaultsKey) ?? [])
                .compactMap(AppDataArtifact.init(rawValue:))
        )
    }

    private func deletedSessionIDs() -> Set<UUID> {
        Set((defaults.stringArray(forKey: Self.deletedSessionsDefaultsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func setDeletedSessionIDs(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.deletedSessionsDefaultsKey)
    }

    private func setPendingArtifacts(_ artifacts: Set<AppDataArtifact>) {
        defaults.set(
            artifacts.map(\.rawValue).sorted(),
            forKey: pendingDefaultsKey
        )
    }
}
