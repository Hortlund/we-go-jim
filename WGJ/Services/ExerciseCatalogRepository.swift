import Foundation
import SwiftData
import UIKit

nonisolated protocol ExerciseCatalogRepositoryProtocol {
    func ensureSeedImportedIfNeeded() throws
    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem]
    func groupedByMuscle(primaryOnly: Bool) throws -> [ExerciseMuscleGroupSection]
    func exerciseMap(for remoteUUIDs: [String]) throws -> [String: ExerciseCatalogItem]
    func exerciseSnapshotMap(for remoteUUIDs: [String]) throws -> [String: TrainingGuidanceCatalogSnapshot]
    func createCustomExercise(draft: CustomExerciseDraft) throws -> ExerciseCatalogItem
    func updateCustomExercise(_ exercise: ExerciseCatalogItem, draft: CustomExerciseDraft) throws
}

enum ExerciseCatalogRepositoryError: LocalizedError {
    case emptyName
    case emptyCategory
    case missingPrimaryMuscles
    case duplicateName
    case invalidMuscleSelection
    case nonEditableExercise

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
        case .nonEditableExercise:
            return "Only custom exercises can be edited."
        }
    }
}

nonisolated final class ExerciseCatalogRepository: ExerciseCatalogRepositoryProtocol {
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

    func ensureSeedImportedIfNeeded() throws {
        try syncService.ensureSeedImportedIfNeeded()
    }

    func createCustomExercise(draft: CustomExerciseDraft) throws -> ExerciseCatalogItem {
        let validated = try validatedCustomExerciseInput(draft: draft)

        let exercise = ExerciseCatalogItem(
            remoteUUID: "custom-\(UUID().uuidString.lowercased())",
            displayName: validated.name,
            categoryName: validated.categoryName,
            equipmentSummary: validated.equipmentSummary,
            instructionText: validated.instructionText,
            isCurated: false,
            isHidden: false,
            sourceName: "custom",
            lastUpdateGlobal: nil,
            updatedAt: .now
        )
        modelContext.insert(exercise)

        exercise.primaryMuscles = validated.primaryMuscles
        exercise.secondaryMuscles = validated.secondaryMuscles
        replaceAliases(on: exercise, aliases: validated.aliases)

        try modelContext.save()
        return exercise
    }

    func updateCustomExercise(_ exercise: ExerciseCatalogItem, draft: CustomExerciseDraft) throws {
        guard exercise.isCustomExercise else {
            throw ExerciseCatalogRepositoryError.nonEditableExercise
        }

        let validated = try validatedCustomExerciseInput(draft: draft, excluding: exercise)

        exercise.displayName = validated.name
        exercise.categoryName = validated.categoryName
        exercise.equipmentSummary = validated.equipmentSummary
        exercise.instructionText = validated.instructionText
        exercise.primaryMuscles = validated.primaryMuscles
        exercise.secondaryMuscles = validated.secondaryMuscles
        exercise.updatedAt = .now
        replaceAliases(on: exercise, aliases: validated.aliases)
        try refreshTemplateSnapshots(for: exercise)

        try modelContext.save()
    }

    func searchExercises(query: String, filters: ExerciseFilters) throws -> [ExerciseCatalogItem] {
        try searchService.searchExercises(query: query, filters: filters)
    }

    func searchExercises(query: String) throws -> [ExerciseCatalogItem] {
        try searchService.searchExercises(query: query, filters: .default)
    }

    func allExercises() throws -> [ExerciseCatalogItem] {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
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

    func exerciseMap(for remoteUUIDs: [String]) throws -> [String: ExerciseCatalogItem] {
        let requested = Set(
            remoteUUIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !requested.isEmpty else {
            return [:]
        }

        let requestedList = Array(requested)
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                requestedList.contains(exercise.remoteUUID)
            }
        )
        let matches = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: matches.map { ($0.remoteUUID, $0) })
    }

    func exerciseSnapshotMap(for remoteUUIDs: [String]) throws -> [String: TrainingGuidanceCatalogSnapshot] {
        try exerciseMap(for: remoteUUIDs).mapValues(TrainingGuidanceCatalogSnapshot.init(exercise:))
    }

    func exactImportMatch(
        remoteUUID: String,
        exerciseName: String,
        categoryName: String
    ) throws -> ExerciseCatalogItem? {
        let normalizedUUID = remoteUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedUUID.isEmpty,
           let exactUUIDMatch = try exerciseMap(for: [normalizedUUID])[normalizedUUID] {
            return exactUUIDMatch
        }

        let normalizedName = normalizedImportMatchToken(exerciseName)
        let normalizedCategory = normalizedImportMatchToken(categoryName)
        guard !normalizedName.isEmpty, !normalizedCategory.isEmpty else {
            return nil
        }

        var matchesByUUID: [String: ExerciseCatalogItem] = [:]
        for exercise in try allExercises() {
            guard normalizedImportMatchToken(exercise.categoryName) == normalizedCategory else {
                continue
            }

            let displayNameMatches = normalizedImportMatchToken(exercise.displayName) == normalizedName
            let aliasMatches = exercise.aliases.contains { alias in
                normalizedImportMatchToken(alias.value) == normalizedName
            }
            guard displayNameMatches || aliasMatches else {
                continue
            }

            matchesByUUID[exercise.remoteUUID] = exercise
            if matchesByUUID.count > 1 {
                return nil
            }
        }

        return matchesByUUID.values.first
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
        var descriptor = FetchDescriptor<ExerciseCatalogSyncState>(
            predicate: #Predicate { $0.key == "global" }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func validatedCustomExerciseInput(
        draft: CustomExerciseDraft,
        excluding excludedExercise: ExerciseCatalogItem? = nil
    ) throws -> ValidatedCustomExerciseInput {
        let name = try ReviewModerationService.validateUserInput(draft.name, kind: .exerciseName)
        let categoryName = draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let equipmentSummary = draft.equipmentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionText = draft.instructionText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !categoryName.isEmpty else {
            throw ExerciseCatalogRepositoryError.emptyCategory
        }

        let primaryMuscleIDs = Array(Set(draft.primaryMuscleIDs)).sorted()
        guard !primaryMuscleIDs.isEmpty else {
            throw ExerciseCatalogRepositoryError.missingPrimaryMuscles
        }

        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let existingExercises = try modelContext.fetch(descriptor)
        if existingExercises.contains(where: {
            $0.remoteUUID != excludedExercise?.remoteUUID
                && $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
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

        return ValidatedCustomExerciseInput(
            name: name,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            instructionText: instructionText.isEmpty ? nil : instructionText,
            aliases: draft.aliases,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles
        )
    }

    private func replaceAliases(on exercise: ExerciseCatalogItem, aliases: [String]) {
        for alias in exercise.aliases {
            modelContext.delete(alias)
        }
        exercise.aliases.removeAll()

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

    private func refreshTemplateSnapshots(for exercise: ExerciseCatalogItem) throws {
        let catalogExerciseUUID = exercise.remoteUUID
        let componentDescriptor = FetchDescriptor<TemplateExerciseComponent>(
            predicate: #Predicate { component in
                component.catalogExerciseUUID == catalogExerciseUUID
            }
        )
        let matchedComponents = try modelContext.fetch(componentDescriptor)
        for component in matchedComponents {
            component.exerciseNameSnapshot = exercise.displayName
            component.categorySnapshot = exercise.categoryName
            component.muscleSummarySnapshot = exercise.primaryMuscleNames
            component.updatedAt = .now
        }

        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { templateExercise in
                templateExercise.catalogExerciseUUID == catalogExerciseUUID
            }
        )

        for templateExercise in try modelContext.fetch(descriptor) {
            templateExercise.exerciseNameSnapshot = exercise.displayName
            templateExercise.categorySnapshot = exercise.categoryName
            templateExercise.muscleSummarySnapshot = exercise.primaryMuscleNames
            templateExercise.updatedAt = .now
        }

        for component in matchedComponents where component.sortOrder == 0 {
            component.templateExercise?.exerciseNameSnapshot = component.exerciseNameSnapshot
            component.templateExercise?.categorySnapshot = component.categorySnapshot
            component.templateExercise?.muscleSummarySnapshot = component.muscleSummarySnapshot
            component.templateExercise?.updatedAt = .now
        }
    }

    private func normalizedImportMatchToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

nonisolated private struct ValidatedCustomExerciseInput {
    let name: String
    let categoryName: String
    let equipmentSummary: String
    let instructionText: String?
    let aliases: [String]
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
}
