import Foundation
import SwiftData

@MainActor
final class ExerciseSearchService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem] {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        let allExercises = try modelContext.fetch(descriptor)
        return allExercises.filter { exercise in
            matchesVisibility(exercise: exercise, filters: filters)
                && matchesFilters(exercise: exercise, filters: filters)
                && matchesQuery(exercise: exercise, query: query)
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
        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let exercises = try modelContext.fetch(descriptor)
        let categories = exercises
            .filter { !$0.isHidden && (includeUncurated || $0.isCurated) }
            .map(\.categoryName)
            .filter { !$0.isEmpty }
        return Array(Set(categories)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func availableEquipmentTokens(includeUncurated: Bool) throws -> [String] {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let exercises = try modelContext.fetch(descriptor)

        let tokens = exercises
            .filter { !$0.isHidden && (includeUncurated || $0.isCurated) }
            .flatMap(\.equipmentTokens)

        return Array(Set(tokens)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func matchesVisibility(exercise: ExerciseCatalogItem, filters: ExerciseFilters) -> Bool {
        !exercise.isHidden && (filters.includeUncurated || exercise.isCurated)
    }

    private func matchesFilters(exercise: ExerciseCatalogItem, filters: ExerciseFilters) -> Bool {
        if let primaryID = filters.primaryMuscleID,
           !exercise.primaryMuscles.contains(where: { $0.remoteID == primaryID }) {
            return false
        }

        if let secondaryID = filters.secondaryMuscleID,
           !exercise.secondaryMuscles.contains(where: { $0.remoteID == secondaryID }) {
            return false
        }

        if let category = filters.categoryName,
           exercise.categoryName.localizedCaseInsensitiveCompare(category) != .orderedSame {
            return false
        }

        if let equipment = filters.equipmentToken {
            let match = exercise.equipmentTokens.contains {
                $0.localizedCaseInsensitiveCompare(equipment) == .orderedSame
            }
            if !match {
                return false
            }
        }

        return true
    }

    private func matchesQuery(exercise: ExerciseCatalogItem, query: String) -> Bool {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return true
        }

        return exercise.searchableTerms.contains {
            $0.lowercased().contains(normalized)
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
}
