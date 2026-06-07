import Foundation
import SwiftData

nonisolated struct ActiveWorkoutExercisePersistenceSnapshot: Equatable, Sendable {
    var setDrafts: [WorkoutSessionSetDraft]
    var restSeconds: Int
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?

    init(
        setDrafts: [WorkoutSessionSetDraft],
        restSeconds: Int,
        notes: String,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil
    ) {
        self.setDrafts = setDrafts
        self.restSeconds = max(0, min(3600, restSeconds))
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
    }
}

nonisolated struct ActiveWorkoutExercisePersistenceChangeSet: Equatable, Sendable {
    let persistDrafts: Bool
    let persistRest: Bool
    let persistNotes: Bool
    let persistRepRange: Bool

    init(
        current: ActiveWorkoutExercisePersistenceSnapshot,
        persisted: ActiveWorkoutExercisePersistenceSnapshot
    ) {
        persistDrafts = current.setDrafts != persisted.setDrafts
        persistRest = current.restSeconds != persisted.restSeconds
        persistNotes = current.notes != persisted.notes
        persistRepRange = current.targetRepMin != persisted.targetRepMin
            || current.targetRepMax != persisted.targetRepMax
    }

    var hasChanges: Bool {
        persistDrafts || persistRest || persistNotes || persistRepRange
    }
}

nonisolated struct ActiveWorkoutCheckpointPersistenceResult: Equatable, Sendable {
    let didPersistSessionMeta: Bool
    let handledExerciseIDs: Set<UUID>
    let persistedExerciseIDs: Set<UUID>
}

nonisolated final class ActiveWorkoutDraftRepository {
    private let modelContext: ModelContext

    private var completedSessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var componentRotationResolver: TemplateExerciseComponentRotationResolver {
        TemplateExerciseComponentRotationResolver(modelContext: modelContext)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func preferredLoadUnit() -> TemplateLoadUnit {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        return (try? profileRepository.currentProfile()?.preferredLoadUnit) ?? .kg
    }

    func createEmptySession(name: String = "Empty Workout") throws -> ActiveWorkoutDraftSession {
        let cleanedName = ReviewModerationService.sanitizedForSharing(name, kind: .workoutName)
        let created = ActiveWorkoutDraftSession(name: cleanedName)
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    func createSessionFromTemplate(templateID: UUID) throws -> ActiveWorkoutDraftSession {
        guard let template = try template(id: templateID) else {
            throw WorkoutSessionRepositoryError.templateNotFound
        }

        let session = ActiveWorkoutDraftSession(
            templateID: template.id,
            name: ReviewModerationService.sanitizedForSharing(template.name, kind: .workoutName),
            notes: template.notes
        )
        modelContext.insert(session)

        let orderedCardioBlocks = orderedTemplateCardioBlocks(template)
        var createdCardioBlocks: [ActiveWorkoutDraftCardioBlock] = []
        for templateCardioBlock in orderedCardioBlocks {
            let cardioBlock = ActiveWorkoutDraftCardioBlock(
                sessionID: session.id,
                phase: templateCardioBlock.phase,
                catalogExerciseUUID: templateCardioBlock.catalogExerciseUUID,
                exerciseNameSnapshot: templateCardioBlock.exerciseNameSnapshot,
                categorySnapshot: templateCardioBlock.categorySnapshot,
                muscleSummarySnapshot: templateCardioBlock.muscleSummarySnapshot,
                targetDurationSeconds: templateCardioBlock.targetDurationSeconds,
                isCompleted: false,
                session: session
            )
            modelContext.insert(cardioBlock)
            createdCardioBlocks.append(cardioBlock)
        }
        session.cardioBlocks = createdCardioBlocks

        let orderedExercises = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var createdExercises: [ActiveWorkoutDraftExercise] = []
        var supersetMembershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft] = [:]
        for (exerciseIndex, templateExercise) in orderedExercises.enumerated() {
            let componentResolution = try componentRotationResolver.resolution(
                for: template,
                exercise: templateExercise,
                before: session.startedAt,
                excludingSessionID: session.id
            )
            let selectedComponent = componentResolution?.selectedComponent
            let exercise = ActiveWorkoutDraftExercise(
                sessionID: session.id,
                templateExerciseID: templateExercise.id,
                catalogExerciseUUID: selectedComponent?.catalogExerciseUUID ?? templateExercise.catalogExerciseUUID,
                exerciseNameSnapshot: selectedComponent?.exerciseNameSnapshot ?? templateExercise.exerciseNameSnapshot,
                categorySnapshot: selectedComponent?.categorySnapshot ?? templateExercise.categorySnapshot,
                muscleSummarySnapshot: selectedComponent?.muscleSummarySnapshot ?? templateExercise.muscleSummarySnapshot,
                notes: templateExercise.notes,
                targetRepMin: templateExercise.targetRepMin,
                targetRepMax: templateExercise.targetRepMax,
                restSeconds: templateExercise.restSeconds,
                sortOrder: exerciseIndex,
                session: session
            )
            modelContext.insert(exercise)

            let createdComponents = componentResolution?.availableComponents.enumerated().map { index, component in
                ActiveWorkoutDraftExerciseComponent(
                    sessionExerciseID: exercise.id,
                    catalogExerciseUUID: component.catalogExerciseUUID,
                    exerciseNameSnapshot: component.exerciseNameSnapshot,
                    categorySnapshot: component.categorySnapshot,
                    muscleSummarySnapshot: component.muscleSummarySnapshot,
                    sortOrder: index,
                    sessionExercise: exercise
                )
            } ?? []
            for component in createdComponents {
                modelContext.insert(component)
            }
            exercise.components = createdComponents

            let orderedSets = (templateExercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            var createdSets: [ActiveWorkoutDraftSet] = []
            for (setIndex, templateSet) in orderedSets.enumerated() {
                let set = ActiveWorkoutDraftSet(
                    sessionExerciseID: exercise.id,
                    sortOrder: setIndex,
                    isWarmup: templateSet.isWarmup,
                    restSeconds: templateSet.restSeconds,
                    targetReps: templateSet.targetReps,
                    targetWeight: templateSet.targetWeight,
                    targetLoadUnit: templateSet.loadUnit,
                    actualReps: nil,
                    actualWeight: nil,
                    actualLoadUnit: templateSet.loadUnit,
                    isCompleted: false,
                    isLocked: templateSet.isLocked,
                    sessionExercise: exercise
                )
                modelContext.insert(set)
                let createdDropStages = (templateSet.dropStages ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .enumerated()
                    .map { stageIndex, templateStage in
                        ActiveWorkoutDraftDropStage(
                            sessionSetID: set.id,
                            sortOrder: stageIndex,
                            targetReps: templateStage.targetReps,
                            targetWeight: templateStage.targetWeight,
                            targetLoadUnit: templateStage.loadUnit,
                            actualReps: nil,
                            actualWeight: nil,
                            actualLoadUnit: templateStage.loadUnit,
                            isCompleted: false,
                            sessionSet: set
                        )
                    }
                for dropStage in createdDropStages {
                    modelContext.insert(dropStage)
                }
                set.dropStages = createdDropStages
                createdSets.append(set)
            }

            if createdSets.isEmpty {
                createdSets = defaultSessionSets(
                    sessionExerciseID: exercise.id,
                    restSeconds: exercise.restSeconds,
                    loadUnit: preferredLoadUnit(),
                    sessionExercise: exercise
                )
            }

            exercise.sets = createdSets
            createdExercises.append(exercise)
            if let membership = templateExercise.supersetMembership {
                supersetMembershipsByExerciseID[exercise.id] = membership
            }
        }

        session.exercises = createdExercises
        syncDraftSupersetGroups(
            for: session,
            exercises: createdExercises,
            membershipsByExerciseID: supersetMembershipsByExerciseID
        )

        try modelContext.save()
        return session
    }

    func session(id: UUID) throws -> ActiveWorkoutDraftSession? {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftSession>(predicate: #Predicate { session in
            session.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    func activeSession() throws -> ActiveWorkoutDraftSession? {
        let localDrafts = try activeDraftSessions()
        if let activeDraft = localDrafts.first {
            try cleanLegacyActiveSessionIfNeeded()
            return activeDraft
        }

        guard let legacySession = try completedSessionRepository.activeSession() else {
            return nil
        }

        return try migrateLegacySession(legacySession)
    }

    func sessionExercises(sessionID: UUID) throws -> [ActiveWorkoutDraftExercise] {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftExercise>(
            predicate: #Predicate { exercise in
                exercise.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func sessionExercises(
        sessionID: UUID,
        exerciseIDs: Set<UUID>
    ) throws -> [ActiveWorkoutDraftExercise] {
        guard !exerciseIDs.isEmpty else { return [] }
        var exercises: [ActiveWorkoutDraftExercise] = []
        exercises.reserveCapacity(exerciseIDs.count)
        for exerciseID in exerciseIDs {
            guard let exercise = try sessionExercise(id: exerciseID),
                  exercise.sessionID == sessionID else {
                continue
            }
            exercises.append(exercise)
        }
        return exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    func cardioBlocks(sessionID: UUID) throws -> [ActiveWorkoutDraftCardioBlock] {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftCardioBlock>(
            predicate: #Predicate { cardioBlock in
                cardioBlock.sessionID == sessionID
            }
        )
        return try modelContext.fetch(descriptor)
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    func cardioBlock(sessionID: UUID, phase: WorkoutCardioPhase) throws -> ActiveWorkoutDraftCardioBlock? {
        let phaseRaw = phase.rawValue
        let descriptor = FetchDescriptor<ActiveWorkoutDraftCardioBlock>(
            predicate: #Predicate { cardioBlock in
                cardioBlock.sessionID == sessionID && cardioBlock.phaseRaw == phaseRaw
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func setDrafts(sessionExerciseID: UUID) throws -> [WorkoutSessionSetDraft] {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        return orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
    }

    func components(sessionExerciseID: UUID) throws -> [ActiveWorkoutDraftExerciseComponent] {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        return orderedComponents(for: exercise)
    }

    func updateSessionName(sessionID: UUID, name: String) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let cleaned = try ReviewModerationService.validateUserInput(name, kind: .workoutName)
        session.name = cleaned
        session.updatedAt = .now
        try modelContext.save()
    }

    func updateSessionNotes(sessionID: UUID, notes: String) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        session.notes = notes
        session.updatedAt = .now
        try modelContext.save()
    }

    func overrideExerciseComponent(sessionExerciseID: UUID, componentID: UUID) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        guard let component = orderedComponents(for: exercise).first(where: { $0.id == componentID }) else {
            return
        }

        guard exercise.catalogExerciseUUID != component.catalogExerciseUUID
            || exercise.exerciseNameSnapshot != component.exerciseNameSnapshot
            || exercise.categorySnapshot != component.categorySnapshot
            || exercise.muscleSummarySnapshot != component.muscleSummarySnapshot else {
            return
        }

        exercise.catalogExerciseUUID = component.catalogExerciseUUID
        exercise.exerciseNameSnapshot = component.exerciseNameSnapshot
        exercise.categorySnapshot = component.categorySnapshot
        exercise.muscleSummarySnapshot = component.muscleSummarySnapshot
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func addExercise(sessionID: UUID, catalogItem: ExerciseCatalogItem, restSeconds: Int = 120) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let existing = try sessionExercises(sessionID: sessionID)
        if existing.contains(where: { $0.catalogExerciseUUID == catalogItem.remoteUUID }) {
            return
        }

        let nextIndex = (existing.map(\.sortOrder).max() ?? -1) + 1
        let created = ActiveWorkoutDraftExercise(
            sessionID: sessionID,
            templateExerciseID: nil,
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            restSeconds: sanitizedRest(restSeconds),
            sortOrder: nextIndex,
            session: session
        )
        modelContext.insert(created)

        let sets = defaultSessionSets(
            sessionExerciseID: created.id,
            restSeconds: created.restSeconds,
            loadUnit: TemplateLoadUnit.inferredDefault(fromEquipmentSummary: catalogItem.equipmentSummary)
                ?? preferredLoadUnit(),
            sessionExercise: created
        )
        created.sets = sets

        session.updatedAt = .now
        try modelContext.save()
    }

    func moveExercise(sessionID: UUID, fromOffsets: IndexSet, toOffset: Int) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        var ordered = try sessionExercises(sessionID: sessionID)
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

        session.exercises = ordered
        syncDraftSupersetGroups(
            for: session,
            exercises: ordered,
            membershipsByExerciseID: Dictionary(
                ordered.compactMap { exercise in
                    exercise.supersetMembership.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        session.updatedAt = .now
        try modelContext.save()
    }

    func removeExercise(sessionID: UUID, sessionExerciseID: UUID) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        modelContext.delete(exercise)

        let remaining = try sessionExercises(sessionID: sessionID)
        for (index, row) in remaining.enumerated() {
            row.sortOrder = index
            row.updatedAt = .now
        }

        session.exercises = remaining
        syncDraftSupersetGroups(
            for: session,
            exercises: remaining,
            membershipsByExerciseID: Dictionary(
                remaining.compactMap { exercise in
                    exercise.supersetMembership.map { (exercise.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        session.updatedAt = .now
        try modelContext.save()
    }

    func upsertCardioBlock(sessionID: UUID, draft: WorkoutCardioBlockDraft) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let cardioBlock = try cardioBlock(sessionID: sessionID, phase: draft.phase)
            ?? ActiveWorkoutDraftCardioBlock(
                id: draft.id,
                sessionID: sessionID,
                phase: draft.phase,
                catalogExerciseUUID: draft.catalogExerciseUUID,
                exerciseNameSnapshot: draft.exerciseNameSnapshot,
                categorySnapshot: draft.categorySnapshot,
                muscleSummarySnapshot: draft.muscleSummarySnapshot,
                targetDurationSeconds: draft.targetDurationSeconds,
                isCompleted: draft.isCompleted,
                session: session
            )

        if cardioBlock.modelContext == nil {
            modelContext.insert(cardioBlock)
        }

        cardioBlock.sessionID = sessionID
        cardioBlock.session = session
        cardioBlock.phase = draft.phase
        cardioBlock.catalogExerciseUUID = draft.catalogExerciseUUID
        cardioBlock.exerciseNameSnapshot = draft.exerciseNameSnapshot
        cardioBlock.categorySnapshot = draft.categorySnapshot
        cardioBlock.muscleSummarySnapshot = draft.muscleSummarySnapshot
        cardioBlock.targetDurationSeconds = sanitizedCardioDuration(draft.targetDurationSeconds)
        cardioBlock.isCompleted = draft.isCompleted
        cardioBlock.updatedAt = .now

        session.cardioBlocks = orderedCardioBlocks(session, adding: cardioBlock)
        session.updatedAt = .now
        try modelContext.save()
    }

    func setCardioCompletion(sessionID: UUID, phase: WorkoutCardioPhase, isCompleted: Bool) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        guard let cardioBlock = try cardioBlock(sessionID: sessionID, phase: phase) else {
            return
        }

        guard cardioBlock.isCompleted != isCompleted else {
            return
        }

        cardioBlock.isCompleted = isCompleted
        cardioBlock.updatedAt = .now
        session.updatedAt = .now
        try modelContext.save()
    }

    func removeCardioBlock(sessionID: UUID, phase: WorkoutCardioPhase) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        guard let cardioBlock = try cardioBlock(sessionID: sessionID, phase: phase) else {
            return
        }

        modelContext.delete(cardioBlock)
        session.cardioBlocks = orderedCardioBlocks(session)
        session.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRest(sessionExerciseID: UUID, restSeconds: Int) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let now = Date()
        guard applyExerciseRest(restSeconds, to: exercise, now: now) else {
            return
        }
        try modelContext.save()
    }

    func updateExerciseRepRange(sessionExerciseID: UUID, minReps: Int?, maxReps: Int?) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let now = Date()
        guard applyExerciseRepRange(minReps: minReps, maxReps: maxReps, to: exercise, now: now) else {
            return
        }
        try modelContext.save()
    }

    func updateExerciseNotes(sessionExerciseID: UUID, notes: String) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let now = Date()
        guard applyExerciseNotes(notes, to: exercise, now: now) else {
            return
        }
        try modelContext.save()
    }

    func saveSetDrafts(sessionExerciseID: UUID, drafts: [WorkoutSessionSetDraft]) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let now = Date()
        let changes = applySetDrafts(drafts, to: exercise, now: now)
        guard changes.didMutateExerciseStructure || changes.didMutateAnySet else {
            return
        }
        try modelContext.save()
    }

    func persistExerciseSnapshot(
        sessionExerciseID: UUID,
        snapshot: ActiveWorkoutExercisePersistenceSnapshot,
        persistDrafts: Bool = true,
        persistRepRange: Bool = true,
        persistRest: Bool = true,
        persistNotes: Bool = true
    ) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let now = Date()
        var shouldSave = false

        if persistDrafts {
            let changes = applySetDrafts(snapshot.setDrafts, to: exercise, now: now)
            shouldSave = shouldSave || changes.didMutateExerciseStructure || changes.didMutateAnySet
        }

        if persistRepRange {
            shouldSave = applyExerciseRepRange(
                minReps: snapshot.targetRepMin,
                maxReps: snapshot.targetRepMax,
                to: exercise,
                now: now
            ) || shouldSave
        }

        if persistRest {
            shouldSave = applyExerciseRest(snapshot.restSeconds, to: exercise, now: now) || shouldSave
        }

        if persistNotes {
            shouldSave = applyExerciseNotes(snapshot.notes, to: exercise, now: now) || shouldSave
        }

        guard shouldSave else { return }
        try modelContext.save()
    }

    func persistCheckpoint(
        sessionID: UUID,
        sessionName: String,
        sessionNotes: String,
        dirtyExerciseIDs: Set<UUID>,
        snapshotsByExerciseID: [UUID: ActiveWorkoutExercisePersistenceSnapshot],
        persistedSnapshotsByExerciseID: [UUID: ActiveWorkoutExercisePersistenceSnapshot],
        cardioCompletionsByPhase: [WorkoutCardioPhase: Bool] = [:]
    ) throws -> ActiveWorkoutCheckpointPersistenceResult {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let now = Date()
        var shouldSave = false
        var didPersistSessionMeta = false
        var handledExerciseIDs: Set<UUID> = []
        var persistedExerciseIDs: Set<UUID> = []

        if try applySessionMeta(
            name: sessionName,
            notes: sessionNotes,
            to: session,
            now: now
        ) {
            shouldSave = true
            didPersistSessionMeta = true
        }

        let exerciseByID: [UUID: ActiveWorkoutDraftExercise]
        if dirtyExerciseIDs.isEmpty {
            exerciseByID = [:]
        } else {
            let requestedExerciseIDs = Array(dirtyExerciseIDs)
            let descriptor = FetchDescriptor<ActiveWorkoutDraftExercise>(
                predicate: #Predicate { exercise in
                    exercise.sessionID == sessionID && requestedExerciseIDs.contains(exercise.id)
                }
            )
            exerciseByID = Dictionary(
                try modelContext.fetch(descriptor).map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
        }

        for exerciseID in dirtyExerciseIDs {
            handledExerciseIDs.insert(exerciseID)

            guard let exercise = exerciseByID[exerciseID],
                  let snapshot = snapshotsByExerciseID[exerciseID]
            else {
                continue
            }

            let persistedSnapshot = persistedSnapshotsByExerciseID[exerciseID] ?? snapshot
            let changes = ActiveWorkoutExercisePersistenceChangeSet(
                current: snapshot,
                persisted: persistedSnapshot
            )
            guard changes.hasChanges else { continue }

            var didMutateExercise = false

            if changes.persistDrafts {
                let draftChanges = applySetDrafts(snapshot.setDrafts, to: exercise, now: now)
                didMutateExercise = draftChanges.didMutateExerciseStructure || draftChanges.didMutateAnySet
            }

            if changes.persistRepRange {
                didMutateExercise = applyExerciseRepRange(
                    minReps: snapshot.targetRepMin,
                    maxReps: snapshot.targetRepMax,
                    to: exercise,
                    now: now
                ) || didMutateExercise
            }

            if changes.persistRest {
                didMutateExercise = applyExerciseRest(snapshot.restSeconds, to: exercise, now: now) || didMutateExercise
            }

            if changes.persistNotes {
                didMutateExercise = applyExerciseNotes(snapshot.notes, to: exercise, now: now) || didMutateExercise
            }

            guard didMutateExercise else { continue }
            persistedExerciseIDs.insert(exerciseID)
            shouldSave = true
        }

        for (phase, isCompleted) in cardioCompletionsByPhase {
            guard let cardioBlock = try cardioBlock(sessionID: sessionID, phase: phase),
                  cardioBlock.isCompleted != isCompleted
            else {
                continue
            }

            cardioBlock.isCompleted = isCompleted
            cardioBlock.updatedAt = now
            session.updatedAt = now
            shouldSave = true
        }

        if shouldSave {
            try modelContext.save()
        }

        return ActiveWorkoutCheckpointPersistenceResult(
            didPersistSessionMeta: didPersistSessionMeta,
            handledExerciseIDs: handledExerciseIDs,
            persistedExerciseIDs: persistedExerciseIDs
        )
    }

    func previousSetMaps(
        forExercises catalogExerciseUUIDs: [String],
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [String: [Int: WorkoutPreviousSetSnapshot]] {
        try completedSessionRepository.previousSetMaps(
            forExercises: catalogExerciseUUIDs,
            before: date,
            excludingSessionID: excludingSessionID
        )
    }

    func previousPerformanceResolutionByExerciseID(
        sessionID: UUID
    ) throws -> [UUID: WorkoutPreviousPerformanceResolution] {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try sessionExercises(sessionID: sessionID)
        guard !exercises.isEmpty else { return [:] }

        let previousMaps = try previousSetMaps(
            forExercises: Array(Set(exercises.map(\.catalogExerciseUUID))),
            before: session.startedAt,
            excludingSessionID: sessionID
        )

        return Dictionary(
            exercises.map { exercise in
                (
                    exercise.id,
                    .resolved(
                        Self.resolvedPreviousMap(
                            baseMap: previousMaps[exercise.catalogExerciseUUID] ?? [:],
                            maxSetCount: orderedSessionSets(for: exercise).count
                        )
                    )
                )
            },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    func preparedFirstRenderSnapshot(sessionID: UUID) throws -> ActiveWorkoutPreparedFirstRenderSnapshot {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try sessionExercises(sessionID: sessionID)
        guard !exercises.isEmpty else {
            return .empty
        }

        let catalogMatchesByUUID = try ExerciseCatalogRepository(modelContext: modelContext)
            .exerciseSnapshotMap(for: Array(Set(exercises.map(\.catalogExerciseUUID))))
        let previousMaps = try previousSetMaps(
            forExercises: Array(Set(exercises.map(\.catalogExerciseUUID))),
            before: session.startedAt,
            excludingSessionID: sessionID
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
            let drafts = orderedSessionSets(for: exercise)
                .map(WorkoutSessionSetDraft.init(model:))
            let normalizedDrafts = Self.normalizedDraftsForActiveLogging(
                drafts,
                catalogExercise: catalogMatchesByUUID[exercise.catalogExerciseUUID]
            )
            draftsByExerciseID[exercise.id] = normalizedDrafts
            restsByExerciseID[exercise.id] = exercise.restSeconds
            notesByExerciseID[exercise.id] = exercise.notes
            previousResolutionByExerciseID[exercise.id] = .resolved(
                Self.resolvedPreviousMap(
                    baseMap: previousMaps[exercise.catalogExerciseUUID] ?? [:],
                    maxSetCount: normalizedDrafts.count
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
                setDrafts: normalizedDrafts
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

    @discardableResult
    func finishSession(sessionID: UUID, notes: String? = nil) throws -> UUID {
        guard let draftSession = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let completedSession = materializeCompletedSession(from: draftSession, notes: notes)
        let projectedFacts = HistoryProjectionSnapshotBuilder.projectedFacts(from: completedSession)
        let summary = try WorkoutMetricsService(modelContext: modelContext).sessionSummary(
            session: completedSession,
            projectedFacts: projectedFacts
        )
        completedSession.totalVolume = summary.totalVolume
        completedSession.prHitsCount = summary.prHitsCount
        completedSession.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion

        modelContext.delete(draftSession)
        try saveUserDataMutation()

        HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
        HistoryProjectionBackgroundReconciler.shared.scheduleRebuild(
            sessionID: completedSession.id,
            container: modelContext.container
        )
        try? CloudKitBrosSocialService.makeIfUserDataSyncEnabled(modelContext: modelContext)?
            .queueCompletedSessionPublish(sessionID: completedSession.id)

        return completedSession.id
    }

    func cancelSession(sessionID: UUID) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        try deleteDraftAggregateRows(sessionID: sessionID)
        modelContext.delete(session)
        try modelContext.save()
    }

    private func deleteDraftAggregateRows(sessionID: UUID) throws {
        let exercises = try sessionExercises(sessionID: sessionID)
        for exercise in exercises {
            for set in orderedSessionSets(for: exercise) {
                for dropStage in try dropStages(sessionSetID: set.id) {
                    modelContext.delete(dropStage)
                }
                modelContext.delete(set)
            }
            for component in orderedComponents(for: exercise) {
                modelContext.delete(component)
            }
            modelContext.delete(exercise)
        }

        for cardioBlock in try cardioBlocks(sessionID: sessionID) {
            modelContext.delete(cardioBlock)
        }

        for supersetGroup in try draftSupersetGroups(sessionID: sessionID) {
            modelContext.delete(supersetGroup)
        }
    }

    private func dropStages(sessionSetID: UUID) throws -> [ActiveWorkoutDraftDropStage] {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftDropStage>(
            predicate: #Predicate { dropStage in
                dropStage.sessionSetID == sessionSetID
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func draftSupersetGroups(sessionID: UUID) throws -> [ActiveWorkoutDraftSupersetGroup] {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftSupersetGroup>(
            predicate: #Predicate { group in
                group.sessionID == sessionID
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func activeDraftSessions() throws -> [ActiveWorkoutDraftSession] {
        var descriptor = FetchDescriptor<ActiveWorkoutDraftSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor)
    }

    private func cleanLegacyActiveSessionIfNeeded() throws {
        guard let legacySession = try completedSessionRepository.activeSession() else {
            return
        }

        modelContext.delete(legacySession)
        try saveUserDataMutation()
    }

    private func migrateLegacySession(_ legacySession: WorkoutSession) throws -> ActiveWorkoutDraftSession {
        let draftSession = ActiveWorkoutDraftSession(
            id: legacySession.id,
            templateID: legacySession.templateID,
            name: legacySession.name,
            startedAt: legacySession.startedAt,
            notes: legacySession.notes,
            createdAt: legacySession.createdAt,
            updatedAt: legacySession.updatedAt
        )
        modelContext.insert(draftSession)

        var draftCardioBlocks: [ActiveWorkoutDraftCardioBlock] = []
        for legacyCardioBlock in orderedSessionCardioBlocks(legacySession) {
            let draftCardioBlock = ActiveWorkoutDraftCardioBlock(
                id: legacyCardioBlock.id,
                sessionID: draftSession.id,
                phase: legacyCardioBlock.phase,
                catalogExerciseUUID: legacyCardioBlock.catalogExerciseUUID,
                exerciseNameSnapshot: legacyCardioBlock.exerciseNameSnapshot,
                categorySnapshot: legacyCardioBlock.categorySnapshot,
                muscleSummarySnapshot: legacyCardioBlock.muscleSummarySnapshot,
                targetDurationSeconds: legacyCardioBlock.targetDurationSeconds,
                isCompleted: legacyCardioBlock.isCompleted,
                createdAt: legacyCardioBlock.createdAt,
                updatedAt: legacyCardioBlock.updatedAt,
                session: draftSession
            )
            modelContext.insert(draftCardioBlock)
            draftCardioBlocks.append(draftCardioBlock)
        }

        var draftExercises: [ActiveWorkoutDraftExercise] = []
        var supersetMembershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft] = [:]
        for legacyExercise in orderedSessionExercises(legacySession) {
            let draftExercise = ActiveWorkoutDraftExercise(
                id: legacyExercise.id,
                sessionID: draftSession.id,
                templateExerciseID: legacyExercise.templateExerciseID,
                catalogExerciseUUID: legacyExercise.catalogExerciseUUID,
                exerciseNameSnapshot: legacyExercise.exerciseNameSnapshot,
                categorySnapshot: legacyExercise.categorySnapshot,
                muscleSummarySnapshot: legacyExercise.muscleSummarySnapshot,
                notes: legacyExercise.notes,
                targetRepMin: legacyExercise.targetRepMin,
                targetRepMax: legacyExercise.targetRepMax,
                restSeconds: legacyExercise.restSeconds,
                sortOrder: legacyExercise.sortOrder,
                createdAt: legacyExercise.createdAt,
                updatedAt: legacyExercise.updatedAt,
                session: draftSession
            )
            modelContext.insert(draftExercise)
            if let membership = legacyExercise.supersetMembership {
                supersetMembershipsByExerciseID[draftExercise.id] = membership
            }

            let draftComponents = try makeDraftComponents(
                fromLegacyExercise: legacyExercise,
                draftExercise: draftExercise,
                templateID: legacySession.templateID
            )
            for component in draftComponents {
                modelContext.insert(component)
            }
            draftExercise.components = draftComponents

            var draftSets: [ActiveWorkoutDraftSet] = []
            let orderedSets = (legacyExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            for legacySet in orderedSets {
                let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
                    actualWeight: legacySet.actualWeight,
                    actualLoadUnit: legacySet.actualLoadUnit,
                    targetLoadUnit: legacySet.targetLoadUnit
                )
                let draftSet = ActiveWorkoutDraftSet(
                    id: legacySet.id,
                    sessionExerciseID: draftExercise.id,
                    sortOrder: legacySet.sortOrder,
                    isWarmup: legacySet.isWarmup,
                    restSeconds: legacySet.restSeconds,
                    targetReps: legacySet.targetReps,
                    targetWeight: legacySet.targetWeight,
                    targetLoadUnit: legacySet.targetLoadUnit,
                    actualReps: legacySet.actualReps,
                    actualWeight: normalizedActualLoad.weight,
                    actualLoadUnit: normalizedActualLoad.unit,
                    isCompleted: legacySet.isCompleted,
                    isLocked: legacySet.isLocked,
                    createdAt: legacySet.createdAt,
                    updatedAt: legacySet.updatedAt,
                    sessionExercise: draftExercise
                )
                modelContext.insert(draftSet)
                let draftDropStages = (legacySet.dropStages ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .enumerated()
                    .map { stageIndex, legacyStage in
                        let normalizedStageLoad = WorkoutLoggedLoadNormalization.resolved(
                            actualWeight: legacyStage.actualWeight,
                            actualLoadUnit: legacyStage.actualLoadUnit,
                            targetLoadUnit: legacyStage.targetLoadUnit
                        )
                        return ActiveWorkoutDraftDropStage(
                            id: legacyStage.id,
                            sessionSetID: draftSet.id,
                            sortOrder: stageIndex,
                            targetReps: legacyStage.targetReps,
                            targetWeight: legacyStage.targetWeight,
                            targetLoadUnit: legacyStage.targetLoadUnit,
                            actualReps: legacyStage.actualReps,
                            actualWeight: normalizedStageLoad.weight,
                            actualLoadUnit: normalizedStageLoad.unit,
                            isCompleted: legacyStage.isCompleted,
                            createdAt: legacyStage.createdAt,
                            updatedAt: legacyStage.updatedAt,
                            sessionSet: draftSet
                        )
                    }
                for draftDropStage in draftDropStages {
                    modelContext.insert(draftDropStage)
                }
                draftSet.dropStages = draftDropStages
                draftSets.append(draftSet)
            }

            draftExercise.sets = draftSets
            draftExercises.append(draftExercise)
        }

        draftSession.cardioBlocks = draftCardioBlocks
        draftSession.exercises = draftExercises
        syncDraftSupersetGroups(
            for: draftSession,
            exercises: draftExercises,
            membershipsByExerciseID: supersetMembershipsByExerciseID
        )
        modelContext.delete(legacySession)
        try saveUserDataMutation()
        return draftSession
    }

    private func materializeCompletedSession(
        from draftSession: ActiveWorkoutDraftSession,
        notes: String?
    ) -> WorkoutSession {
        let completedAt = Date()
        let completedSession = WorkoutSession(
            id: draftSession.id,
            templateID: draftSession.templateID,
            name: draftSession.name,
            status: .completed,
            startedAt: draftSession.startedAt,
            endedAt: completedAt,
            durationSeconds: max(0, Int(completedAt.timeIntervalSince(draftSession.startedAt))),
            totalVolume: 0,
            prHitsCount: 0,
            summaryMetricsVersion: 0,
            notes: notes ?? draftSession.notes,
            createdAt: draftSession.createdAt,
            updatedAt: completedAt
        )
        modelContext.insert(completedSession)

        var completedCardioBlocks: [WorkoutSessionCardioBlock] = []
        for draftCardioBlock in orderedSessionCardioBlocks(draftSession) {
            let completedCardioBlock = WorkoutSessionCardioBlock(
                id: draftCardioBlock.id,
                sessionID: completedSession.id,
                phase: draftCardioBlock.phase,
                catalogExerciseUUID: draftCardioBlock.catalogExerciseUUID,
                exerciseNameSnapshot: draftCardioBlock.exerciseNameSnapshot,
                categorySnapshot: draftCardioBlock.categorySnapshot,
                muscleSummarySnapshot: draftCardioBlock.muscleSummarySnapshot,
                targetDurationSeconds: draftCardioBlock.targetDurationSeconds,
                isCompleted: draftCardioBlock.isCompleted,
                createdAt: draftCardioBlock.createdAt,
                updatedAt: draftCardioBlock.updatedAt,
                session: completedSession
            )
            modelContext.insert(completedCardioBlock)
            completedCardioBlocks.append(completedCardioBlock)
        }

        var completedExercises: [WorkoutSessionExercise] = []
        var supersetMembershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft] = [:]
        for draftExercise in orderedSessionExercises(draftSession) {
            let completedExercise = WorkoutSessionExercise(
                id: draftExercise.id,
                sessionID: completedSession.id,
                templateExerciseID: draftExercise.templateExerciseID,
                catalogExerciseUUID: draftExercise.catalogExerciseUUID,
                exerciseNameSnapshot: draftExercise.exerciseNameSnapshot,
                categorySnapshot: draftExercise.categorySnapshot,
                muscleSummarySnapshot: draftExercise.muscleSummarySnapshot,
                notes: draftExercise.notes,
                targetRepMin: draftExercise.targetRepMin,
                targetRepMax: draftExercise.targetRepMax,
                restSeconds: draftExercise.restSeconds,
                sortOrder: draftExercise.sortOrder,
                createdAt: draftExercise.createdAt,
                updatedAt: draftExercise.updatedAt,
                session: completedSession
            )
            modelContext.insert(completedExercise)
            if let membership = draftExercise.supersetMembership {
                supersetMembershipsByExerciseID[completedExercise.id] = membership
            }

            var completedSets: [WorkoutSessionSet] = []
            for draftSet in orderedSessionSets(for: draftExercise) {
                let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
                    actualWeight: draftSet.actualWeight,
                    actualLoadUnit: draftSet.actualLoadUnit,
                    targetLoadUnit: draftSet.targetLoadUnit
                )
                let completedSet = WorkoutSessionSet(
                    id: draftSet.id,
                    sessionExerciseID: completedExercise.id,
                    sortOrder: draftSet.sortOrder,
                    isWarmup: draftSet.isWarmup,
                    restSeconds: draftSet.restSeconds,
                    targetReps: draftSet.targetReps,
                    targetWeight: draftSet.targetWeight,
                    targetLoadUnit: draftSet.targetLoadUnit,
                    actualReps: draftSet.actualReps,
                    actualWeight: normalizedActualLoad.weight,
                    actualLoadUnit: normalizedActualLoad.unit,
                    isCompleted: draftSet.isCompleted,
                    isLocked: draftSet.isLocked,
                    createdAt: draftSet.createdAt,
                    updatedAt: draftSet.updatedAt,
                    sessionExercise: completedExercise
                )
                modelContext.insert(completedSet)
                let completedDropStages = (draftSet.dropStages ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .enumerated()
                    .map { stageIndex, draftStage in
                        let normalizedStageLoad = WorkoutLoggedLoadNormalization.resolved(
                            actualWeight: draftStage.actualWeight,
                            actualLoadUnit: draftStage.actualLoadUnit,
                            targetLoadUnit: draftStage.targetLoadUnit
                        )
                        return WorkoutSessionDropStage(
                            id: draftStage.id,
                            sessionSetID: completedSet.id,
                            sortOrder: stageIndex,
                            targetReps: draftStage.targetReps,
                            targetWeight: draftStage.targetWeight,
                            targetLoadUnit: draftStage.targetLoadUnit,
                            actualReps: draftStage.actualReps,
                            actualWeight: normalizedStageLoad.weight,
                            actualLoadUnit: normalizedStageLoad.unit,
                            isCompleted: draftStage.isCompleted,
                            createdAt: draftStage.createdAt,
                            updatedAt: draftStage.updatedAt,
                            sessionSet: completedSet
                        )
                    }
                for completedDropStage in completedDropStages {
                    modelContext.insert(completedDropStage)
                }
                completedSet.dropStages = completedDropStages
                completedSets.append(completedSet)
            }

            completedExercise.sets = completedSets
            completedExercise.updateSetSummary(
                totalSetCount: completedSets.count,
                completedSetCount: completedSets.filter { set in
                    guard set.isCompleted else { return false }
                    let dropStages = set.dropStages ?? []
                    return dropStages.allSatisfy(\.isCompleted)
                }.count,
                hasDropsets: completedSets.contains { !($0.dropStages ?? []).isEmpty }
            )
            completedExercises.append(completedExercise)
        }

        completedSession.cardioBlocks = completedCardioBlocks
        completedSession.exercises = completedExercises
        syncCompletedSupersetGroups(
            for: completedSession,
            exercises: completedExercises,
            membershipsByExerciseID: supersetMembershipsByExerciseID
        )
        return completedSession
    }

    private func template(id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { template in
            template.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func saveUserDataMutation() throws {
        try modelContext.save()
        UserDataSyncTrackerBridge.markLocalMutation()
    }

    private func sessionExercise(id: UUID) throws -> ActiveWorkoutDraftExercise? {
        let descriptor = FetchDescriptor<ActiveWorkoutDraftExercise>(predicate: #Predicate { exercise in
            exercise.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func makeDraftComponents(
        fromLegacyExercise legacyExercise: WorkoutSessionExercise,
        draftExercise: ActiveWorkoutDraftExercise,
        templateID: UUID?
    ) throws -> [ActiveWorkoutDraftExerciseComponent] {
        if let templateID,
           let templateExerciseID = legacyExercise.templateExerciseID,
           let template = try template(id: templateID),
           let templateExercise = (template.exercises ?? []).first(where: { $0.id == templateExerciseID }) {
            let orderedTemplateComponents = (templateExercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            if !orderedTemplateComponents.isEmpty {
                return orderedTemplateComponents.enumerated().map { index, component in
                    ActiveWorkoutDraftExerciseComponent(
                        sessionExerciseID: draftExercise.id,
                        catalogExerciseUUID: component.catalogExerciseUUID,
                        exerciseNameSnapshot: component.exerciseNameSnapshot,
                        categorySnapshot: component.categorySnapshot,
                        muscleSummarySnapshot: component.muscleSummarySnapshot,
                        sortOrder: index,
                        createdAt: component.createdAt,
                        updatedAt: component.updatedAt,
                        sessionExercise: draftExercise
                    )
                }
            }
        }

        guard !legacyExercise.catalogExerciseUUID.isEmpty else {
            return []
        }

        return [
            ActiveWorkoutDraftExerciseComponent(
                sessionExerciseID: draftExercise.id,
                catalogExerciseUUID: legacyExercise.catalogExerciseUUID,
                exerciseNameSnapshot: legacyExercise.exerciseNameSnapshot,
                categorySnapshot: legacyExercise.categorySnapshot,
                muscleSummarySnapshot: legacyExercise.muscleSummarySnapshot,
                sortOrder: 0,
                createdAt: legacyExercise.createdAt,
                updatedAt: legacyExercise.updatedAt,
                sessionExercise: draftExercise
            ),
        ]
    }

    private func defaultSessionSets(
        sessionExerciseID: UUID,
        restSeconds: Int,
        loadUnit: TemplateLoadUnit,
        sessionExercise: ActiveWorkoutDraftExercise
    ) -> [ActiveWorkoutDraftSet] {
        let defaults = [0, 1, 2].map { index in
            ActiveWorkoutDraftSet(
                sessionExerciseID: sessionExerciseID,
                sortOrder: index,
                isWarmup: index == 0,
                restSeconds: sanitizedRest(restSeconds),
                targetReps: nil,
                targetWeight: nil,
                targetLoadUnit: loadUnit,
                actualReps: nil,
                actualWeight: nil,
                actualLoadUnit: loadUnit,
                isCompleted: false,
                isLocked: false,
                sessionExercise: sessionExercise
            )
        }

        for set in defaults {
            modelContext.insert(set)
        }

        return defaults
    }

    private func sanitizedReps(_ reps: Int?) -> Int? {
        guard let reps else { return nil }
        return min(999, max(0, reps))
    }

    private func sanitizedWeight(_ weight: Double?) -> Double? {
        guard let weight else { return nil }
        return min(5000, max(0, weight))
    }

    private func sanitizedRepRange(min minReps: Int?, max maxReps: Int?) -> (min: Int?, max: Int?) {
        (sanitizedReps(minReps), sanitizedReps(maxReps))
    }

    private func sanitizedRest(_ seconds: Int) -> Int {
        min(3600, max(0, seconds))
    }

    private func sanitizedCardioDuration(_ seconds: Int) -> Int {
        min(24 * 60 * 60, max(0, seconds))
    }

    private func orderedSessionExercises(_ session: WorkoutSession) -> [WorkoutSessionExercise] {
        (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func orderedSessionExercises(_ session: ActiveWorkoutDraftSession) -> [ActiveWorkoutDraftExercise] {
        (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func orderedTemplateCardioBlocks(_ template: WorkoutTemplate) -> [TemplateCardioBlock] {
        (template.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func orderedSessionCardioBlocks(_ session: WorkoutSession) -> [WorkoutSessionCardioBlock] {
        (session.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func orderedSessionCardioBlocks(_ session: ActiveWorkoutDraftSession) -> [ActiveWorkoutDraftCardioBlock] {
        (session.cardioBlocks ?? [])
            .filter { $0.modelContext != nil }
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func orderedCardioBlocks(
        _ session: ActiveWorkoutDraftSession,
        adding cardioBlock: ActiveWorkoutDraftCardioBlock? = nil
    ) -> [ActiveWorkoutDraftCardioBlock] {
        var blocks = orderedSessionCardioBlocks(session)
        if let cardioBlock, !blocks.contains(where: { $0.id == cardioBlock.id }) {
            blocks.append(cardioBlock)
        }
        return blocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func orderedSessionSets(for exercise: ActiveWorkoutDraftExercise) -> [ActiveWorkoutDraftSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
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

    private func orderedComponents(for exercise: ActiveWorkoutDraftExercise) -> [ActiveWorkoutDraftExerciseComponent] {
        (exercise.components ?? [])
            .filter { $0.modelContext != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func syncDraftSupersetGroups(
        for session: ActiveWorkoutDraftSession,
        exercises: [ActiveWorkoutDraftExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) {
        let orderedExercises = exercises.sorted { $0.sortOrder < $1.sortOrder }
        let existingGroups = (session.supersetGroups ?? []).filter { $0.modelContext != nil }
        let existingGroupsByID = Dictionary(
            existingGroups.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let normalized = normalizedSupersetMemberships(
            for: orderedExercises.map(ActiveWorkoutSupersetExerciseSnapshot.init),
            membershipsByExerciseID: membershipsByExerciseID
        )

        for group in existingGroups where normalized.groupsByID[group.id] == nil {
            modelContext.delete(group)
        }

        var updatedGroups: [ActiveWorkoutDraftSupersetGroup] = []
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
            let group = existingGroupsByID[membership.groupID] ?? ActiveWorkoutDraftSupersetGroup(
                id: membership.groupID,
                sessionID: session.id,
                roundRestSeconds: membership.roundRestSeconds,
                session: session
            )

            if group.modelContext == nil {
                modelContext.insert(group)
            }

            group.sessionID = session.id
            group.session = session
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
                    ($0.supersetPosition?.sortOrder ?? Int.max) < ($1.supersetPosition?.sortOrder ?? Int.max)
                }
            group.exercises = members
        }

        session.supersetGroups = updatedGroups.sorted { lhs, rhs in
            let lhsOrder = lhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? Int.max
            let rhsOrder = rhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func syncCompletedSupersetGroups(
        for session: WorkoutSession,
        exercises: [WorkoutSessionExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) {
        let orderedExercises = exercises.sorted { $0.sortOrder < $1.sortOrder }
        let existingGroups = (session.supersetGroups ?? []).filter { $0.modelContext != nil }
        let existingGroupsByID = Dictionary(
            existingGroups.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let normalized = normalizedSupersetMemberships(
            for: orderedExercises.map(ActiveWorkoutSupersetExerciseSnapshot.init),
            membershipsByExerciseID: membershipsByExerciseID
        )

        for group in existingGroups where normalized.groupsByID[group.id] == nil {
            modelContext.delete(group)
        }

        var updatedGroups: [WorkoutSessionSupersetGroup] = []
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
            let group = existingGroupsByID[membership.groupID] ?? WorkoutSessionSupersetGroup(
                id: membership.groupID,
                sessionID: session.id,
                roundRestSeconds: membership.roundRestSeconds,
                session: session
            )

            if group.modelContext == nil {
                modelContext.insert(group)
            }

            group.sessionID = session.id
            group.session = session
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
                    ($0.supersetPosition?.sortOrder ?? Int.max) < ($1.supersetPosition?.sortOrder ?? Int.max)
                }
            group.exercises = members
        }

        session.supersetGroups = updatedGroups.sorted { lhs, rhs in
            let lhsOrder = lhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? Int.max
            let rhsOrder = rhs.exercises?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first?
                .sortOrder ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func normalizedSupersetMemberships(
        for exercises: [ActiveWorkoutSupersetExerciseSnapshot],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) -> ActiveWorkoutSupersetNormalization {
        var memberships: [UUID: ExerciseSupersetMembershipDraft] = [:]
        var standaloneRestSecondsByExerciseID: [UUID: Int] = [:]
        var groupsByID: [UUID: ActiveWorkoutSupersetGroupSpec] = [:]
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
                let roundRestSeconds = sanitizedRest(membership.roundRestSeconds)
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
                groupsByID[membership.groupID] = ActiveWorkoutSupersetGroupSpec(
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
            standaloneRestSecondsByExerciseID[exercise.id] = sanitizedRest(
                membershipsByExerciseID[exercise.id]?.roundRestSeconds ?? exercise.restSeconds
            )
        }

        return ActiveWorkoutSupersetNormalization(
            membershipsByExerciseID: memberships,
            standaloneRestSecondsByExerciseID: standaloneRestSecondsByExerciseID,
            groupsByID: groupsByID
        )
    }

    private func clearSupersetMembership(for exercise: ActiveWorkoutDraftExercise) {
        exercise.supersetGroupID = nil
        exercise.supersetPosition = nil
        exercise.supersetGroup = nil
        exercise.updatedAt = .now
    }

    private func clearSupersetMembership(for exercise: WorkoutSessionExercise) {
        exercise.supersetGroupID = nil
        exercise.supersetPosition = nil
        exercise.supersetGroup = nil
        exercise.updatedAt = .now
    }

    private func applyStandaloneRest(_ restSeconds: Int, to exercise: ActiveWorkoutDraftExercise) {
        let normalizedRest = sanitizedRest(restSeconds)
        guard exercise.restSeconds != normalizedRest
            || (exercise.sets ?? []).contains(where: { $0.restSeconds != normalizedRest }) else {
            return
        }

        exercise.restSeconds = normalizedRest
        for set in exercise.sets ?? [] where set.restSeconds != normalizedRest {
            set.restSeconds = normalizedRest
            set.updatedAt = .now
        }
        exercise.updatedAt = .now
    }

    private func applyStandaloneRest(_ restSeconds: Int, to exercise: WorkoutSessionExercise) {
        let normalizedRest = sanitizedRest(restSeconds)
        guard exercise.restSeconds != normalizedRest
            || (exercise.sets ?? []).contains(where: { $0.restSeconds != normalizedRest }) else {
            return
        }

        exercise.restSeconds = normalizedRest
        for set in exercise.sets ?? [] where set.restSeconds != normalizedRest {
            set.restSeconds = normalizedRest
            set.updatedAt = .now
        }
        exercise.updatedAt = .now
    }

    private func syncDropStageStructure(
        for set: ActiveWorkoutDraftSet,
        desiredDrafts: [WorkoutSessionDropStageDraft],
        now: Date
    ) -> Bool {
        let normalizedDrafts = desiredDrafts
        let existingStages = (set.dropStages ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let existingByID = Dictionary(
            existingStages.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let incomingIDs = Set(normalizedDrafts.map(\.id))
        let existingOrderedIDs = existingStages.map(\.id)
        let incomingOrderedIDs = normalizedDrafts.map(\.id)
        var didChange = existingOrderedIDs != incomingOrderedIDs

        for stage in existingStages where !incomingIDs.contains(stage.id) {
            modelContext.delete(stage)
            didChange = true
        }

        var updatedStages: [ActiveWorkoutDraftDropStage] = []
        updatedStages.reserveCapacity(normalizedDrafts.count)
        for (index, draft) in normalizedDrafts.enumerated() {
            let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
                actualWeight: sanitizedWeight(draft.actualWeight),
                actualLoadUnit: draft.actualLoadUnit,
                targetLoadUnit: draft.targetLoadUnit
            )
            let stage = existingByID[draft.id] ?? ActiveWorkoutDraftDropStage(
                id: draft.id,
                sessionSetID: set.id,
                sortOrder: index,
                targetReps: sanitizedReps(draft.targetReps),
                targetWeight: sanitizedWeight(draft.targetWeight),
                targetLoadUnit: draft.targetLoadUnit,
                actualReps: sanitizedReps(draft.actualReps),
                actualWeight: normalizedActualLoad.weight,
                actualLoadUnit: normalizedActualLoad.unit,
                isCompleted: draft.isCompleted,
                sessionSet: set
            )

            if stage.modelContext == nil {
                modelContext.insert(stage)
                didChange = true
            }

            if stage.sortOrder != index {
                stage.sortOrder = index
                didChange = true
            }
            let normalizedTargetReps = sanitizedReps(draft.targetReps)
            let normalizedTargetWeight = sanitizedWeight(draft.targetWeight)
            let normalizedActualReps = sanitizedReps(draft.actualReps)
            let normalizedActualWeight = normalizedActualLoad.weight
            if stage.targetReps != normalizedTargetReps {
                stage.targetReps = normalizedTargetReps
                didChange = true
            }
            if stage.targetWeight != normalizedTargetWeight {
                stage.targetWeight = normalizedTargetWeight
                didChange = true
            }
            if stage.targetLoadUnit != draft.targetLoadUnit {
                stage.targetLoadUnit = draft.targetLoadUnit
                didChange = true
            }
            if stage.actualReps != normalizedActualReps {
                stage.actualReps = normalizedActualReps
                didChange = true
            }
            if stage.actualWeight != normalizedActualWeight {
                stage.actualWeight = normalizedActualWeight
                didChange = true
            }
            if stage.actualLoadUnit != normalizedActualLoad.unit {
                stage.actualLoadUnit = normalizedActualLoad.unit
                didChange = true
            }
            if stage.isCompleted != draft.isCompleted {
                stage.isCompleted = draft.isCompleted
                didChange = true
            }
            if didChange {
                stage.updatedAt = now
            }
            stage.sessionSetID = set.id
            stage.sessionSet = set
            updatedStages.append(stage)
        }

        if didChange {
            set.dropStages = updatedStages
        }

        return didChange
    }

    private func applySetDrafts(
        _ drafts: [WorkoutSessionSetDraft],
        to exercise: ActiveWorkoutDraftExercise,
        now: Date
    ) -> (didMutateExerciseStructure: Bool, didMutateAnySet: Bool) {
        let existing = exercise.sets ?? []
        let existingByID = Dictionary(
            existing.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let incomingIDs = Set(drafts.map(\.id))
        let existingOrderedIDs = orderedSessionSets(for: exercise).map(\.id)
        let incomingOrderedIDs = drafts.map(\.id)
        var didMutateExerciseStructure = existingOrderedIDs != incomingOrderedIDs
        var didMutateAnySet = false

        for set in existing where !incomingIDs.contains(set.id) {
            modelContext.delete(set)
            didMutateExerciseStructure = true
        }

        var updatedSets: [ActiveWorkoutDraftSet] = []
        updatedSets.reserveCapacity(drafts.count)
        for (index, draft) in drafts.enumerated() {
            let set: ActiveWorkoutDraftSet
            if let existingSet = existingByID[draft.id] {
                set = existingSet
            } else {
                set = ActiveWorkoutDraftSet(
                    id: draft.id,
                    sessionExerciseID: exercise.id,
                    sessionExercise: exercise
                )
                modelContext.insert(set)
                didMutateExerciseStructure = true
            }

            let didMutateSet = apply(draft: draft, to: set, sortOrder: index, now: now)
            if didMutateSet {
                set.updatedAt = now
                didMutateAnySet = true
            }
            updatedSets.append(set)
        }

        if didMutateExerciseStructure {
            exercise.sets = updatedSets
            exercise.updatedAt = now
        }

        return (didMutateExerciseStructure, didMutateAnySet)
    }

    @discardableResult
    private func applyExerciseRest(
        _ restSeconds: Int,
        to exercise: ActiveWorkoutDraftExercise,
        now: Date
    ) -> Bool {
        let normalizedRest = sanitizedRest(restSeconds)
        guard exercise.restSeconds != normalizedRest else {
            return false
        }

        let previousRest = exercise.restSeconds
        exercise.restSeconds = normalizedRest
        for set in exercise.sets ?? [] where !set.isLocked {
            guard set.restSeconds == previousRest else {
                continue
            }
            set.restSeconds = normalizedRest
            set.updatedAt = now
        }
        exercise.updatedAt = now
        return true
    }

    @discardableResult
    private func applyExerciseRepRange(
        minReps: Int?,
        maxReps: Int?,
        to exercise: ActiveWorkoutDraftExercise,
        now: Date
    ) -> Bool {
        let normalized = sanitizedRepRange(min: minReps, max: maxReps)
        guard exercise.targetRepMin != normalized.min || exercise.targetRepMax != normalized.max else {
            return false
        }

        exercise.targetRepMin = normalized.min
        exercise.targetRepMax = normalized.max
        exercise.updatedAt = now
        return true
    }

    @discardableResult
    private func applyExerciseNotes(
        _ notes: String,
        to exercise: ActiveWorkoutDraftExercise,
        now: Date
    ) -> Bool {
        guard exercise.notes != notes else {
            return false
        }

        exercise.notes = notes
        exercise.updatedAt = now
        return true
    }

    @discardableResult
    private func applySessionMeta(
        name: String,
        notes: String,
        to session: ActiveWorkoutDraftSession,
        now: Date
    ) throws -> Bool {
        var didChange = false
        let normalizedSessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedSessionName.isEmpty {
            let cleaned = try ReviewModerationService.validateUserInput(name, kind: .workoutName)
            if session.name != cleaned {
                session.name = cleaned
                didChange = true
            }
        }

        if session.notes != notes {
            session.notes = notes
            didChange = true
        }

        if didChange {
            session.updatedAt = now
        }

        return didChange
    }

    private func apply(
        draft: WorkoutSessionSetDraft,
        to set: ActiveWorkoutDraftSet,
        sortOrder: Int,
        now: Date
    ) -> Bool {
        let normalizedRest = sanitizedRest(draft.restSeconds)
        let normalizedTargetReps = sanitizedReps(draft.targetReps)
        let normalizedTargetWeight = sanitizedWeight(draft.targetWeight)
        let normalizedActualReps = sanitizedReps(draft.actualReps)
        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: sanitizedWeight(draft.actualWeight),
            actualLoadUnit: draft.actualLoadUnit,
            targetLoadUnit: draft.targetLoadUnit
        )
        var didChange = false

        if set.sortOrder != sortOrder {
            set.sortOrder = sortOrder
            didChange = true
        }
        if set.isWarmup != draft.isWarmup {
            set.isWarmup = draft.isWarmup
            didChange = true
        }
        if set.restSeconds != normalizedRest {
            set.restSeconds = normalizedRest
            didChange = true
        }
        if set.targetReps != normalizedTargetReps {
            set.targetReps = normalizedTargetReps
            didChange = true
        }
        if set.targetWeight != normalizedTargetWeight {
            set.targetWeight = normalizedTargetWeight
            didChange = true
        }
        if set.targetLoadUnit != draft.targetLoadUnit {
            set.targetLoadUnit = draft.targetLoadUnit
            didChange = true
        }
        if set.actualReps != normalizedActualReps {
            set.actualReps = normalizedActualReps
            didChange = true
        }
        if set.actualWeight != normalizedActualLoad.weight {
            set.actualWeight = normalizedActualLoad.weight
            didChange = true
        }
        if set.actualLoadUnit != normalizedActualLoad.unit {
            set.actualLoadUnit = normalizedActualLoad.unit
            didChange = true
        }
        if set.isCompleted != draft.isCompleted {
            set.isCompleted = draft.isCompleted
            didChange = true
        }
        if set.isLocked != draft.isLocked {
            set.isLocked = draft.isLocked
            didChange = true
        }

        if syncDropStageStructure(for: set, desiredDrafts: draft.dropStages, now: now) {
            didChange = true
        }

        return didChange
    }
}

nonisolated private struct ActiveWorkoutSupersetExerciseSnapshot: Sendable {
    let id: UUID
    let restSeconds: Int

    init(exercise: ActiveWorkoutDraftExercise) {
        id = exercise.id
        restSeconds = exercise.restSeconds
    }

    init(exercise: WorkoutSessionExercise) {
        id = exercise.id
        restSeconds = exercise.restSeconds
    }
}

private struct ActiveWorkoutSupersetNormalization {
    let membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    let standaloneRestSecondsByExerciseID: [UUID: Int]
    let groupsByID: [UUID: ActiveWorkoutSupersetGroupSpec]
}

private struct ActiveWorkoutSupersetGroupSpec {
    let roundRestSeconds: Int
    let exerciseIDs: [UUID]
}
