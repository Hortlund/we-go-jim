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
    static let shared = AppDataArtifactCleanupQueue { artifact in
        switch artifact {
        case .activeWorkoutSnapshot:
            try await ActiveWorkoutSnapshotStore.shared.invalidateSnapshotsSavedBefore(.now)
            try await ActiveWorkoutSnapshotStore.shared.delete()
        case .weeklyGoalWidgetSnapshot:
            WeeklyGoalWidgetPublisher()?.clear()
        case .exerciseImageCache:
            AppDataDeletionService.removeExerciseImageCacheDirectory()
        }
    }

    private let defaults: UserDefaults
    private let cleanup: @Sendable (AppDataArtifact) async throws -> Void
    private var pendingRun: Task<[AppDataArtifactCleanupWarning], Never>?
    private var runGeneration: UInt64 = 0
    private var artifactRevisions: [AppDataArtifact: UInt64] = [:]
    private let pendingDefaultsKey = "appDataArtifactCleanupQueue.pendingArtifacts"

    init(
        defaults: UserDefaults = .standard,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void
    ) {
        self.defaults = defaults
        self.cleanup = cleanup
    }

    init(
        defaultsSuiteName: String,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void
    ) {
        self.defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.cleanup = cleanup
    }

    func enqueue(_ artifacts: Set<AppDataArtifact>) async -> [AppDataArtifactCleanupWarning] {
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

        for artifact in AppDataArtifact.allCases where pending.contains(artifact) {
            let revision = artifactRevisions[artifact, default: 0]
            do {
                try await cleanup(artifact)
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

    private func setPendingArtifacts(_ artifacts: Set<AppDataArtifact>) {
        defaults.set(
            artifacts.map(\.rawValue).sorted(),
            forKey: pendingDefaultsKey
        )
    }
}
