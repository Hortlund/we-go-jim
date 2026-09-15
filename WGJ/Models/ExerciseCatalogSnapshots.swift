import Foundation
import SwiftData

nonisolated struct ExerciseDetailDisplaySnapshot: Hashable, Sendable {
    let remoteUUID: String
    let displayName: String
    let categoryName: String
    let equipmentSummary: String
    let primaryMuscleNames: String
    let secondaryMuscleNames: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let instructionSteps: [String]

    init(
        remoteUUID: String,
        displayName: String,
        categoryName: String,
        equipmentSummary: String = "",
        primaryMuscleNames: String = "",
        secondaryMuscleNames: String = "",
        primaryMuscleIDs: Set<Int> = [],
        secondaryMuscleIDs: Set<Int> = [],
        instructionSteps: [String] = []
    ) {
        self.remoteUUID = remoteUUID
        self.displayName = displayName
        self.categoryName = categoryName
        self.equipmentSummary = equipmentSummary
        self.primaryMuscleNames = primaryMuscleNames
        self.secondaryMuscleNames = secondaryMuscleNames
        self.primaryMuscleIDs = primaryMuscleIDs
        self.secondaryMuscleIDs = secondaryMuscleIDs
        self.instructionSteps = instructionSteps
    }

    init(exercise: ExerciseCatalogItemSnapshot) {
        remoteUUID = exercise.remoteUUID
        displayName = exercise.displayName
        categoryName = exercise.categoryName
        equipmentSummary = exercise.equipmentSummary
        primaryMuscleNames = exercise.primaryMuscleNames
        secondaryMuscleNames = exercise.secondaryMuscleNames
        primaryMuscleIDs = exercise.primaryMuscleIDs
        secondaryMuscleIDs = exercise.secondaryMuscleIDs
        instructionSteps = exercise.instructionSteps
    }

    @MainActor
    init(exercise: ExerciseCatalogItem) {
        remoteUUID = exercise.remoteUUID
        displayName = exercise.displayName
        categoryName = exercise.categoryName
        equipmentSummary = exercise.equipmentSummary
        primaryMuscleNames = exercise.primaryMuscleNames
        secondaryMuscleNames = exercise.secondaryMuscleNames
        primaryMuscleIDs = Set(exercise.primaryMuscles.map(\.remoteID))
        secondaryMuscleIDs = Set(exercise.secondaryMuscles.map(\.remoteID))
        instructionSteps = exercise.instructionSteps
    }
}

struct ExercisesCatalogSearchState: Equatable {
    private(set) var debouncedQuery = ""
    private(set) var resetToken = 0
    var selectedPrimaryMuscleID: Int?
    var selectedSecondaryMuscleID: Int?
    var selectedEquipmentToken: String?
    var selectedCategory: String?
    var includeUncurated: Bool
    var sortDescending = false

    init(filters: ExerciseFilters = .default) {
        selectedPrimaryMuscleID = filters.primaryMuscleID
        selectedSecondaryMuscleID = filters.secondaryMuscleID
        selectedEquipmentToken = filters.equipmentToken
        selectedCategory = filters.categoryName
        includeUncurated = filters.includeUncurated
    }

    var hasActiveFilters: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPrimaryMuscleID != nil
            || selectedSecondaryMuscleID != nil
            || selectedEquipmentToken != nil
            || selectedCategory != nil
            || includeUncurated
            || sortDescending
    }

    var exerciseFilters: ExerciseFilters {
        ExerciseFilters(
            primaryMuscleID: selectedPrimaryMuscleID,
            secondaryMuscleID: selectedSecondaryMuscleID,
            equipmentToken: selectedEquipmentToken,
            categoryName: selectedCategory,
            includeUncurated: includeUncurated
        )
    }

    mutating func updateDebouncedQuery(_ query: String) {
        debouncedQuery = query
    }

    mutating func clearSearchAndFilters() {
        debouncedQuery = ""
        selectedPrimaryMuscleID = nil
        selectedSecondaryMuscleID = nil
        selectedEquipmentToken = nil
        selectedCategory = nil
        includeUncurated = false
        sortDescending = false
        resetToken += 1
    }
}

nonisolated enum ExercisesCatalogSnapshotLoader {
    static func load(modelContext: ModelContext) throws -> ExercisesCatalogSnapshot {
        let repository = ExerciseCatalogRepository(modelContext: modelContext)
        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(
            from: try repository.allExercises(),
            muscleGroups: try repository.availableMuscles()
        )
        return snapshot
    }
}

nonisolated struct ExerciseMuscleSnapshot: Identifiable, Equatable, Sendable {
    let id: Int
    let remoteID: Int
    let name: String

    init(muscle: MuscleGroup) {
        self.id = muscle.remoteID
        self.remoteID = muscle.remoteID
        self.name = muscle.name
    }
}

nonisolated struct ExerciseCatalogImageSnapshot: Equatable, Sendable {
    let localPath: String?
    let remoteURL: String
}

nonisolated struct ExerciseCatalogItemSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let remoteUUID: String
    let displayName: String
    let categoryName: String
    let equipmentSummary: String
    let equipmentTokens: Set<String>
    let primaryMuscleNames: String
    let cardioTrackingProfileRaw: String?
    let secondaryMuscleNames: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let instructionSteps: [String]
    let isHidden: Bool
    let isCurated: Bool
    let isCustomExercise: Bool
    let aliases: [String]
    let image: ExerciseCatalogImageSnapshot?

    var selection: ExerciseCatalogSelection {
        ExerciseCatalogSelection(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            primaryMuscleNames: primaryMuscleNames,
            cardioTrackingProfileRaw: cardioTrackingProfileRaw
        )
    }

    init(exercise: ExerciseCatalogItem) {
        id = exercise.remoteUUID
        remoteUUID = exercise.remoteUUID
        displayName = exercise.displayName
        categoryName = exercise.categoryName
        equipmentSummary = exercise.equipmentSummary
        equipmentTokens = Set(exercise.equipmentTokens.map { $0.lowercased() })
        primaryMuscleNames = exercise.primaryMuscleNames
        cardioTrackingProfileRaw = exercise.cardioTrackingProfile?.rawValue
        secondaryMuscleNames = exercise.secondaryMuscleNames
        primaryMuscleIDs = Set(exercise.primaryMuscles.map(\.remoteID))
        secondaryMuscleIDs = Set(exercise.secondaryMuscles.map(\.remoteID))
        instructionSteps = exercise.instructionSteps
        isHidden = exercise.isHidden
        isCurated = exercise.isCurated
        isCustomExercise = exercise.isCustomExercise
        aliases = exercise.aliases.map(\.value)
        image = exercise.images.first.map {
            ExerciseCatalogImageSnapshot(
                localPath: $0.localPath,
                remoteURL: $0.remoteURL
            )
        }
    }
}

nonisolated struct ExercisesCatalogSnapshot: Sendable {
    var catalogExercises: [ExerciseCatalogItemSnapshot] = []
    var muscleGroups: [ExerciseMuscleSnapshot] = []
    var exerciseByUUID: [String: ExerciseCatalogItemSnapshot] = [:]
    var availableMuscleNamesByID: [Int: String] = [:]
    var availableMuscles: [ExerciseMuscleSnapshot] = []
    var availableCategories: [String] = []
    var searchDocuments: [ExerciseCatalogSearchDocument] = []
    var totalSectionCount = 0

    static let empty = ExercisesCatalogSnapshot()

    mutating func rebuild(from exercises: [ExerciseCatalogItem], muscleGroups: [MuscleGroup]) {
        let muscleSnapshots = muscleGroups.map(ExerciseMuscleSnapshot.init(muscle:))
        let muscleByID = Dictionary(
            muscleSnapshots.map { ($0.remoteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenExerciseUUIDs: Set<String> = []
        let uniqueExercises = exercises.map(ExerciseCatalogItemSnapshot.init(exercise:)).filter { exercise in
            seenExerciseUUIDs.insert(exercise.remoteUUID).inserted
        }

        catalogExercises = uniqueExercises
        self.muscleGroups = muscleSnapshots
        exerciseByUUID = Dictionary(
            uniqueExercises.map { ($0.remoteUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var muscleNameByID: [Int: String] = [:]
        var categories = Set<String>()

        for exercise in uniqueExercises where !exercise.isHidden {
            for muscleID in exercise.primaryMuscleIDs {
                if let muscle = muscleByID[muscleID] {
                    muscleNameByID[muscle.remoteID] = muscle.name
                }
            }
            if !exercise.categoryName.isEmpty {
                categories.insert(exercise.categoryName)
            }

        }

        availableMuscleNamesByID = muscleNameByID
        availableMuscles = muscleSnapshots
            .filter { muscleNameByID[$0.remoteID] != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        availableCategories = categories
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        searchDocuments = uniqueExercises
            .filter { !$0.isHidden }
            .map { exercise in
                ExerciseCatalogSearchDocument(
                    id: exercise.remoteUUID,
                    displayName: exercise.displayName,
                    aliases: exercise.aliases,
                    categoryName: exercise.categoryName,
                    primaryMuscleNames: exercise.primaryMuscleNames,
                    secondaryMuscleNames: exercise.secondaryMuscleNames,
                    primaryMuscleIDs: exercise.primaryMuscleIDs,
                    secondaryMuscleIDs: exercise.secondaryMuscleIDs,
                    equipmentTokens: exercise.equipmentTokens,
                    isCurated: exercise.isCurated,
                    isCustomExercise: exercise.isCustomExercise
                )
            }
        totalSectionCount = Set(searchDocuments.map(\.indexKey)).count
    }

    func muscleName(for muscleID: Int?) -> String? {
        guard let muscleID else { return nil }
        return availableMuscleNamesByID[muscleID]
    }

}
