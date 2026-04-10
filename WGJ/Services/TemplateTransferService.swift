import Foundation
import SwiftData
import UniformTypeIdentifiers

enum TemplateTransferFileFormat {
    static let typeIdentifier = "com.hortlund.wgj.template"
    static let filenameExtension = "wgjtemplate"
}

struct TemplateTransferEnvelope: Codable, Equatable {
    static let currentFormatVersion = 4

    let formatVersion: Int
    let exportedAt: Date
    let template: TemplateTransferTemplate

    init(
        formatVersion: Int = TemplateTransferEnvelope.currentFormatVersion,
        exportedAt: Date = .now,
        template: TemplateTransferTemplate
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.template = template
    }
}

struct TemplateTransferTemplate: Codable, Equatable {
    let name: String
    let notes: String
    let preWorkoutCardio: TemplateTransferCardioBlock?
    let postWorkoutCardio: TemplateTransferCardioBlock?
    let exercises: [TemplateTransferExercise]

    init(
        name: String,
        notes: String,
        preWorkoutCardio: TemplateTransferCardioBlock? = nil,
        postWorkoutCardio: TemplateTransferCardioBlock? = nil,
        exercises: [TemplateTransferExercise]
    ) {
        self.name = name
        self.notes = notes
        self.preWorkoutCardio = preWorkoutCardio
        self.postWorkoutCardio = postWorkoutCardio
        self.exercises = exercises
    }
}

struct TemplateTransferCardioBlock: Codable, Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetDurationSeconds: Int
}

struct TemplateTransferExercise: Codable, Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let sets: [TemplateTransferSet]
    let components: [TemplateTransferExerciseComponent]?

    init(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        sets: [TemplateTransferSet],
        components: [TemplateTransferExerciseComponent]? = nil
    ) {
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = restSeconds
        self.sets = sets
        self.components = components
    }

    private enum CodingKeys: String, CodingKey {
        case catalogExerciseUUID
        case exerciseNameSnapshot
        case categorySnapshot
        case muscleSummarySnapshot
        case notes
        case targetRepMin
        case targetRepMax
        case restSeconds
        case sets
        case components
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogExerciseUUID = try container.decode(String.self, forKey: .catalogExerciseUUID)
        exerciseNameSnapshot = try container.decode(String.self, forKey: .exerciseNameSnapshot)
        categorySnapshot = try container.decode(String.self, forKey: .categorySnapshot)
        muscleSummarySnapshot = try container.decode(String.self, forKey: .muscleSummarySnapshot)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        targetRepMin = try container.decodeIfPresent(Int.self, forKey: .targetRepMin)
        targetRepMax = try container.decodeIfPresent(Int.self, forKey: .targetRepMax)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        sets = try container.decode([TemplateTransferSet].self, forKey: .sets)
        components = try container.decodeIfPresent([TemplateTransferExerciseComponent].self, forKey: .components)
    }
}

struct TemplateTransferExerciseComponent: Codable, Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
}

struct TemplateTransferSet: Codable, Equatable {
    let targetReps: Int?
    let targetWeight: Double?
    let loadUnit: TemplateLoadUnit
    let restSeconds: Int
    let isWarmup: Bool
    let isLocked: Bool
}

enum TemplateTransferError: LocalizedError, Equatable {
    case unreadableFile
    case malformedFile
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "That template file could not be read."
        case .malformedFile:
            return "That template file is invalid."
        case .unsupportedVersion(let version):
            return "That template file uses unsupported format version \(version)."
        }
    }
}

extension UTType {
    static var wgjTemplate: UTType {
        UTType(TemplateTransferFileFormat.typeIdentifier)
            ?? UTType(
                filenameExtension: TemplateTransferFileFormat.filenameExtension,
                conformingTo: .json
            )
            ?? UTType(
                tag: TemplateTransferFileFormat.filenameExtension,
                tagClass: .filenameExtension,
                conformingTo: .json
            )
            ?? .json
    }
}

@MainActor
final class TemplateTransferService {
    private let modelContext: ModelContext
    private let fileManager: FileManager

    init(modelContext: ModelContext, fileManager: FileManager = .default) {
        self.modelContext = modelContext
        self.fileManager = fileManager
    }

    func exportData(templateID: UUID) throws -> Data {
        try encoded(exportEnvelope(templateID: templateID))
    }

    func writeExportFile(templateID: UUID) throws -> URL {
        let envelope = try exportEnvelope(templateID: templateID)
        let data = try encoded(envelope)
        let directoryURL = try exportDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent(exportFilename(for: envelope.template.name))

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func importTemplate(from fileURL: URL) throws -> WorkoutTemplate {
        let startedAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw TemplateTransferError.unreadableFile
        }

        return try importTemplate(from: data)
    }

    func importTemplate(from data: Data) throws -> WorkoutTemplate {
        let envelope = try decodedEnvelope(from: data)
        let repository = TemplateRepository(modelContext: modelContext)
        let importedName = try nextImportedTemplateName(
            baseName: envelope.template.name,
            repository: repository
        )
        let template = try repository.createTemplate(
            name: importedName,
            notes: envelope.template.notes
        )

        do {
            try repository.importExercises(
                templateID: template.id,
                drafts: envelope.template.exercises.map(exerciseDraft(from:))
            )
            try repository.setCardioBlocks(
                templateID: template.id,
                drafts: cardioDrafts(from: envelope.template)
            )
            return template
        } catch {
            try? repository.deleteTemplate(id: template.id)
            throw error
        }
    }

    private func exportEnvelope(templateID: UUID) throws -> TemplateTransferEnvelope {
        let repository = TemplateRepository(modelContext: modelContext)
        guard let template = try repository.template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }
        let cardioBlocks = try repository.cardioBlocks(templateID: templateID)
        let cardioByPhase = Dictionary(uniqueKeysWithValues: cardioBlocks.map { ($0.phase, $0) })

        let exercises = try repository.exercises(in: templateID).map { exercise in
            let components = try repository.components(for: exercise.id).map { component in
                TemplateTransferExerciseComponent(
                    catalogExerciseUUID: component.catalogExerciseUUID,
                    exerciseNameSnapshot: component.exerciseNameSnapshot,
                    categorySnapshot: component.categorySnapshot,
                    muscleSummarySnapshot: component.muscleSummarySnapshot
                )
            }
            return TemplateTransferExercise(
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                notes: exercise.notes,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                restSeconds: exercise.restSeconds,
                sets: try repository.setDrafts(for: exercise.id).map(transferSet(from:)),
                components: components
            )
        }

        return TemplateTransferEnvelope(
            template: TemplateTransferTemplate(
                name: template.name,
                notes: template.notes,
                preWorkoutCardio: cardioByPhase[.preWorkout].map { transferCardio(from: TemplateCardioBlockDraft(model: $0)) },
                postWorkoutCardio: cardioByPhase[.postWorkout].map { transferCardio(from: TemplateCardioBlockDraft(model: $0)) },
                exercises: exercises
            )
        )
    }

    private func encoded(_ envelope: TemplateTransferEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    private func decodedEnvelope(from data: Data) throws -> TemplateTransferEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: TemplateTransferEnvelope
        do {
            envelope = try decoder.decode(TemplateTransferEnvelope.self, from: data)
        } catch {
            throw TemplateTransferError.malformedFile
        }

        guard (1...TemplateTransferEnvelope.currentFormatVersion).contains(envelope.formatVersion) else {
            throw TemplateTransferError.unsupportedVersion(envelope.formatVersion)
        }

        return envelope
    }

    private func transferSet(from draft: TemplateExerciseSetDraft) -> TemplateTransferSet {
        TemplateTransferSet(
            targetReps: draft.targetReps,
            targetWeight: draft.targetWeight,
            loadUnit: draft.loadUnit,
            restSeconds: draft.restSeconds,
            isWarmup: draft.isWarmup,
            isLocked: draft.isLocked
        )
    }

    private func transferCardio(from draft: TemplateCardioBlockDraft) -> TemplateTransferCardioBlock {
        TemplateTransferCardioBlock(
            catalogExerciseUUID: draft.catalogExerciseUUID,
            exerciseNameSnapshot: draft.exerciseNameSnapshot,
            categorySnapshot: draft.categorySnapshot,
            muscleSummarySnapshot: draft.muscleSummarySnapshot,
            targetDurationSeconds: draft.targetDurationSeconds
        )
    }

    private func exerciseDraft(from exercise: TemplateTransferExercise) -> TemplateExerciseDraft {
        TemplateExerciseDraft(
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseNameSnapshot: exercise.exerciseNameSnapshot,
            categorySnapshot: exercise.categorySnapshot,
            muscleSummarySnapshot: exercise.muscleSummarySnapshot,
            notes: exercise.notes,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            restSeconds: exercise.restSeconds,
            setDrafts: exercise.sets.map { set in
                TemplateExerciseSetDraft(
                    targetReps: set.targetReps,
                    targetWeight: set.targetWeight,
                    loadUnit: set.loadUnit,
                    restSeconds: set.restSeconds,
                    isWarmup: set.isWarmup,
                    isLocked: set.isLocked,
                    previousLoadUnit: set.loadUnit
                )
            },
            components: exercise.components?.map { component in
                TemplateExerciseComponentDraft(
                    catalogExerciseUUID: component.catalogExerciseUUID,
                    exerciseNameSnapshot: component.exerciseNameSnapshot,
                    categorySnapshot: component.categorySnapshot,
                    muscleSummarySnapshot: component.muscleSummarySnapshot
                )
            } ?? []
        )
    }

    private func cardioDrafts(from template: TemplateTransferTemplate) -> [TemplateCardioBlockDraft] {
        var drafts: [TemplateCardioBlockDraft] = []

        if let preWorkoutCardio = template.preWorkoutCardio {
            drafts.append(
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: preWorkoutCardio.catalogExerciseUUID,
                    exerciseNameSnapshot: preWorkoutCardio.exerciseNameSnapshot,
                    categorySnapshot: preWorkoutCardio.categorySnapshot,
                    muscleSummarySnapshot: preWorkoutCardio.muscleSummarySnapshot,
                    targetDurationSeconds: preWorkoutCardio.targetDurationSeconds
                )
            )
        }

        if let postWorkoutCardio = template.postWorkoutCardio {
            drafts.append(
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: postWorkoutCardio.catalogExerciseUUID,
                    exerciseNameSnapshot: postWorkoutCardio.exerciseNameSnapshot,
                    categorySnapshot: postWorkoutCardio.categorySnapshot,
                    muscleSummarySnapshot: postWorkoutCardio.muscleSummarySnapshot,
                    targetDurationSeconds: postWorkoutCardio.targetDurationSeconds
                )
            )
        }

        return drafts
    }

    private func nextImportedTemplateName(
        baseName: String,
        repository: TemplateRepository
    ) throws -> String {
        let sanitizedBase = ReviewModerationService.sanitizedForSharing(baseName, kind: .templateName)
        let existingNames = try repository.templatesWithoutFolder().map(\.name)
        guard containsName(sanitizedBase, in: existingNames) else {
            return sanitizedBase
        }

        var copyIndex = 1
        while true {
            let suffix = copyIndex == 1 ? " Copy" : " Copy \(copyIndex)"
            let candidate = suffixedTemplateName(base: sanitizedBase, suffix: suffix)
            if !containsName(candidate, in: existingNames) {
                return candidate
            }
            copyIndex += 1
        }
    }

    private func containsName(_ name: String, in existingNames: [String]) -> Bool {
        existingNames.contains { existing in
            existing.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func suffixedTemplateName(base: String, suffix: String) -> String {
        let limit = ReviewTextKind.templateName.maxLength
        let availableCount = max(1, limit - suffix.count)
        let truncatedBase = String(base.prefix(availableCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncatedBase)\(suffix)"
    }

    private func exportDirectoryURL() throws -> URL {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("WGJTemplateExports", isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }

    private func exportFilename(for templateName: String) -> String {
        let base = ReviewModerationService.sanitizedForSharing(templateName, kind: .templateName)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = base.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : String(scalar)
        }
        .joined()
        let normalized = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = normalized.isEmpty ? ReviewTextKind.templateName.fallbackValue : normalized
        return "\(resolved).\(TemplateTransferFileFormat.filenameExtension)"
    }
}
