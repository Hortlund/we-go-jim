import Foundation
import SwiftData

nonisolated struct TemplateExerciseComponentDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String

    init(
        id: UUID = UUID(),
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String
    ) {
        self.id = id
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
    }

    nonisolated init(model: TemplateExerciseComponent) {
        self.id = model.id
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
    }

    init(catalogItem: ExerciseCatalogItem) {
        self.id = UUID()
        self.catalogExerciseUUID = catalogItem.remoteUUID
        self.exerciseNameSnapshot = catalogItem.displayName
        self.categorySnapshot = catalogItem.categoryName
        self.muscleSummarySnapshot = catalogItem.primaryMuscleNames
    }
}

nonisolated struct TemplateExerciseSetDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnit: TemplateLoadUnit
    var restSeconds: Int
    var isWarmup: Bool
    var isLocked: Bool
    var previousTargetReps: Int?
    var previousTargetWeight: Double?
    var previousLoadUnit: TemplateLoadUnit
    var dropStages: [TemplateExerciseDropStageDraft]

    init(
        id: UUID = UUID(),
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        loadUnit: TemplateLoadUnit = .kg,
        restSeconds: Int = 120,
        isWarmup: Bool = false,
        isLocked: Bool = false,
        previousTargetReps: Int? = nil,
        previousTargetWeight: Double? = nil,
        previousLoadUnit: TemplateLoadUnit = .kg,
        dropStages: [TemplateExerciseDropStageDraft] = []
    ) {
        self.id = id
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadUnit = loadUnit
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.isLocked = isLocked
        self.previousTargetReps = previousTargetReps
        self.previousTargetWeight = previousTargetWeight
        self.previousLoadUnit = previousLoadUnit
        self.dropStages = dropStages
    }

    nonisolated init(model: TemplateExerciseSet) {
        self.id = model.id
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.loadUnit = model.loadUnit
        self.restSeconds = model.restSeconds
        self.isWarmup = model.isWarmup
        self.isLocked = model.isLocked
        self.previousTargetReps = model.previousTargetReps
        self.previousTargetWeight = model.previousTargetWeight
        self.previousLoadUnit = model.previousLoadUnit
        self.dropStages = (model.dropStages ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(TemplateExerciseDropStageDraft.init(model:))
    }
}

nonisolated struct TemplateExerciseDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var setDrafts: [TemplateExerciseSetDraft]
    var components: [TemplateExerciseComponentDraft]
    var superset: ExerciseSupersetMembershipDraft?

    init(
        id: UUID = UUID(),
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        setDrafts: [TemplateExerciseSetDraft] = [],
        components: [TemplateExerciseComponentDraft] = [],
        superset: ExerciseSupersetMembershipDraft? = nil
    ) {
        let normalizedComponents = Self.normalizedComponents(
            from: components,
            fallbackCatalogExerciseUUID: catalogExerciseUUID,
            fallbackExerciseNameSnapshot: exerciseNameSnapshot,
            fallbackCategorySnapshot: categorySnapshot,
            fallbackMuscleSummarySnapshot: muscleSummarySnapshot
        )
        let primaryComponent = normalizedComponents.first
        self.id = id
        self.catalogExerciseUUID = primaryComponent?.catalogExerciseUUID ?? catalogExerciseUUID
        self.exerciseNameSnapshot = primaryComponent?.exerciseNameSnapshot ?? exerciseNameSnapshot
        self.categorySnapshot = primaryComponent?.categorySnapshot ?? categorySnapshot
        self.muscleSummarySnapshot = primaryComponent?.muscleSummarySnapshot ?? muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = restSeconds
        self.setDrafts = setDrafts
        self.components = normalizedComponents
        self.superset = superset
    }

    nonisolated init(model: TemplateExercise, preferredLoadUnit: TemplateLoadUnit = .kg) {
        let normalizedComponents = Self.normalizedComponents(
            from: (model.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(TemplateExerciseComponentDraft.init(model:)),
            fallbackCatalogExerciseUUID: model.catalogExerciseUUID,
            fallbackExerciseNameSnapshot: model.exerciseNameSnapshot,
            fallbackCategorySnapshot: model.categorySnapshot,
            fallbackMuscleSummarySnapshot: model.muscleSummarySnapshot
        )
        let primaryComponent = normalizedComponents.first
        self.id = model.id
        self.catalogExerciseUUID = primaryComponent?.catalogExerciseUUID ?? model.catalogExerciseUUID
        self.exerciseNameSnapshot = primaryComponent?.exerciseNameSnapshot ?? model.exerciseNameSnapshot
        self.categorySnapshot = primaryComponent?.categorySnapshot ?? model.categorySnapshot
        self.muscleSummarySnapshot = primaryComponent?.muscleSummarySnapshot ?? model.muscleSummarySnapshot
        self.notes = model.notes
        self.targetRepMin = model.targetRepMin
        self.targetRepMax = model.targetRepMax
        self.restSeconds = model.restSeconds
        self.components = normalizedComponents
        self.superset = model.supersetMembership
        let orderedSets = (model.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        if orderedSets.isEmpty {
            self.setDrafts = Self.defaultSetDrafts(restSeconds: model.restSeconds, loadUnit: preferredLoadUnit)
        } else {
            var drafts: [TemplateExerciseSetDraft] = []
            drafts.reserveCapacity(orderedSets.count)
            for set in orderedSets {
                drafts.append(
                    TemplateExerciseSetDraft(
                        id: set.id,
                        targetReps: set.targetReps,
                        targetWeight: set.targetWeight,
                        loadUnit: set.loadUnit,
                        restSeconds: model.restSeconds,
                        isWarmup: set.isWarmup,
                        isLocked: set.isLocked,
                        previousTargetReps: set.previousTargetReps,
                        previousTargetWeight: set.previousTargetWeight,
                        previousLoadUnit: set.previousLoadUnit,
                        dropStages: (set.dropStages ?? [])
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map(TemplateExerciseDropStageDraft.init(model:))
                    )
                )
            }
            self.setDrafts = drafts
        }
    }

    init(catalogItem: ExerciseCatalogItem, preferredLoadUnit: TemplateLoadUnit = .kg) {
        self.id = UUID()
        self.catalogExerciseUUID = catalogItem.remoteUUID
        self.exerciseNameSnapshot = catalogItem.displayName
        self.categorySnapshot = catalogItem.categoryName
        self.muscleSummarySnapshot = catalogItem.primaryMuscleNames
        self.notes = ""
        self.targetRepMin = nil
        self.targetRepMax = nil
        self.restSeconds = 120
        self.components = [TemplateExerciseComponentDraft(catalogItem: catalogItem)]
        self.setDrafts = Self.defaultSetDrafts(
            restSeconds: self.restSeconds,
            loadUnit: TemplateLoadUnit.inferredDefault(fromEquipmentSummary: catalogItem.equipmentSummary)
                ?? preferredLoadUnit
        )
        self.superset = nil
    }

    static func normalizedComponents(
        from components: [TemplateExerciseComponentDraft],
        fallbackCatalogExerciseUUID: String,
        fallbackExerciseNameSnapshot: String,
        fallbackCategorySnapshot: String,
        fallbackMuscleSummarySnapshot: String
    ) -> [TemplateExerciseComponentDraft] {
        if !components.isEmpty {
            var seenIDs: Set<UUID> = []
            return components.filter { component in
                seenIDs.insert(component.id).inserted
            }
        }

        guard !fallbackCatalogExerciseUUID.isEmpty else {
            return []
        }

        return [
            TemplateExerciseComponentDraft(
                catalogExerciseUUID: fallbackCatalogExerciseUUID,
                exerciseNameSnapshot: fallbackExerciseNameSnapshot,
                categorySnapshot: fallbackCategorySnapshot,
                muscleSummarySnapshot: fallbackMuscleSummarySnapshot
            ),
        ]
    }

    static func defaultSetDrafts(
        count: Int = 3,
        restSeconds: Int = 120,
        loadUnit: TemplateLoadUnit = .kg
    ) -> [TemplateExerciseSetDraft] {
        let safeCount = max(1, count)
        let normalizedRest = max(0, min(3600, restSeconds))
        return (0..<safeCount).map { index in
            TemplateExerciseSetDraft(
                loadUnit: loadUnit,
                restSeconds: normalizedRest,
                isWarmup: index == 0,
                previousLoadUnit: loadUnit
            )
        }
    }

    func replacingExercise(
        with catalogItem: ExerciseCatalogItem,
        preferredLoadUnit: TemplateLoadUnit
    ) -> TemplateExerciseDraft {
        let replacement = TemplateExerciseDraft(
            catalogItem: catalogItem,
            preferredLoadUnit: preferredLoadUnit
        )

        return TemplateExerciseDraft(
            id: id,
            catalogExerciseUUID: replacement.catalogExerciseUUID,
            exerciseNameSnapshot: replacement.exerciseNameSnapshot,
            categorySnapshot: replacement.categorySnapshot,
            muscleSummarySnapshot: replacement.muscleSummarySnapshot,
            notes: "",
            targetRepMin: nil,
            targetRepMax: nil,
            restSeconds: replacement.restSeconds,
            setDrafts: replacement.setDrafts,
            components: replacement.components,
            superset: superset
        )
    }
}

nonisolated enum TemplateRepositoryError: Error {
    case invalidName
    case folderNotFound
    case templateNotFound
    case templateExerciseNotFound
    case templateExerciseSetNotFound
    case workoutSessionNotFound
    case duplicateExerciseComponent
}

nonisolated final class TemplateRepository {
    nonisolated static let unfiledFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let modelContext: ModelContext
    private let autoSaveChanges: Bool

    init(modelContext: ModelContext, autoSaveChanges: Bool = true) {
        self.modelContext = modelContext
        self.autoSaveChanges = autoSaveChanges
    }

    private func preferredLoadUnit() -> TemplateLoadUnit {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        return (try? profileRepository.currentProfile()?.preferredLoadUnit) ?? .kg
    }

    private func normalizedTemplateNotes(_ notes: String) -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveUserDataChanges() throws {
        guard autoSaveChanges else { return }
        try modelContext.save()
        UserDataSyncTrackerBridge.markLocalMutation()
    }

    func finalizeDeferredUserDataChangesIfNeeded() throws {
        guard !autoSaveChanges else { return }
        guard modelContext.hasChanges else { return }
        try modelContext.save()
        UserDataSyncTrackerBridge.markLocalMutation()
    }

    func folders() throws -> [TemplateFolder] {
        let descriptor = FetchDescriptor<TemplateFolder>(
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.name, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func createFolder(name: String) throws -> TemplateFolder {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .folderName)

        let existing = try folders()
        let created = TemplateFolder(name: cleaned, sortOrder: (existing.last?.sortOrder ?? -1) + 1)
        modelContext.insert(created)
        try saveUserDataChanges()
        return created
    }

    func renameFolder(id: UUID, name: String) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .folderName)

        guard let folder = try folder(id: id) else {
            throw TemplateRepositoryError.folderNotFound
        }

        folder.name = cleaned
        folder.updatedAt = .now
        try saveUserDataChanges()
    }

    func moveFolder(id: UUID, toIndex destinationIndex: Int) throws {
        var orderedFolders = try folders()

        guard let currentIndex = orderedFolders.firstIndex(where: { $0.id == id }) else {
            throw TemplateRepositoryError.folderNotFound
        }

        let clampedDestination = max(0, min(destinationIndex, orderedFolders.count - 1))
        guard currentIndex != clampedDestination else {
            return
        }

        let movingFolder = orderedFolders.remove(at: currentIndex)
        orderedFolders.insert(movingFolder, at: clampedDestination)

        for (index, folder) in orderedFolders.enumerated() {
            folder.sortOrder = index
            folder.updatedAt = .now
        }

        try saveUserDataChanges()
    }

    func deleteFolder(id: UUID) throws {
        guard let folder = try folder(id: id) else {
            throw TemplateRepositoryError.folderNotFound
        }

        for template in folder.templates ?? [] {
            for cardioBlock in template.cardioBlocks ?? [] {
                modelContext.delete(cardioBlock)
            }
            for exercise in template.exercises ?? [] {
                modelContext.delete(exercise)
            }
            modelContext.delete(template)
        }

        modelContext.delete(folder)
        try saveUserDataChanges()
    }

    func templates(in folderID: UUID) throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { item in
                item.folderID == folderID
            },
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.name, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func templates() throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [
                SortDescriptor(\.folderID, order: .forward),
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.name, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func latestFolderUpdatedAt() throws -> Date? {
        var descriptor = FetchDescriptor<TemplateFolder>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.updatedAt
    }

    func latestTemplateUpdatedAt() throws -> Date? {
        var descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.updatedAt
    }

    func templatesWithoutFolder() throws -> [WorkoutTemplate] {
        let rootID = Self.unfiledFolderID
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { item in
                item.folderID == rootID
            },
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.name, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func template(id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { item in
            item.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    func createTemplate(folderID: UUID? = nil, name: String, notes: String) throws -> WorkoutTemplate {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .templateName)

        let targetFolder: TemplateFolder?
        let folderRefID: UUID
        let existing: [WorkoutTemplate]

        if let folderID {
            guard let foundFolder = try self.folder(id: folderID) else {
                throw TemplateRepositoryError.folderNotFound
            }
            targetFolder = foundFolder
            folderRefID = folderID
            existing = try templates(in: folderID)
        } else {
            targetFolder = nil
            folderRefID = Self.unfiledFolderID
            existing = try templatesWithoutFolder()
        }

        let template = WorkoutTemplate(
            folderID: folderRefID,
            name: cleaned,
            notes: notes,
            sortOrder: (existing.last?.sortOrder ?? -1) + 1,
            folder: targetFolder
        )

        if let targetFolder {
            template.folder = targetFolder
            var templates = targetFolder.templates ?? []
            templates.append(template)
            targetFolder.templates = templates
        }

        modelContext.insert(template)
        try saveUserDataChanges()
        return template
    }

    func createTemplate(fromSessionID sessionID: UUID, name: String, folderID: UUID? = nil) throws -> WorkoutTemplate {
        guard let session = try workoutSession(id: sessionID) else {
            throw TemplateRepositoryError.workoutSessionNotFound
        }

        let deferredRepository = TemplateRepository(modelContext: modelContext, autoSaveChanges: false)
        let template = try deferredRepository.createTemplate(
            folderID: folderID,
            name: name,
            notes: normalizedTemplateNotes(session.notes)
        )

        let sessionExercises = try workoutSessionExercises(sessionID: sessionID)
        let drafts: [TemplateExerciseDraft] = sessionExercises.map { exercise in
            let orderedSets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let setDrafts = orderedSets.map { set in
                let usedActual = set.actualReps != nil || set.actualWeight != nil
                return TemplateExerciseSetDraft(
                    targetReps: usedActual ? set.actualReps : set.targetReps,
                    targetWeight: usedActual ? set.actualWeight : set.targetWeight,
                    loadUnit: usedActual ? set.actualLoadUnit : set.targetLoadUnit,
                    restSeconds: exercise.restSeconds,
                    isWarmup: set.isWarmup,
                    isLocked: set.isLocked,
                    dropStages: (set.dropStages ?? [])
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { stage in
                            let usedActualStage = stage.actualReps != nil || stage.actualWeight != nil
                            return TemplateExerciseDropStageDraft(
                                targetReps: usedActualStage ? stage.actualReps : stage.targetReps,
                                targetWeight: usedActualStage ? stage.actualWeight : stage.targetWeight,
                                loadUnit: usedActualStage ? stage.actualLoadUnit : stage.targetLoadUnit
                            )
                        }
                )
            }

            return TemplateExerciseDraft(
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                notes: exercise.notes,
                targetRepMin: nil,
                targetRepMax: nil,
                restSeconds: exercise.restSeconds,
                setDrafts: setDrafts.isEmpty
                    ? TemplateExerciseDraft.defaultSetDrafts(
                        restSeconds: exercise.restSeconds,
                        loadUnit: preferredLoadUnit()
                    )
                    : setDrafts,
                components: [
                    TemplateExerciseComponentDraft(
                        catalogExerciseUUID: exercise.catalogExerciseUUID,
                        exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                        categorySnapshot: exercise.categorySnapshot,
                        muscleSummarySnapshot: exercise.muscleSummarySnapshot
                    ),
                ],
                superset: exercise.supersetMembership
            )
        }

        let cardioDrafts = try workoutSessionCardioBlocks(sessionID: sessionID).map { cardioBlock in
            TemplateCardioBlockDraft(
                id: cardioBlock.id,
                phase: cardioBlock.phase,
                catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
                exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
                categorySnapshot: cardioBlock.categorySnapshot,
                muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
                targetDurationSeconds: cardioBlock.targetDurationSeconds
            )
        }

        do {
            try deferredRepository.setExercises(templateID: template.id, drafts: drafts)
            try deferredRepository.setCardioBlocks(templateID: template.id, drafts: cardioDrafts)
            try deferredRepository.finalizeDeferredUserDataChangesIfNeeded()
            return template
        } catch {
            modelContext.delete(template)
            throw error
        }
    }

    func duplicateTemplate(id sourceTemplateID: UUID, name: String? = nil) throws -> WorkoutTemplate {
        guard let sourceTemplate = try template(id: sourceTemplateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let targetFolderID = sourceTemplate.folderID == Self.unfiledFolderID ? nil : sourceTemplate.folderID
        let deferredRepository = TemplateRepository(modelContext: modelContext, autoSaveChanges: false)
        let copy = try deferredRepository.createTemplate(
            folderID: targetFolderID,
            name: name ?? "\(sourceTemplate.name) Copy",
            notes: sourceTemplate.notes
        )

        let sourceExercises = (sourceTemplate.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
        let groupIDMap = duplicateSupersetGroupIDMap(from: sourceExercises)
        let exerciseDrafts = sourceExercises.map { exercise in
            duplicateDraft(from: exercise, groupIDMap: groupIDMap)
        }
        let cardioDrafts = orderedCardioBlocks(for: sourceTemplate).map(duplicateDraft(from:))

        do {
            try deferredRepository.setExercises(templateID: copy.id, drafts: exerciseDrafts)
            try deferredRepository.setCardioBlocks(templateID: copy.id, drafts: cardioDrafts)
            try deferredRepository.finalizeDeferredUserDataChangesIfNeeded()
            return copy
        } catch {
            modelContext.delete(copy)
            throw error
        }
    }

    func updateTemplate(id: UUID, name: String, notes: String) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .templateName)
        let normalizedNotes = normalizedTemplateNotes(notes)

        guard let template = try template(id: id) else {
            throw TemplateRepositoryError.templateNotFound
        }

        guard template.name != cleaned || template.notes != normalizedNotes else {
            return
        }

        template.name = cleaned
        template.notes = normalizedNotes
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateTemplateContents(
        id: UUID,
        name: String,
        notes: String,
        exerciseDrafts: [TemplateExerciseDraft],
        cardioDrafts: [TemplateCardioBlockDraft]
    ) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .templateName)
        let normalizedNotes = normalizedTemplateNotes(notes)

        try persistTemplateContents(
            templateID: id,
            templateName: cleaned,
            templateNotes: normalizedNotes,
            exercises: exerciseDrafts.map { templateSyncExerciseMutation(from: $0) },
            cardioBlocks: cardioDrafts.map { templateSyncCardioMutation(from: $0) }
        )
    }

    func updateExerciseRepRange(templateExerciseID: UUID, minReps: Int?, maxReps: Int?) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let normalized = sanitizedRepRange(min: minReps, max: maxReps)
        guard exercise.targetRepMin != normalized.min || exercise.targetRepMax != normalized.max else {
            return
        }

        exercise.targetRepMin = normalized.min
        exercise.targetRepMax = normalized.max
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateExerciseNotes(templateExerciseID: UUID, notes: String) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        guard exercise.notes != notes else {
            return
        }

        exercise.notes = notes
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func updateExerciseRestSeconds(templateExerciseID: UUID, restSeconds: Int) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let normalized = sanitizedRestSeconds(restSeconds)
        let orderedSets = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let needsSetRestUpdate = orderedSets.contains { $0.restSeconds != normalized }
        guard exercise.restSeconds != normalized || needsSetRestUpdate else {
            return
        }

        exercise.restSeconds = normalized

        for set in orderedSets where set.restSeconds != normalized {
            set.restSeconds = normalized
            set.updatedAt = .now
        }

        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func applyRestSecondsToAllSets(templateExerciseID: UUID, restSeconds: Int) throws {
        try updateExerciseRestSeconds(templateExerciseID: templateExerciseID, restSeconds: restSeconds)
    }

    func moveTemplate(id: UUID, toFolderID destinationFolderID: UUID?) throws {
        guard let template = try template(id: id) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let destinationFolderRefID: UUID
        let destinationFolder: TemplateFolder?

        if let destinationFolderID {
            guard let resolvedDestination = try folder(id: destinationFolderID) else {
                throw TemplateRepositoryError.folderNotFound
            }
            destinationFolderRefID = destinationFolderID
            destinationFolder = resolvedDestination
        } else {
            destinationFolderRefID = Self.unfiledFolderID
            destinationFolder = nil
        }

        guard template.folderID != destinationFolderRefID else {
            return
        }

        if let currentFolder = template.folder {
            var currentTemplates = currentFolder.templates ?? []
            currentTemplates.removeAll(where: { $0.id == template.id })
            currentFolder.templates = currentTemplates
        }

        let destinationTemplates: [WorkoutTemplate]
        if let destinationFolderID {
            destinationTemplates = try templates(in: destinationFolderID)
        } else {
            destinationTemplates = try templatesWithoutFolder()
        }
        let nextSortOrder = (destinationTemplates
            .filter { $0.id != template.id }
            .map(\.sortOrder)
            .max() ?? -1) + 1

        template.folder = destinationFolder
        template.folderID = destinationFolderRefID
        template.sortOrder = nextSortOrder
        template.updatedAt = .now

        if let destinationFolder {
            var folderTemplates = destinationFolder.templates ?? []
            if !folderTemplates.contains(where: { $0.id == template.id }) {
                folderTemplates.append(template)
                destinationFolder.templates = folderTemplates
            }
        }

        try saveUserDataChanges()
    }

    func deleteTemplate(id: UUID) throws {
        guard let template = try template(id: id) else {
            throw TemplateRepositoryError.templateNotFound
        }

        for cardioBlock in template.cardioBlocks ?? [] {
            modelContext.delete(cardioBlock)
        }

        for exercise in template.exercises ?? [] {
            modelContext.delete(exercise)
        }

        modelContext.delete(template)
        try saveUserDataChanges()
    }

    func exercises(in templateID: UUID) throws -> [TemplateExercise] {
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { item in
                item.templateID == templateID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let exercises = try modelContext.fetch(descriptor)
        var didNormalize = false
        for exercise in exercises {
            didNormalize = ensureTemplateComponentStructure(for: exercise) || didNormalize
        }
        if didNormalize {
            try saveUserDataChanges()
        }
        return exercises
    }

    func cardioBlocks(templateID: UUID) throws -> [TemplateCardioBlock] {
        let descriptor = FetchDescriptor<TemplateCardioBlock>(
            predicate: #Predicate { item in
                item.templateID == templateID
            }
        )
        return try modelContext.fetch(descriptor)
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    func cardioBlock(templateID: UUID, phase: WorkoutCardioPhase) throws -> TemplateCardioBlock? {
        let phaseRaw = phase.rawValue
        let descriptor = FetchDescriptor<TemplateCardioBlock>(
            predicate: #Predicate { item in
                item.templateID == templateID && item.phaseRaw == phaseRaw
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func upsertCardioBlock(templateID: UUID, draft: TemplateCardioBlockDraft) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let cardioBlock = try cardioBlock(templateID: templateID, phase: draft.phase)
            ?? TemplateCardioBlock(
                id: draft.id,
                templateID: templateID,
                phase: draft.phase,
                catalogExerciseUUID: draft.catalogExerciseUUID,
                exerciseNameSnapshot: draft.exerciseNameSnapshot,
                categorySnapshot: draft.categorySnapshot,
                muscleSummarySnapshot: draft.muscleSummarySnapshot,
                targetDurationSeconds: draft.targetDurationSeconds,
                template: template
            )

        if cardioBlock.modelContext == nil {
            modelContext.insert(cardioBlock)
        }

        cardioBlock.templateID = templateID
        cardioBlock.template = template
        cardioBlock.phase = draft.phase
        cardioBlock.catalogExerciseUUID = draft.catalogExerciseUUID
        cardioBlock.exerciseNameSnapshot = draft.exerciseNameSnapshot
        cardioBlock.categorySnapshot = draft.categorySnapshot
        cardioBlock.muscleSummarySnapshot = draft.muscleSummarySnapshot
        cardioBlock.targetDurationSeconds = sanitizedCardioDurationSeconds(draft.targetDurationSeconds)
        cardioBlock.updatedAt = .now

        syncTemplateCardioCollection(for: template)
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func removeCardioBlock(templateID: UUID, phase: WorkoutCardioPhase) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        guard let cardioBlock = try cardioBlock(templateID: templateID, phase: phase) else {
            return
        }

        modelContext.delete(cardioBlock)
        syncTemplateCardioCollection(for: template)
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func setCardioBlocks(templateID: UUID, drafts: [TemplateCardioBlockDraft]) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        syncCardioStructure(
            for: template,
            desiredDrafts: drafts
        )
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func setDrafts(for templateExerciseID: UUID) throws -> [TemplateExerciseSetDraft] {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }
        return orderedSetDrafts(for: exercise)
    }

    func components(for templateExerciseID: UUID) throws -> [TemplateExerciseComponent] {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let didNormalize = ensureTemplateComponentStructure(for: exercise)
        if didNormalize {
            try saveUserDataChanges()
        }

        return orderedComponents(for: exercise)
    }

    func addComponent(templateExerciseID: UUID, catalogItem: ExerciseCatalogItem) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }
        guard let template = exercise.template else {
            throw TemplateRepositoryError.templateNotFound
        }
        if containsComponentCatalogUUID(
            catalogItem.remoteUUID,
            in: template,
            excludingTemplateExerciseID: exercise.id
        ) {
            throw TemplateRepositoryError.duplicateExerciseComponent
        }

        var updatedComponents = orderedComponents(for: exercise)
        let created = TemplateExerciseComponent(
            templateExerciseID: exercise.id,
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            sortOrder: updatedComponents.count,
            templateExercise: exercise
        )
        modelContext.insert(created)
        updatedComponents.append(created)
        exercise.components = updatedComponents
        _ = syncPrimaryComponentSnapshot(for: exercise)
        exercise.updatedAt = .now
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func removeComponent(templateExerciseID: UUID, componentID: UUID) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }
        guard let template = exercise.template else {
            throw TemplateRepositoryError.templateNotFound
        }

        let components = orderedComponents(for: exercise)
        guard components.count > 1 else {
            return
        }
        guard let component = components.first(where: { $0.id == componentID }) else {
            return
        }

        modelContext.delete(component)
        let remaining = orderedComponents(for: exercise)
        for (index, row) in remaining.enumerated() {
            row.sortOrder = index
            row.updatedAt = .now
        }
        exercise.components = remaining
        _ = syncPrimaryComponentSnapshot(for: exercise)
        exercise.updatedAt = .now
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func moveComponent(templateExerciseID: UUID, fromOffsets: IndexSet, toOffset: Int) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }
        guard let template = exercise.template else {
            throw TemplateRepositoryError.templateNotFound
        }

        var ordered = orderedComponents(for: exercise)
        let movingItems = fromOffsets.sorted().map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            ordered.remove(at: index)
        }

        var destination = toOffset
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        destination -= removedBeforeDestination
        destination = max(0, min(destination, ordered.count))
        ordered.insert(contentsOf: movingItems, at: destination)

        for (index, component) in ordered.enumerated() {
            component.sortOrder = index
            component.updatedAt = .now
        }

        exercise.components = ordered
        _ = syncPrimaryComponentSnapshot(for: exercise)
        exercise.updatedAt = .now
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func upsertSet(
        templateExerciseID: UUID,
        setID: UUID,
        reps: Int?,
        weight: Double?,
        unit: TemplateLoadUnit
    ) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let set: TemplateExerciseSet
        if let existing = (exercise.prescribedSets ?? []).first(where: { $0.id == setID }) {
            set = existing
        } else {
            set = TemplateExerciseSet(
                id: setID,
                templateExerciseID: templateExerciseID,
                sortOrder: ((exercise.prescribedSets ?? []).map(\.sortOrder).max() ?? -1) + 1,
                restSeconds: exercise.restSeconds,
                templateExercise: exercise
            )
            modelContext.insert(set)
            var sets = exercise.prescribedSets ?? []
            sets.append(set)
            exercise.prescribedSets = sets
        }

        if hasTargetDelta(modelSet: set, draft: TemplateExerciseSetDraft(targetReps: reps, targetWeight: weight, loadUnit: unit)) {
            set.previousTargetReps = set.targetReps
            set.previousTargetWeight = set.targetWeight
            set.previousLoadUnit = set.loadUnit
        }

        set.targetReps = sanitizedReps(reps)
        set.targetWeight = sanitizedWeight(weight)
        set.loadUnit = unit
        set.updatedAt = .now

        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func addSet(templateExerciseID: UUID) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let orderedSets = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let created = TemplateExerciseSet(
            templateExerciseID: templateExerciseID,
            sortOrder: (orderedSets.last?.sortOrder ?? -1) + 1,
            restSeconds: exercise.restSeconds,
            isWarmup: false,
            templateExercise: exercise
        )
        modelContext.insert(created)

        var sets = exercise.prescribedSets ?? []
        sets.append(created)
        exercise.prescribedSets = sets
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func removeSet(templateExerciseID: UUID, setID: UUID) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let sets = exercise.prescribedSets ?? []
        guard let set = sets.first(where: { $0.id == setID }) else {
            throw TemplateRepositoryError.templateExerciseSetNotFound
        }

        modelContext.delete(set)

        var updated = sets
        updated.removeAll(where: { $0.id == setID })
        exercise.prescribedSets = updated
        reorderSets(for: exercise)
        normalizeWarmupSet(for: exercise)
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func moveSet(templateExerciseID: UUID, fromOffsets: IndexSet, toOffset: Int) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        var ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let movingItems = fromOffsets.sorted().map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            ordered.remove(at: index)
        }

        var destination = toOffset
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        destination -= removedBeforeDestination
        destination = max(0, min(destination, ordered.count))
        ordered.insert(contentsOf: movingItems, at: destination)

        for (index, set) in ordered.enumerated() {
            set.sortOrder = index
            set.updatedAt = .now
        }

        exercise.prescribedSets = ordered
        normalizeWarmupSet(for: exercise)
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func saveSetDrafts(templateExerciseID: UUID, drafts: [TemplateExerciseSetDraft]) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let defaultRestSeconds = sanitizedRestSeconds(exercise.restSeconds)
        let canonicalDrafts = drafts.map { draft in
            var updated = draft
            updated.restSeconds = defaultRestSeconds
            return updated
        }
        let existingSets = exercise.prescribedSets ?? []
        let orderedExistingSets = existingSets.sorted { $0.sortOrder < $1.sortOrder }
        let incomingSignatures = canonicalDrafts.enumerated().map { index, draft in
            persistenceSignature(for: draft, at: index)
        }
        let existingSignatures = orderedExistingSets.enumerated().map { index, set in
            persistenceSignature(for: set, at: index)
        }
        guard incomingSignatures != existingSignatures else {
            return
        }

        let incomingIDs = Set(canonicalDrafts.map(\.id))

        for set in existingSets where !incomingIDs.contains(set.id) {
            modelContext.delete(set)
        }

        var updatedSets: [TemplateExerciseSet] = []
        for (index, draft) in canonicalDrafts.enumerated() {
            let modelSet = existingSets.first(where: { $0.id == draft.id }) ?? TemplateExerciseSet(
                id: draft.id,
                templateExerciseID: templateExerciseID,
                templateExercise: exercise
            )

            if modelSet.modelContext == nil {
                modelContext.insert(modelSet)
            }

            if hasTargetDelta(modelSet: modelSet, draft: draft) {
                modelSet.previousTargetReps = modelSet.targetReps
                modelSet.previousTargetWeight = modelSet.targetWeight
                modelSet.previousLoadUnit = modelSet.loadUnit
            }

            modelSet.templateExerciseID = templateExerciseID
            modelSet.sortOrder = index
            modelSet.targetReps = sanitizedReps(draft.targetReps)
            modelSet.targetWeight = sanitizedWeight(draft.targetWeight)
            modelSet.loadUnit = draft.loadUnit
            modelSet.restSeconds = defaultRestSeconds
            modelSet.isWarmup = draft.isWarmup
            modelSet.isLocked = draft.isLocked
            modelSet.updatedAt = .now
            syncDropStageStructure(for: modelSet, desiredDrafts: draft.dropStages)
            updatedSets.append(modelSet)
        }

        exercise.prescribedSets = updatedSets
        normalizeWarmupSet(for: exercise)
        exercise.updatedAt = .now
        try saveUserDataChanges()
    }

    func applyWorkoutTemplateSync(
        templateID: UUID,
        templateNotes: String,
        exercises mutations: [WorkoutTemplateSyncExerciseMutation],
        cardioBlocks cardioMutations: [WorkoutTemplateSyncCardioMutation]
    ) throws {
        try persistTemplateContents(
            templateID: templateID,
            templateName: nil,
            templateNotes: normalizedTemplateNotes(templateNotes),
            exercises: mutations,
            cardioBlocks: cardioMutations
        )
    }

    private func persistTemplateContents(
        templateID: UUID,
        templateName: String?,
        templateNotes: String,
        exercises mutations: [WorkoutTemplateSyncExerciseMutation],
        cardioBlocks cardioMutations: [WorkoutTemplateSyncCardioMutation]
    ) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        try validateUniqueComponentCatalogUUIDs(
            in: mutations.map { mutation in
                TemplateExerciseDraft(
                    id: mutation.templateExerciseID ?? UUID(),
                    catalogExerciseUUID: mutation.catalogExerciseUUID,
                    exerciseNameSnapshot: mutation.exerciseNameSnapshot,
                    categorySnapshot: mutation.categorySnapshot,
                    muscleSummarySnapshot: mutation.muscleSummarySnapshot,
                    notes: mutation.notes,
                    targetRepMin: mutation.targetRepMin,
                    targetRepMax: mutation.targetRepMax,
                    restSeconds: mutation.restSeconds,
                    setDrafts: mutation.setDrafts,
                    components: mutation.components,
                    superset: mutation.superset
                )
            }
        )

        let orderedExistingExercises = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingByID = Dictionary(
            orderedExistingExercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingByCatalogUUID = Dictionary(
            orderedExistingExercises.map { ($0.catalogExerciseUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolvedTemplateName = templateName ?? template.name
        let existingSignature = persistenceSignature(
            for: template,
            resolvedName: resolvedTemplateName
        )
        let incomingSignature = persistenceSignature(
            templateName: resolvedTemplateName,
            templateNotes: templateNotes,
            exercises: mutations,
            cardioBlocks: cardioMutations,
            existingByCatalogUUID: existingByCatalogUUID
        )

        guard existingSignature != incomingSignature else {
            return
        }

        if let templateName {
            template.name = templateName
        }
        template.notes = templateNotes
        template.updatedAt = .now

        var updatedExercises: [TemplateExercise] = []
        updatedExercises.reserveCapacity(mutations.count)

        for (index, mutation) in mutations.enumerated() {
            let normalizedRange = sanitizedRepRange(min: mutation.targetRepMin, max: mutation.targetRepMax)
            let normalizedRest = sanitizedRestSeconds(mutation.restSeconds)
            let normalizedComponents = TemplateExerciseDraft.normalizedComponents(
                from: mutation.components,
                fallbackCatalogExerciseUUID: mutation.catalogExerciseUUID,
                fallbackExerciseNameSnapshot: mutation.exerciseNameSnapshot,
                fallbackCategorySnapshot: mutation.categorySnapshot,
                fallbackMuscleSummarySnapshot: mutation.muscleSummarySnapshot
            )
            let primaryComponent = normalizedComponents.first
            let exercise = mutation.templateExerciseID.flatMap { existingByID[$0] }
                ?? existingByCatalogUUID[mutation.catalogExerciseUUID]
                ?? TemplateExercise(
                    id: mutation.templateExerciseID ?? UUID(),
                    templateID: templateID,
                    catalogExerciseUUID: primaryComponent?.catalogExerciseUUID ?? mutation.catalogExerciseUUID,
                    exerciseNameSnapshot: primaryComponent?.exerciseNameSnapshot ?? mutation.exerciseNameSnapshot,
                    categorySnapshot: primaryComponent?.categorySnapshot ?? mutation.categorySnapshot,
                    muscleSummarySnapshot: primaryComponent?.muscleSummarySnapshot ?? mutation.muscleSummarySnapshot,
                    notes: mutation.notes,
                    targetRepMin: normalizedRange.min,
                    targetRepMax: normalizedRange.max,
                    restSeconds: normalizedRest,
                    sortOrder: index,
                    template: template
                )

            if exercise.modelContext == nil {
                modelContext.insert(exercise)
            }

            exercise.templateID = templateID
            exercise.template = template
            exercise.notes = mutation.notes
            exercise.targetRepMin = normalizedRange.min
            exercise.targetRepMax = normalizedRange.max
            exercise.restSeconds = normalizedRest
            exercise.sortOrder = index

            syncComponentStructure(
                for: exercise,
                desiredDrafts: normalizedComponents
            )
            syncSetStructure(
                for: exercise,
                desiredDrafts: mutation.setDrafts,
                defaultRestSeconds: normalizedRest
            )

            normalizeWarmupSet(for: exercise)
            exercise.updatedAt = .now
            updatedExercises.append(exercise)
        }

        let updatedIDs = Set(updatedExercises.map(\.id))
        for exercise in orderedExistingExercises where !updatedIDs.contains(exercise.id) {
            modelContext.delete(exercise)
        }

        template.exercises = updatedExercises
        syncTemplateSupersetGroups(
            for: template,
            exercises: updatedExercises,
            membershipsByExerciseID: Dictionary(
                zip(updatedExercises, mutations).compactMap { exercise, mutation in
                    mutation.superset.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        syncCardioStructure(
            for: template,
            desiredDrafts: cardioMutations.map { mutation in
                TemplateCardioBlockDraft(
                    phase: mutation.phase,
                    catalogExerciseUUID: mutation.catalogExerciseUUID,
                    exerciseNameSnapshot: mutation.exerciseNameSnapshot,
                    categorySnapshot: mutation.categorySnapshot,
                    muscleSummarySnapshot: mutation.muscleSummarySnapshot,
                    targetDurationSeconds: mutation.targetDurationSeconds
                )
            }
        )
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func ensureDefaultSetPlans(templateID: UUID, defaultCount: Int = 3) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let setCount = max(1, defaultCount)
        var didChange = false
        let defaultLoadUnit = preferredLoadUnit()

        for exercise in (template.exercises ?? []) {
            let ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            if ordered.isEmpty {
                let defaults = TemplateExerciseDraft.defaultSetDrafts(
                    count: setCount,
                    restSeconds: exercise.restSeconds,
                    loadUnit: defaultLoadUnit
                )
                var sets: [TemplateExerciseSet] = []
                for (index, draft) in defaults.enumerated() {
                    let created = TemplateExerciseSet(
                        templateExerciseID: exercise.id,
                        sortOrder: index,
                        loadUnit: draft.loadUnit,
                        restSeconds: exercise.restSeconds,
                        isWarmup: draft.isWarmup,
                        isLocked: draft.isLocked,
                        previousLoadUnit: draft.previousLoadUnit,
                        templateExercise: exercise
                    )
                    modelContext.insert(created)
                    sets.append(created)
                }
                exercise.prescribedSets = sets
                exercise.updatedAt = .now
                didChange = true
                continue
            }

            for (index, set) in ordered.enumerated() {
                if set.sortOrder != index {
                    set.sortOrder = index
                    set.updatedAt = .now
                    didChange = true
                }
            }

            exercise.prescribedSets = ordered
        }

        if didChange {
            template.updatedAt = .now
            try saveUserDataChanges()
        }
    }

    func addExercise(templateID: UUID, catalogItem: ExerciseCatalogItem) throws {
        let draft = TemplateExerciseDraft(catalogItem: catalogItem, preferredLoadUnit: preferredLoadUnit())
        try addExercise(templateID: templateID, draft: draft)
    }

    func removeExercise(templateID: UUID, templateExerciseID: UUID) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let currentExercises = template.exercises ?? []
        guard let exercise = currentExercises.first(where: { $0.id == templateExerciseID }) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        deleteTemplateExerciseChildren(exercise)
        modelContext.delete(exercise)
        var updatedExercises = currentExercises
        updatedExercises.removeAll(where: { $0.id == templateExerciseID })
        template.exercises = updatedExercises
        reorder(template: template)
        syncTemplateSupersetGroups(
            for: template,
            exercises: (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder },
            membershipsByExerciseID: Dictionary(
                (template.exercises ?? []).compactMap { exercise in
                    exercise.supersetMembership.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    private func deleteTemplateExerciseChildren(_ exercise: TemplateExercise) {
        for set in exercise.prescribedSets ?? [] {
            for dropStage in set.dropStages ?? [] {
                modelContext.delete(dropStage)
            }
            modelContext.delete(set)
        }

        for component in exercise.components ?? [] {
            modelContext.delete(component)
        }
    }

    func moveExercise(templateID: UUID, fromOffsets: IndexSet, toOffset: Int) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        var ordered = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let movingItems = fromOffsets.sorted().map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            ordered.remove(at: index)
        }

        var destination = toOffset
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        destination -= removedBeforeDestination
        destination = max(0, min(destination, ordered.count))
        ordered.insert(contentsOf: movingItems, at: destination)

        for (index, exercise) in ordered.enumerated() {
            exercise.sortOrder = index
            exercise.updatedAt = .now
        }

        template.exercises = ordered
        syncTemplateSupersetGroups(
            for: template,
            exercises: ordered,
            membershipsByExerciseID: Dictionary(
                ordered.compactMap { exercise in
                    exercise.supersetMembership.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    func setExercises(templateID: UUID, drafts: [TemplateExerciseDraft]) throws {
        try replaceExercises(
            templateID: templateID,
            drafts: drafts,
            appliesDefaultSetPlansWhenEmpty: true
        )
    }

    func importExercises(templateID: UUID, drafts: [TemplateExerciseDraft]) throws {
        try replaceExercises(
            templateID: templateID,
            drafts: drafts,
            appliesDefaultSetPlansWhenEmpty: false
        )
    }

    private func replaceExercises(
        templateID: UUID,
        drafts: [TemplateExerciseDraft],
        appliesDefaultSetPlansWhenEmpty: Bool
    ) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        try validateUniqueComponentCatalogUUIDs(in: drafts)

        for existing in template.exercises ?? [] {
            modelContext.delete(existing)
        }
        template.exercises = []

        var createdExercises: [TemplateExercise] = []
        for (index, draft) in drafts.enumerated() {
            let normalizedRange = sanitizedRepRange(min: draft.targetRepMin, max: draft.targetRepMax)
            let normalizedRest = sanitizedRestSeconds(draft.restSeconds)
            let componentDrafts = normalizedComponentDrafts(from: draft)
            let primaryComponent = componentDrafts.first
            let exercise = TemplateExercise(
                templateID: templateID,
                catalogExerciseUUID: primaryComponent?.catalogExerciseUUID ?? draft.catalogExerciseUUID,
                exerciseNameSnapshot: primaryComponent?.exerciseNameSnapshot ?? draft.exerciseNameSnapshot,
                categorySnapshot: primaryComponent?.categorySnapshot ?? draft.categorySnapshot,
                muscleSummarySnapshot: primaryComponent?.muscleSummarySnapshot ?? draft.muscleSummarySnapshot,
                notes: draft.notes,
                targetRepMin: normalizedRange.min,
                targetRepMax: normalizedRange.max,
                restSeconds: normalizedRest,
                sortOrder: index,
                template: template
            )
            modelContext.insert(exercise)

            syncComponentStructure(
                for: exercise,
                desiredDrafts: componentDrafts
            )
            let sets = draft.setDrafts.isEmpty && appliesDefaultSetPlansWhenEmpty
                ? TemplateExerciseDraft.defaultSetDrafts(
                    restSeconds: normalizedRest,
                    loadUnit: preferredLoadUnit()
                )
                : draft.setDrafts
            syncSetStructure(
                for: exercise,
                desiredDrafts: sets,
                defaultRestSeconds: normalizedRest
            )
            normalizeWarmupSet(for: exercise)
            createdExercises.append(exercise)
        }
        template.exercises = createdExercises
        syncTemplateSupersetGroups(
            for: template,
            exercises: createdExercises,
            membershipsByExerciseID: Dictionary(
                zip(createdExercises, drafts).compactMap { exercise, draft in
                    draft.superset.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )

        template.updatedAt = .now
        try saveUserDataChanges()
    }

    private func addExercise(templateID: UUID, draft: TemplateExerciseDraft) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let componentDrafts = normalizedComponentDrafts(from: draft)
        for component in componentDrafts {
            if containsComponentCatalogUUID(
                component.catalogExerciseUUID,
                in: template
            ) {
                throw TemplateRepositoryError.duplicateExerciseComponent
            }
        }

        let existingExercises = template.exercises ?? []
        let nextIndex = existingExercises.map(\.sortOrder).max() ?? -1
        let normalizedRange = sanitizedRepRange(min: draft.targetRepMin, max: draft.targetRepMax)
        let normalizedRest = sanitizedRestSeconds(draft.restSeconds)
        let primaryComponent = componentDrafts.first
        let created = TemplateExercise(
            templateID: templateID,
            catalogExerciseUUID: primaryComponent?.catalogExerciseUUID ?? draft.catalogExerciseUUID,
            exerciseNameSnapshot: primaryComponent?.exerciseNameSnapshot ?? draft.exerciseNameSnapshot,
            categorySnapshot: primaryComponent?.categorySnapshot ?? draft.categorySnapshot,
            muscleSummarySnapshot: primaryComponent?.muscleSummarySnapshot ?? draft.muscleSummarySnapshot,
            notes: draft.notes,
            targetRepMin: normalizedRange.min,
            targetRepMax: normalizedRange.max,
            restSeconds: normalizedRest,
            sortOrder: nextIndex + 1,
            template: template
        )

        modelContext.insert(created)
        syncComponentStructure(for: created, desiredDrafts: componentDrafts)
        let setDrafts = draft.setDrafts.isEmpty
            ? TemplateExerciseDraft.defaultSetDrafts(
                restSeconds: normalizedRest,
                loadUnit: preferredLoadUnit()
            )
            : draft.setDrafts
        syncSetStructure(
            for: created,
            desiredDrafts: setDrafts,
            defaultRestSeconds: normalizedRest
        )
        normalizeWarmupSet(for: created)

        var updatedExercises = existingExercises
        updatedExercises.append(created)
        template.exercises = updatedExercises
        template.updatedAt = .now
        try saveUserDataChanges()
    }

    private func folder(id: UUID) throws -> TemplateFolder? {
        let descriptor = FetchDescriptor<TemplateFolder>(predicate: #Predicate { folder in
            folder.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func templateExercise(id: UUID) throws -> TemplateExercise? {
        let descriptor = FetchDescriptor<TemplateExercise>(predicate: #Predicate { exercise in
            exercise.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func workoutSession(id: UUID) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { session in
            session.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func workoutSessionExercises(sessionID: UUID) throws -> [WorkoutSessionExercise] {
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(
            predicate: #Predicate { exercise in
                exercise.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func workoutSessionCardioBlocks(sessionID: UUID) throws -> [WorkoutSessionCardioBlock] {
        let descriptor = FetchDescriptor<WorkoutSessionCardioBlock>(
            predicate: #Predicate { cardioBlock in
                cardioBlock.sessionID == sessionID
            }
        )
        return try modelContext.fetch(descriptor)
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func reorder(template: WorkoutTemplate) {
        let ordered = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        for (index, exercise) in ordered.enumerated() {
            exercise.sortOrder = index
            exercise.updatedAt = .now
        }
        template.exercises = ordered
    }

    private func reorderSets(for exercise: TemplateExercise) {
        let ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        for (index, set) in ordered.enumerated() {
            set.sortOrder = index
            set.updatedAt = .now
        }
        exercise.prescribedSets = ordered
    }

    private func orderedSetDrafts(for exercise: TemplateExercise) -> [TemplateExerciseSetDraft] {
        let ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return ordered.map { set in
            var draft = TemplateExerciseSetDraft(model: set)
            draft.restSeconds = exercise.restSeconds
            return draft
        }
    }

    private func orderedComponents(for exercise: TemplateExercise) -> [TemplateExerciseComponent] {
        (exercise.components ?? [])
            .filter { $0.modelContext != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func normalizedComponentDrafts(from draft: TemplateExerciseDraft) -> [TemplateExerciseComponentDraft] {
        TemplateExerciseDraft.normalizedComponents(
            from: draft.components,
            fallbackCatalogExerciseUUID: draft.catalogExerciseUUID,
            fallbackExerciseNameSnapshot: draft.exerciseNameSnapshot,
            fallbackCategorySnapshot: draft.categorySnapshot,
            fallbackMuscleSummarySnapshot: draft.muscleSummarySnapshot
        )
    }

    private func ensureTemplateComponentStructure(for exercise: TemplateExercise) -> Bool {
        var didChange = false
        var components = orderedComponents(for: exercise)

        if components.isEmpty, !exercise.catalogExerciseUUID.isEmpty {
            let created = TemplateExerciseComponent(
                templateExerciseID: exercise.id,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                sortOrder: 0,
                createdAt: exercise.createdAt,
                updatedAt: exercise.updatedAt,
                templateExercise: exercise
            )
            modelContext.insert(created)
            components = [created]
            didChange = true
        }

        for (index, component) in components.enumerated() {
            if component.templateExerciseID != exercise.id {
                component.templateExerciseID = exercise.id
                didChange = true
            }
            if component.sortOrder != index {
                component.sortOrder = index
                didChange = true
            }
        }

        if exercise.components?.map(\.id) != components.map(\.id) {
            exercise.components = components
            didChange = true
        }

        if syncPrimaryComponentSnapshot(for: exercise) {
            didChange = true
        }

        return didChange
    }

    private func syncComponentStructure(
        for exercise: TemplateExercise,
        desiredDrafts: [TemplateExerciseComponentDraft]
    ) {
        let normalizedDrafts = TemplateExerciseDraft.normalizedComponents(
            from: desiredDrafts,
            fallbackCatalogExerciseUUID: exercise.catalogExerciseUUID,
            fallbackExerciseNameSnapshot: exercise.exerciseNameSnapshot,
            fallbackCategorySnapshot: exercise.categorySnapshot,
            fallbackMuscleSummarySnapshot: exercise.muscleSummarySnapshot
        )
        let existingByID = Dictionary(
            orderedComponents(for: exercise).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let incomingIDs = Set(normalizedDrafts.map(\.id))

        for component in orderedComponents(for: exercise) where !incomingIDs.contains(component.id) {
            modelContext.delete(component)
        }

        var updatedComponents: [TemplateExerciseComponent] = []
        updatedComponents.reserveCapacity(normalizedDrafts.count)
        for (index, draft) in normalizedDrafts.enumerated() {
            let component = existingByID[draft.id] ?? TemplateExerciseComponent(
                id: draft.id,
                templateExerciseID: exercise.id,
                catalogExerciseUUID: draft.catalogExerciseUUID,
                exerciseNameSnapshot: draft.exerciseNameSnapshot,
                categorySnapshot: draft.categorySnapshot,
                muscleSummarySnapshot: draft.muscleSummarySnapshot,
                sortOrder: index,
                templateExercise: exercise
            )

            if component.modelContext == nil {
                modelContext.insert(component)
            }

            component.templateExerciseID = exercise.id
            component.templateExercise = exercise
            component.catalogExerciseUUID = draft.catalogExerciseUUID
            component.exerciseNameSnapshot = draft.exerciseNameSnapshot
            component.categorySnapshot = draft.categorySnapshot
            component.muscleSummarySnapshot = draft.muscleSummarySnapshot
            component.sortOrder = index
            component.updatedAt = .now
            updatedComponents.append(component)
        }

        exercise.components = updatedComponents
        _ = syncPrimaryComponentSnapshot(for: exercise)
    }

    @discardableResult
    private func syncPrimaryComponentSnapshot(for exercise: TemplateExercise) -> Bool {
        guard let primaryComponent = orderedComponents(for: exercise).first else {
            return false
        }

        var didChange = false
        if exercise.catalogExerciseUUID != primaryComponent.catalogExerciseUUID {
            exercise.catalogExerciseUUID = primaryComponent.catalogExerciseUUID
            didChange = true
        }
        if exercise.exerciseNameSnapshot != primaryComponent.exerciseNameSnapshot {
            exercise.exerciseNameSnapshot = primaryComponent.exerciseNameSnapshot
            didChange = true
        }
        if exercise.categorySnapshot != primaryComponent.categorySnapshot {
            exercise.categorySnapshot = primaryComponent.categorySnapshot
            didChange = true
        }
        if exercise.muscleSummarySnapshot != primaryComponent.muscleSummarySnapshot {
            exercise.muscleSummarySnapshot = primaryComponent.muscleSummarySnapshot
            didChange = true
        }
        return didChange
    }

    private func containsComponentCatalogUUID(
        _ catalogExerciseUUID: String,
        in template: WorkoutTemplate,
        excludingTemplateExerciseID excludedTemplateExerciseID: UUID? = nil
    ) -> Bool {
        let trimmed = catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return (template.exercises ?? []).contains { exercise in
            if let excludedTemplateExerciseID, exercise.id == excludedTemplateExerciseID {
                return false
            }
            let components = TemplateExerciseDraft.normalizedComponents(
                from: orderedComponents(for: exercise).map(TemplateExerciseComponentDraft.init(model:)),
                fallbackCatalogExerciseUUID: exercise.catalogExerciseUUID,
                fallbackExerciseNameSnapshot: exercise.exerciseNameSnapshot,
                fallbackCategorySnapshot: exercise.categorySnapshot,
                fallbackMuscleSummarySnapshot: exercise.muscleSummarySnapshot
            )
            return components.contains { $0.catalogExerciseUUID == trimmed }
        }
    }

    private func validateUniqueComponentCatalogUUIDs(in drafts: [TemplateExerciseDraft]) throws {
        var seen: Set<String> = []
        for draft in drafts {
            for component in normalizedComponentDrafts(from: draft) {
                let normalizedUUID = component.catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedUUID.isEmpty else {
                    continue
                }
                if seen.insert(normalizedUUID).inserted == false {
                    throw TemplateRepositoryError.duplicateExerciseComponent
                }
            }
        }
    }

    private func syncCardioStructure(
        for template: WorkoutTemplate,
        desiredDrafts: [TemplateCardioBlockDraft]
    ) {
        let orderedExisting = orderedCardioBlocks(for: template)
        let existingByPhase = Dictionary(
            orderedExisting.map { ($0.phase, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let desiredPhases = Set(desiredDrafts.map(\.phase))

        for cardioBlock in orderedExisting where !desiredPhases.contains(cardioBlock.phase) {
            modelContext.delete(cardioBlock)
        }

        var updatedBlocks: [TemplateCardioBlock] = []
        updatedBlocks.reserveCapacity(desiredDrafts.count)

        for draft in desiredDrafts.sorted(by: { $0.phase.sortOrder < $1.phase.sortOrder }) {
            let cardioBlock = existingByPhase[draft.phase]
                ?? TemplateCardioBlock(
                    id: draft.id,
                    templateID: template.id,
                    phase: draft.phase,
                    catalogExerciseUUID: draft.catalogExerciseUUID,
                    exerciseNameSnapshot: draft.exerciseNameSnapshot,
                    categorySnapshot: draft.categorySnapshot,
                    muscleSummarySnapshot: draft.muscleSummarySnapshot,
                    targetDurationSeconds: draft.targetDurationSeconds,
                    template: template
                )

            if cardioBlock.modelContext == nil {
                modelContext.insert(cardioBlock)
            }

            cardioBlock.templateID = template.id
            cardioBlock.template = template
            cardioBlock.phase = draft.phase
            cardioBlock.catalogExerciseUUID = draft.catalogExerciseUUID
            cardioBlock.exerciseNameSnapshot = draft.exerciseNameSnapshot
            cardioBlock.categorySnapshot = draft.categorySnapshot
            cardioBlock.muscleSummarySnapshot = draft.muscleSummarySnapshot
            cardioBlock.targetDurationSeconds = sanitizedCardioDurationSeconds(draft.targetDurationSeconds)
            cardioBlock.updatedAt = .now
            updatedBlocks.append(cardioBlock)
        }

        template.cardioBlocks = updatedBlocks
    }

    private func syncTemplateCardioCollection(for template: WorkoutTemplate) {
        template.cardioBlocks = orderedCardioBlocks(for: template)
    }

    private func orderedCardioBlocks(for template: WorkoutTemplate) -> [TemplateCardioBlock] {
        (template.cardioBlocks ?? [])
            .filter { $0.modelContext != nil }
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func syncSetStructure(
        for exercise: TemplateExercise,
        desiredDrafts: [TemplateExerciseSetDraft],
        defaultRestSeconds: Int
    ) {
        let existingSets = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingByID = Dictionary(
            existingSets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let incomingIDs = Set(desiredDrafts.map(\.id))
        var updatedSets: [TemplateExerciseSet] = []
        updatedSets.reserveCapacity(desiredDrafts.count)

        for (index, draft) in desiredDrafts.enumerated() {
            let modelSet = existingByID[draft.id]
                ?? TemplateExerciseSet(
                    id: draft.id,
                    templateExerciseID: exercise.id,
                    sortOrder: index,
                    restSeconds: defaultRestSeconds,
                    templateExercise: exercise
                )

            if modelSet.modelContext == nil {
                modelContext.insert(modelSet)
            }

            if hasTargetDelta(modelSet: modelSet, draft: draft) {
                modelSet.previousTargetReps = modelSet.targetReps
                modelSet.previousTargetWeight = modelSet.targetWeight
                modelSet.previousLoadUnit = modelSet.loadUnit
            }

            modelSet.templateExerciseID = exercise.id
            modelSet.sortOrder = index
            modelSet.targetReps = sanitizedReps(draft.targetReps)
            modelSet.targetWeight = sanitizedWeight(draft.targetWeight)
            modelSet.loadUnit = draft.loadUnit
            modelSet.restSeconds = sanitizedRestSeconds(defaultRestSeconds)
            modelSet.isWarmup = draft.isWarmup
            modelSet.isLocked = draft.isLocked
            modelSet.updatedAt = .now
            syncDropStageStructure(for: modelSet, desiredDrafts: draft.dropStages)
            updatedSets.append(modelSet)
        }

        for extraSet in existingSets where !incomingIDs.contains(extraSet.id) {
            modelContext.delete(extraSet)
        }

        exercise.prescribedSets = updatedSets
    }

    private func syncDropStageStructure(
        for set: TemplateExerciseSet,
        desiredDrafts: [TemplateExerciseDropStageDraft]
    ) {
        let normalizedDrafts = desiredDrafts
        let existingStages = (set.dropStages ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingByID = Dictionary(
            existingStages.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let incomingIDs = Set(normalizedDrafts.map(\.id))

        for stage in existingStages where !incomingIDs.contains(stage.id) {
            modelContext.delete(stage)
        }

        var updatedStages: [TemplateExerciseDropStage] = []
        updatedStages.reserveCapacity(normalizedDrafts.count)
        for (index, draft) in normalizedDrafts.enumerated() {
            let stage = existingByID[draft.id] ?? TemplateExerciseDropStage(
                id: draft.id,
                templateExerciseSetID: set.id,
                sortOrder: index,
                targetReps: sanitizedReps(draft.targetReps),
                targetWeight: sanitizedWeight(draft.targetWeight),
                loadUnit: draft.loadUnit,
                templateExerciseSet: set
            )

            if stage.modelContext == nil {
                modelContext.insert(stage)
            }

            stage.templateExerciseSetID = set.id
            stage.templateExerciseSet = set
            stage.sortOrder = index
            stage.targetReps = sanitizedReps(draft.targetReps)
            stage.targetWeight = sanitizedWeight(draft.targetWeight)
            stage.loadUnit = draft.loadUnit
            stage.updatedAt = .now
            updatedStages.append(stage)
        }

        set.dropStages = updatedStages
    }

    private func syncTemplateSupersetGroups(
        for template: WorkoutTemplate,
        exercises: [TemplateExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) {
        let orderedExercises = exercises.sorted { $0.sortOrder < $1.sortOrder }
        let existingGroups = (template.supersetGroups ?? []).filter { $0.modelContext != nil }
        let existingGroupsByID = Dictionary(
            existingGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalized = normalizedSupersetMemberships(
            for: orderedExercises,
            membershipsByExerciseID: membershipsByExerciseID
        )

        for group in existingGroups where normalized.groupsByID[group.id] == nil {
            modelContext.delete(group)
        }

        var updatedGroups: [TemplateSupersetGroup] = []
        updatedGroups.reserveCapacity(normalized.groupsByID.count)
        for exercise in orderedExercises {
            guard let membership = normalized.membershipsByExerciseID[exercise.id] else {
                clearSupersetMembership(for: exercise)
                if let standaloneRest = normalized.standaloneRestSecondsByExerciseID[exercise.id] {
                    applyStandaloneRest(standaloneRest, to: exercise)
                }
                continue
            }

            let spec = normalized.groupsByID[membership.groupID]
            let group = existingGroupsByID[membership.groupID] ?? TemplateSupersetGroup(
                id: membership.groupID,
                templateID: template.id,
                roundRestSeconds: membership.roundRestSeconds,
                template: template
            )

            if group.modelContext == nil {
                modelContext.insert(group)
            }

            group.templateID = template.id
            group.template = template
            group.roundRestSeconds = spec?.roundRestSeconds ?? membership.roundRestSeconds
            group.updatedAt = .now

            exercise.supersetGroupID = group.id
            exercise.supersetPosition = membership.position
            exercise.supersetGroup = group
            exercise.updatedAt = .now

            if updatedGroups.contains(where: { $0.id == group.id }) == false {
                updatedGroups.append(group)
            }
        }

        for group in updatedGroups {
            let members = orderedExercises
                .filter { $0.supersetGroupID == group.id }
                .sorted {
                    ($0.supersetPosition?.sortOrder ?? .max) < ($1.supersetPosition?.sortOrder ?? .max)
                }
            group.exercises = members
        }

        template.supersetGroups = updatedGroups.sorted { lhs, rhs in
            let lhsOrder = lhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? .max
            let rhsOrder = rhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? .max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func normalizedSupersetMemberships(
        for exercises: [TemplateExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) -> TemplateSupersetNormalization {
        var memberships: [UUID: ExerciseSupersetMembershipDraft] = [:]
        var standaloneRestSecondsByExerciseID: [UUID: Int] = [:]
        var groupsByID: [UUID: TemplateSupersetGroupSpec] = [:]
        var duplicateGroupIDs: Set<UUID> = []
        var index = 0

        while index < exercises.count {
            let exercise = exercises[index]
            guard let membership = membershipsByExerciseID[exercise.id] else {
                index += 1
                continue
            }

            guard membership.position == .first else {
                standaloneRestSecondsByExerciseID[exercise.id] = membership.roundRestSeconds
                index += 1
                continue
            }

            let nextIndex = index + 1
            guard nextIndex < exercises.count,
                  let nextMembership = membershipsByExerciseID[exercises[nextIndex].id],
                  nextMembership.groupID == membership.groupID,
                  nextMembership.position == .second else {
                standaloneRestSecondsByExerciseID[exercise.id] = membership.roundRestSeconds
                index += 1
                continue
            }

            if groupsByID[membership.groupID] != nil {
                duplicateGroupIDs.insert(membership.groupID)
            } else {
                let roundRestSeconds = sanitizedRestSeconds(nextMembership.roundRestSeconds)
                memberships[exercise.id] = ExerciseSupersetMembershipDraft(
                    groupID: membership.groupID,
                    position: .first,
                    roundRestSeconds: roundRestSeconds
                )
                memberships[exercises[nextIndex].id] = ExerciseSupersetMembershipDraft(
                    groupID: membership.groupID,
                    position: .second,
                    roundRestSeconds: roundRestSeconds
                )
                groupsByID[membership.groupID] = TemplateSupersetGroupSpec(
                    roundRestSeconds: roundRestSeconds,
                    exerciseIDs: [exercise.id, exercises[nextIndex].id]
                )
            }

            index += 2
        }

        for duplicateGroupID in duplicateGroupIDs {
            guard let spec = groupsByID.removeValue(forKey: duplicateGroupID) else { continue }
            for exerciseID in spec.exerciseIDs {
                memberships.removeValue(forKey: exerciseID)
                standaloneRestSecondsByExerciseID[exerciseID] = spec.roundRestSeconds
            }
        }

        for exercise in exercises where membershipsByExerciseID[exercise.id] != nil && memberships[exercise.id] == nil {
            standaloneRestSecondsByExerciseID[exercise.id] = sanitizedRestSeconds(
                membershipsByExerciseID[exercise.id]?.roundRestSeconds ?? exercise.restSeconds
            )
        }

        return TemplateSupersetNormalization(
            membershipsByExerciseID: memberships,
            standaloneRestSecondsByExerciseID: standaloneRestSecondsByExerciseID,
            groupsByID: groupsByID
        )
    }

    private func clearSupersetMembership(for exercise: TemplateExercise) {
        exercise.supersetGroupID = nil
        exercise.supersetPosition = nil
        exercise.supersetGroup = nil
        exercise.updatedAt = .now
    }

    private func applyStandaloneRest(_ restSeconds: Int, to exercise: TemplateExercise) {
        let normalizedRest = sanitizedRestSeconds(restSeconds)
        guard exercise.restSeconds != normalizedRest
            || (exercise.prescribedSets ?? []).contains(where: { $0.restSeconds != normalizedRest }) else {
            return
        }

        exercise.restSeconds = normalizedRest
        for set in exercise.prescribedSets ?? [] where set.restSeconds != normalizedRest {
            set.restSeconds = normalizedRest
            set.updatedAt = .now
        }
        exercise.updatedAt = .now
    }

    private func templateSyncExerciseMutation(
        from draft: TemplateExerciseDraft
    ) -> WorkoutTemplateSyncExerciseMutation {
        WorkoutTemplateSyncExerciseMutation(
            templateExerciseID: draft.id,
            catalogExerciseUUID: draft.catalogExerciseUUID,
            exerciseNameSnapshot: draft.exerciseNameSnapshot,
            categorySnapshot: draft.categorySnapshot,
            muscleSummarySnapshot: draft.muscleSummarySnapshot,
            notes: draft.notes,
            targetRepMin: draft.targetRepMin,
            targetRepMax: draft.targetRepMax,
            restSeconds: draft.restSeconds,
            setDrafts: draft.setDrafts,
            components: draft.components,
            superset: draft.superset
        )
    }

    private func templateSyncCardioMutation(
        from draft: TemplateCardioBlockDraft
    ) -> WorkoutTemplateSyncCardioMutation {
        WorkoutTemplateSyncCardioMutation(
            phase: draft.phase,
            catalogExerciseUUID: draft.catalogExerciseUUID,
            exerciseNameSnapshot: draft.exerciseNameSnapshot,
            categorySnapshot: draft.categorySnapshot,
            muscleSummarySnapshot: draft.muscleSummarySnapshot,
            targetDurationSeconds: draft.targetDurationSeconds
        )
    }

    private func duplicateSupersetGroupIDMap(from exercises: [TemplateExercise]) -> [UUID: UUID] {
        let sourceGroupIDs = Set(exercises.compactMap(\.supersetGroupID))
        return Dictionary(
            sourceGroupIDs.map { ($0, UUID()) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func duplicateDraft(
        from exercise: TemplateExercise,
        groupIDMap: [UUID: UUID]
    ) -> TemplateExerciseDraft {
        let copiedSuperset = exercise.supersetMembership.map { membership in
            ExerciseSupersetMembershipDraft(
                groupID: groupIDMap[membership.groupID] ?? UUID(),
                position: membership.position,
                roundRestSeconds: membership.roundRestSeconds
            )
        }

        return TemplateExerciseDraft(
            id: UUID(),
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseNameSnapshot: exercise.exerciseNameSnapshot,
            categorySnapshot: exercise.categorySnapshot,
            muscleSummarySnapshot: exercise.muscleSummarySnapshot,
            notes: exercise.notes,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            restSeconds: exercise.restSeconds,
            setDrafts: (exercise.prescribedSets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { set in
                    var draft = duplicateDraft(from: set)
                    draft.restSeconds = exercise.restSeconds
                    return draft
                },
            components: (exercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(duplicateDraft(from:)),
            superset: copiedSuperset
        )
    }

    private func duplicateDraft(from set: TemplateExerciseSet) -> TemplateExerciseSetDraft {
        TemplateExerciseSetDraft(
            id: UUID(),
            targetReps: set.targetReps,
            targetWeight: set.targetWeight,
            loadUnit: set.loadUnit,
            restSeconds: set.restSeconds,
            isWarmup: set.isWarmup,
            isLocked: set.isLocked,
            previousTargetReps: set.previousTargetReps,
            previousTargetWeight: set.previousTargetWeight,
            previousLoadUnit: set.previousLoadUnit,
            dropStages: (set.dropStages ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(duplicateDraft(from:))
        )
    }

    private func duplicateDraft(from stage: TemplateExerciseDropStage) -> TemplateExerciseDropStageDraft {
        TemplateExerciseDropStageDraft(
            id: UUID(),
            targetReps: stage.targetReps,
            targetWeight: stage.targetWeight,
            loadUnit: stage.loadUnit
        )
    }

    private func duplicateDraft(from component: TemplateExerciseComponent) -> TemplateExerciseComponentDraft {
        TemplateExerciseComponentDraft(
            id: UUID(),
            catalogExerciseUUID: component.catalogExerciseUUID,
            exerciseNameSnapshot: component.exerciseNameSnapshot,
            categorySnapshot: component.categorySnapshot,
            muscleSummarySnapshot: component.muscleSummarySnapshot
        )
    }

    private func duplicateDraft(from cardioBlock: TemplateCardioBlock) -> TemplateCardioBlockDraft {
        TemplateCardioBlockDraft(
            id: UUID(),
            phase: cardioBlock.phase,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            targetDurationSeconds: cardioBlock.targetDurationSeconds
        )
    }

    private func normalizeWarmupSet(for exercise: TemplateExercise) {
        let ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        exercise.prescribedSets = ordered
    }

    private func persistenceSignature(
        for template: WorkoutTemplate,
        resolvedName: String
    ) -> TemplateContentsPersistenceSignature {
        let exercises = (template.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, exercise in
                persistenceSignature(for: exercise, at: index)
            }
        let cardioBlocks = (template.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
            .map(persistenceSignature(for:))

        return TemplateContentsPersistenceSignature(
            name: resolvedName,
            notes: normalizedTemplateNotes(template.notes),
            exercises: exercises,
            cardioBlocks: cardioBlocks
        )
    }

    private func persistenceSignature(
        templateName: String,
        templateNotes: String,
        exercises mutations: [WorkoutTemplateSyncExerciseMutation],
        cardioBlocks cardioMutations: [WorkoutTemplateSyncCardioMutation],
        existingByCatalogUUID: [String: TemplateExercise]
    ) -> TemplateContentsPersistenceSignature {
        let exercises = mutations.enumerated().map { index, mutation in
            persistenceSignature(
                for: mutation,
                at: index,
                existingByCatalogUUID: existingByCatalogUUID
            )
        }
        let cardioBlocks = cardioMutations
            .map(persistenceSignature(for:))
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }

        return TemplateContentsPersistenceSignature(
            name: templateName,
            notes: normalizedTemplateNotes(templateNotes),
            exercises: exercises,
            cardioBlocks: cardioBlocks
        )
    }

    private func persistenceSignature(
        for exercise: TemplateExercise,
        at index: Int
    ) -> TemplateExercisePersistenceSignature {
        let orderedComponents = (exercise.components ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(TemplateExerciseComponentDraft.init(model:))
        let normalizedComponents = TemplateExerciseDraft.normalizedComponents(
            from: orderedComponents,
            fallbackCatalogExerciseUUID: exercise.catalogExerciseUUID,
            fallbackExerciseNameSnapshot: exercise.exerciseNameSnapshot,
            fallbackCategorySnapshot: exercise.categorySnapshot,
            fallbackMuscleSummarySnapshot: exercise.muscleSummarySnapshot
        )
        let orderedSets = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }

        return TemplateExercisePersistenceSignature(
            id: exercise.id,
            sortOrder: index,
            catalogExerciseUUID: exercise.catalogExerciseUUID,
            exerciseNameSnapshot: exercise.exerciseNameSnapshot,
            categorySnapshot: exercise.categorySnapshot,
            muscleSummarySnapshot: exercise.muscleSummarySnapshot,
            notes: exercise.notes,
            targetRepMin: sanitizedReps(exercise.targetRepMin),
            targetRepMax: sanitizedReps(exercise.targetRepMax),
            restSeconds: sanitizedRestSeconds(exercise.restSeconds),
            setDrafts: orderedSets.enumerated().map { setIndex, set in
                persistenceSignature(for: set, at: setIndex)
            },
            components: normalizedComponents.map(persistenceSignature(for:)),
            superset: persistenceSignature(forSupersetOf: exercise)
        )
    }

    private func persistenceSignature(
        for mutation: WorkoutTemplateSyncExerciseMutation,
        at index: Int,
        existingByCatalogUUID: [String: TemplateExercise]
    ) -> TemplateExercisePersistenceSignature {
        let normalizedRange = sanitizedRepRange(min: mutation.targetRepMin, max: mutation.targetRepMax)
        let normalizedRest = sanitizedRestSeconds(mutation.restSeconds)
        let normalizedComponents = TemplateExerciseDraft.normalizedComponents(
            from: mutation.components,
            fallbackCatalogExerciseUUID: mutation.catalogExerciseUUID,
            fallbackExerciseNameSnapshot: mutation.exerciseNameSnapshot,
            fallbackCategorySnapshot: mutation.categorySnapshot,
            fallbackMuscleSummarySnapshot: mutation.muscleSummarySnapshot
        )
        let primaryComponent = normalizedComponents.first
        let exerciseID = mutation.templateExerciseID
            ?? existingByCatalogUUID[mutation.catalogExerciseUUID]?.id
            ?? UUID()
        let canonicalSetDrafts = mutation.setDrafts.map { draft in
            var updated = draft
            updated.restSeconds = normalizedRest
            return updated
        }

        return TemplateExercisePersistenceSignature(
            id: exerciseID,
            sortOrder: index,
            catalogExerciseUUID: primaryComponent?.catalogExerciseUUID ?? mutation.catalogExerciseUUID,
            exerciseNameSnapshot: primaryComponent?.exerciseNameSnapshot ?? mutation.exerciseNameSnapshot,
            categorySnapshot: primaryComponent?.categorySnapshot ?? mutation.categorySnapshot,
            muscleSummarySnapshot: primaryComponent?.muscleSummarySnapshot ?? mutation.muscleSummarySnapshot,
            notes: mutation.notes,
            targetRepMin: normalizedRange.min,
            targetRepMax: normalizedRange.max,
            restSeconds: normalizedRest,
            setDrafts: canonicalSetDrafts.enumerated().map { setIndex, draft in
                persistenceSignature(for: draft, at: setIndex)
            },
            components: normalizedComponents.map(persistenceSignature(for:)),
            superset: mutation.superset.map(persistenceSignature(for:))
        )
    }

    private func persistenceSignature(
        for component: TemplateExerciseComponentDraft
    ) -> TemplateExerciseComponentPersistenceSignature {
        TemplateExerciseComponentPersistenceSignature(
            catalogExerciseUUID: component.catalogExerciseUUID,
            exerciseNameSnapshot: component.exerciseNameSnapshot,
            categorySnapshot: component.categorySnapshot,
            muscleSummarySnapshot: component.muscleSummarySnapshot
        )
    }

    private func persistenceSignature(
        for cardioBlock: TemplateCardioBlock
    ) -> TemplateCardioPersistenceSignature {
        TemplateCardioPersistenceSignature(
            phase: cardioBlock.phase,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            targetDurationSeconds: sanitizedCardioDurationSeconds(cardioBlock.targetDurationSeconds)
        )
    }

    private func persistenceSignature(
        for mutation: WorkoutTemplateSyncCardioMutation
    ) -> TemplateCardioPersistenceSignature {
        TemplateCardioPersistenceSignature(
            phase: mutation.phase,
            catalogExerciseUUID: mutation.catalogExerciseUUID,
            exerciseNameSnapshot: mutation.exerciseNameSnapshot,
            categorySnapshot: mutation.categorySnapshot,
            muscleSummarySnapshot: mutation.muscleSummarySnapshot,
            targetDurationSeconds: sanitizedCardioDurationSeconds(mutation.targetDurationSeconds)
        )
    }

    private func persistenceSignature(
        for membership: ExerciseSupersetMembershipDraft
    ) -> TemplateExerciseSupersetPersistenceSignature {
        TemplateExerciseSupersetPersistenceSignature(
            groupID: membership.groupID,
            position: membership.position,
            roundRestSeconds: sanitizedRestSeconds(membership.roundRestSeconds)
        )
    }

    private func persistenceSignature(
        forSupersetOf exercise: TemplateExercise
    ) -> TemplateExerciseSupersetPersistenceSignature? {
        guard let groupID = exercise.supersetGroupID,
              let position = exercise.supersetPosition else {
            return nil
        }

        return TemplateExerciseSupersetPersistenceSignature(
            groupID: groupID,
            position: position,
            roundRestSeconds: sanitizedRestSeconds(exercise.supersetGroup?.roundRestSeconds ?? 0)
        )
    }

    private func persistenceSignature(
        for draft: TemplateExerciseSetDraft,
        at index: Int
    ) -> TemplateExerciseSetPersistenceSignature {
        TemplateExerciseSetPersistenceSignature(
            id: draft.id,
            sortOrder: index,
            targetReps: sanitizedReps(draft.targetReps),
            targetWeight: sanitizedWeight(draft.targetWeight),
            loadUnit: draft.loadUnit,
            restSeconds: sanitizedRestSeconds(draft.restSeconds),
            isWarmup: draft.isWarmup,
            isLocked: draft.isLocked,
            dropStages: draft.dropStages.enumerated().map { stageIndex, stage in
                persistenceSignature(for: stage, at: stageIndex)
            }
        )
    }

    private func persistenceSignature(
        for set: TemplateExerciseSet,
        at index: Int
    ) -> TemplateExerciseSetPersistenceSignature {
        TemplateExerciseSetPersistenceSignature(
            id: set.id,
            sortOrder: index,
            targetReps: set.targetReps,
            targetWeight: set.targetWeight,
            loadUnit: set.loadUnit,
            restSeconds: set.restSeconds,
            isWarmup: set.isWarmup,
            isLocked: set.isLocked,
            dropStages: (set.dropStages ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated()
                .map { stageIndex, stage in
                    persistenceSignature(for: stage, at: stageIndex)
                }
        )
    }

    private func persistenceSignature(
        for draft: TemplateExerciseDropStageDraft,
        at index: Int
    ) -> TemplateExerciseDropStagePersistenceSignature {
        TemplateExerciseDropStagePersistenceSignature(
            id: draft.id,
            sortOrder: index,
            targetReps: sanitizedReps(draft.targetReps),
            targetWeight: sanitizedWeight(draft.targetWeight),
            loadUnit: draft.loadUnit
        )
    }

    private func persistenceSignature(
        for stage: TemplateExerciseDropStage,
        at index: Int
    ) -> TemplateExerciseDropStagePersistenceSignature {
        TemplateExerciseDropStagePersistenceSignature(
            id: stage.id,
            sortOrder: index,
            targetReps: stage.targetReps,
            targetWeight: stage.targetWeight,
            loadUnit: stage.loadUnit
        )
    }

    private func hasTargetDelta(modelSet: TemplateExerciseSet, draft: TemplateExerciseSetDraft) -> Bool {
        sanitizedReps(draft.targetReps) != modelSet.targetReps
            || sanitizedWeight(draft.targetWeight) != modelSet.targetWeight
            || draft.loadUnit != modelSet.loadUnit
    }

    private func sanitizedReps(_ reps: Int?) -> Int? {
        guard let reps else { return nil }
        return min(999, max(0, reps))
    }

    private func sanitizedWeight(_ weight: Double?) -> Double? {
        guard let weight else { return nil }
        return min(5000, max(0, weight))
    }

    private func sanitizedRestSeconds(_ seconds: Int) -> Int {
        min(3600, max(0, seconds))
    }

    private func sanitizedCardioDurationSeconds(_ seconds: Int) -> Int {
        min(24 * 60 * 60, max(0, seconds))
    }

    private func sanitizedRepRange(min minReps: Int?, max maxReps: Int?) -> (min: Int?, max: Int?) {
        let safeMin = sanitizedReps(minReps)
        let safeMax = sanitizedReps(maxReps)
        return (safeMin, safeMax)
    }
}

nonisolated private struct TemplateContentsPersistenceSignature: Equatable {
    let name: String
    let notes: String
    let exercises: [TemplateExercisePersistenceSignature]
    let cardioBlocks: [TemplateCardioPersistenceSignature]
}

nonisolated private struct TemplateExercisePersistenceSignature: Equatable {
    let id: UUID
    let sortOrder: Int
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let setDrafts: [TemplateExerciseSetPersistenceSignature]
    let components: [TemplateExerciseComponentPersistenceSignature]
    let superset: TemplateExerciseSupersetPersistenceSignature?
}

nonisolated private struct TemplateExerciseComponentPersistenceSignature: Equatable {
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
}

nonisolated private struct TemplateExerciseSupersetPersistenceSignature: Equatable {
    let groupID: UUID
    let position: SupersetExercisePosition
    let roundRestSeconds: Int
}

nonisolated private struct TemplateCardioPersistenceSignature: Equatable {
    let phase: WorkoutCardioPhase
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetDurationSeconds: Int
}

nonisolated private struct TemplateExerciseSetPersistenceSignature: Equatable {
    let id: UUID
    let sortOrder: Int
    let targetReps: Int?
    let targetWeight: Double?
    let loadUnit: TemplateLoadUnit
    let restSeconds: Int
    let isWarmup: Bool
    let isLocked: Bool
    let dropStages: [TemplateExerciseDropStagePersistenceSignature]
}

nonisolated private struct TemplateExerciseDropStagePersistenceSignature: Equatable {
    let id: UUID
    let sortOrder: Int
    let targetReps: Int?
    let targetWeight: Double?
    let loadUnit: TemplateLoadUnit
}

private struct TemplateSupersetNormalization {
    let membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    let standaloneRestSecondsByExerciseID: [UUID: Int]
    let groupsByID: [UUID: TemplateSupersetGroupSpec]
}

private struct TemplateSupersetGroupSpec {
    let roundRestSeconds: Int
    let exerciseIDs: [UUID]
}
