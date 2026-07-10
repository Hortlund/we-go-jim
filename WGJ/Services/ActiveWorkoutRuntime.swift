import Foundation
import Observation
import SwiftData

nonisolated struct ActiveWorkoutRuntimeSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var templateID: UUID?
    var name: String
    var startedAt: Date
    var notes: String
    var cardioBlocks: [ActiveWorkoutRuntimeCardioBlock]
    var exercises: [ActiveWorkoutRuntimeExercise]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        name: String,
        startedAt: Date = .now,
        notes: String = "",
        cardioBlocks: [ActiveWorkoutRuntimeCardioBlock] = [],
        exercises: [ActiveWorkoutRuntimeExercise] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.templateID = templateID
        self.name = ReviewModerationService.sanitizedForSharing(name, kind: .workoutName)
        self.startedAt = startedAt
        self.notes = notes
        self.cardioBlocks = cardioBlocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
        self.exercises = exercises.sorted { $0.sortOrder < $1.sortOrder }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct RestTimerSnapshot: Equatable, Codable, Sendable {
    let endsAt: Date
    let exerciseName: String?
    let setLabel: String?
    let sourceSetID: UUID?

    var isExpired: Bool {
        isExpired(at: .now)
    }

    func isExpired(at date: Date) -> Bool {
        endsAt <= date
    }
}

nonisolated enum ActiveWorkoutStoredPresentationMode: String, Codable, Sendable {
    case presented
    case collapsed
}

nonisolated struct ActiveWorkoutStoredSnapshot: Equatable, Codable, Sendable {
    let session: ActiveWorkoutRuntimeSession
    let restTimer: RestTimerSnapshot?
    let presentationMode: ActiveWorkoutStoredPresentationMode?
    let scrollTarget: ActiveWorkoutScrollTarget?
    let expandedExerciseIDs: Set<UUID>

    init(
        session: ActiveWorkoutRuntimeSession,
        restTimer: RestTimerSnapshot? = nil,
        presentationMode: ActiveWorkoutStoredPresentationMode? = nil,
        scrollTarget: ActiveWorkoutScrollTarget? = nil,
        expandedExerciseIDs: Set<UUID> = []
    ) {
        self.session = session
        self.restTimer = restTimer
        self.presentationMode = presentationMode
        self.scrollTarget = scrollTarget
        self.expandedExerciseIDs = expandedExerciseIDs
    }

    private enum CodingKeys: String, CodingKey {
        case session
        case restTimer
        case presentationMode
        case scrollTarget
        case expandedExerciseIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(ActiveWorkoutRuntimeSession.self, forKey: .session)
        restTimer = try container.decodeIfPresent(RestTimerSnapshot.self, forKey: .restTimer)
        presentationMode = try container.decodeIfPresent(ActiveWorkoutStoredPresentationMode.self, forKey: .presentationMode)
        scrollTarget = try container.decodeIfPresent(ActiveWorkoutScrollTarget.self, forKey: .scrollTarget)
        expandedExerciseIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .expandedExerciseIDs) ?? []
    }
}

nonisolated extension ActiveWorkoutRuntimeSession {
    mutating func touch(date: Date = .now) {
        updatedAt = date
    }

    mutating func normalizeExerciseSortOrder() {
        exercises = exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, exercise in
                var updated = exercise
                updated.sortOrder = index
                return updated
            }
    }

    mutating func normalizeSetRestToExerciseDefaults() {
        exercises = exercises.map { exercise in
            var updated = exercise
            updated.normalizeSetRestToExerciseDefault()
            return updated
        }
    }

    func snapshotForActiveWorkoutPersistence(
        sessionNameDraft: String,
        notesDraft: String,
        pendingCardioCompletionsByPhase: [WorkoutCardioPhase: Bool],
        setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        restByExerciseID: [UUID: Int],
        notesByExerciseID: [UUID: String],
        date: Date = .now
    ) -> ActiveWorkoutRuntimeSession {
        var snapshot = self
        let normalizedName = sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedName.isEmpty {
            snapshot.name = ReviewModerationService.sanitizedForSharing(normalizedName, kind: .workoutName)
        }
        snapshot.notes = notesDraft
        snapshot.cardioBlocks = snapshot.cardioBlocks.map { cardioBlock in
            var updated = cardioBlock
            if let completion = pendingCardioCompletionsByPhase[cardioBlock.phase] {
                updated.isCompleted = completion
                updated.updatedAt = date
            }
            return updated
        }
        snapshot.exercises = snapshot.exercises.map { exercise in
            var updated = exercise
            updated.setDrafts = setDraftsByExerciseID[exercise.id] ?? exercise.setDrafts
            updated.restSeconds = restByExerciseID[exercise.id] ?? exercise.restSeconds
            updated.notes = notesByExerciseID[exercise.id] ?? exercise.notes
            return updated
        }
        snapshot.normalizeExerciseSortOrder()
        if snapshot != self {
            snapshot.touch(date: date)
        }
        return snapshot
    }
}

nonisolated struct ActiveWorkoutRuntimeCardioBlock: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var phase: WorkoutCardioPhase
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetDurationSeconds: Int
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.phase = phase
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = min(24 * 60 * 60, max(0, targetDurationSeconds))
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(model: ActiveWorkoutDraftCardioBlock) {
        self.init(
            id: model.id,
            phase: model.phase,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot,
            targetDurationSeconds: model.targetDurationSeconds,
            isCompleted: model.isCompleted,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

nonisolated struct ActiveWorkoutRuntimeExercise: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var templateExerciseID: UUID?
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var sortOrder: Int
    var components: [ActiveWorkoutRuntimeExerciseComponent]
    var setDrafts: [WorkoutSessionSetDraft]
    var superset: ExerciseSupersetMembershipDraft?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        templateExerciseID: UUID? = nil,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        sortOrder: Int = 0,
        components: [ActiveWorkoutRuntimeExerciseComponent] = [],
        setDrafts: [WorkoutSessionSetDraft] = [],
        superset: ExerciseSupersetMembershipDraft? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.templateExerciseID = templateExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.sortOrder = sortOrder
        self.components = components.sorted { $0.sortOrder < $1.sortOrder }
        self.setDrafts = Self.setDrafts(setDrafts, normalizedTo: self.restSeconds)
        self.superset = superset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(model: ActiveWorkoutDraftExercise) {
        self.init(
            id: model.id,
            templateExerciseID: model.templateExerciseID,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot,
            notes: model.notes,
            targetRepMin: model.targetRepMin,
            targetRepMax: model.targetRepMax,
            restSeconds: model.restSeconds,
            sortOrder: model.sortOrder,
            components: (model.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(ActiveWorkoutRuntimeExerciseComponent.init(model:)),
            setDrafts: (model.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(WorkoutSessionSetDraft.init(model:)),
            superset: model.supersetMembership,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

nonisolated extension ActiveWorkoutRuntimeExercise {
    var supersetGroupID: UUID? {
        get { superset?.groupID }
        set {
            guard let newValue else {
                superset = nil
                return
            }
            let position = superset?.position ?? .first
            let roundRestSeconds = superset?.roundRestSeconds ?? restSeconds
            superset = ExerciseSupersetMembershipDraft(
                groupID: newValue,
                position: position,
                roundRestSeconds: roundRestSeconds
            )
        }
    }

    var supersetPosition: SupersetExercisePosition? {
        get { superset?.position }
        set {
            guard let newValue else {
                superset = nil
                return
            }
            let groupID = superset?.groupID ?? UUID()
            let roundRestSeconds = superset?.roundRestSeconds ?? restSeconds
            superset = ExerciseSupersetMembershipDraft(
                groupID: groupID,
                position: newValue,
                roundRestSeconds: roundRestSeconds
            )
        }
    }

    var supersetPositionRaw: String? {
        superset?.position.rawValue
    }

    mutating func normalizeSetRestToExerciseDefault() {
        setDrafts = Self.setDrafts(setDrafts, normalizedTo: restSeconds)
    }

    private static func setDrafts(
        _ drafts: [WorkoutSessionSetDraft],
        normalizedTo restSeconds: Int
    ) -> [WorkoutSessionSetDraft] {
        let normalizedRest = max(0, min(3600, restSeconds))
        return drafts.map { draft in
            var updated = draft
            updated.restSeconds = normalizedRest
            return updated
        }
    }

    func replacingExercise(
        with catalogItem: ExerciseCatalogItem,
        preferredLoadUnit: TemplateLoadUnit,
        date: Date = .now
    ) -> ActiveWorkoutRuntimeExercise {
        replacingExercise(
            with: ExerciseCatalogSelection(catalogItem: catalogItem),
            preferredLoadUnit: preferredLoadUnit,
            date: date
        )
    }

    func replacingExercise(
        with selection: ExerciseCatalogSelection,
        preferredLoadUnit: TemplateLoadUnit,
        date: Date = .now
    ) -> ActiveWorkoutRuntimeExercise {
        let loadUnit = TemplateLoadUnit.inferredDefault(fromEquipmentSummary: selection.equipmentSummary)
            ?? preferredLoadUnit

        return ActiveWorkoutRuntimeExercise(
            id: id,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: selection.remoteUUID,
            exerciseNameSnapshot: selection.displayName,
            categorySnapshot: selection.categoryName,
            muscleSummarySnapshot: selection.primaryMuscleNames,
            notes: "",
            targetRepMin: nil,
            targetRepMax: nil,
            restSeconds: restSeconds,
            sortOrder: sortOrder,
            components: [
                ActiveWorkoutRuntimeExerciseComponent(
                    catalogExerciseUUID: selection.remoteUUID,
                    exerciseNameSnapshot: selection.displayName,
                    categorySnapshot: selection.categoryName,
                    muscleSummarySnapshot: selection.primaryMuscleNames,
                    createdAt: date,
                    updatedAt: date
                ),
            ],
            setDrafts: setDrafts.isEmpty
                ? Self.defaultSetDrafts(restSeconds: restSeconds, loadUnit: loadUnit)
                : setDrafts,
            superset: superset,
            createdAt: createdAt,
            updatedAt: date
        )
    }

    static func catalogExercise(
        from selection: ExerciseCatalogSelection,
        sortOrder: Int,
        restSeconds: Int = 120,
        preferredLoadUnit: TemplateLoadUnit,
        date: Date = .now
    ) -> ActiveWorkoutRuntimeExercise {
        let loadUnit = TemplateLoadUnit.inferredDefault(fromEquipmentSummary: selection.equipmentSummary)
            ?? preferredLoadUnit
        return ActiveWorkoutRuntimeExercise(
            catalogExerciseUUID: selection.remoteUUID,
            exerciseNameSnapshot: selection.displayName,
            categorySnapshot: selection.categoryName,
            muscleSummarySnapshot: selection.primaryMuscleNames,
            restSeconds: restSeconds,
            sortOrder: sortOrder,
            setDrafts: Self.defaultSetDrafts(restSeconds: restSeconds, loadUnit: loadUnit),
            createdAt: date,
            updatedAt: date
        )
    }

    private static func defaultSetDrafts(
        restSeconds: Int,
        loadUnit: TemplateLoadUnit
    ) -> [WorkoutSessionSetDraft] {
        [0, 1, 2].map { index in
            WorkoutSessionSetDraft(
                isWarmup: index == 0,
                restSeconds: restSeconds,
                targetLoadUnit: loadUnit,
                actualLoadUnit: loadUnit
            )
        }
    }
}

nonisolated struct ActiveWorkoutRuntimeExerciseComponent: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(model: ActiveWorkoutDraftExerciseComponent) {
        self.init(
            id: model.id,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot,
            sortOrder: model.sortOrder,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}

nonisolated extension ExerciseComponentSnapshot {
    init(model: ActiveWorkoutRuntimeExerciseComponent) {
        self.init(
            id: model.id,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot
        )
    }
}

actor ActiveWorkoutSnapshotStore {
    static let shared = ActiveWorkoutSnapshotStore()

    private static let defaultFileName = "active-workout-snapshot.json"
    private static let invalidationFileName = "active-workout-invalidated-before.json"

    private let baseDirectory: URL
    private var cachedSnapshotData: Data?

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = Self.defaultBaseDirectory()
        }
    }

#if DEBUG
    nonisolated static func deleteDefaultSnapshotFileForUITests() {
        let url = defaultBaseDirectory().appendingPathComponent(defaultFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
#endif

    func load() throws -> ActiveWorkoutRuntimeSession? {
        try loadStoredSnapshot()?.session
    }

    func loadDiscardingCorruptSnapshot() throws -> ActiveWorkoutRuntimeSession? {
        do {
            return try load()
        } catch let error as CancellationError {
            throw error
        } catch {
            try delete()
            return nil
        }
    }

    func loadStoredSnapshot() throws -> ActiveWorkoutStoredSnapshot? {
        try Task.checkCancellation()
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedSnapshotData = nil
            return nil
        }
        if try isSnapshotInvalidated(url) {
            cachedSnapshotData = nil
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let data = try Data(contentsOf: url)
        cachedSnapshotData = data
        if let storedSnapshot = try? decoder.decode(ActiveWorkoutStoredSnapshot.self, from: data) {
            var session = storedSnapshot.session
            session.normalizeSetRestToExerciseDefaults()
            return ActiveWorkoutStoredSnapshot(
                session: session,
                restTimer: storedSnapshot.restTimer,
                presentationMode: storedSnapshot.presentationMode,
                scrollTarget: storedSnapshot.scrollTarget,
                expandedExerciseIDs: storedSnapshot.expandedExerciseIDs
            )
        }

        var session = try decoder.decode(ActiveWorkoutRuntimeSession.self, from: data)
        session.normalizeSetRestToExerciseDefaults()
        return ActiveWorkoutStoredSnapshot(session: session, restTimer: nil, presentationMode: nil, scrollTarget: nil)
    }

    func save(
        _ session: ActiveWorkoutRuntimeSession,
        restTimer: RestTimerSnapshot? = nil,
        presentationMode: ActiveWorkoutStoredPresentationMode? = nil,
        scrollTarget: ActiveWorkoutScrollTarget? = nil,
        expandedExerciseIDs: Set<UUID>? = nil,
        preservesExistingRestTimer: Bool = true,
        preservesExistingPresentationMode: Bool = true,
        preservesExistingScrollTarget: Bool = true,
        preservesExistingExpandedExerciseIDs: Bool = true
    ) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        var normalizedSession = session
        normalizedSession.normalizeSetRestToExerciseDefaults()
        try Task.checkCancellation()
        let existingSnapshot = preservesExistingRestTimer
            || preservesExistingPresentationMode
            || preservesExistingScrollTarget
            || preservesExistingExpandedExerciseIDs
            ? (try? loadStoredSnapshot())
            : nil
        let existingRestTimer = preservesExistingRestTimer ? existingSnapshot?.restTimer : nil
        let existingPresentationMode = preservesExistingPresentationMode
            ? existingSnapshot?.presentationMode
            : nil
        let existingScrollTarget = preservesExistingScrollTarget ? existingSnapshot?.scrollTarget : nil
        let existingExpandedExerciseIDs = preservesExistingExpandedExerciseIDs ? existingSnapshot?.expandedExerciseIDs : nil
        let resolvedRestTimer = restTimer ?? existingRestTimer
        let resolvedPresentationMode = presentationMode ?? existingPresentationMode
        let resolvedScrollTarget = scrollTarget ?? existingScrollTarget
        let resolvedExpandedExerciseIDs = expandedExerciseIDs ?? existingExpandedExerciseIDs ?? []
        let storedSnapshot = ActiveWorkoutStoredSnapshot(
            session: normalizedSession,
            restTimer: resolvedRestTimer?.isExpired == true ? nil : resolvedRestTimer,
            presentationMode: resolvedPresentationMode,
            scrollTarget: resolvedScrollTarget,
            expandedExerciseIDs: resolvedExpandedExerciseIDs
        )
        try Task.checkCancellation()
        let data = try encoder.encode(storedSnapshot)
        let url = snapshotURL
        if cachedSnapshotData == data,
           FileManager.default.fileExists(atPath: url.path) {
            return
        }
        if cachedSnapshotData == nil,
           FileManager.default.fileExists(atPath: url.path),
           let existingData = try? Data(contentsOf: url) {
            cachedSnapshotData = existingData
            if existingData == data {
                return
            }
        }
        try Task.checkCancellation()
        try data.write(to: url, options: [.atomic])
        cachedSnapshotData = data
    }

    func delete() throws {
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedSnapshotData = nil
            return
        }
        try FileManager.default.removeItem(at: url)
        cachedSnapshotData = nil
    }

    func invalidateSnapshotsSavedBefore(_ cutoff: Date) throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let existingCutoff = try invalidationCutoff()
        let resolvedCutoff = max(existingCutoff ?? .distantPast, cutoff)
        let markerData = try encoder.encode(resolvedCutoff)
        try markerData.write(to: invalidationURL, options: [.atomic])

        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path),
              try isSnapshotInvalidated(url) else {
            return
        }
        try FileManager.default.removeItem(at: url)
        cachedSnapshotData = nil
    }

    func hasSnapshot() throws -> Bool {
        FileManager.default.fileExists(atPath: snapshotURL.path)
    }

    private var snapshotURL: URL {
        baseDirectory.appendingPathComponent(Self.defaultFileName, isDirectory: false)
    }

    private var invalidationURL: URL {
        baseDirectory.appendingPathComponent(Self.invalidationFileName, isDirectory: false)
    }

    private func invalidationCutoff() throws -> Date? {
        guard FileManager.default.fileExists(atPath: invalidationURL.path) else {
            return nil
        }
        return try decoder.decode(Date.self, from: Data(contentsOf: invalidationURL))
    }

    private func isSnapshotInvalidated(_ url: URL) throws -> Bool {
        guard let cutoff = try invalidationCutoff() else { return false }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        return modificationDate <= cutoff
    }

    nonisolated private static func defaultBaseDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("WGJ", isDirectory: true)
            .appendingPathComponent("ActiveWorkout", isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated final class ActiveWorkoutSessionFactory {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createEmptySession(name: String = "Empty Workout") -> ActiveWorkoutRuntimeSession {
        let now = Date()
        return ActiveWorkoutRuntimeSession(
            name: name,
            startedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func createSessionFromTemplate(templateID: UUID) throws -> ActiveWorkoutRuntimeSession {
        guard let template = try template(id: templateID) else {
            throw WorkoutSessionRepositoryError.templateNotFound
        }

        let now = Date()
        let sessionID = UUID()
        var session = ActiveWorkoutRuntimeSession(
            id: sessionID,
            templateID: template.id,
            name: template.name,
            startedAt: now,
            notes: template.notes,
            createdAt: now,
            updatedAt: now
        )

        session.cardioBlocks = try templateCardioBlocks(templateID: template.id)
            .map { templateCardioBlock in
                ActiveWorkoutRuntimeCardioBlock(
                    phase: templateCardioBlock.phase,
                    catalogExerciseUUID: templateCardioBlock.catalogExerciseUUID,
                    exerciseNameSnapshot: templateCardioBlock.exerciseNameSnapshot,
                    categorySnapshot: templateCardioBlock.categorySnapshot,
                    muscleSummarySnapshot: templateCardioBlock.muscleSummarySnapshot,
                    targetDurationSeconds: templateCardioBlock.targetDurationSeconds,
                    isCompleted: false,
                    createdAt: now,
                    updatedAt: now
                )
            }

        let componentResolver = TemplateExerciseComponentRotationResolver(modelContext: modelContext)
        session.exercises = try templateExercises(templateID: template.id)
            .enumerated()
            .map { index, templateExercise in
                let componentResolution = try componentResolver.resolution(
                    for: template,
                    exercise: templateExercise,
                    before: now,
                    excludingSessionID: sessionID
                )
                let selectedComponent = componentResolution?.selectedComponent
                let components = componentResolution?.availableComponents.enumerated().map { componentIndex, component in
                    ActiveWorkoutRuntimeExerciseComponent(
                        id: component.id,
                        catalogExerciseUUID: component.catalogExerciseUUID,
                        exerciseNameSnapshot: component.exerciseNameSnapshot,
                        categorySnapshot: component.categorySnapshot,
                        muscleSummarySnapshot: component.muscleSummarySnapshot,
                        sortOrder: componentIndex,
                        createdAt: now,
                        updatedAt: now
                    )
                } ?? []

                var setDrafts = try templateExerciseSets(templateExerciseID: templateExercise.id)
                    .map { templateSet in
                        WorkoutSessionSetDraft(
                            isWarmup: templateSet.isWarmup,
                            restSeconds: templateExercise.restSeconds,
                            targetReps: templateSet.targetReps,
                            targetWeight: templateSet.targetWeight,
                            targetLoadUnit: templateSet.loadUnit,
                            actualLoadUnit: templateSet.loadUnit,
                            isLocked: templateSet.isLocked,
                            dropStages: try templateExerciseDropStages(templateExerciseSetID: templateSet.id)
                                .map { templateStage in
                                    WorkoutSessionDropStageDraft(
                                        targetReps: templateStage.targetReps,
                                        targetWeight: templateStage.targetWeight,
                                        targetLoadUnit: templateStage.loadUnit,
                                        actualLoadUnit: templateStage.loadUnit
                                    )
                                }
                        )
                    }
                if setDrafts.isEmpty {
                    setDrafts = Self.defaultSetDrafts(
                        restSeconds: templateExercise.restSeconds,
                        loadUnit: preferredLoadUnit()
                    )
                }

                return ActiveWorkoutRuntimeExercise(
                    templateExerciseID: templateExercise.id,
                    catalogExerciseUUID: selectedComponent?.catalogExerciseUUID ?? templateExercise.catalogExerciseUUID,
                    exerciseNameSnapshot: selectedComponent?.exerciseNameSnapshot ?? templateExercise.exerciseNameSnapshot,
                    categorySnapshot: selectedComponent?.categorySnapshot ?? templateExercise.categorySnapshot,
                    muscleSummarySnapshot: selectedComponent?.muscleSummarySnapshot ?? templateExercise.muscleSummarySnapshot,
                    notes: templateExercise.notes,
                    targetRepMin: templateExercise.targetRepMin,
                    targetRepMax: templateExercise.targetRepMax,
                    restSeconds: templateExercise.restSeconds,
                    sortOrder: index,
                    components: components,
                    setDrafts: setDrafts,
                    superset: templateExercise.supersetMembership,
                    createdAt: now,
                    updatedAt: now
                )
            }

        return session
    }

    func createExercise(from catalogItem: ExerciseCatalogItem, sortOrder: Int, restSeconds: Int = 120) -> ActiveWorkoutRuntimeExercise {
        let now = Date()
        let loadUnit = TemplateLoadUnit.inferredDefault(fromEquipmentSummary: catalogItem.equipmentSummary)
            ?? preferredLoadUnit()
        return ActiveWorkoutRuntimeExercise(
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            restSeconds: restSeconds,
            sortOrder: sortOrder,
            setDrafts: Self.defaultSetDrafts(restSeconds: restSeconds, loadUnit: loadUnit),
            createdAt: now,
            updatedAt: now
        )
    }

    func importLegacyActiveSessionIfNeeded() throws -> ActiveWorkoutRuntimeSession? {
        let legacySessions = try activeDraftSessions()
        guard let legacySession = legacySessions.first else {
            return nil
        }

        let runtime = ActiveWorkoutRuntimeSession(
            id: legacySession.id,
            templateID: legacySession.templateID,
            name: legacySession.name,
            startedAt: legacySession.startedAt,
            notes: legacySession.notes,
            cardioBlocks: (legacySession.cardioBlocks ?? [])
                .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
                .map(ActiveWorkoutRuntimeCardioBlock.init(model:)),
            exercises: (legacySession.exercises ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(ActiveWorkoutRuntimeExercise.init(model:)),
            createdAt: legacySession.createdAt,
            updatedAt: legacySession.updatedAt
        )

        for legacySession in legacySessions {
            modelContext.delete(legacySession)
        }
        try modelContext.save()
        return runtime
    }

    private func activeDraftSessions() throws -> [ActiveWorkoutDraftSession] {
        return try modelContext.fetch(
            FetchDescriptor<ActiveWorkoutDraftSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        )
    }

    private func template(id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { template in
            template.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func templateCardioBlocks(templateID: UUID) throws -> [TemplateCardioBlock] {
        let descriptor = FetchDescriptor<TemplateCardioBlock>(
            predicate: #Predicate { block in
                block.templateID == templateID
            },
            sortBy: [SortDescriptor(\.phaseRaw, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func templateExercises(templateID: UUID) throws -> [TemplateExercise] {
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { exercise in
                exercise.templateID == templateID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func templateExerciseSets(templateExerciseID: UUID) throws -> [TemplateExerciseSet] {
        let descriptor = FetchDescriptor<TemplateExerciseSet>(
            predicate: #Predicate { set in
                set.templateExerciseID == templateExerciseID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func templateExerciseDropStages(templateExerciseSetID: UUID) throws -> [TemplateExerciseDropStage] {
        let descriptor = FetchDescriptor<TemplateExerciseDropStage>(
            predicate: #Predicate { stage in
                stage.templateExerciseSetID == templateExerciseSetID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func preferredLoadUnit() -> TemplateLoadUnit {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        return (try? profileRepository.currentProfile()?.preferredLoadUnit) ?? .kg
    }

    private static func defaultSetDrafts(restSeconds: Int, loadUnit: TemplateLoadUnit) -> [WorkoutSessionSetDraft] {
        [0, 1, 2].map { index in
            WorkoutSessionSetDraft(
                isWarmup: index == 0,
                restSeconds: restSeconds,
                targetLoadUnit: loadUnit,
                actualLoadUnit: loadUnit
            )
        }
    }
}


nonisolated enum ActiveWorkoutRuntimeFirstRenderSnapshotBuilder {
    static func build(
        session: ActiveWorkoutRuntimeSession,
        modelContext: ModelContext
    ) throws -> ActiveWorkoutPreparedFirstRenderSnapshot {
        let exercises = session.exercises.sorted { $0.sortOrder < $1.sortOrder }
        guard !exercises.isEmpty else { return .empty }

        let catalogMatchesByUUID = try ExerciseCatalogRepository(modelContext: modelContext)
            .exerciseSnapshotMap(for: Array(Set(exercises.map(\.catalogExerciseUUID))))
        let previousMaps = try WorkoutSessionRepository(modelContext: modelContext).previousSetMaps(
            forExercises: Array(Set(exercises.map(\.catalogExerciseUUID))),
            before: session.startedAt,
            excludingSessionID: session.id
        )

        var draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
        var restsByExerciseID: [UUID: Int] = [:]
        var notesByExerciseID: [UUID: String] = [:]
        var previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution] = [:]
        var guidanceByExerciseID: [UUID: ActiveWorkoutExerciseGuidancePresentation?] = [:]
        let guidanceService = TrainingGuidanceService()

        draftsByExerciseID.reserveCapacity(exercises.count)
        restsByExerciseID.reserveCapacity(exercises.count)
        notesByExerciseID.reserveCapacity(exercises.count)
        previousResolutionByExerciseID.reserveCapacity(exercises.count)
        guidanceByExerciseID.reserveCapacity(exercises.count)

        for exercise in exercises {
            let drafts = normalizedDraftsForActiveLogging(
                exercise.setDrafts,
                catalogExercise: catalogMatchesByUUID[exercise.catalogExerciseUUID]
            )
            draftsByExerciseID[exercise.id] = drafts
            restsByExerciseID[exercise.id] = exercise.restSeconds
            notesByExerciseID[exercise.id] = exercise.notes
            previousResolutionByExerciseID[exercise.id] = .resolved(
                resolvedPreviousMap(
                    baseMap: previousMaps[exercise.catalogExerciseUUID] ?? [:],
                    maxSetCount: drafts.count
                )
            )
            let catalogExercise = catalogMatchesByUUID[exercise.catalogExerciseUUID]
                ?? TrainingGuidanceCatalogSnapshot(
                    exerciseName: exercise.exerciseNameSnapshot,
                    categoryName: exercise.categorySnapshot,
                    equipmentSummary: "",
                    primaryMuscleNames: exercise.muscleSummarySnapshot
                )
            guidanceByExerciseID[exercise.id] = guidanceService.activeWorkoutGuidance(
                for: catalogExercise,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                setDrafts: drafts
            )
        }

        return ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: draftsByExerciseID,
            restsByExerciseID: restsByExerciseID,
            notesByExerciseID: notesByExerciseID,
            catalogMatchesByUUID: catalogMatchesByUUID,
            previousResolutionByExerciseID: previousResolutionByExerciseID,
            guidanceByExerciseID: guidanceByExerciseID
        )
    }

    private static func normalizedDraftsForActiveLogging(
        _ drafts: [WorkoutSessionSetDraft],
        catalogExercise: TrainingGuidanceCatalogSnapshot?
    ) -> [WorkoutSessionSetDraft] {
        guard TemplateLoadUnit.inferredDefault(
            fromEquipmentSummary: catalogExercise?.equipmentSummary ?? ""
        ) == .bodyweight else {
            return drafts
        }

        var normalized = drafts
        var changed = false
        for index in normalized.indices {
            guard normalized[index].targetWeight == nil, normalized[index].actualWeight == nil else {
                continue
            }

            if normalized[index].targetLoadUnit != .bodyweight {
                normalized[index].targetLoadUnit = .bodyweight
                changed = true
            }

            if normalized[index].actualLoadUnit != .bodyweight {
                normalized[index].actualLoadUnit = .bodyweight
                changed = true
            }
        }

        return changed ? normalized : drafts
    }

    private static func resolvedPreviousMap(
        baseMap: [Int: WorkoutPreviousSetSnapshot],
        maxSetCount: Int
    ) -> [Int: WorkoutPreviousSetSnapshot] {
        guard maxSetCount > 0, !baseMap.isEmpty else { return [:] }

        let fallback = baseMap[(baseMap.keys.max() ?? 0)]
        var resolved: [Int: WorkoutPreviousSetSnapshot] = [:]
        resolved.reserveCapacity(maxSetCount)

        for index in 0..<maxSetCount {
            if let exact = baseMap[index] {
                resolved[index] = exact
            } else if let fallback {
                resolved[index] = fallback
            }
        }

        return resolved
    }
}

@MainActor
@Observable
final class ActiveWorkoutRuntimeController {
    private let snapshotStore: ActiveWorkoutSnapshotStore
    private(set) var session: ActiveWorkoutRuntimeSession?

    init(
        session: ActiveWorkoutRuntimeSession? = nil,
        snapshotStore: ActiveWorkoutSnapshotStore = .shared
    ) {
        self.session = session
        self.snapshotStore = snapshotStore
    }

    func loadSnapshot() async throws -> ActiveWorkoutRuntimeSession? {
        let loaded = try await snapshotStore.load()
        session = loaded
        return loaded
    }

    func replaceSession(_ session: ActiveWorkoutRuntimeSession) {
        self.session = session
    }

    func saveLifecycleSnapshot() async throws {
        guard let session else { return }
        try await snapshotStore.save(session)
    }

    func discard() async throws {
        session = nil
        try await snapshotStore.delete()
    }
}
