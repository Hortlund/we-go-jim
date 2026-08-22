import Foundation
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
        self.cardioBlocks = cardioBlocks.sorted(by: ActiveWorkoutRuntimeCardioBlock.areInIncreasingOrder)
        self.exercises = exercises.sorted { $0.sortOrder < $1.sortOrder }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case templateID
        case name
        case startedAt
        case notes
        case cardioBlocks
        case exercises
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        name = try container.decode(String.self, forKey: .name)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        notes = try container.decode(String.self, forKey: .notes)
        cardioBlocks = try container.decode([ActiveWorkoutRuntimeCardioBlock].self, forKey: .cardioBlocks)
            .sorted(by: ActiveWorkoutRuntimeCardioBlock.areInIncreasingOrder)
        exercises = try container.decode([ActiveWorkoutRuntimeExercise].self, forKey: .exercises)
            .sorted { $0.sortOrder < $1.sortOrder }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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

nonisolated enum ActiveWorkoutSnapshotWriteResult: Equatable, Sendable {
    case written
    case unchanged
    case rejectedStale(currentRevision: UInt64)
}

nonisolated protocol ActiveWorkoutSnapshotStoring: Sendable {
    func loadStoredSnapshot() async throws -> ActiveWorkoutStoredSnapshot?
    func save(_ snapshot: ActiveWorkoutStoredSnapshot) async throws -> ActiveWorkoutSnapshotWriteResult
    func delete() async throws
}

nonisolated struct ActiveWorkoutStoredSnapshot: Equatable, Codable, Sendable {
    var revision: UInt64
    var session: ActiveWorkoutRuntimeSession
    var restTimer: RestTimerSnapshot?
    var presentationMode: ActiveWorkoutStoredPresentationMode?
    var scrollTarget: ActiveWorkoutScrollTarget?
    var expandedExerciseIDs: Set<UUID>
    var previousSetSnapshotsByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]]

    init(
        revision: UInt64 = 0,
        session: ActiveWorkoutRuntimeSession,
        restTimer: RestTimerSnapshot? = nil,
        presentationMode: ActiveWorkoutStoredPresentationMode? = nil,
        scrollTarget: ActiveWorkoutScrollTarget? = nil,
        expandedExerciseIDs: Set<UUID> = [],
        previousSetSnapshotsByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    ) {
        self.revision = revision
        self.session = session
        self.restTimer = restTimer
        self.presentationMode = presentationMode
        self.scrollTarget = scrollTarget
        self.expandedExerciseIDs = expandedExerciseIDs
        self.previousSetSnapshotsByExerciseID = previousSetSnapshotsByExerciseID
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case session
        case restTimer
        case presentationMode
        case scrollTarget
        case expandedExerciseIDs
        case previousSetSnapshotsByExerciseID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        session = try container.decode(ActiveWorkoutRuntimeSession.self, forKey: .session)
        restTimer = try container.decodeIfPresent(RestTimerSnapshot.self, forKey: .restTimer)
        presentationMode = try container.decodeIfPresent(ActiveWorkoutStoredPresentationMode.self, forKey: .presentationMode)
        scrollTarget = try container.decodeIfPresent(ActiveWorkoutScrollTarget.self, forKey: .scrollTarget)
        expandedExerciseIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .expandedExerciseIDs) ?? []
        previousSetSnapshotsByExerciseID = try container.decodeIfPresent(
            [UUID: [Int: WorkoutPreviousSetSnapshot]].self,
            forKey: .previousSetSnapshotsByExerciseID
        ) ?? [:]
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
        pendingCardioCompletionsByID: [UUID: Bool],
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
            if let completion = pendingCardioCompletionsByID[cardioBlock.id] {
                updated.isCompleted = completion
                updated.updatedAt = date
            }
            return updated
        }
        .sorted(by: ActiveWorkoutRuntimeCardioBlock.areInIncreasingOrder)
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
    var sourceTemplateCardioID: UUID?
    var phase: WorkoutCardioPhase
    var roleRaw: String?
    var sortOrder: Int
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var trackingProfileRaw: String?
    var goalKindRaw: String?
    var targetDurationSeconds: Int
    var targetDistanceMeters: Double?
    var actualDurationSeconds: Int?
    var actualDistanceMeters: Double?
    var preferredDistanceUnitRaw: String?
    var inclinePercent: Double?
    var resistanceLevel: Double?
    var cardioNotes: String
    var timerStateRaw: String?
    var timerSegmentStartedAt: Date?
    var timerAccumulatedSeconds: Int
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    var role: WorkoutCardioRole {
        get {
            roleRaw.flatMap(WorkoutCardioRole.init(rawValue:))
                ?? (phase == .preWorkout ? .warmUp : .finisher)
        }
        set { roleRaw = newValue.rawValue }
    }

    var trackingProfile: WorkoutCardioTrackingProfile? {
        get { trackingProfileRaw.flatMap(WorkoutCardioTrackingProfile.init(rawValue:)) }
        set { trackingProfileRaw = newValue?.rawValue }
    }

    var goalKind: WorkoutCardioGoalKind {
        get {
            goalKindRaw.flatMap(WorkoutCardioGoalKind.init(rawValue:))
                ?? (targetDurationSeconds > 0 ? .time : .open)
        }
        set { goalKindRaw = newValue.rawValue }
    }

    var preferredDistanceUnit: WorkoutDistanceUnit? {
        get { preferredDistanceUnitRaw.flatMap(WorkoutDistanceUnit.init(rawValue:)) }
        set { preferredDistanceUnitRaw = newValue?.rawValue }
    }

    var timerState: WorkoutCardioTimerState {
        get { timerStateRaw.flatMap(WorkoutCardioTimerState.init(rawValue:)) ?? .idle }
        set { timerStateRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sourceTemplateCardioID: UUID? = nil,
        phase: WorkoutCardioPhase,
        role: WorkoutCardioRole? = nil,
        sortOrder: Int = 0,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        trackingProfile: WorkoutCardioTrackingProfile? = nil,
        goalKind: WorkoutCardioGoalKind? = nil,
        targetDurationSeconds: Int,
        targetDistanceMeters: Double? = nil,
        actualDurationSeconds: Int? = nil,
        actualDistanceMeters: Double? = nil,
        preferredDistanceUnit: WorkoutDistanceUnit? = nil,
        inclinePercent: Double? = nil,
        resistanceLevel: Double? = nil,
        cardioNotes: String = "",
        timerState: WorkoutCardioTimerState = .idle,
        timerSegmentStartedAt: Date? = nil,
        timerAccumulatedSeconds: Int = 0,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sourceTemplateCardioID = sourceTemplateCardioID
        self.phase = phase
        self.roleRaw = role?.rawValue
        self.sortOrder = sortOrder
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.trackingProfileRaw = trackingProfile?.rawValue
        self.goalKindRaw = goalKind?.rawValue
        self.targetDurationSeconds = min(24 * 60 * 60, max(0, targetDurationSeconds))
        self.targetDistanceMeters = targetDistanceMeters
        self.actualDurationSeconds = actualDurationSeconds
        self.actualDistanceMeters = actualDistanceMeters
        self.preferredDistanceUnitRaw = preferredDistanceUnit?.rawValue
        self.inclinePercent = inclinePercent
        self.resistanceLevel = resistanceLevel
        self.cardioNotes = cardioNotes
        self.timerStateRaw = timerState.rawValue
        self.timerSegmentStartedAt = timerSegmentStartedAt
        self.timerAccumulatedSeconds = max(0, timerAccumulatedSeconds)
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(model: ActiveWorkoutDraftCardioBlock) {
        self.init(
            id: model.id,
            sourceTemplateCardioID: model.sourceTemplateCardioID,
            phase: model.phase,
            sortOrder: model.sortOrder,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot,
            targetDurationSeconds: model.targetDurationSeconds,
            targetDistanceMeters: model.targetDistanceMeters,
            actualDurationSeconds: model.actualDurationSeconds,
            actualDistanceMeters: model.actualDistanceMeters,
            inclinePercent: model.inclinePercent,
            resistanceLevel: model.resistanceLevel,
            cardioNotes: model.cardioNotes,
            timerState: model.timerState,
            timerSegmentStartedAt: model.timerSegmentStartedAt,
            timerAccumulatedSeconds: model.timerAccumulatedSeconds,
            isCompleted: model.isCompleted,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
        roleRaw = model.roleRaw
        trackingProfileRaw = model.trackingProfileRaw
        goalKindRaw = model.goalKindRaw
        preferredDistanceUnitRaw = model.preferredDistanceUnitRaw
        timerStateRaw = model.timerStateRaw
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceTemplateCardioID
        case phase
        case roleRaw
        case sortOrder
        case catalogExerciseUUID
        case exerciseNameSnapshot
        case categorySnapshot
        case muscleSummarySnapshot
        case trackingProfileRaw
        case goalKindRaw
        case targetDurationSeconds
        case targetDistanceMeters
        case actualDurationSeconds
        case actualDistanceMeters
        case preferredDistanceUnitRaw
        case inclinePercent
        case resistanceLevel
        case cardioNotes
        case timerStateRaw
        case timerSegmentStartedAt
        case timerAccumulatedSeconds
        case isCompleted
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceTemplateCardioID = try container.decodeIfPresent(UUID.self, forKey: .sourceTemplateCardioID)
        phase = try container.decode(WorkoutCardioPhase.self, forKey: .phase)
        roleRaw = try container.decodeIfPresent(String.self, forKey: .roleRaw)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        catalogExerciseUUID = try container.decode(String.self, forKey: .catalogExerciseUUID)
        exerciseNameSnapshot = try container.decode(String.self, forKey: .exerciseNameSnapshot)
        categorySnapshot = try container.decode(String.self, forKey: .categorySnapshot)
        muscleSummarySnapshot = try container.decode(String.self, forKey: .muscleSummarySnapshot)
        trackingProfileRaw = try container.decodeIfPresent(String.self, forKey: .trackingProfileRaw)
        goalKindRaw = try container.decodeIfPresent(String.self, forKey: .goalKindRaw)
        targetDurationSeconds = min(
            24 * 60 * 60,
            max(0, try container.decode(Int.self, forKey: .targetDurationSeconds))
        )
        targetDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .targetDistanceMeters)
        actualDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .actualDurationSeconds)
        actualDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .actualDistanceMeters)
        preferredDistanceUnitRaw = try container.decodeIfPresent(String.self, forKey: .preferredDistanceUnitRaw)
        inclinePercent = try container.decodeIfPresent(Double.self, forKey: .inclinePercent)
        resistanceLevel = try container.decodeIfPresent(Double.self, forKey: .resistanceLevel)
        cardioNotes = try container.decodeIfPresent(String.self, forKey: .cardioNotes) ?? ""
        timerStateRaw = try container.decodeIfPresent(String.self, forKey: .timerStateRaw)
        timerSegmentStartedAt = try container.decodeIfPresent(Date.self, forKey: .timerSegmentStartedAt)
        timerAccumulatedSeconds = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .timerAccumulatedSeconds) ?? 0
        )
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static func areInIncreasingOrder(
        _ lhs: ActiveWorkoutRuntimeCardioBlock,
        _ rhs: ActiveWorkoutRuntimeCardioBlock
    ) -> Bool {
        if lhs.role.sortOrder != rhs.role.sortOrder {
            return lhs.role.sortOrder < rhs.role.sortOrder
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
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

actor ActiveWorkoutSnapshotStore: ActiveWorkoutSnapshotStoring {
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
                revision: storedSnapshot.revision,
                session: session,
                restTimer: storedSnapshot.restTimer,
                presentationMode: storedSnapshot.presentationMode,
                scrollTarget: storedSnapshot.scrollTarget,
                expandedExerciseIDs: storedSnapshot.expandedExerciseIDs,
                previousSetSnapshotsByExerciseID: storedSnapshot.previousSetSnapshotsByExerciseID
            )
        }

        var session = try decoder.decode(ActiveWorkoutRuntimeSession.self, from: data)
        session.normalizeSetRestToExerciseDefaults()
        return ActiveWorkoutStoredSnapshot(session: session, restTimer: nil, presentationMode: nil, scrollTarget: nil)
    }

    func save(
        _ snapshot: ActiveWorkoutStoredSnapshot
    ) throws -> ActiveWorkoutSnapshotWriteResult {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        var normalizedSession = snapshot.session
        normalizedSession.normalizeSetRestToExerciseDefaults()
        let normalizedSnapshot = ActiveWorkoutStoredSnapshot(
            revision: snapshot.revision,
            session: normalizedSession,
            restTimer: snapshot.restTimer?.isExpired == true ? nil : snapshot.restTimer,
            presentationMode: snapshot.presentationMode,
            scrollTarget: snapshot.scrollTarget,
            expandedExerciseIDs: snapshot.expandedExerciseIDs,
            previousSetSnapshotsByExerciseID: snapshot.previousSetSnapshotsByExerciseID
        )
        let currentSnapshot = try loadStoredSnapshot()
        if let currentRevision = currentSnapshot?.revision,
           normalizedSnapshot.revision < currentRevision {
            return .rejectedStale(currentRevision: currentRevision)
        }

        try Task.checkCancellation()
        let data = try encoder.encode(normalizedSnapshot)
        let url = snapshotURL
        if cachedSnapshotData == data,
           FileManager.default.fileExists(atPath: url.path) {
            return .unchanged
        }
        if cachedSnapshotData == nil,
           FileManager.default.fileExists(atPath: url.path) {
            let existingData = try Data(contentsOf: url)
            cachedSnapshotData = existingData
            if existingData == data {
                return .unchanged
            }
        }

        try Task.checkCancellation()
        try data.write(to: url, options: [.atomic])
        cachedSnapshotData = data
        return .written
    }

    @discardableResult
    func save(
        _ session: ActiveWorkoutRuntimeSession,
        revision: UInt64? = nil,
        restTimer: RestTimerSnapshot? = nil,
        presentationMode: ActiveWorkoutStoredPresentationMode? = nil,
        scrollTarget: ActiveWorkoutScrollTarget? = nil,
        expandedExerciseIDs: Set<UUID>? = nil,
        previousSetSnapshotsByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]]? = nil,
        preservesExistingRestTimer: Bool = true,
        preservesExistingPresentationMode: Bool = true,
        preservesExistingScrollTarget: Bool = true,
        preservesExistingExpandedExerciseIDs: Bool = true,
        preservesExistingPreviousSetSnapshots: Bool = true
    ) throws -> ActiveWorkoutSnapshotWriteResult {
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
            || preservesExistingPreviousSetSnapshots
            ? (try? loadStoredSnapshot())
            : nil
        let existingRestTimer = preservesExistingRestTimer ? existingSnapshot?.restTimer : nil
        let existingPresentationMode = preservesExistingPresentationMode
            ? existingSnapshot?.presentationMode
            : nil
        let existingScrollTarget = preservesExistingScrollTarget ? existingSnapshot?.scrollTarget : nil
        let existingExpandedExerciseIDs = preservesExistingExpandedExerciseIDs ? existingSnapshot?.expandedExerciseIDs : nil
        let existingPreviousSetSnapshots = preservesExistingPreviousSetSnapshots
            ? existingSnapshot?.previousSetSnapshotsByExerciseID
            : nil
        let resolvedRestTimer = restTimer ?? existingRestTimer
        let resolvedPresentationMode = presentationMode ?? existingPresentationMode
        let resolvedScrollTarget = scrollTarget ?? existingScrollTarget
        let resolvedExpandedExerciseIDs = expandedExerciseIDs ?? existingExpandedExerciseIDs ?? []
        let resolvedPreviousSetSnapshots = previousSetSnapshotsByExerciseID ?? existingPreviousSetSnapshots ?? [:]
        let storedSnapshot = ActiveWorkoutStoredSnapshot(
            revision: revision ?? existingSnapshot?.revision ?? 0,
            session: normalizedSession,
            restTimer: resolvedRestTimer?.isExpired == true ? nil : resolvedRestTimer,
            presentationMode: resolvedPresentationMode,
            scrollTarget: resolvedScrollTarget,
            expandedExerciseIDs: resolvedExpandedExerciseIDs,
            previousSetSnapshotsByExerciseID: resolvedPreviousSetSnapshots
        )
        return try save(storedSnapshot)
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
                    sourceTemplateCardioID: templateCardioBlock.id,
                    phase: templateCardioBlock.phase,
                    role: templateCardioBlock.role,
                    sortOrder: templateCardioBlock.sortOrder,
                    catalogExerciseUUID: templateCardioBlock.catalogExerciseUUID,
                    exerciseNameSnapshot: templateCardioBlock.exerciseNameSnapshot,
                    categorySnapshot: templateCardioBlock.categorySnapshot,
                    muscleSummarySnapshot: templateCardioBlock.muscleSummarySnapshot,
                    trackingProfile: templateCardioBlock.trackingProfile,
                    goalKind: templateCardioBlock.goalKind,
                    targetDurationSeconds: templateCardioBlock.targetDurationSeconds,
                    targetDistanceMeters: templateCardioBlock.targetDistanceMeters,
                    preferredDistanceUnit: templateCardioBlock.preferredDistanceUnit,
                    isCompleted: false,
                    createdAt: now,
                    updatedAt: now
                )
            }
            .sorted(by: ActiveWorkoutRuntimeCardioBlock.areInIncreasingOrder)

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
            .sorted { lhs, rhs in
                if lhs.role.sortOrder != rhs.role.sortOrder {
                    return lhs.role.sortOrder < rhs.role.sortOrder
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
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

        draftsByExerciseID.reserveCapacity(exercises.count)
        restsByExerciseID.reserveCapacity(exercises.count)
        notesByExerciseID.reserveCapacity(exercises.count)
        previousResolutionByExerciseID.reserveCapacity(exercises.count)

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
        }

        return ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: draftsByExerciseID,
            restsByExerciseID: restsByExerciseID,
            notesByExerciseID: notesByExerciseID,
            catalogMatchesByUUID: catalogMatchesByUUID,
            previousResolutionByExerciseID: previousResolutionByExerciseID
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
