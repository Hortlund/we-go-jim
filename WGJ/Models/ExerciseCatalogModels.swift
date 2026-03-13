import Foundation
import SwiftData

@Model
final class ExerciseCatalogItem {
    @Attribute(.unique) var remoteUUID: String
    var remoteID: Int?
    var displayName: String
    var categoryName: String
    var equipmentSummary: String
    var instructionText: String?
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
        instructionText: String? = nil,
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

    init(
        name: String,
        categoryName: String,
        equipmentSummary: String,
        aliases: [String],
        primaryMuscleIDs: [Int],
        secondaryMuscleIDs: [Int],
        instructionText: String
    ) {
        self.name = name
        self.categoryName = categoryName
        self.equipmentSummary = equipmentSummary
        self.aliases = aliases
        self.primaryMuscleIDs = primaryMuscleIDs
        self.secondaryMuscleIDs = secondaryMuscleIDs
        self.instructionText = instructionText
    }

    init(exercise: ExerciseCatalogItem) {
        self.init(
            name: exercise.displayName,
            categoryName: exercise.categoryName,
            equipmentSummary: exercise.equipmentSummary,
            aliases: exercise.aliases.map(\.value).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            },
            primaryMuscleIDs: exercise.primaryMuscles.map(\.remoteID).sorted(),
            secondaryMuscleIDs: exercise.secondaryMuscles.map(\.remoteID).sorted(),
            instructionText: exercise.instructionTextValue
        )
    }
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

    var instructionTextValue: String {
        instructionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var instructionSteps: [String] {
        Self.instructionSteps(from: instructionTextValue)
    }

    private static func instructionSteps(from rawValue: String) -> [String] {
        let normalized = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return []
        }

        let explicitLineSteps = normalized
            .split(separator: "\n")
            .map { cleanedInstructionStep(String($0)) }
            .filter { !$0.isEmpty }

        if explicitLineSteps.count > 1 {
            return explicitLineSteps
        }

        let sentenceSteps = normalized
            .split(whereSeparator: { $0 == ";" || $0 == "." || $0 == "\n" })
            .flatMap { sentenceStepSegments(from: String($0)) }
            .map(cleanedInstructionStep)
            .filter { !$0.isEmpty }

        if sentenceSteps.count > 1 {
            return sentenceSteps
        }

        let fallback = cleanedInstructionStep(normalized)
        return fallback.isEmpty ? [] : [fallback]
    }

    private static func sentenceStepSegments(from rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let commaSeparated = trimmed.split(separator: ",").map(String.init)
        return commaSeparated.isEmpty ? [trimmed] : commaSeparated
    }

    private static func cleanedInstructionStep(_ rawValue: String) -> String {
        let withoutStepPrefix = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^(?:step\s*)?\d+\s*[:.)-]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: [.regularExpression])
            .replacingOccurrences(of: #"^(?:and|then)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstCharacter = withoutStepPrefix.first, firstCharacter.isLowercase else {
            return withoutStepPrefix
        }

        return String(firstCharacter).uppercased() + withoutStepPrefix.dropFirst()
    }
}
