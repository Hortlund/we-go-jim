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
}

enum WorkoutSessionRepositoryError: Error {
    case sessionNotFound
    case sessionExerciseNotFound
    case sessionSetNotFound
    case templateNotFound
    case invalidSessionState
}

@MainActor
final class WorkoutSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createEmptySession(name: String = "Empty Workout") throws -> WorkoutSession {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = WorkoutSession(name: cleanedName.isEmpty ? "Empty Workout" : cleanedName)
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    func createSessionFromTemplate(templateID: UUID) throws -> WorkoutSession {
        guard let template = try template(id: templateID) else {
            throw WorkoutSessionRepositoryError.templateNotFound
        }

        let session = WorkoutSession(templateID: template.id, name: template.name)
        modelContext.insert(session)

        let orderedExercises = (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        for (exerciseIndex, templateExercise) in orderedExercises.enumerated() {
            let exercise = WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: templateExercise.catalogExerciseUUID,
                exerciseNameSnapshot: templateExercise.exerciseNameSnapshot,
                categorySnapshot: templateExercise.categorySnapshot,
                muscleSummarySnapshot: templateExercise.muscleSummarySnapshot,
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
                createdSets = defaultSessionSets(sessionExerciseID: exercise.id, restSeconds: exercise.restSeconds, sessionExercise: exercise)
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
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first(where: { $0.status == .active })
    }

    func completedSessions() throws -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).filter { $0.status == .completed }
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

        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

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
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            restSeconds: sanitizedRest(restSeconds),
            sortOrder: nextIndex,
            session: session
        )
        modelContext.insert(created)

        let sets = defaultSessionSets(sessionExerciseID: created.id, restSeconds: created.restSeconds, sessionExercise: created)
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

        let previousDefaultRest = exercise.restSeconds
        let normalizedRest = sanitizedRest(restSeconds)
        exercise.restSeconds = normalizedRest
        for set in exercise.sets ?? [] where set.restSeconds == previousDefaultRest {
            set.restSeconds = normalizedRest
            set.updatedAt = .now
        }
        exercise.updatedAt = .now
        exercise.session?.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseRepRange(sessionExerciseID: UUID, minReps: Int?, maxReps: Int?) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let normalized = sanitizedRepRange(min: minReps, max: maxReps)
        exercise.targetRepMin = normalized.min
        exercise.targetRepMax = normalized.max
        exercise.updatedAt = .now
        exercise.session?.updatedAt = .now
        try modelContext.save()
    }

    func addSet(sessionExerciseID: UUID) throws {
        guard let exercise = try sessionExercise(id: sessionExerciseID) else {
            throw WorkoutSessionRepositoryError.sessionExerciseNotFound
        }

        let ordered = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let nextSort = (ordered.last?.sortOrder ?? -1) + 1
        let newSet = WorkoutSessionSet(
            sessionExerciseID: exercise.id,
            sortOrder: nextSort,
            isWarmup: false,
            restSeconds: sanitizedRest(ordered.last?.restSeconds ?? exercise.restSeconds),
            targetReps: ordered.last?.targetReps,
            targetWeight: ordered.last?.targetWeight,
            targetLoadUnit: ordered.last?.targetLoadUnit ?? .kg,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: ordered.last?.actualLoadUnit ?? .kg,
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
        let incomingIDs = Set(drafts.map(\.id))

        for set in existing where !incomingIDs.contains(set.id) {
            modelContext.delete(set)
        }

        var updatedSets: [WorkoutSessionSet] = []
        for (index, draft) in drafts.enumerated() {
            let set = existing.first(where: { $0.id == draft.id }) ?? WorkoutSessionSet(
                id: draft.id,
                sessionExerciseID: sessionExerciseID,
                sessionExercise: exercise
            )

            if set.modelContext == nil {
                modelContext.insert(set)
            }

            set.sortOrder = index
            set.isWarmup = draft.isWarmup
            set.restSeconds = sanitizedRest(draft.restSeconds)
            set.targetReps = sanitizedReps(draft.targetReps)
            set.targetWeight = sanitizedWeight(draft.targetWeight)
            set.targetLoadUnit = draft.targetLoadUnit
            set.actualReps = sanitizedReps(draft.actualReps)
            set.actualWeight = sanitizedWeight(draft.actualWeight)
            set.actualLoadUnit = draft.actualLoadUnit
            set.isCompleted = draft.isCompleted
            set.isLocked = draft.isLocked
            set.updatedAt = .now
            updatedSets.append(set)
        }

        exercise.sets = updatedSets
        exercise.updatedAt = .now
        if let parent = exercise.session {
            parent.updatedAt = .now
        }

        try modelContext.save()
    }

    func previousSet(
        for catalogExerciseUUID: String,
        setIndex: Int,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> WorkoutSessionSet? {
        let sessions = try completedSessions()

        for session in sessions {
            if let excludingSessionID, session.id == excludingSessionID {
                continue
            }

            let referenceDate = session.endedAt ?? session.startedAt
            if referenceDate >= date {
                continue
            }

            let exercises = (session.exercises ?? [])
                .filter { $0.catalogExerciseUUID == catalogExerciseUUID }
                .sorted { $0.sortOrder < $1.sortOrder }

            guard let firstExercise = exercises.first else { continue }
            let sets = (firstExercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            guard !sets.isEmpty else { continue }

            if sets.indices.contains(setIndex) {
                return sets[setIndex]
            }

            if let fallback = sets.last {
                return fallback
            }
        }

        return nil
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

        let sessions = try completedSessions()
        var remaining = requested
        var results: [String: [Int: WorkoutPreviousSetSnapshot]] = [:]

        for session in sessions {
            if let excludingSessionID, session.id == excludingSessionID {
                continue
            }

            let referenceDate = session.endedAt ?? session.startedAt
            if referenceDate >= date {
                continue
            }

            let exercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
            for exercise in exercises where remaining.contains(exercise.catalogExerciseUUID) {
                let sets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
                guard !sets.isEmpty else { continue }

                var perIndex: [Int: WorkoutPreviousSetSnapshot] = [:]
                perIndex.reserveCapacity(sets.count)

                for (index, set) in sets.enumerated() {
                    perIndex[index] = previousSnapshot(from: set)
                }

                if !perIndex.isEmpty {
                    results[exercise.catalogExerciseUUID] = perIndex
                    remaining.remove(exercise.catalogExerciseUUID)
                }
            }

            if remaining.isEmpty {
                break
            }
        }

        return results
    }

    func finishSession(sessionID: UUID, notes: String? = nil) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        if let notes {
            session.notes = notes
        }

        session.status = .completed
        session.endedAt = .now
        session.durationSeconds = max(0, Int((session.endedAt ?? .now).timeIntervalSince(session.startedAt)))

        let metrics = WorkoutMetricsService(modelContext: modelContext)
        session.totalVolume = try metrics.totalVolume(sessionID: sessionID)
        session.prHitsCount = try metrics.countPRHits(sessionID: sessionID)
        session.updatedAt = .now

        try modelContext.save()
        try? CloudKitBrosSocialService(modelContext: modelContext).queueCompletedSessionPublish(sessionID: sessionID)
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
    }

    func recalculateSessionSummary(sessionID: UUID) throws {
        guard let session = try session(id: sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let metrics = WorkoutMetricsService(modelContext: modelContext)
        session.totalVolume = try metrics.totalVolume(sessionID: sessionID)
        session.prHitsCount = try metrics.countPRHits(sessionID: sessionID)

        if session.status == .completed {
            let end = session.endedAt ?? .now
            session.durationSeconds = max(0, Int(end.timeIntervalSince(session.startedAt)))
        }

        session.updatedAt = .now
        try modelContext.save()
    }

    func deleteSession(id: UUID) throws {
        guard let session = try session(id: id) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        try? CloudKitBrosSocialService(modelContext: modelContext).queueDeletedSession(sessionID: id)
        modelContext.delete(session)
        try modelContext.save()
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

    private func defaultSessionSets(
        sessionExerciseID: UUID,
        restSeconds: Int,
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
                targetLoadUnit: .kg,
                actualReps: nil,
                actualWeight: nil,
                actualLoadUnit: .kg,
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

    private func previousSnapshot(from set: WorkoutSessionSet) -> WorkoutPreviousSetSnapshot {
        let chosenWeight = set.actualWeight ?? set.targetWeight
        let chosenReps = set.actualReps ?? set.targetReps
        let chosenUnit = set.actualWeight != nil ? set.actualLoadUnit : set.targetLoadUnit
        return WorkoutPreviousSetSnapshot(reps: chosenReps, weight: chosenWeight, unit: chosenUnit)
    }
}
