import Foundation
import SwiftData
import UIKit

@MainActor
protocol ExerciseCatalogRepositoryProtocol {
    func refreshCatalog(force: Bool) async throws
    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem]
    func groupedByMuscle(primaryOnly: Bool) throws -> [ExerciseMuscleGroupSection]
}

@MainActor
final class ExerciseCatalogRepository: ExerciseCatalogRepositoryProtocol {
    private let syncService: ExerciseCatalogSyncService
    private let searchService: ExerciseSearchService
    private let imageCacheService: ExerciseImageCacheService
    private let modelContext: ModelContext

    init(
        modelContext: ModelContext,
        remoteClient: ExerciseCatalogRemoteClient,
        seedLoader: ExerciseSeedLoading
    ) {
        self.modelContext = modelContext
        self.syncService = ExerciseCatalogSyncService(
            modelContext: modelContext,
            remoteClient: remoteClient,
            seedLoader: seedLoader
        )
        self.searchService = ExerciseSearchService(modelContext: modelContext)
        self.imageCacheService = ExerciseImageCacheService(modelContext: modelContext)
    }

    convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            remoteClient: WgerRemoteClient(),
            seedLoader: BundleExerciseSeedLoader()
        )
    }

    func refreshCatalog(force: Bool) async throws {
        try await syncService.refreshCatalog(force: force)
    }

    func ensureSeedImportedIfNeeded() throws {
        try syncService.ensureSeedImportedIfNeeded()
    }

    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem] {
        try searchService.searchExercises(query: query, filters: filters)
    }

    func searchExercises(query: String) throws -> [ExerciseCatalogItem] {
        try searchService.searchExercises(query: query, filters: .default)
    }

    func groupedByMuscle(primaryOnly: Bool) throws -> [ExerciseMuscleGroupSection] {
        try searchService.groupedByMuscle(primaryOnly: primaryOnly, query: "", filters: .default)
    }

    func groupedByMuscle(
        primaryOnly: Bool,
        query: String,
        filters: ExerciseFilters
    ) throws -> [ExerciseMuscleGroupSection] {
        try searchService.groupedByMuscle(primaryOnly: primaryOnly, query: query, filters: filters)
    }

    func availableMuscles() throws -> [MuscleGroup] {
        try searchService.availableMuscles()
    }

    func availableCategories(includeUncurated: Bool) throws -> [String] {
        try searchService.availableCategories(includeUncurated: includeUncurated)
    }

    func availableEquipmentTokens(includeUncurated: Bool) throws -> [String] {
        try searchService.availableEquipmentTokens(includeUncurated: includeUncurated)
    }

    func image(for exercise: ExerciseCatalogItem) async -> UIImage? {
        await imageCacheService.image(for: exercise)
    }

    func syncState() -> ExerciseCatalogSyncState? {
        let descriptor = FetchDescriptor<ExerciseCatalogSyncState>()
        return (try? modelContext.fetch(descriptor))?.first(where: { $0.key == "global" })
    }
}
