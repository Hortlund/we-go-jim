import Foundation
import SwiftData

nonisolated final class ExerciseSearchService {
    private let modelContext: ModelContext
    private static let cacheLock = NSLock()
    private static var cachedCatalogIndexByContextID: [ObjectIdentifier: CatalogSearchCacheEntry] = [:]
    private static var catalogGenerationByContainerID: [ObjectIdentifier: Int] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func invalidateCatalogIndex(for modelContext: ModelContext) {
        let containerID = ObjectIdentifier(modelContext.container)

        cacheLock.lock()
        catalogGenerationByContainerID[containerID, default: 0] += 1
        cachedCatalogIndexByContextID = cachedCatalogIndexByContextID.filter { _, entry in
            entry.containerID != containerID
        }
        cacheLock.unlock()
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
        let contextID = ObjectIdentifier(modelContext)
        let containerID = ObjectIdentifier(modelContext.container)
        let generation = Self.catalogGeneration(for: containerID)
        if let cachedEntry = Self.cachedCatalogIndex(for: contextID),
           cachedEntry.containerID == containerID,
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
            containerID: containerID,
            generation: generation,
            index: index
        )
        Self.setCachedCatalogIndex(cacheEntry, for: contextID)
        return index
    }

    private static func catalogGeneration(for containerID: ObjectIdentifier) -> Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return catalogGenerationByContainerID[containerID, default: 0]
    }

    private static func cachedCatalogIndex(for contextID: ObjectIdentifier) -> CatalogSearchCacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedCatalogIndexByContextID[contextID]
    }

    private static func setCachedCatalogIndex(_ entry: CatalogSearchCacheEntry, for contextID: ObjectIdentifier) {
        cacheLock.lock()
        cachedCatalogIndexByContextID[contextID] = entry
        cacheLock.unlock()
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
    let containerID: ObjectIdentifier
    let generation: Int
    let index: CatalogSearchIndex
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
