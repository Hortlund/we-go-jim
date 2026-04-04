import Foundation
import SwiftData

@MainActor
final class HistoryProjectionRepository {
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

        let drafts = makeFactDrafts(from: session)
        let existingFacts = try facts(forSessionID: sessionID)
        let didChange = apply(drafts: drafts, to: existingFacts, sessionID: sessionID)

        if didChange, persistChanges {
            try modelContext.save()
        }

        return didChange ? drafts.count : 0
    }

    @discardableResult
    func deleteFacts(forSessionID sessionID: UUID, persistChanges: Bool = true) throws -> Int {
        let existingFacts = try facts(forSessionID: sessionID)
        guard !existingFacts.isEmpty else { return 0 }

        for fact in existingFacts {
            modelContext.delete(fact)
        }

        if persistChanges {
            try modelContext.save()
        }

        return existingFacts.count
    }

    @discardableResult
    func backfillIfNeeded(persistChanges: Bool = true) throws -> Int {
        let completedSessions = try sessionRepository.completedSessions()
        let validSessionIDs = Set(completedSessions.map(\.id))
        let existingFacts = try allFacts()
        let factsBySessionID = Dictionary(grouping: existingFacts, by: \.sessionID)
        var rebuiltSessions = 0
        var didMutate = false

        for fact in existingFacts where !validSessionIDs.contains(fact.sessionID) {
            modelContext.delete(fact)
            didMutate = true
        }

        for session in completedSessions {
            let drafts = makeFactDrafts(from: session)
            let existing = factsBySessionID[session.id] ?? []
            guard !factsMatch(existing, drafts: drafts) else { continue }

            if apply(drafts: drafts, to: existing, sessionID: session.id) {
                rebuiltSessions += 1
                didMutate = true
            }
        }

        if didMutate, persistChanges {
            try modelContext.save()
        }

        return rebuiltSessions
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

    private func apply(
        drafts: [CompletedSetFactDraft],
        to existingFacts: [CompletedSetFact],
        sessionID: UUID
    ) -> Bool {
        let existingBySessionSetID = Dictionary(uniqueKeysWithValues: existingFacts.map { ($0.sessionSetID, $0) })
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
        let existingBySessionSetID = Dictionary(uniqueKeysWithValues: existingFacts.map { ($0.sessionSetID, $0) })

        for draft in drafts {
            guard let existing = existingBySessionSetID[draft.sessionSetID], draft.matches(existing) else {
                return false
            }
        }

        return true
    }

    private func makeFactDrafts(from session: WorkoutSession) -> [CompletedSetFactDraft] {
        let completedAt = session.endedAt ?? session.startedAt
        let sourceSessionUpdatedAt = projectionSourceUpdatedAt(for: session)
        let orderedExercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }

        return orderedExercises.flatMap { exercise in
            let orderedSets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            return orderedSets.compactMap { set in
                makeFactDraft(
                    from: set,
                    session: session,
                    exercise: exercise,
                    completedAt: completedAt,
                    sourceSessionUpdatedAt: sourceSessionUpdatedAt
                )
            }
        }
    }

    private func makeFactDraft(
        from set: WorkoutSessionSet,
        session: WorkoutSession,
        exercise: WorkoutSessionExercise,
        completedAt: Date,
        sourceSessionUpdatedAt: Date
    ) -> CompletedSetFactDraft? {
        guard set.isCompleted, let reps = set.actualReps, reps > 0 else {
            return nil
        }

        switch set.actualLoadUnit {
        case .kg, .lb:
            guard let weight = set.actualWeight, weight > 0 else {
                return nil
            }

            let normalizedWeightKg = normalizedLoad(weight, unit: set.actualLoadUnit)
            let estimatedOneRepMaxKg = normalizedLoad(
                estimatedOneRepMax(weight: weight, reps: reps),
                unit: set.actualLoadUnit
            )

            return CompletedSetFactDraft(
                sessionSetID: set.id,
                sessionID: session.id,
                sessionExerciseID: exercise.id,
                templateID: session.templateID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                completedAt: completedAt,
                setIndex: set.sortOrder,
                isWarmup: set.isWarmup,
                reps: reps,
                weight: weight,
                loadUnit: set.actualLoadUnit,
                normalizedWeightKg: normalizedWeightKg,
                estimatedOneRepMaxKg: estimatedOneRepMaxKg,
                volumeKg: normalizedWeightKg * Double(reps),
                sourceSessionUpdatedAt: sourceSessionUpdatedAt
            )

        case .bodyweight:
            return CompletedSetFactDraft(
                sessionSetID: set.id,
                sessionID: session.id,
                sessionExerciseID: exercise.id,
                templateID: session.templateID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                completedAt: completedAt,
                setIndex: set.sortOrder,
                isWarmup: set.isWarmup,
                reps: reps,
                weight: nil,
                loadUnit: .bodyweight,
                normalizedWeightKg: nil,
                estimatedOneRepMaxKg: nil,
                volumeKg: nil,
                sourceSessionUpdatedAt: sourceSessionUpdatedAt
            )
        }
    }

    private func projectionSourceUpdatedAt(for session: WorkoutSession) -> Date {
        var latest = session.updatedAt

        for exercise in session.exercises ?? [] {
            latest = max(latest, exercise.updatedAt)
            for set in exercise.sets ?? [] {
                latest = max(latest, set.updatedAt)
            }
        }

        return latest
    }

    private func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    private func normalizedLoad(_ value: Double, unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .kg:
            return value
        case .lb:
            return value * 0.45359237
        case .bodyweight:
            return value
        }
    }
}

private struct CompletedSetFactDraft: Equatable {
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

    func makeModel() -> CompletedSetFact {
        CompletedSetFact(
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
    }

    func matches(_ fact: CompletedSetFact) -> Bool {
        fact.sessionSetID == sessionSetID
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
