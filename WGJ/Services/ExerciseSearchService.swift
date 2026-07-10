import Foundation
import SwiftData

nonisolated final class ExerciseSearchService {
    private let modelContext: ModelContext
    private static let generationStore = CatalogSearchGenerationStore()
    private var cachedCatalogIndex: CatalogSearchCacheEntry?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func invalidateCatalogIndex(for modelContext: ModelContext) {
        generationStore.invalidate(container: modelContext.container)
    }

    static func clearCachedCatalogIndexes() {
        generationStore.invalidateAll()
    }

    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem] {
        let rows = try catalogRows()
        return rows.compactMap { row in
            guard matchesVisibility(row: row, filters: filters),
                  matchesFilters(row: row, filters: filters),
                  matchesQuery(row: row, query: query)
            else {
                return nil
            }
            return row.exercise
        }
    }

    func groupedByMuscle(
        primaryOnly: Bool,
        query: String,
        filters: ExerciseFilters
    ) throws -> [ExerciseMuscleGroupSection] {
        let exercises = try searchExercises(query: query, filters: filters)
        var groups: [String: [ExerciseCatalogItem]] = [:]

        for exercise in exercises {
            var didAssign = false

            for muscle in exercise.primaryMuscles {
                groups[muscle.name, default: []].append(exercise)
                didAssign = true
            }

            if !primaryOnly {
                for muscle in exercise.secondaryMuscles {
                    groups["\(muscle.name) (secondary)", default: []].append(exercise)
                    didAssign = true
                }
            }

            if !didAssign {
                groups["Unspecified", default: []].append(exercise)
            }
        }

        return groups
            .map { key, values in
                let deduplicated = deduplicateByUUID(values)
                return ExerciseMuscleGroupSection(
                    id: key,
                    title: key,
                    exercises: deduplicated.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func availableMuscles() throws -> [MuscleGroup] {
        let descriptor = FetchDescriptor<MuscleGroup>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func availableCategories(includeUncurated: Bool) throws -> [String] {
        let categories = try catalogRows()
            .filter { isVisibleInCatalog($0, includeUncurated: includeUncurated) }
            .map(\.categoryName)
            .filter { !$0.isEmpty }
        return Array(Set(categories)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func availableEquipmentTokens(includeUncurated: Bool) throws -> [String] {
        let tokens = try catalogRows()
            .filter { isVisibleInCatalog($0, includeUncurated: includeUncurated) }
            .flatMap { Array($0.equipmentTokenSet) }

        return Array(Set(tokens)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func catalogRows() throws -> [CatalogSearchRow] {
        try catalogIndex().rows
    }

    private func catalogIndex() throws -> CatalogSearchIndex {
        let generation = Self.generationStore.generation(for: modelContext.container)
        if let cachedEntry = cachedCatalogIndex,
           cachedEntry.generation == generation {
            return cachedEntry.index
        }

        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        let exercises = try modelContext.fetch(descriptor)
        let index = CatalogSearchIndex(
            rows: exercises.map(CatalogSearchRow.init(exercise:))
        )
        let cacheEntry = CatalogSearchCacheEntry(
            generation: generation,
            index: index
        )
        cachedCatalogIndex = cacheEntry
        return index
    }

    private func matchesVisibility(row: CatalogSearchRow, filters: ExerciseFilters) -> Bool {
        isVisibleInCatalog(row, includeUncurated: filters.includeUncurated)
    }

    private func matchesFilters(row: CatalogSearchRow, filters: ExerciseFilters) -> Bool {
        if let primaryID = filters.primaryMuscleID,
           !row.primaryMuscleIDs.contains(primaryID) {
            return false
        }

        if let secondaryID = filters.secondaryMuscleID,
           !row.secondaryMuscleIDs.contains(secondaryID) {
            return false
        }

        if let category = filters.categoryName,
           row.categoryName.localizedCaseInsensitiveCompare(category) != .orderedSame {
            return false
        }

        if let equipment = filters.equipmentToken {
            let normalizedEquipment = equipment.lowercased()
            if !row.equipmentTokenSet.contains(normalizedEquipment) {
                return false
            }
        }

        return true
    }

    private func matchesQuery(row: CatalogSearchRow, query: String) -> Bool {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return true
        }

        return row.searchTerms.contains {
            $0.contains(normalized)
        }
    }

    private func deduplicateByUUID(_ exercises: [ExerciseCatalogItem]) -> [ExerciseCatalogItem] {
        var seen: Set<String> = []
        var deduplicated: [ExerciseCatalogItem] = []

        for exercise in exercises where !seen.contains(exercise.remoteUUID) {
            seen.insert(exercise.remoteUUID)
            deduplicated.append(exercise)
        }

        return deduplicated
    }

    private func isVisibleInCatalog(_ row: CatalogSearchRow, includeUncurated: Bool) -> Bool {
        guard !row.isHidden else {
            return false
        }

        if row.isCustomExercise {
            return true
        }

        return includeUncurated || row.isCurated
    }
}

nonisolated private struct CatalogSearchCacheEntry {
    let generation: CatalogSearchGeneration
    let index: CatalogSearchIndex
}

nonisolated private struct CatalogSearchGeneration: Equatable, Sendable {
    let global: Int
    let container: Int
}

/// The only process-wide search state is a revision counter. Context-bound
/// SwiftData models stay in each service instance and never enter this store.
nonisolated private final class CatalogSearchGenerationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var globalGeneration = 0
    private var generationByContainerID: [ObjectIdentifier: Int] = [:]

    func generation(for container: ModelContainer) -> CatalogSearchGeneration {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        defer { lock.unlock() }
        return CatalogSearchGeneration(
            global: globalGeneration,
            container: generationByContainerID[containerID, default: 0]
        )
    }

    func invalidate(container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        generationByContainerID[containerID, default: 0] += 1
        lock.unlock()
    }

    func invalidateAll() {
        lock.lock()
        globalGeneration += 1
        generationByContainerID.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

nonisolated private struct CatalogSearchIndex {
    let rows: [CatalogSearchRow]
}

nonisolated private struct CatalogSearchRow {
    let exercise: ExerciseCatalogItem
    let searchTerms: [String]
    let categoryName: String
    let equipmentTokenSet: Set<String>
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let isHidden: Bool
    let isCustomExercise: Bool
    let isCurated: Bool

    init(exercise: ExerciseCatalogItem) {
        self.exercise = exercise
        self.searchTerms = exercise.searchableTerms.map { $0.lowercased() }
        self.categoryName = exercise.categoryName
        self.equipmentTokenSet = Set(exercise.equipmentTokens.map { $0.lowercased() })
        self.primaryMuscleIDs = Set(exercise.primaryMuscles.map(\.remoteID))
        self.secondaryMuscleIDs = Set(exercise.secondaryMuscles.map(\.remoteID))
        self.isHidden = exercise.isHidden
        self.isCustomExercise = exercise.isCustomExercise
        self.isCurated = exercise.isCurated
    }
}
