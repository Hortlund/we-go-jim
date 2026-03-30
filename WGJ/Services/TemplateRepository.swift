import Foundation
import SwiftData

struct TemplateExerciseSetDraft: Identifiable, Equatable {
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
        previousLoadUnit: TemplateLoadUnit = .kg
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
    }

    init(model: TemplateExerciseSet) {
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
    }
}

struct TemplateExerciseDraft: Identifiable, Equatable {
    let id: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var setDrafts: [TemplateExerciseSetDraft]

    init(
        id: UUID = UUID(),
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        setDrafts: [TemplateExerciseSetDraft] = []
    ) {
        self.id = id
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = restSeconds
        self.setDrafts = setDrafts
    }

    init(model: TemplateExercise, preferredLoadUnit: TemplateLoadUnit = .kg) {
        self.id = model.id
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.targetRepMin = model.targetRepMin
        self.targetRepMax = model.targetRepMax
        self.restSeconds = model.restSeconds
        let orderedSets = (model.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        if orderedSets.isEmpty {
            self.setDrafts = Self.defaultSetDrafts(loadUnit: preferredLoadUnit)
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
                        restSeconds: set.restSeconds,
                        isWarmup: set.isWarmup,
                        isLocked: set.isLocked,
                        previousTargetReps: set.previousTargetReps,
                        previousTargetWeight: set.previousTargetWeight,
                        previousLoadUnit: set.previousLoadUnit
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
        self.targetRepMin = nil
        self.targetRepMax = nil
        self.restSeconds = 120
        self.setDrafts = Self.defaultSetDrafts(loadUnit: preferredLoadUnit)
    }

    static func defaultSetDrafts(count: Int = 3, loadUnit: TemplateLoadUnit = .kg) -> [TemplateExerciseSetDraft] {
        let safeCount = max(1, count)
        return (0..<safeCount).map { index in
            TemplateExerciseSetDraft(
                loadUnit: loadUnit,
                restSeconds: 120,
                isWarmup: index == 0,
                previousLoadUnit: loadUnit
            )
        }
    }
}

enum TemplateRepositoryError: Error {
    case invalidName
    case folderNotFound
    case templateNotFound
    case templateExerciseNotFound
    case templateExerciseSetNotFound
    case workoutSessionNotFound
}

@MainActor
final class TemplateRepository {
    static let unfiledFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func preferredLoadUnit() -> TemplateLoadUnit {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        return (try? profileRepository.currentProfile()?.preferredLoadUnit) ?? .kg
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

    func createFolder(name: String) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .folderName)

        let existing = try folders()
        let created = TemplateFolder(name: cleaned, sortOrder: (existing.last?.sortOrder ?? -1) + 1)
        modelContext.insert(created)
        try modelContext.save()
    }

    func renameFolder(id: UUID, name: String) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .folderName)

        guard let folder = try folder(id: id) else {
            throw TemplateRepositoryError.folderNotFound
        }

        folder.name = cleaned
        folder.updatedAt = .now
        try modelContext.save()
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

        try modelContext.save()
    }

    func deleteFolder(id: UUID) throws {
        guard let folder = try folder(id: id) else {
            throw TemplateRepositoryError.folderNotFound
        }

        for template in folder.templates ?? [] {
            for exercise in template.exercises ?? [] {
                modelContext.delete(exercise)
            }
            modelContext.delete(template)
        }

        modelContext.delete(folder)
        try modelContext.save()
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
        try modelContext.save()
        return template
    }

    func createTemplate(fromSessionID sessionID: UUID, name: String, folderID: UUID? = nil) throws -> WorkoutTemplate {
        guard let session = try workoutSession(id: sessionID) else {
            throw TemplateRepositoryError.workoutSessionNotFound
        }

        let template = try createTemplate(
            folderID: folderID,
            name: name,
            notes: "Saved from workout \(session.startedAt.formatted(date: .abbreviated, time: .shortened))"
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
                    isLocked: set.isLocked
                )
            }

            return TemplateExerciseDraft(
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                targetRepMin: nil,
                targetRepMax: nil,
                restSeconds: exercise.restSeconds,
                setDrafts: setDrafts.isEmpty ? TemplateExerciseDraft.defaultSetDrafts(loadUnit: preferredLoadUnit()) : setDrafts
            )
        }

        try setExercises(templateID: template.id, drafts: drafts)
        return template
    }

    func updateTemplate(id: UUID, name: String, notes: String) throws {
        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .templateName)

        guard let template = try template(id: id) else {
            throw TemplateRepositoryError.templateNotFound
        }

        template.name = cleaned
        template.notes = notes
        template.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRepRange(templateExerciseID: UUID, minReps: Int?, maxReps: Int?) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let normalized = sanitizedRepRange(min: minReps, max: maxReps)
        exercise.targetRepMin = normalized.min
        exercise.targetRepMax = normalized.max
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRestSeconds(templateExerciseID: UUID, restSeconds: Int) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let normalized = sanitizedRestSeconds(restSeconds)
        exercise.restSeconds = normalized

        for set in exercise.prescribedSets ?? [] {
            set.restSeconds = normalized
            set.updatedAt = .now
        }

        exercise.updatedAt = .now
        try modelContext.save()
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

        try modelContext.save()
    }

    func deleteTemplate(id: UUID) throws {
        guard let template = try template(id: id) else {
            throw TemplateRepositoryError.templateNotFound
        }

        for exercise in template.exercises ?? [] {
            modelContext.delete(exercise)
        }

        modelContext.delete(template)
        try modelContext.save()
    }

    func exercises(in templateID: UUID) throws -> [TemplateExercise] {
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { item in
                item.templateID == templateID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func setDrafts(for templateExerciseID: UUID) throws -> [TemplateExerciseSetDraft] {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }
        return orderedSetDrafts(for: exercise)
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
        try modelContext.save()
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
        try modelContext.save()
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
        try modelContext.save()
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
        try modelContext.save()
    }

    func saveSetDrafts(templateExerciseID: UUID, drafts: [TemplateExerciseSetDraft]) throws {
        guard let exercise = try templateExercise(id: templateExerciseID) else {
            throw TemplateRepositoryError.templateExerciseNotFound
        }

        let existingSets = exercise.prescribedSets ?? []
        let incomingIDs = Set(drafts.map(\.id))

        for set in existingSets where !incomingIDs.contains(set.id) {
            modelContext.delete(set)
        }

        var updatedSets: [TemplateExerciseSet] = []
        for (index, draft) in drafts.enumerated() {
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
            modelSet.restSeconds = sanitizedRestSeconds(draft.restSeconds)
            modelSet.isWarmup = draft.isWarmup
            modelSet.isLocked = draft.isLocked
            modelSet.updatedAt = .now
            updatedSets.append(modelSet)
        }

        exercise.prescribedSets = updatedSets
        normalizeWarmupSet(for: exercise)
        exercise.updatedAt = .now
        try modelContext.save()
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
                let defaults = TemplateExerciseDraft.defaultSetDrafts(count: setCount, loadUnit: defaultLoadUnit)
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
            try modelContext.save()
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

        modelContext.delete(exercise)
        var updatedExercises = currentExercises
        updatedExercises.removeAll(where: { $0.id == templateExerciseID })
        template.exercises = updatedExercises
        reorder(template: template)
        template.updatedAt = .now
        try modelContext.save()
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
        template.updatedAt = .now
        try modelContext.save()
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

        for existing in template.exercises ?? [] {
            modelContext.delete(existing)
        }
        template.exercises = []

        var createdExercises: [TemplateExercise] = []
        for (index, draft) in drafts.enumerated() {
            let normalizedRange = sanitizedRepRange(min: draft.targetRepMin, max: draft.targetRepMax)
            let normalizedRest = sanitizedRestSeconds(draft.restSeconds)
            let exercise = TemplateExercise(
                templateID: templateID,
                catalogExerciseUUID: draft.catalogExerciseUUID,
                exerciseNameSnapshot: draft.exerciseNameSnapshot,
                categorySnapshot: draft.categorySnapshot,
                muscleSummarySnapshot: draft.muscleSummarySnapshot,
                targetRepMin: normalizedRange.min,
                targetRepMax: normalizedRange.max,
                restSeconds: normalizedRest,
                sortOrder: index,
                template: template
            )
            modelContext.insert(exercise)

            let sets = draft.setDrafts.isEmpty && appliesDefaultSetPlansWhenEmpty
                ? TemplateExerciseDraft.defaultSetDrafts(loadUnit: preferredLoadUnit())
                : draft.setDrafts
            var createdSets: [TemplateExerciseSet] = []
            for (setIndex, setDraft) in sets.enumerated() {
                let createdSet = TemplateExerciseSet(
                    id: setDraft.id,
                    templateExerciseID: exercise.id,
                    sortOrder: setIndex,
                    targetReps: sanitizedReps(setDraft.targetReps),
                    targetWeight: sanitizedWeight(setDraft.targetWeight),
                    loadUnit: setDraft.loadUnit,
                    restSeconds: sanitizedRestSeconds(setDraft.restSeconds),
                    isWarmup: setDraft.isWarmup,
                    isLocked: setDraft.isLocked,
                    previousTargetReps: sanitizedReps(setDraft.previousTargetReps),
                    previousTargetWeight: sanitizedWeight(setDraft.previousTargetWeight),
                    previousLoadUnit: setDraft.previousLoadUnit,
                    templateExercise: exercise
                )
                modelContext.insert(createdSet)
                createdSets.append(createdSet)
            }
            exercise.prescribedSets = createdSets
            normalizeWarmupSet(for: exercise)
            createdExercises.append(exercise)
        }
        template.exercises = createdExercises

        template.updatedAt = .now
        try modelContext.save()
    }

    private func addExercise(templateID: UUID, draft: TemplateExerciseDraft) throws {
        guard let template = try template(id: templateID) else {
            throw TemplateRepositoryError.templateNotFound
        }

        let existingExercises = template.exercises ?? []
        if existingExercises.contains(where: { $0.catalogExerciseUUID == draft.catalogExerciseUUID }) {
            return
        }

        let nextIndex = existingExercises.map(\.sortOrder).max() ?? -1
        let normalizedRange = sanitizedRepRange(min: draft.targetRepMin, max: draft.targetRepMax)
        let normalizedRest = sanitizedRestSeconds(draft.restSeconds)
        let created = TemplateExercise(
            templateID: templateID,
            catalogExerciseUUID: draft.catalogExerciseUUID,
            exerciseNameSnapshot: draft.exerciseNameSnapshot,
            categorySnapshot: draft.categorySnapshot,
            muscleSummarySnapshot: draft.muscleSummarySnapshot,
            targetRepMin: normalizedRange.min,
            targetRepMax: normalizedRange.max,
            restSeconds: normalizedRest,
            sortOrder: nextIndex + 1,
            template: template
        )

        modelContext.insert(created)
        let setDrafts = draft.setDrafts.isEmpty
            ? TemplateExerciseDraft.defaultSetDrafts(loadUnit: preferredLoadUnit())
            : draft.setDrafts
        var createdSets: [TemplateExerciseSet] = []
        for (index, setDraft) in setDrafts.enumerated() {
            let createdSet = TemplateExerciseSet(
                id: setDraft.id,
                templateExerciseID: created.id,
                sortOrder: index,
                targetReps: sanitizedReps(setDraft.targetReps),
                targetWeight: sanitizedWeight(setDraft.targetWeight),
                loadUnit: setDraft.loadUnit,
                restSeconds: sanitizedRestSeconds(setDraft.restSeconds),
                isWarmup: setDraft.isWarmup,
                isLocked: setDraft.isLocked,
                previousTargetReps: sanitizedReps(setDraft.previousTargetReps),
                previousTargetWeight: sanitizedWeight(setDraft.previousTargetWeight),
                previousLoadUnit: setDraft.previousLoadUnit,
                templateExercise: created
            )
            modelContext.insert(createdSet)
            createdSets.append(createdSet)
        }
        created.prescribedSets = createdSets
        normalizeWarmupSet(for: created)

        var updatedExercises = existingExercises
        updatedExercises.append(created)
        template.exercises = updatedExercises
        template.updatedAt = .now
        try modelContext.save()
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
        return ordered.map(TemplateExerciseSetDraft.init(model:))
    }

    private func normalizeWarmupSet(for exercise: TemplateExercise) {
        let ordered = (exercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        exercise.prescribedSets = ordered
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

    private func sanitizedRepRange(min minReps: Int?, max maxReps: Int?) -> (min: Int?, max: Int?) {
        let safeMin = sanitizedReps(minReps)
        let safeMax = sanitizedReps(maxReps)
        return (safeMin, safeMax)
    }
}
