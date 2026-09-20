import Foundation
import SwiftData

nonisolated final class HistoryProjectionRepository {
    static let currentVersion = 5
    private let modelContext: ModelContext
    private let sessionRepository: WorkoutSessionRepository

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
    }

    @discardableResult
    func rebuildFacts(forSessionID sessionID: UUID, persistChanges: Bool = true) throws -> Int {
        guard let session = try sessionRepository.session(id: sessionID), session.status == .completed else {
            return try deleteFacts(forSessionID: sessionID, persistChanges: persistChanges)
        }

        let drafts = try HistoryProjectionSnapshotBuilder.projectedFacts(
            from: session,
            repository: sessionRepository
        )
        let existingFacts = try facts(forSessionID: sessionID)
        var didChange = apply(drafts: drafts, to: existingFacts, sessionID: sessionID)
        let summaries = try modelContext.fetch(FetchDescriptor<ExerciseSessionSummary>(predicate: #Predicate { $0.sessionID == sessionID }))
        let projected = drafts.map { $0.makeModel() }
        let oldCardio = try modelContext.fetch(FetchDescriptor<CompletedCardioFact>(predicate: #Predicate { $0.sessionID == sessionID }))
        let activities = try sessionRepository.sessionCardioBlocks(sessionID: sessionID).filter { $0.isCompleted && ($0.actualDurationSeconds ?? 0) > 0 }
        let oldByID = Dictionary(oldCardio.map { ($0.activityID, $0) }, uniquingKeysWith: { first, _ in first })
        let activityIDs = Set(activities.map(\.id))
        for old in oldCardio where !activityIDs.contains(old.activityID) { modelContext.delete(old); didChange = true }
        var cardio: [CompletedCardioFact] = []
        for activity in activities {
            if let old = oldByID[activity.id] {
                let duration = Double(activity.actualDurationSeconds ?? 0)
                let date = session.endedAt ?? session.startedAt
                if old.durationSeconds != duration || old.distanceMeters != activity.actualDistanceMeters
                    || old.completedAt != date || old.isArchived != (session.archivedAt != nil)
                    || old.exerciseName != activity.exerciseNameSnapshot || old.catalogExerciseUUID != activity.catalogExerciseUUID {
                    old.durationSeconds = duration; old.distanceMeters = activity.actualDistanceMeters
                    old.completedAt = date; old.isArchived = session.archivedAt != nil
                    old.exerciseName = activity.exerciseNameSnapshot; old.catalogExerciseUUID = activity.catalogExerciseUUID
                    didChange = true
                }
                cardio.append(old)
            } else {
                let fact = CompletedCardioFact(activity: activity, session: session)
                modelContext.insert(fact); cardio.append(fact); didChange = true
            }
        }
        let entries = ExerciseHistorySummaryBuilder.entries(facts: projected, cardio: cardio)
        let existingByExercise = Dictionary(summaries.map { ($0.catalogExerciseUUID, $0) }, uniquingKeysWith: { first, _ in first })
        for row in summaries where entries[row.catalogExerciseUUID] == nil {
            modelContext.delete(row)
            didChange = true
        }
        for (exerciseUUID, entry) in entries {
            let payload = try BackupArchiveCodec.json(entry)
            if let row = existingByExercise[exerciseUUID] {
                if row.payload != payload || row.sourceUpdatedAt != session.updatedAt || row.isArchived != (session.archivedAt != nil) {
                    row.payload = payload
                    row.oneRepMax = entry.weightedOneRepMaxInKilograms
                    row.maxWeight = entry.maxWeightInKilograms
                    row.volume = entry.totalWeightedVolumeInKilograms
                    row.maxReps = entry.maxReps
                    row.completedAt = entry.completedAt
                    row.sourceUpdatedAt = session.updatedAt
                    row.isArchived = session.archivedAt != nil
                    didChange = true
                }
            } else {
                modelContext.insert(try ExerciseSessionSummary(entry: entry, exerciseUUID: exerciseUUID, session: session))
                didChange = true
            }
        }
        for fact in try facts(forSessionID: sessionID) {
            if fact.isArchived != (session.archivedAt != nil) {
                fact.isArchived = session.archivedAt != nil
                didChange = true
            }
        }
        if session.projectionVersion != Self.currentVersion || session.projectionSourceUpdatedAt != session.updatedAt {
            session.projectionVersion = Self.currentVersion
            session.projectionSourceUpdatedAt = session.updatedAt
            didChange = true
        }

        if didChange, persistChanges {
            try modelContext.saveWithRecoveryProtection()
        }
        if didChange {
            HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
        }

        return didChange ? max(1, drafts.count) : 0
    }

    @discardableResult
    func deleteFacts(forSessionID sessionID: UUID, persistChanges: Bool = true) throws -> Int {
        let existingFacts = try facts(forSessionID: sessionID)
        let summaries = try modelContext.fetch(FetchDescriptor<ExerciseSessionSummary>(predicate: #Predicate { $0.sessionID == sessionID }))
        let cardio = try modelContext.fetch(FetchDescriptor<CompletedCardioFact>(predicate: #Predicate { $0.sessionID == sessionID }))
        guard !existingFacts.isEmpty || !summaries.isEmpty || !cardio.isEmpty else { return 0 }
        for row in cardio { modelContext.delete(row) }
        for row in summaries { modelContext.delete(row) }

        for fact in existingFacts {
            modelContext.delete(fact)
        }

        if persistChanges {
            try modelContext.saveWithRecoveryProtection()
        }
        HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)

        return existingFacts.count
    }

    @discardableResult
    func backfillIfNeeded(persistChanges: Bool = true) throws -> Int {
        let checkpoint = try modelContext.fetch(FetchDescriptor<HistoryProjectionCheckpoint>()).first
        if checkpoint == nil {
            // First upgrade, or disposable projection store was removed. Only headers are touched.
            for session in try sessionRepository.completedSessions(includeArchived: true) {
                session.projectionVersion = 0
            }
            modelContext.insert(HistoryProjectionCheckpoint(version: Self.currentVersion))
        }
        var count = 0
        while true {
            let sessions = try staleSessions(limit: 100)
            guard !sessions.isEmpty else { break }
            for session in sessions {
                _ = try rebuildFacts(forSessionID: session.id, persistChanges: false)
                count += 1
            }
            if persistChanges, modelContext.hasChanges { try modelContext.saveWithRecoveryProtection() }
        }
        if let checkpoint, checkpoint.version != Self.currentVersion { checkpoint.version = Self.currentVersion }
        if persistChanges, modelContext.hasChanges { try modelContext.saveWithRecoveryProtection() }
        return count
    }

    func needsBackfill() throws -> Bool {
        if try !staleSessions(limit: 1).isEmpty { return true }
        if try modelContext.fetchCount(FetchDescriptor<HistoryProjectionCheckpoint>()) == 0 {
            let completed = WorkoutSessionStatus.completed.rawValue
            return try modelContext.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == completed })) > 0
        }
        return false
    }

    private func staleSessions(limit: Int) throws -> [WorkoutSession] {
        let completed = WorkoutSessionStatus.completed.rawValue
        let version = Self.currentVersion
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate {
            $0.statusRaw == completed && ($0.projectionVersion < version || $0.projectionSourceUpdatedAt != $0.updatedAt)
        })
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func facts(forSessionID sessionID: UUID) throws -> [CompletedSetFact] {
        let descriptor = FetchDescriptor<CompletedSetFact>(
            predicate: #Predicate { fact in
                fact.sessionID == sessionID
            },
            sortBy: [
                SortDescriptor(\CompletedSetFact.sessionExerciseID, order: .forward),
                SortDescriptor(\CompletedSetFact.setIndex, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func allFacts() throws -> [CompletedSetFact] {
        let descriptor = FetchDescriptor<CompletedSetFact>(
            sortBy: [
                SortDescriptor(\CompletedSetFact.completedAt, order: .reverse),
                SortDescriptor(\CompletedSetFact.catalogExerciseUUID, order: .forward),
                SortDescriptor(\CompletedSetFact.sessionID, order: .forward),
                SortDescriptor(\CompletedSetFact.setIndex, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func facts(forExercises exerciseUUIDs: Set<String>) throws -> [CompletedSetFact] {
        guard !exerciseUUIDs.isEmpty else { return [] }
        let requested = Array(exerciseUUIDs)
        let descriptor = FetchDescriptor<CompletedSetFact>(
            predicate: #Predicate { fact in
                requested.contains(fact.catalogExerciseUUID)
            },
            sortBy: [
                SortDescriptor(\CompletedSetFact.completedAt, order: .reverse),
                SortDescriptor(\CompletedSetFact.catalogExerciseUUID, order: .forward),
                SortDescriptor(\CompletedSetFact.sessionID, order: .forward),
                SortDescriptor(\CompletedSetFact.setIndex, order: .forward),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func apply(
        drafts: [CompletedSetFactDraft],
        to existingFacts: [CompletedSetFact],
        sessionID: UUID
    ) -> Bool {
        let existingBySessionSetID = Dictionary(
            existingFacts.map { ($0.sessionSetID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let incomingIDs = Set(drafts.map(\.sessionSetID))
        var didMutate = false

        for fact in existingFacts where !incomingIDs.contains(fact.sessionSetID) {
            modelContext.delete(fact)
            didMutate = true
        }

        for draft in drafts {
            if let existing = existingBySessionSetID[draft.sessionSetID] {
                if update(existing, with: draft) {
                    didMutate = true
                }
            } else {
                modelContext.insert(draft.makeModel())
                didMutate = true
            }
        }

        return didMutate
    }

    private func update(_ fact: CompletedSetFact, with draft: CompletedSetFactDraft) -> Bool {
        guard !draft.matches(fact) else { return false }

        fact.parentSetID = draft.parentSetID
        fact.muscleSummarySnapshot = draft.muscleSummarySnapshot
        fact.sessionID = draft.sessionID
        fact.sessionExerciseID = draft.sessionExerciseID
        fact.templateID = draft.templateID
        fact.catalogExerciseUUID = draft.catalogExerciseUUID
        fact.exerciseNameSnapshot = draft.exerciseNameSnapshot
        fact.completedAt = draft.completedAt
        fact.setIndex = draft.setIndex
        fact.isWarmup = draft.isWarmup
        fact.reps = draft.reps
        fact.weight = draft.weight
        fact.loadUnit = draft.loadUnit
        fact.normalizedWeightKg = draft.normalizedWeightKg
        fact.estimatedOneRepMaxKg = draft.estimatedOneRepMaxKg
        fact.volumeKg = draft.volumeKg
        fact.sourceSessionUpdatedAt = draft.sourceSessionUpdatedAt
        return true
    }

    private func factsMatch(_ existingFacts: [CompletedSetFact], drafts: [CompletedSetFactDraft]) -> Bool {
        guard existingFacts.count == drafts.count else { return false }
        let existingBySessionSetID = Dictionary(
            existingFacts.map { ($0.sessionSetID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        for draft in drafts {
            guard let existing = existingBySessionSetID[draft.sessionSetID], draft.matches(existing) else {
                return false
            }
        }

        return true
    }

}

nonisolated struct CompletedSetFactDraft: Equatable, Sendable {
    let sessionSetID: UUID
    let sessionID: UUID
    let sessionExerciseID: UUID
    let templateID: UUID?
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let completedAt: Date
    let setIndex: Int
    let isWarmup: Bool
    let reps: Int
    let weight: Double?
    let loadUnit: TemplateLoadUnit
    let normalizedWeightKg: Double?
    let estimatedOneRepMaxKg: Double?
    let volumeKg: Double?
    let sourceSessionUpdatedAt: Date
    var muscleSummarySnapshot: String = ""
    var parentSetID: UUID? = nil

    nonisolated func makeModel() -> CompletedSetFact {
        let model = CompletedSetFact(
            sessionSetID: sessionSetID,
            sessionID: sessionID,
            sessionExerciseID: sessionExerciseID,
            templateID: templateID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            completedAt: completedAt,
            setIndex: setIndex,
            isWarmup: isWarmup,
            reps: reps,
            weight: weight,
            loadUnit: loadUnit,
            normalizedWeightKg: normalizedWeightKg,
            estimatedOneRepMaxKg: estimatedOneRepMaxKg,
            volumeKg: volumeKg,
            sourceSessionUpdatedAt: sourceSessionUpdatedAt
        )
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.parentSetID = parentSetID
        return model
    }

    nonisolated func matches(_ fact: CompletedSetFact) -> Bool {
        fact.parentSetID == parentSetID
            && fact.muscleSummarySnapshot == muscleSummarySnapshot
            && fact.sessionSetID == sessionSetID
            && fact.sessionID == sessionID
            && fact.sessionExerciseID == sessionExerciseID
            && fact.templateID == templateID
            && fact.catalogExerciseUUID == catalogExerciseUUID
            && fact.exerciseNameSnapshot == exerciseNameSnapshot
            && fact.completedAt == completedAt
            && fact.setIndex == setIndex
            && fact.isWarmup == isWarmup
            && fact.reps == reps
            && fact.weight == weight
            && fact.loadUnit == loadUnit
            && fact.normalizedWeightKg == normalizedWeightKg
            && fact.estimatedOneRepMaxKg == estimatedOneRepMaxKg
            && fact.volumeKg == volumeKg
            && fact.sourceSessionUpdatedAt == sourceSessionUpdatedAt
    }
}
