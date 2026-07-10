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
    private let pendingDefaultsKey = "appDataArtifactCleanupQueue.pendingArtifacts"

    init(
        defaults: UserDefaults = .standard,
        cleanup: @escaping @Sendable (AppDataArtifact) async throws -> Void
    ) {
        self.defaults = defaults
        self.cleanup = cleanup
    }

    func enqueue(_ artifacts: Set<AppDataArtifact>) async -> [AppDataArtifactCleanupWarning] {
        setPendingArtifacts(pendingArtifacts().union(artifacts))
        return await retryPending()
    }

    func retryPending() async -> [AppDataArtifactCleanupWarning] {
        var pending = pendingArtifacts()
        var warnings: [AppDataArtifactCleanupWarning] = []

        for artifact in AppDataArtifact.allCases where pending.contains(artifact) {
            do {
                try await cleanup(artifact)
                pending.remove(artifact)
                setPendingArtifacts(pending)
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
