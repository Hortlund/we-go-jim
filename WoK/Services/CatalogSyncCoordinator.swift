import Foundation
import SwiftData

@MainActor
@Observable
final class CatalogSyncCoordinator {
    enum SyncReason {
        case appLaunch
        case appForeground
        case manual
    }

    private let minimumIntervalBetweenAttempts: TimeInterval
    private var lastAttemptAt: Date?
    private var inFlightTask: Task<Void, Never>?
    private var isPrimingLocalCatalog = false
    private(set) var hasPrimedLocalCatalog = false

    init(minimumIntervalBetweenAttempts: TimeInterval = 20) {
        self.minimumIntervalBetweenAttempts = minimumIntervalBetweenAttempts
    }

    func primeLocalCatalogIfNeeded(modelContext: ModelContext) {
        guard !hasPrimedLocalCatalog, !isPrimingLocalCatalog else { return }
        isPrimingLocalCatalog = true
        defer { isPrimingLocalCatalog = false }

        let repository = ExerciseCatalogRepository(modelContext: modelContext)
        do {
            try repository.ensureSeedImportedIfNeeded()
            hasPrimedLocalCatalog = true
        } catch {
            // Priming errors are surfaced by view-level empty/retry states.
        }
    }

    func scheduleStaleSyncIfNeeded(
        modelContext: ModelContext,
        reason: SyncReason
    ) {
        guard inFlightTask == nil else { return }

        if reason != .manual,
           let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt) < minimumIntervalBetweenAttempts {
            return
        }

        lastAttemptAt = Date()
        inFlightTask = Task { @MainActor [weak self] in
            defer {
                self?.inFlightTask = nil
            }

            let repository = ExerciseCatalogRepository(modelContext: modelContext)
            do {
                try repository.ensureSeedImportedIfNeeded()
                try await repository.refreshCatalog(force: reason == .manual)
            } catch {
                // Sync errors are intentionally ignored in lifecycle sync;
                // Settings/manual paths are responsible for user-facing errors.
            }
        }
    }
}
