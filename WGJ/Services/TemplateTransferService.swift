import Foundation
import SwiftData
import UniformTypeIdentifiers

enum TemplateTransferFileFormat {
    static let typeIdentifier = "com.hortlund.wgj.template"
    static let filenameExtension = "wgjtemplate"
}

struct TemplateTransferEnvelope: Codable, Equatable {
    static let currentFormatVersion = 1

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
    let exercises: [TemplateTransferExercise]
}

struct TemplateTransferExercise: Codable, Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let sets: [TemplateTransferSet]
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

        let exercises = try repository.exercises(in: templateID).map { exercise in
            TemplateTransferExercise(
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                restSeconds: exercise.restSeconds,
                sets: try repository.setDrafts(for: exercise.id).map(transferSet(from:))
            )
        }

        return TemplateTransferEnvelope(
            template: TemplateTransferTemplate(
                name: template.name,
                notes: template.notes,
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

        guard envelope.formatVersion == TemplateTransferEnvelope.currentFormatVersion else {
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

    private func exerciseDraft(from exercise: TemplateTransferExercise) -> TemplateExerciseDraft {
        TemplateExerciseDraft(
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseNameSnapshot: exercise.exerciseNameSnapshot,
            categorySnapshot: exercise.categorySnapshot,
            muscleSummarySnapshot: exercise.muscleSummarySnapshot,
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
            }
        )
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
