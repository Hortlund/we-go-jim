import Foundation
import SwiftData

struct WorkoutPreviousSetSnapshot: Equatable {
    var reps: Int?
    var weight: Double?
    var unit: TemplateLoadUnit
}

struct WorkoutSessionSetDraft: Identifiable, Equatable {
    let id: UUID
    var isWarmup: Bool
    var restSeconds: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnit: TemplateLoadUnit
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnit: TemplateLoadUnit
    var isCompleted: Bool
    var isLocked: Bool

    init(
        id: UUID = UUID(),
        isWarmup: Bool = false,
        restSeconds: Int = 120,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.isWarmup = isWarmup
        self.restSeconds = max(0, min(3600, restSeconds))
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnit = targetLoadUnit
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnit = actualLoadUnit
        self.isCompleted = isCompleted
        self.isLocked = isLocked
    }

    init(model: WorkoutSessionSet) {
        self.id = model.id
        self.isWarmup = model.isWarmup
        self.restSeconds = model.restSeconds
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.targetLoadUnit = model.targetLoadUnit
        self.actualReps = model.actualReps
        self.actualWeight = model.actualWeight
        self.actualLoadUnit = model.actualLoadUnit
        self.isCompleted = model.isCompleted
        self.isLocked = model.isLocked
    }

    init(model: ActiveWorkoutDraftSet) {
        self.id = model.id
        self.isWarmup = model.isWarmup
        self.restSeconds = model.restSeconds
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.targetLoadUnit = model.targetLoadUnit
        self.actualReps = model.actualReps
        self.actualWeight = model.actualWeight
        self.actualLoadUnit = model.actualLoadUnit
        self.isCompleted = model.isCompleted
        self.isLocked = model.isLocked
    }
}

enum WorkoutRestTimerContextBuilder {
    static func nextSetLabel(
        afterCompletingSetAt completedIndex: Int,
        in setDrafts: [WorkoutSessionSetDraft]
    ) -> String? {
        guard setDrafts.indices.contains(completedIndex) else {
            return nil
        }

        guard let nextIndex = setDrafts.indices.first(where: { index in
            index > completedIndex && !setDrafts[index].isCompleted
        }) else {
            return nil
        }

        return setLabel(for: nextIndex, in: setDrafts)
    }

    static func setLabel(for index: Int, in setDrafts: [WorkoutSessionSetDraft]) -> String? {
        guard setDrafts.indices.contains(index) else {
            return nil
        }

        if setDrafts[index].isWarmup {
            return "Warmup Set"
        }

        let workingSetNumber = setDrafts.prefix(index + 1).reduce(into: 0) { count, draft in
            if !draft.isWarmup {
                count += 1
            }
        }
        return "Working Set \(workingSetNumber)"
    }
}

enum WorkoutSessionRepositoryError: Error {
    case sessionNotFound
    case sessionExerciseNotFound
    case sessionSetNotFound
    case templateNotFound
    case invalidSessionState
}

final class WorkoutSessionRepository {
    private let modelContext: ModelContext
    private var historyProjectionRepository: HistoryProjectionRepository {
        HistoryProjectionRepository(modelContext: modelContext)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func preferredLoadUnit() -> TemplateLoadUnit {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        return (try? profileRepository.currentProfile()?.preferredLoadUnit) ?? .kg
    }

    private var componentRotationResolver: TemplateExerciseComponentRotationResolver {
        TemplateExerciseComponentRotationResolver(modelContext: modelContext)
    }

    private func invalidateAnalyticsCache() {
        HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
    }

    private func scheduleProjectionRebuild(for sessionID: UUID) {
        HistoryProjectionBackgroundReconciler.shared.scheduleRebuild(
            sessionID: sessionID,
            container: modelContext.container
        )
    }

    func createEmptySession(name: String = "Empty Workout") throws -> WorkoutSession {
        let cleanedName = ReviewModerationService.sanitizedForSharing(name, kind: .workoutName)
        let created = WorkoutSession(name: cleanedName)
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    func createSessionFromTemplate(templateID: UUID) throws -> WorkoutSession {
        guard let template = try template(id: templateID) else {
            throw WorkoutSessionRepositoryError.templateNotFound
        }

        let session = WorkoutSession(
            templateID: template.id,
            name: ReviewModerationService.sanitizedForSharing(template.name, kind: .workoutName),
            notes: template.notes
        )
        modelContext.insert(session)

        let orderedCardioBlocks = orderedTemplateCardioBlocks(template)
        var createdCardioBlocks: [WorkoutSessionCardioBlock] = []
        for templateCardioBlock in orderedCardioBlocks {
            let cardioBlock = WorkoutSessionCardioBlock(
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
        for (exerciseIndex, templateExercise) in orderedExercises.enumerated() {
            let selectedComponent = try componentRotationResolver
                .resolution(
                    for: template,
                    exercise: templateExercise,
                    before: session.startedAt,
                    excludingSessionID: session.id
                )?
                .selectedComponent
            let exercise = WorkoutSessionExercise(
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

            let orderedSets = (templateExercise.prescribedSets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            var createdSets: [WorkoutSessionSet] = []
            for (setIndex, templateSet) in orderedSets.enumerated() {
                let set = WorkoutSessionSet(
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
        }

        try modelContext.save()
        return session
    }

    func session(id: UUID) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { session in
            session.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    func activeSession() throws -> WorkoutSession? {
        let activeStatus = WorkoutSessionStatus.active.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == activeStatus
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func completedSessions(includeArchived: Bool = false) throws -> [WorkoutSession] {
        try completedSessions(before: nil, excludingSessionID: nil, includeArchived: includeArchived)
    }

    func archivedSessions() throws -> [WorkoutSession] {
        try completedSessions(includeArchived: true)
            .filter { $0.archivedAt != nil }
            .sorted { lhs, rhs in
                let lhsArchivedAt = lhs.archivedAt ?? .distantPast
                let rhsArchivedAt = rhs.archivedAt ?? .distantPast
                if lhsArchivedAt != rhsArchivedAt {
                    return lhsArchivedAt > rhsArchivedAt
                }

                let lhsCompletedAt = lhs.endedAt ?? lhs.startedAt
                let rhsCompletedAt = rhs.endedAt ?? rhs.startedAt
                return lhsCompletedAt > rhsCompletedAt
            }
    }

    func sessionExercises(sessionID: UUID) throws -> [WorkoutSessionExercise] {
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(
            predicate: #Predicate { exercise in
                exercise.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func sessionCardioBlocks(sessionID: UUID) throws -> [WorkoutSessionCardioBlock] {
        let descriptor = FetchDescriptor<WorkoutSessionCardioBlock>(
            predicate: #Predicate { cardioBlock in
                cardioBlock.sessionID == sessionID
            }
        )
        return try modelContext.fetch(descriptor)
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    func setDrafts(sessionExerciseID: UUID) throws -> [WorkoutSessionSetDraft] {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }
        let ordered = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return ordered.map(WorkoutSessionSetDraft.init(model:))
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

    func addExercise(sessionID: UUID, catalogItem: ExerciseCatalogItem, restSeconds: Int = 120) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let existing = try sessionExercises(sessionID: sessionID)
        if existing.contains(where: { $0.catalogExerciseUUID == catalogItem.remoteUUID }) {
            return
        }

        let nextIndex = (existing.map(\.sortOrder).max() ?? -1) + 1
        let created = WorkoutSessionExercise(
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

        session.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRest(sessionExerciseID: UUID, restSeconds: Int) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let normalizedRest = sanitizedRest(restSeconds)
        guard exercise.restSeconds != normalizedRest else {
            return
        }
        let previousRest = exercise.restSeconds
        exercise.restSeconds = normalizedRest
        for set in exercise.sets ?? [] where !set.isLocked {
            guard set.restSeconds == previousRest else {
                continue
            }
            set.restSeconds = normalizedRest
            set.updatedAt = .now
        }
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRepRange(sessionExerciseID: UUID, minReps: Int?, maxReps: Int?) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let normalized = sanitizedRepRange(min: minReps, max: maxReps)
        guard exercise.targetRepMin != normalized.min || exercise.targetRepMax != normalized.max else {
            return
        }
        exercise.targetRepMin = normalized.min
        exercise.targetRepMax = normalized.max
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseNotes(sessionExerciseID: UUID, notes: String) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        guard exercise.notes != notes else {
            return
        }

        exercise.notes = notes
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func addSet(sessionExerciseID: UUID) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let ordered = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let nextSort = (ordered.last?.sortOrder ?? -1) + 1
        let defaultLoadUnit = preferredLoadUnit()
        let newSet = WorkoutSessionSet(
            sessionExerciseID: exercise.id,
            sortOrder: nextSort,
            isWarmup: false,
            restSeconds: sanitizedRest(ordered.last?.restSeconds ?? exercise.restSeconds),
            targetReps: ordered.last?.targetReps,
            targetWeight: ordered.last?.targetWeight,
            targetLoadUnit: ordered.last?.targetLoadUnit ?? defaultLoadUnit,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: ordered.last?.actualLoadUnit ?? ordered.last?.targetLoadUnit ?? defaultLoadUnit,
            isCompleted: false,
            isLocked: false,
            sessionExercise: exercise
        )
        modelContext.insert(newSet)

        var sets = exercise.sets ?? []
        sets.append(newSet)
        exercise.sets = sets
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func removeSet(sessionExerciseID: UUID, setID: UUID) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let sets = exercise.sets ?? []
        guard let target = sets.first(where: { $0.id == setID }) else {
            throw WorkoutSessionRepositoryError.sessionSetNotFound
        }

        modelContext.delete(target)

        var remaining = sets
        remaining.removeAll(where: { $0.id == setID })
        for (index, set) in remaining.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            set.sortOrder = index
            set.updatedAt = .now
        }

        exercise.sets = remaining
        exercise.updatedAt = .now
        try modelContext.save()
    }

    func saveSetDrafts(sessionExerciseID: UUID, drafts: [WorkoutSessionSetDraft]) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let existing = exercise.sets ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(drafts.map(\.id))
        let existingOrderedIDs = existing
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
        let incomingOrderedIDs = drafts.map(\.id)
        let now = Date()
        var didMutateExerciseStructure = existingOrderedIDs != incomingOrderedIDs
        var didMutateAnySet = false

        for set in existing where !incomingIDs.contains(set.id) {
            modelContext.delete(set)
            didMutateExerciseStructure = true
        }

        var updatedSets: [WorkoutSessionSet] = []
        updatedSets.reserveCapacity(drafts.count)
        for (index, draft) in drafts.enumerated() {
            let set: WorkoutSessionSet
            if let existingSet = existingByID[draft.id] {
                set = existingSet
            } else {
                set = WorkoutSessionSet(
                    id: draft.id,
                    sessionExerciseID: sessionExerciseID,
                    sessionExercise: exercise
                )
                modelContext.insert(set)
                didMutateExerciseStructure = true
            }

            let didMutateSet = apply(draft: draft, to: set, sortOrder: index)
            if didMutateSet {
                didMutateAnySet = true
                set.updatedAt = now
            }
            updatedSets.append(set)
        }

        if didMutateExerciseStructure {
            exercise.sets = updatedSets
            exercise.updatedAt = now
        }

        guard didMutateExerciseStructure || didMutateAnySet else {
            return
        }

        try modelContext.save()
    }

    func previousSet(
        for catalogExerciseUUID: String,
        setIndex: Int,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> WorkoutSessionSet? {
        let exercisesByCatalogUUID = try latestPreviousExercises(
            forExercises: [catalogExerciseUUID],
            before: date,
            excludingSessionID: excludingSessionID
        )

        guard let exercise = exercisesByCatalogUUID[catalogExerciseUUID] else {
            return nil
        }

        let orderedSets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        guard !orderedSets.isEmpty else { return nil }
        if let exact = orderedSets.first(where: { $0.sortOrder == setIndex }) {
            return exact
        }

        return orderedSets.last
    }

    func previousSetMap(
        for catalogExerciseUUID: String,
        before date: Date,
        excludingSessionID: UUID?,
        maxSetCount: Int
    ) throws -> [Int: WorkoutPreviousSetSnapshot] {
        guard maxSetCount > 0 else { return [:] }
        let maps = try previousSetMaps(
            forExercises: [catalogExerciseUUID],
            before: date,
            excludingSessionID: excludingSessionID
        )

        guard let baseMap = maps[catalogExerciseUUID], !baseMap.isEmpty else {
            return [:]
        }

        let maxKnownIndex = baseMap.keys.max() ?? 0
        let fallbackSnapshot = baseMap[maxKnownIndex]
        var result: [Int: WorkoutPreviousSetSnapshot] = [:]
        result.reserveCapacity(maxSetCount)

        for index in 0..<maxSetCount {
            if let exact = baseMap[index] {
                result[index] = exact
            } else if let fallbackSnapshot {
                result[index] = fallbackSnapshot
            }
        }

        return result
    }

    func previousSetMaps(
        forExercises catalogExerciseUUIDs: [String],
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [String: [Int: WorkoutPreviousSetSnapshot]] {
        let requested = Set(
            catalogExerciseUUIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !requested.isEmpty else { return [:] }

        let exercisesByCatalogUUID = try latestPreviousExercises(
            forExercises: Array(requested),
            before: date,
            excludingSessionID: excludingSessionID
        )

        return exercisesByCatalogUUID.mapValues { exercise in
            let orderedSets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            return Dictionary(uniqueKeysWithValues: orderedSets.map { set in
                (
                    set.sortOrder,
                    previousSnapshot(from: set)
                )
            })
        }
    }

    func finishSession(sessionID: UUID, notes: String? = nil) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        if let notes {
            session.notes = notes
        }

        session.status = .completed
        let now = Date()
        session.endedAt = now
        session.durationSeconds = max(0, Int((session.endedAt ?? .now).timeIntervalSince(session.startedAt)))
        session.updatedAt = now

        let metrics = WorkoutMetricsService(modelContext: modelContext)
        let projectedFacts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
        let summary = try metrics.sessionSummary(session: session, projectedFacts: projectedFacts)
        session.totalVolume = summary.totalVolume
        session.prHitsCount = summary.prHitsCount
        session.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion

        try modelContext.save()
        invalidateAnalyticsCache()
        scheduleProjectionRebuild(for: sessionID)
        try? CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)?.queueCompletedSessionPublish(sessionID: sessionID)
    }

    func archiveSession(id: UUID) throws {
        guard let session = try session(id: id) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }
        guard session.status == .completed else {
            throw WorkoutSessionRepositoryError.invalidSessionState
        }
        guard session.archivedAt == nil else {
            return
        }

        let now = Date()
        session.archivedAt = now
        session.updatedAt = now
        try modelContext.save()
        invalidateAnalyticsCache()
    }

    func restoreArchivedSession(id: UUID) throws {
        guard let session = try session(id: id) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }
        guard session.status == .completed else {
            throw WorkoutSessionRepositoryError.invalidSessionState
        }
        guard session.archivedAt != nil else {
            return
        }

        session.archivedAt = nil
        session.updatedAt = Date()
        try modelContext.save()
        invalidateAnalyticsCache()
    }

    func cancelSession(sessionID: UUID) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }
        guard session.status == .active else {
            throw WorkoutSessionRepositoryError.invalidSessionState
        }

        modelContext.delete(session)
        try modelContext.save()
        invalidateAnalyticsCache()
    }

    func recalculateSessionSummary(sessionID: UUID) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let now = Date()
        session.updatedAt = now

        let metrics = WorkoutMetricsService(modelContext: modelContext)
        let projectedFacts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
        let summary = try metrics.sessionSummary(session: session, projectedFacts: projectedFacts)
        session.totalVolume = summary.totalVolume
        session.prHitsCount = summary.prHitsCount
        session.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion

        if session.status == .completed {
            let end = session.endedAt ?? .now
            session.durationSeconds = max(0, Int(end.timeIntervalSince(session.startedAt)))
        }

        try modelContext.save()
        invalidateAnalyticsCache()
        scheduleProjectionRebuild(for: sessionID)
    }

    @discardableResult
    func backfillCompletedSessionSummariesIfNeeded() throws -> Int {
        let rebuiltProjectionCount = try historyProjectionRepository.backfillIfNeeded(persistChanges: false)
        let sessions = try completedSessions(includeArchived: true)
        let staleSessions = sessions.filter {
            $0.summaryMetricsVersion < WorkoutMetricsService.currentSummaryMetricsVersion
        }
        guard !staleSessions.isEmpty else {
            if rebuiltProjectionCount > 0 {
                try modelContext.save()
            }
            return 0
        }

        let metrics = WorkoutMetricsService(modelContext: modelContext)

        for session in staleSessions {
            let summary = try metrics.sessionSummary(sessionID: session.id)
            session.totalVolume = summary.totalVolume
            session.prHitsCount = summary.prHitsCount
            session.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion
        }

        try modelContext.save()
        invalidateAnalyticsCache()
        return staleSessions.count
    }

    func hasStaleCompletedSessionSummaries() throws -> Bool {
        let sessions = try completedSessions(includeArchived: true)
        return sessions.contains {
            $0.summaryMetricsVersion < WorkoutMetricsService.currentSummaryMetricsVersion
        }
    }

    func deleteSession(id: UUID) throws {
        guard let session = try session(id: id) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        try? CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)?.queueDeletedSession(sessionID: id)
        try historyProjectionRepository.deleteFacts(forSessionID: id, persistChanges: false)
        modelContext.delete(session)
        try modelContext.save()
        invalidateAnalyticsCache()
    }

    private func template(id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { template in
            template.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func sessionExercise(id: UUID) throws -> WorkoutSessionExercise? {
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate { exercise in
            exercise.id == id
        })
        return try modelContext.fetch(descriptor).first
    }

    private func completedSessions(
        before date: Date?,
        excludingSessionID: UUID?,
        includeArchived: Bool = false
    ) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue

        let descriptor: FetchDescriptor<WorkoutSession>
        switch (date, excludingSessionID) {
        case let (date?, excludingSessionID?):
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                        && session.startedAt < date
                        && session.id != excludingSessionID
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        case let (date?, nil):
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                        && session.startedAt < date
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        case let (nil, excludingSessionID?):
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                        && session.id != excludingSessionID
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        case (nil, nil):
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        }

        let sessions = try modelContext.fetch(descriptor)
        if includeArchived {
            return sessions
        }

        return sessions.filter { $0.archivedAt == nil }
    }

    private func defaultSessionSets(
        sessionExerciseID: UUID,
        restSeconds: Int,
        loadUnit: TemplateLoadUnit,
        sessionExercise: WorkoutSessionExercise
    ) -> [WorkoutSessionSet] {
        let defaults = [0, 1, 2].map { index in
            WorkoutSessionSet(
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

    private func orderedTemplateCardioBlocks(_ template: WorkoutTemplate) -> [TemplateCardioBlock] {
        (template.cardioBlocks ?? [])
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func previousSnapshot(from set: WorkoutSessionSet) -> WorkoutPreviousSetSnapshot {
        let chosenWeight = set.actualWeight ?? set.targetWeight
        let chosenReps = set.actualReps ?? set.targetReps
        let chosenUnit = set.actualWeight != nil ? set.actualLoadUnit : set.targetLoadUnit
        return WorkoutPreviousSetSnapshot(reps: chosenReps, weight: chosenWeight, unit: chosenUnit)
    }

    private func latestPreviousExercises(
        forExercises catalogExerciseUUIDs: [String],
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [String: WorkoutSessionExercise] {
        let requested = Set(
            catalogExerciseUUIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !requested.isEmpty else { return [:] }

        var latestSessionIDByExercise = try latestProjectedSessionIDs(
            forExercises: requested,
            before: date,
            excludingSessionID: excludingSessionID
        )

        let canonicalSessionIDs = try latestCanonicalSessionIDs(
            forExercises: requested,
            before: date,
            excludingSessionID: excludingSessionID
        )
        for (catalogExerciseUUID, sessionID) in canonicalSessionIDs {
            latestSessionIDByExercise[catalogExerciseUUID] = sessionID
        }

        guard !latestSessionIDByExercise.isEmpty else { return [:] }

        var exercisesBySessionID: [UUID: [WorkoutSessionExercise]] = [:]
        for sessionID in Set(latestSessionIDByExercise.values) {
            exercisesBySessionID[sessionID] = try sessionExercises(sessionID: sessionID)
        }

        var resolved: [String: WorkoutSessionExercise] = [:]
        resolved.reserveCapacity(latestSessionIDByExercise.count)

        for (catalogExerciseUUID, sessionID) in latestSessionIDByExercise {
            guard let exercises = exercisesBySessionID[sessionID] else { continue }
            let chosenExercise = exercises
                .filter { $0.catalogExerciseUUID == catalogExerciseUUID }
                .sorted { $0.sortOrder < $1.sortOrder }
                .first
            if let chosenExercise {
                resolved[catalogExerciseUUID] = chosenExercise
            }
        }

        return resolved
    }

    private func latestProjectedSessionIDs(
        forExercises requested: Set<String>,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [String: UUID] {
        let facts = try historyProjectionRepository.allFacts()
        let visibleSessionIDs = Set(
            try completedSessions(
                before: date,
                excludingSessionID: excludingSessionID,
                includeArchived: false
            ).map(\.id)
        )
        guard !visibleSessionIDs.isEmpty else { return [:] }
        var chosenSessionByExercise: [String: UUID] = [:]

        for fact in facts {
            guard requested.contains(fact.catalogExerciseUUID) else { continue }
            guard visibleSessionIDs.contains(fact.sessionID) else { continue }
            if let excludingSessionID, fact.sessionID == excludingSessionID {
                continue
            }
            guard fact.completedAt < date else { continue }
            guard chosenSessionByExercise[fact.catalogExerciseUUID] == nil else { continue }
            chosenSessionByExercise[fact.catalogExerciseUUID] = fact.sessionID
        }

        return chosenSessionByExercise
    }

    private func latestCanonicalSessionIDs(
        forExercises requested: Set<String>,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [String: UUID] {
        guard !requested.isEmpty else { return [:] }

        let sessions = try completedSessions(before: date, excludingSessionID: excludingSessionID)
        var chosenSessionByExercise: [String: UUID] = [:]

        for session in sessions {
            for exercise in orderedSessionExercises(session) {
                guard requested.contains(exercise.catalogExerciseUUID) else { continue }
                guard chosenSessionByExercise[exercise.catalogExerciseUUID] == nil else { continue }
                chosenSessionByExercise[exercise.catalogExerciseUUID] = session.id
            }

            if chosenSessionByExercise.count == requested.count {
                break
            }
        }

        return chosenSessionByExercise
    }

    private func orderedSessionExercises(_ session: WorkoutSession) -> [WorkoutSessionExercise] {
        (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private func apply(
        draft: WorkoutSessionSetDraft,
        to set: WorkoutSessionSet,
        sortOrder: Int
    ) -> Bool {
        let normalizedRest = sanitizedRest(draft.restSeconds)
        let normalizedTargetReps = sanitizedReps(draft.targetReps)
        let normalizedTargetWeight = sanitizedWeight(draft.targetWeight)
        let normalizedActualReps = sanitizedReps(draft.actualReps)
        let normalizedActualWeight = sanitizedWeight(draft.actualWeight)
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
        if set.actualWeight != normalizedActualWeight {
            set.actualWeight = normalizedActualWeight
            didChange = true
        }
        if set.actualLoadUnit != draft.actualLoadUnit {
            set.actualLoadUnit = draft.actualLoadUnit
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

        return didChange
    }
}
