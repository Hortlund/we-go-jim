import Foundation
import SwiftData
import UIKit

@MainActor
protocol ExerciseCatalogRepositoryProtocol {
    func ensureSeedImportedIfNeeded() throws
    func refreshCatalog(force: Bool) async throws
    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem]
    func groupedByMuscle(primaryOnly: Bool) throws -> [ExerciseMuscleGroupSection]
    func createCustomExercise(draft: CustomExerciseDraft) throws -> ExerciseCatalogItem
}

enum ExerciseCatalogRepositoryError: LocalizedError {
    case emptyName
    case emptyCategory
    case missingPrimaryMuscles
    case duplicateName
    case invalidMuscleSelection

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Exercise name is required."
        case .emptyCategory:
            return "Exercise category is required."
        case .missingPrimaryMuscles:
            return "Select at least one primary muscle."
        case .duplicateName:
            return "An exercise with that name already exists."
        case .invalidMuscleSelection:
            return "The selected muscles are no longer available."
        }
    }
}

@MainActor
final class ExerciseCatalogRepository: ExerciseCatalogRepositoryProtocol {
    private let syncService: ExerciseCatalogSyncService
    private let searchService: ExerciseSearchService
    private let imageCacheService: ExerciseImageCacheService
    private let modelContext: ModelContext

    init(
        modelContext: ModelContext,
        seedLoader: ExerciseSeedLoading
    ) {
        self.modelContext = modelContext
        self.syncService = ExerciseCatalogSyncService(
            modelContext: modelContext,
            seedLoader: seedLoader
        )
        self.searchService = ExerciseSearchService(modelContext: modelContext)
        self.imageCacheService = ExerciseImageCacheService(modelContext: modelContext)
    }

    convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            seedLoader: BundleExerciseSeedLoader()
        )
    }

    func refreshCatalog(force: Bool) async throws {
        try await syncService.refreshCatalog(force: force)
    }

    func ensureSeedImportedIfNeeded() throws {
        try syncService.ensureSeedImportedIfNeeded()
    }

    func createCustomExercise(draft: CustomExerciseDraft) throws -> ExerciseCatalogItem {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryName = draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let equipmentSummary = draft.equipmentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionText = draft.instructionText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            throw ExerciseCatalogRepositoryError.emptyName
        }

        guard !categoryName.isEmpty else {
            throw ExerciseCatalogRepositoryError.emptyCategory
        }

        let primaryMuscleIDs = Array(Set(draft.primaryMuscleIDs)).sorted()
        guard !primaryMuscleIDs.isEmpty else {
            throw ExerciseCatalogRepositoryError.missingPrimaryMuscles
        }

        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let existingExercises = try modelContext.fetch(descriptor)
        if existingExercises.contains(where: { $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            throw ExerciseCatalogRepositoryError.duplicateName
        }

        let muscles = try modelContext.fetch(FetchDescriptor<MuscleGroup>())
        let musclesByID = Dictionary(uniqueKeysWithValues: muscles.map { ($0.remoteID, $0) })

        let primaryMuscles = primaryMuscleIDs.compactMap { musclesByID[$0] }
        guard primaryMuscles.count == primaryMuscleIDs.count else {
            throw ExerciseCatalogRepositoryError.invalidMuscleSelection
        }

        let secondaryMuscleIDs = Array(Set(draft.secondaryMuscleIDs))
            .filter { !primaryMuscleIDs.contains($0) }
            .sorted()
        let secondaryMuscles = secondaryMuscleIDs.compactMap { musclesByID[$0] }
        guard secondaryMuscles.count == secondaryMuscleIDs.count else {
            throw ExerciseCatalogRepositoryError.invalidMuscleSelection
        }

        let exercise = ExerciseCatalogItem(
            remoteUUID: "custom-\(UUID().uuidString.lowercased())",
            displayName: name,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            instructionText: instructionText,
            isCurated: false,
            isHidden: false,
            sourceName: "custom",
            lastUpdateGlobal: nil,
            updatedAt: .now
        )
        modelContext.insert(exercise)

        exercise.primaryMuscles = primaryMuscles
        exercise.secondaryMuscles = secondaryMuscles
        replaceAliases(on: exercise, aliases: draft.aliases)

        try modelContext.save()
        return exercise
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

    private func replaceAliases(on exercise: ExerciseCatalogItem, aliases: [String]) {
        let uniqueAliases = Set(
            aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(exercise.displayName) != .orderedSame }
        )

        for alias in uniqueAliases.sorted() {
            let model = ExerciseAlias(value: alias, exercise: exercise)
            modelContext.insert(model)
            exercise.aliases.append(model)
        }
    }
}
