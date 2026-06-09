import Foundation
import SwiftData

@MainActor
@Observable
final class CatalogSyncCoordinator {
    private var isPrimingLocalCatalog = false
    private(set) var hasPrimedLocalCatalog = false

    init() {}

    func primeLocalCatalogIfNeeded(backgroundStore: AppBackgroundStore) async {
        guard !hasPrimedLocalCatalog, !isPrimingLocalCatalog else { return }
        isPrimingLocalCatalog = true
        defer { isPrimingLocalCatalog = false }

        do {
            try await backgroundStore.perform("catalog.prime-local") { backgroundContext in
                try ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
            }
            hasPrimedLocalCatalog = true
        } catch {
            // Priming errors are surfaced by view-level empty/retry states.
        }
    }

    func markPrimed() {
        hasPrimedLocalCatalog = true
    }
}
