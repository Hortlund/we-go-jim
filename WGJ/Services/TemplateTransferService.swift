import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated enum TemplateTransferFileFormat {
    static let typeIdentifier = "com.hortlund.wgj.template"
    static let filenameExtension = "wgjtemplate"
    static let jsonFilenameExtension = "json"
    static let textFilenameExtension = "txt"

    static let supportedImportFilenameExtensions: Set<String> = [
        filenameExtension,
        jsonFilenameExtension,
    ]
}

nonisolated enum TemplateTransferExportFormat: String, CaseIterable, Equatable, Sendable {
    case bundle
    case json
    case text

    var filenameExtension: String {
        switch self {
        case .bundle:
            return TemplateTransferFileFormat.filenameExtension
        case .json:
            return TemplateTransferFileFormat.jsonFilenameExtension
        case .text:
            return TemplateTransferFileFormat.textFilenameExtension
        }
    }
}

nonisolated enum TemplateTransferArtifactKind: String, Codable, Equatable, Sendable {
    case template
    case folder
}

nonisolated enum TemplateTransferImportResult: Equatable, Sendable {
    case template(UUID)
    case folder(UUID)
}

nonisolated enum TemplateTransferArtifact: Codable, Equatable, Sendable {
    case template(TemplateTransferTemplate)
    case folder(TemplateTransferFolder)

    private enum CodingKeys: String, CodingKey {
        case kind
        case template
        case folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(TemplateTransferArtifactKind.self, forKey: .kind)

        switch kind {
        case .template:
            self = .template(try container.decode(TemplateTransferTemplate.self, forKey: .template))
        case .folder:
            self = .folder(try container.decode(TemplateTransferFolder.self, forKey: .folder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .template(let template):
            try container.encode(TemplateTransferArtifactKind.template, forKey: .kind)
            try container.encode(template, forKey: .template)
        case .folder(let folder):
            try container.encode(TemplateTransferArtifactKind.folder, forKey: .kind)
            try container.encode(folder, forKey: .folder)
        }
    }

    var suggestedFilenameBase: String {
        switch self {
        case .template(let template):
            return template.name
        case .folder(let folder):
            return folder.name
        }
    }

    var suggestedFilenameKind: ReviewTextKind {
        switch self {
        case .template:
            return .templateName
        case .folder:
            return .folderName
        }
    }
}

nonisolated struct TemplateTransferEnvelope: Codable, Equatable, Sendable {
    static let currentFormatVersion = 6

    let formatVersion: Int
    let exportedAt: Date
    let artifact: TemplateTransferArtifact

    init(
        formatVersion: Int = TemplateTransferEnvelope.currentFormatVersion,
        exportedAt: Date = .now,
        artifact: TemplateTransferArtifact
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.artifact = artifact
    }

    init(
        formatVersion: Int = TemplateTransferEnvelope.currentFormatVersion,
        exportedAt: Date = .now,
        template: TemplateTransferTemplate
    ) {
        self.init(
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            artifact: .template(template)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case artifact
        case template
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)

        if formatVersion >= TemplateTransferEnvelope.currentFormatVersion,
           container.contains(.artifact)
        {
            artifact = try container.decode(TemplateTransferArtifact.self, forKey: .artifact)
            return
        }

        artifact = .template(try container.decode(TemplateTransferTemplate.self, forKey: .template))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)

        if formatVersion >= TemplateTransferEnvelope.currentFormatVersion {
            try container.encode(artifact, forKey: .artifact)
            return
        }

        switch artifact {
        case .template(let template):
            try container.encode(template, forKey: .template)
        case .folder:
            try container.encode(artifact, forKey: .artifact)
        }
    }
}

nonisolated struct TemplateTransferFolder: Codable, Equatable, Sendable {
    let name: String
    let templates: [TemplateTransferTemplate]

    init(name: String, templates: [TemplateTransferTemplate]) {
        self.name = name
        self.templates = templates
    }
}

nonisolated struct TemplateTransferTemplate: Codable, Equatable, Sendable {
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

nonisolated struct TemplateTransferCardioBlock: Codable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetDurationSeconds: Int
}

nonisolated struct TemplateTransferExercise: Codable, Equatable, Sendable {
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
    let superset: ExerciseSupersetMembershipDraft?

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
        components: [TemplateTransferExerciseComponent]? = nil,
        superset: ExerciseSupersetMembershipDraft? = nil
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
        self.superset = superset
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
        case superset
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
        superset = try container.decodeIfPresent(ExerciseSupersetMembershipDraft.self, forKey: .superset)
    }
}

nonisolated struct TemplateTransferExerciseComponent: Codable, Equatable, Sendable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
}

nonisolated struct TemplateTransferSet: Codable, Equatable, Sendable {
    let targetReps: Int?
    let targetWeight: Double?
    let loadUnit: TemplateLoadUnit
    let restSeconds: Int
    let isWarmup: Bool
    let isLocked: Bool
    let dropStages: [TemplateExerciseDropStageDraft]

    init(
        targetReps: Int?,
        targetWeight: Double?,
        loadUnit: TemplateLoadUnit,
        restSeconds: Int,
        isWarmup: Bool,
        isLocked: Bool,
        dropStages: [TemplateExerciseDropStageDraft] = []
    ) {
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadUnit = loadUnit
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.isLocked = isLocked
        self.dropStages = dropStages
    }

    private enum CodingKeys: String, CodingKey {
        case targetReps
        case targetWeight
        case loadUnit
        case restSeconds
        case isWarmup
        case isLocked
        case dropStages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetReps = try container.decodeIfPresent(Int.self, forKey: .targetReps)
        targetWeight = try container.decodeIfPresent(Double.self, forKey: .targetWeight)
        loadUnit = try container.decode(TemplateLoadUnit.self, forKey: .loadUnit)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        isWarmup = try container.decode(Bool.self, forKey: .isWarmup)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        dropStages = try container.decodeIfPresent([TemplateExerciseDropStageDraft].self, forKey: .dropStages) ?? []
    }
}

nonisolated enum TemplateTransferError: LocalizedError, Equatable, Sendable {
    case unreadableFile
    case malformedFile
    case unsupportedVersion(Int)
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "That template file could not be read."
        case .malformedFile:
            return "That template file is invalid."
        case .unsupportedVersion(let version):
            return "That template file uses unsupported format version \(version)."
        case .unsupportedFileType:
            return "WGJ can only import .wgjtemplate or .json files."
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

nonisolated final class TemplateTransferService {
    private let modelContext: ModelContext
    private let fileManager: FileManager

    init(modelContext: ModelContext, fileManager: FileManager = .default) {
        self.modelContext = modelContext
        self.fileManager = fileManager
    }

    func exportData(templateID: UUID) throws -> Data {
        try exportData(templateID: templateID, format: .bundle)
    }

    func exportData(templateID: UUID, format: TemplateTransferExportFormat) throws -> Data {
        try encodedExportData(
            artifact: try exportTemplateArtifact(templateID: templateID),
            format: format
        )
    }

    func exportData(folderID: UUID, format: TemplateTransferExportFormat) throws -> Data {
        try encodedExportData(
            artifact: try exportFolderArtifact(folderID: folderID),
            format: format
        )
    }

    func writeExportFile(templateID: UUID) throws -> URL {
        try writeExportFile(templateID: templateID, format: .bundle)
    }

    func writeExportFile(templateID: UUID, format: TemplateTransferExportFormat) throws -> URL {
        let artifact = try exportTemplateArtifact(templateID: templateID)
        return try writeExportFile(artifact: artifact, format: format)
    }

    func writeExportFile(folderID: UUID, format: TemplateTransferExportFormat) throws -> URL {
        let artifact = try exportFolderArtifact(folderID: folderID)
        return try writeExportFile(artifact: artifact, format: format)
    }

    func importTransfer(from fileURL: URL) throws -> TemplateTransferImportResult {
        try validateSupportedImportFileURL(fileURL)

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

        return try importTransfer(from: data)
    }

    func importTransfer(from data: Data) throws -> TemplateTransferImportResult {
        try importTransfer(from: decodedEnvelope(from: data))
    }

    func importTemplate(from fileURL: URL) throws -> WorkoutTemplate {
        try importedTemplate(from: importTransfer(from: fileURL))
    }

    func importTemplate(from data: Data) throws -> WorkoutTemplate {
        try importedTemplate(from: importTransfer(from: data))
    }

    private func encodedExportData(
        artifact: TemplateTransferArtifact,
        format: TemplateTransferExportFormat
    ) throws -> Data {
        switch format {
        case .bundle, .json:
            return try encoded(TemplateTransferEnvelope(artifact: artifact))
        case .text:
            return Data(textDocument(for: artifact).utf8)
        }
    }

    private func writeExportFile(
        artifact: TemplateTransferArtifact,
        format: TemplateTransferExportFormat
    ) throws -> URL {
        let data = try encodedExportData(artifact: artifact, format: format)
        let directoryURL = try exportDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent(
            exportFilename(
                for: artifact.suggestedFilenameBase,
                kind: artifact.suggestedFilenameKind,
                format: format
            )
        )

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func importedTemplate(from result: TemplateTransferImportResult) throws -> WorkoutTemplate {
        guard case .template(let templateID) = result,
              let template = try TemplateRepository(modelContext: modelContext).template(id: templateID)
        else {
            throw TemplateTransferError.malformedFile
        }

        return template
    }

    private func importTransfer(from envelope: TemplateTransferEnvelope) throws -> TemplateTransferImportResult {
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)
        try? catalogRepository.ensureSeedImportedIfNeeded()

        switch envelope.artifact {
        case .template(let template):
            return .template(try importTemplateArtifact(template, catalogRepository: catalogRepository))
        case .folder(let folder):
            return .folder(try importFolderArtifact(folder, catalogRepository: catalogRepository))
        }
    }

    private func importTemplateArtifact(
        _ transferTemplate: TemplateTransferTemplate,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> UUID {
        let repository = TemplateRepository(modelContext: modelContext, autoSaveChanges: false)
        let importedName = try nextImportedTemplateName(
            baseName: transferTemplate.name,
            repository: repository
        )
        let template = try repository.createTemplate(
            name: importedName,
            notes: transferTemplate.notes
        )

        do {
            try repository.importExercises(
                templateID: template.id,
                drafts: try transferTemplate.exercises.map {
                    try exerciseDraft(from: $0, catalogRepository: catalogRepository)
                }
            )
            try repository.setCardioBlocks(
                templateID: template.id,
                drafts: try cardioDrafts(from: transferTemplate, catalogRepository: catalogRepository)
            )
            try repository.finalizeDeferredUserDataChangesIfNeeded()
            return template.id
        } catch {
            throw error
        }
    }

    private func importFolderArtifact(
        _ transferFolder: TemplateTransferFolder,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> UUID {
        let repository = TemplateRepository(modelContext: modelContext, autoSaveChanges: false)
        let importedName = try nextImportedFolderName(
            baseName: transferFolder.name,
            repository: repository
        )
        let folder = try repository.createFolder(name: importedName)

        do {
            for transferTemplate in transferFolder.templates {
                let template = try repository.createTemplate(
                    folderID: folder.id,
                    name: transferTemplate.name,
                    notes: transferTemplate.notes
                )
                try repository.importExercises(
                    templateID: template.id,
                    drafts: try transferTemplate.exercises.map {
                        try exerciseDraft(from: $0, catalogRepository: catalogRepository)
                    }
                )
                try repository.setCardioBlocks(
                    templateID: template.id,
                    drafts: try cardioDrafts(from: transferTemplate, catalogRepository: catalogRepository)
                )
            }

            try repository.finalizeDeferredUserDataChangesIfNeeded()
            return folder.id
        } catch {
            throw error
        }
    }

    private func exportTemplateArtifact(templateID: UUID) throws -> TemplateTransferArtifact {
        .template(try transferTemplate(templateID: templateID))
    }

    private func exportFolderArtifact(folderID: UUID) throws -> TemplateTransferArtifact {
        .folder(try transferFolder(folderID: folderID))
    }

    private func transferFolder(folderID: UUID) throws -> TemplateTransferFolder {
        let repository = TemplateRepository(modelContext: modelContext)
        guard let folder = try repository.folders().first(where: { $0.id == folderID }) else {
            throw TemplateRepositoryError.folderNotFound
        }

        let templates = try repository.templates(in: folder.id).map { template in
            try transferTemplate(templateID: template.id)
        }

        return TemplateTransferFolder(name: folder.name, templates: templates)
    }

    private func transferTemplate(templateID: UUID) throws -> TemplateTransferTemplate {
        let repository = TemplateRepository(modelContext: modelContext)
        guard let template = try repository.template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let cardioBlocks = try repository.cardioBlocks(templateID: templateID)
        let cardioByPhase = Dictionary(
            cardioBlocks.map { ($0.phase, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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
                components: components,
                superset: exercise.supersetMembership
            )
        }

        return TemplateTransferTemplate(
            name: template.name,
            notes: template.notes,
            preWorkoutCardio: cardioByPhase[.preWorkout].map {
                transferCardio(from: TemplateCardioBlockDraft(model: $0))
            },
            postWorkoutCardio: cardioByPhase[.postWorkout].map {
                transferCardio(from: TemplateCardioBlockDraft(model: $0))
            },
            exercises: exercises
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
            isLocked: draft.isLocked,
            dropStages: draft.dropStages
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

    private func exerciseDraft(
        from exercise: TemplateTransferExercise,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> TemplateExerciseDraft {
        let resolvedExercise = try resolveImportedExercise(
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseNameSnapshot: exercise.exerciseNameSnapshot,
            categorySnapshot: exercise.categorySnapshot,
            muscleSummarySnapshot: exercise.muscleSummarySnapshot,
            catalogRepository: catalogRepository
        )

        return TemplateExerciseDraft(
            catalogExerciseUUID: resolvedExercise.catalogExerciseUUID,
            exerciseNameSnapshot: resolvedExercise.exerciseNameSnapshot,
            categorySnapshot: resolvedExercise.categorySnapshot,
            muscleSummarySnapshot: resolvedExercise.muscleSummarySnapshot,
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
                    previousLoadUnit: set.loadUnit,
                    dropStages: set.dropStages
                )
            },
            components: try componentDrafts(
                from: exercise.components,
                catalogRepository: catalogRepository
            ),
            superset: exercise.superset
        )
    }

    private func componentDrafts(
        from components: [TemplateTransferExerciseComponent]?,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> [TemplateExerciseComponentDraft] {
        guard let components, !components.isEmpty else {
            return []
        }

        var drafts: [TemplateExerciseComponentDraft] = []
        drafts.reserveCapacity(components.count)
        var seenCatalogExerciseUUIDs: Set<String> = []

        for component in components {
            let resolvedComponent = try resolveImportedExercise(
                catalogExerciseUUID: component.catalogExerciseUUID,
                exerciseNameSnapshot: component.exerciseNameSnapshot,
                categorySnapshot: component.categorySnapshot,
                muscleSummarySnapshot: component.muscleSummarySnapshot,
                catalogRepository: catalogRepository
            )

            guard seenCatalogExerciseUUIDs.insert(resolvedComponent.catalogExerciseUUID).inserted else {
                continue
            }

            drafts.append(resolvedComponent.makeComponentDraft())
        }

        return drafts
    }

    private func cardioDrafts(
        from template: TemplateTransferTemplate,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> [TemplateCardioBlockDraft] {
        var drafts: [TemplateCardioBlockDraft] = []

        if let preWorkoutCardio = template.preWorkoutCardio {
            let resolvedPreWorkoutCardio = try resolveImportedExercise(
                catalogExerciseUUID: preWorkoutCardio.catalogExerciseUUID,
                exerciseNameSnapshot: preWorkoutCardio.exerciseNameSnapshot,
                categorySnapshot: preWorkoutCardio.categorySnapshot,
                muscleSummarySnapshot: preWorkoutCardio.muscleSummarySnapshot,
                catalogRepository: catalogRepository
            )
            drafts.append(
                TemplateCardioBlockDraft(
                    phase: .preWorkout,
                    catalogExerciseUUID: resolvedPreWorkoutCardio.catalogExerciseUUID,
                    exerciseNameSnapshot: resolvedPreWorkoutCardio.exerciseNameSnapshot,
                    categorySnapshot: resolvedPreWorkoutCardio.categorySnapshot,
                    muscleSummarySnapshot: resolvedPreWorkoutCardio.muscleSummarySnapshot,
                    targetDurationSeconds: preWorkoutCardio.targetDurationSeconds
                )
            )
        }

        if let postWorkoutCardio = template.postWorkoutCardio {
            let resolvedPostWorkoutCardio = try resolveImportedExercise(
                catalogExerciseUUID: postWorkoutCardio.catalogExerciseUUID,
                exerciseNameSnapshot: postWorkoutCardio.exerciseNameSnapshot,
                categorySnapshot: postWorkoutCardio.categorySnapshot,
                muscleSummarySnapshot: postWorkoutCardio.muscleSummarySnapshot,
                catalogRepository: catalogRepository
            )
            drafts.append(
                TemplateCardioBlockDraft(
                    phase: .postWorkout,
                    catalogExerciseUUID: resolvedPostWorkoutCardio.catalogExerciseUUID,
                    exerciseNameSnapshot: resolvedPostWorkoutCardio.exerciseNameSnapshot,
                    categorySnapshot: resolvedPostWorkoutCardio.categorySnapshot,
                    muscleSummarySnapshot: resolvedPostWorkoutCardio.muscleSummarySnapshot,
                    targetDurationSeconds: postWorkoutCardio.targetDurationSeconds
                )
            )
        }

        return drafts
    }

    private func resolveImportedExercise(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        catalogRepository: ExerciseCatalogRepository
    ) throws -> ImportedExerciseResolution {
        if let matchedExercise = try catalogRepository.exactImportMatch(
            remoteUUID: catalogExerciseUUID,
            exerciseName: exerciseNameSnapshot,
            categoryName: categorySnapshot
        ) {
            return ImportedExerciseResolution(catalogItem: matchedExercise)
        }

        return ImportedExerciseResolution(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            wasCanonicalized: false
        )
    }

    private func nextImportedTemplateName(
        baseName: String,
        repository: TemplateRepository
    ) throws -> String {
        try nextImportedName(
            baseName: baseName,
            kind: .templateName,
            existingNames: repository.templatesWithoutFolder().map(\.name)
        )
    }

    private func nextImportedFolderName(
        baseName: String,
        repository: TemplateRepository
    ) throws -> String {
        try nextImportedName(
            baseName: baseName,
            kind: .folderName,
            existingNames: repository.folders().map(\.name)
        )
    }

    private func nextImportedName(
        baseName: String,
        kind: ReviewTextKind,
        existingNames: [String]
    ) throws -> String {
        let sanitizedBase = ReviewModerationService.sanitizedForSharing(baseName, kind: kind)
        guard !containsName(sanitizedBase, in: existingNames) else {
            var copyIndex = 1

            while true {
                let suffix = copyIndex == 1 ? " Copy" : " Copy \(copyIndex)"
                let candidate = suffixedName(base: sanitizedBase, suffix: suffix, kind: kind)
                if !containsName(candidate, in: existingNames) {
                    return candidate
                }
                copyIndex += 1
            }
        }

        return sanitizedBase
    }

    private func containsName(_ name: String, in existingNames: [String]) -> Bool {
        existingNames.contains { existing in
            existing.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func suffixedName(base: String, suffix: String, kind: ReviewTextKind) -> String {
        let availableCount = max(1, kind.maxLength - suffix.count)
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

    private func exportFilename(
        for baseName: String,
        kind: ReviewTextKind,
        format: TemplateTransferExportFormat
    ) -> String {
        let base = ReviewModerationService.sanitizedForSharing(baseName, kind: kind)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = base.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : String(scalar)
        }
        .joined()
        let normalized = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = normalized.isEmpty ? kind.fallbackValue : normalized
        return "\(resolved).\(format.filenameExtension)"
    }

    private func validateSupportedImportFileURL(_ fileURL: URL) throws {
        guard fileURL.isFileURL else {
            throw TemplateTransferError.unreadableFile
        }

        let fileExtension = fileURL.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return
        }

        guard TemplateTransferFileFormat.supportedImportFilenameExtensions.contains(fileExtension) else {
            throw TemplateTransferError.unsupportedFileType(fileExtension)
        }
    }

    private func textDocument(for artifact: TemplateTransferArtifact) -> String {
        switch artifact {
        case .template(let template):
            return render(template: template, heading: "Template: \(template.name)")
        case .folder(let folder):
            var sections = ["Folder: \(folder.name)"]

            for (index, template) in folder.templates.enumerated() {
                sections.append("")
                sections.append(
                    render(
                        template: template,
                        heading: "Template \(index + 1): \(template.name)"
                    )
                )
            }

            return sections.joined(separator: "\n")
        }
    }

    private func render(template: TemplateTransferTemplate, heading: String) -> String {
        var lines: [String] = [heading]
        lines.append("Notes: \(template.notes.isEmpty ? "-" : template.notes)")

        if let preWorkoutCardio = template.preWorkoutCardio {
            lines.append("")
            lines.append(contentsOf: render(cardio: preWorkoutCardio, title: "Pre-workout cardio"))
        }

        if let postWorkoutCardio = template.postWorkoutCardio {
            lines.append("")
            lines.append(contentsOf: render(cardio: postWorkoutCardio, title: "Post-workout cardio"))
        }

        if template.exercises.isEmpty {
            lines.append("")
            lines.append("Exercises: none")
            return lines.joined(separator: "\n")
        }

        for (index, exercise) in template.exercises.enumerated() {
            lines.append("")
            lines.append(contentsOf: render(exercise: exercise, index: index + 1))
        }

        return lines.joined(separator: "\n")
    }

    private func render(cardio: TemplateTransferCardioBlock, title: String) -> [String] {
        [
            title,
            "Exercise: \(cardio.exerciseNameSnapshot)",
            "Duration: \(cardio.targetDurationSeconds)s",
            "Category: \(cardio.categorySnapshot)",
            "Muscles: \(cardio.muscleSummarySnapshot)",
        ]
    }

    private func render(exercise: TemplateTransferExercise, index: Int) -> [String] {
        var lines = [
            "Exercise \(index): \(exercise.exerciseNameSnapshot)",
            "Category: \(exercise.categorySnapshot)",
            "Muscles: \(exercise.muscleSummarySnapshot)",
            "Notes: \(exercise.notes.isEmpty ? "-" : exercise.notes)",
        ]

        if let targetRepMin = exercise.targetRepMin, let targetRepMax = exercise.targetRepMax {
            lines.append("Rep range: \(targetRepMin)-\(targetRepMax)")
        } else if let targetRepMin = exercise.targetRepMin {
            lines.append("Rep range: \(targetRepMin)+")
        } else if let targetRepMax = exercise.targetRepMax {
            lines.append("Rep range: up to \(targetRepMax)")
        }

        lines.append("Rest: \(exercise.restSeconds)s")

        if let components = exercise.components, !components.isEmpty {
            lines.append(
                "Components: \(components.map(\.exerciseNameSnapshot).joined(separator: ", "))"
            )
        }

        if let superset = exercise.superset {
            lines.append("Superset: \(superset.position.rawValue), round rest \(superset.roundRestSeconds)s")
        }

        for (setIndex, set) in exercise.sets.enumerated() {
            lines.append(contentsOf: render(set: set, index: setIndex + 1))
        }

        return lines
    }

    private func render(set: TemplateTransferSet, index: Int) -> [String] {
        let status = setStatusDescription(set)
        var lines = ["Set \(index): \(status)"]
        lines.append("  Target: \(loadDescription(weight: set.targetWeight, unit: set.loadUnit, reps: set.targetReps))")
        lines.append("  Rest: \(set.restSeconds)s")

        for (dropIndex, stage) in set.dropStages.enumerated() {
            lines.append(
                "  Drop set \(dropIndex + 1): \(loadDescription(weight: stage.targetWeight, unit: stage.loadUnit, reps: stage.targetReps))"
            )
        }

        return lines
    }

    private func setStatusDescription(_ set: TemplateTransferSet) -> String {
        switch (set.isWarmup, set.isLocked) {
        case (true, true):
            return "warmup, locked"
        case (true, false):
            return "warmup"
        case (false, true):
            return "locked"
        case (false, false):
            return "working"
        }
    }

    private func loadDescription(weight: Double?, unit: TemplateLoadUnit, reps: Int?) -> String {
        let load: String
        if let weight {
            load = "\(formattedNumber(weight)) \(unit.shortLabel)"
        } else if unit == .bodyweight {
            load = unit.shortLabel
        } else {
            load = "-"
        }

        if let reps {
            return "\(load) x \(reps)"
        }

        return load
    }

    private func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(value)
    }
}

nonisolated private struct ImportedExerciseResolution: Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let wasCanonicalized: Bool

    init(
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        wasCanonicalized: Bool
    ) {
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.wasCanonicalized = wasCanonicalized
    }

    init(catalogItem: ExerciseCatalogItem) {
        self.init(
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            wasCanonicalized: true
        )
    }

    func makeComponentDraft() -> TemplateExerciseComponentDraft {
        TemplateExerciseComponentDraft(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot
        )
    }
}
