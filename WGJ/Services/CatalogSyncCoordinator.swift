import Foundation
import SwiftData

@MainActor
@Observable
final class CatalogSyncCoordinator {
    private var isPrimingLocalCatalog = false
    private(set) var hasPrimedLocalCatalog = false

    init() {}

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

    func markPrimed() {
        hasPrimedLocalCatalog = true
    }
}
