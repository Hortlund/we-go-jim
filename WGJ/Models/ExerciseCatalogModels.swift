import Foundation
import SwiftData

@Model
final class ExerciseCatalogItem {
    @Attribute(.unique) var remoteUUID: String
    var remoteID: Int?
    var displayName: String
    var categoryName: String
    var equipmentSummary: String
    var instructionText: String
    var isCurated: Bool
    var isHidden: Bool
    var sourceName: String
    var lastUpdateGlobal: Date?
    var updatedAt: Date

    @Relationship(inverse: \MuscleGroup.primaryExercises) var primaryMuscles: [MuscleGroup]
    @Relationship(inverse: \MuscleGroup.secondaryExercises) var secondaryMuscles: [MuscleGroup]
    @Relationship(deleteRule: .cascade, inverse: \ExerciseAlias.exercise) var aliases: [ExerciseAlias]
    @Relationship(deleteRule: .cascade, inverse: \ExerciseImageAsset.exercise) var images: [ExerciseImageAsset]
    @Relationship(deleteRule: .cascade, inverse: \ExerciseAttribution.exercise) var attributions: [ExerciseAttribution]

    init(
        remoteUUID: String,
        remoteID: Int? = nil,
        displayName: String,
        categoryName: String = "Unknown",
        equipmentSummary: String = "",
        instructionText: String = "",
        isCurated: Bool = false,
        isHidden: Bool = false,
        sourceName: String = "seed",
        lastUpdateGlobal: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.remoteUUID = remoteUUID
        self.remoteID = remoteID
        self.displayName = displayName
        self.categoryName = categoryName
        self.equipmentSummary = equipmentSummary
        self.instructionText = instructionText
        self.isCurated = isCurated
        self.isHidden = isHidden
        self.sourceName = sourceName
        self.lastUpdateGlobal = lastUpdateGlobal
        self.updatedAt = updatedAt
        self.primaryMuscles = []
        self.secondaryMuscles = []
        self.aliases = []
        self.images = []
        self.attributions = []
    }
}

@Model
final class MuscleGroup {
    @Attribute(.unique) var remoteID: Int
    var name: String
    var nameEn: String

    @Relationship var primaryExercises: [ExerciseCatalogItem]
    @Relationship var secondaryExercises: [ExerciseCatalogItem]

    init(remoteID: Int, name: String, nameEn: String) {
        self.remoteID = remoteID
        self.name = name
        self.nameEn = nameEn
        self.primaryExercises = []
        self.secondaryExercises = []
    }
}

@Model
final class ExerciseImageAsset {
    var remoteImageID: Int?
    var remoteURL: String
    var localPath: String?
    var licenseName: String
    var licenseAuthor: String
    var sourceName: String
    var lastAccessedAt: Date
    var fileSizeBytes: Int

    @Relationship var exercise: ExerciseCatalogItem?

    init(
        remoteImageID: Int? = nil,
        remoteURL: String,
        localPath: String? = nil,
        licenseName: String = "Unknown",
        licenseAuthor: String = "",
        sourceName: String = "seed",
        lastAccessedAt: Date = .now,
        fileSizeBytes: Int = 0,
        exercise: ExerciseCatalogItem? = nil
    ) {
        self.remoteImageID = remoteImageID
        self.remoteURL = remoteURL
        self.localPath = localPath
        self.licenseName = licenseName
        self.licenseAuthor = licenseAuthor
        self.sourceName = sourceName
        self.lastAccessedAt = lastAccessedAt
        self.fileSizeBytes = fileSizeBytes
        self.exercise = exercise
    }
}

@Model
final class ExerciseAlias {
    var value: String

    @Relationship var exercise: ExerciseCatalogItem?

    init(value: String, exercise: ExerciseCatalogItem? = nil) {
        self.value = value
        self.exercise = exercise
    }
}

@Model
final class ExerciseAttribution {
    var sourceName: String
    var sourceURL: String
    var licenseName: String
    var licenseURL: String
    var authorName: String

    @Relationship var exercise: ExerciseCatalogItem?

    init(
        sourceName: String,
        sourceURL: String,
        licenseName: String,
        licenseURL: String,
        authorName: String,
        exercise: ExerciseCatalogItem? = nil
    ) {
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.authorName = authorName
        self.exercise = exercise
    }
}

@Model
final class ExerciseCatalogSyncState {
    @Attribute(.unique) var key: String
    var seedVersion: Int
    var seedImportedAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastUpdateCursor: Date?
    var lastRefreshAttemptAt: Date?
    var lastErrorMessage: String?

    init(
        key: String = "global",
        seedVersion: Int = 0,
        seedImportedAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastUpdateCursor: Date? = nil,
        lastRefreshAttemptAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.key = key
        self.seedVersion = seedVersion
        self.seedImportedAt = seedImportedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastUpdateCursor = lastUpdateCursor
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastErrorMessage = lastErrorMessage
    }
}

struct ExerciseFilters: Equatable {
    var primaryMuscleID: Int?
    var secondaryMuscleID: Int?
    var equipmentToken: String?
    var categoryName: String?
    var includeUncurated: Bool

    static let `default` = ExerciseFilters(
        primaryMuscleID: nil,
        secondaryMuscleID: nil,
        equipmentToken: nil,
        categoryName: nil,
        includeUncurated: false
    )
}

struct CustomExerciseDraft: Equatable {
    var name: String
    var categoryName: String
    var equipmentSummary: String
    var aliases: [String]
    var primaryMuscleIDs: [Int]
    var secondaryMuscleIDs: [Int]
    var instructionText: String

    static let empty = CustomExerciseDraft(
        name: "",
        categoryName: "",
        equipmentSummary: "",
        aliases: [],
        primaryMuscleIDs: [],
        secondaryMuscleIDs: [],
        instructionText: ""
    )
}

struct ExerciseMuscleGroupSection: Identifiable {
    let id: String
    let title: String
    let exercises: [ExerciseCatalogItem]
}

extension ExerciseCatalogItem {
    var searchableTerms: [String] {
        let aliasTerms = aliases.map(\.value)
        return ([displayName] + aliasTerms)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var primaryMuscleNames: String {
        let names = primaryMuscles.map(\.name)
        return names.joined(separator: ", ")
    }

    var secondaryMuscleNames: String {
        let names = secondaryMuscles.map(\.name)
        return names.joined(separator: ", ")
    }

    var equipmentTokens: [String] {
        equipmentSummary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var primaryAttribution: ExerciseAttribution? {
        attributions.first
    }

    var isCustomExercise: Bool {
        sourceName == "custom"
    }
}
