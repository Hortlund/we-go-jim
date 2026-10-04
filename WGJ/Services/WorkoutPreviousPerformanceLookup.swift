import Foundation
import SwiftData

nonisolated struct WorkoutPreviousPerformanceRequest: Sendable {
    let id: UUID
    let catalogExerciseUUID: String
    let templateExerciseID: UUID?
    let drafts: [WorkoutSessionSetDraft]
}

nonisolated struct WorkoutPreviousWorkoutSource: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let date: Date
    let sets: [Int: WorkoutPreviousSetSnapshot]
}

/// Immutable history retained for remapping after local set-layout edits, without another fetch.
nonisolated struct WorkoutPreviousPerformanceHistory: Equatable, Sendable {
    struct Sets: Equatable, Sendable {
        let warmups: [Int: WorkoutPreviousSetSnapshot]
        let working: [Int: WorkoutPreviousSetSnapshot]

        func matching(_ warmupFlags: [Bool]) -> [Int: WorkoutPreviousSetSnapshot] {
            var warmupIndex = 0
            var workingIndex = 0
            var result: [Int: WorkoutPreviousSetSnapshot] = [:]
            for (index, isWarmup) in warmupFlags.enumerated() {
                result[index] = isWarmup ? warmups[warmupIndex] : working[workingIndex]
                if isWarmup { warmupIndex += 1 } else { workingIndex += 1 }
            }
            return result
        }
    }

    struct Session: Equatable, Sendable {
        let id: UUID
        let name: String
        let date: Date
        let isPrimary: Bool
        let candidates: [Sets]
    }

    let initialWarmupFlags: [Bool]
    let usesTemplate: Bool
    let sessions: [Session]

    func resolve(warmupFlags: [Bool]) -> WorkoutPreviousPerformanceResolution {
        var previous: [Int: WorkoutPreviousSetSnapshot] = [:]
        var alternate: WorkoutPreviousWorkoutSource?
        for session in sessions {
            for candidate in session.candidates {
                let map = candidate.matching(warmupFlags)
                guard !map.isEmpty else { continue }
                if session.isPrimary {
                    previous.merge(map) { current, _ in current }
                } else if alternate == nil {
                    alternate = WorkoutPreviousWorkoutSource(id: session.id, name: session.name,
                        date: session.date, sets: map)
                }
                break
            }
            if previous.count == warmupFlags.count { break }
        }
        return previous.isEmpty && usesTemplate ? .noTemplateHistory(alternate) : .resolved(previous)
    }
}

/// Reads canonical completed sets. Empty sessions and unfinished sets cannot erase a reference.
nonisolated struct WorkoutPreviousPerformanceLookup {
    let modelContext: ModelContext

    func load(requests: [WorkoutPreviousPerformanceRequest], templateID: UUID?, before date: Date,
              excludingSessionID: UUID) throws -> [UUID: WorkoutPreviousPerformanceResolution] {
        guard !requests.isEmpty else { return [:] }
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        let sessions = try repository.completedSessions(before: date, limit: Int.max)
            .filter { $0.id != excludingSessionID }
        let sessionIDs = Set(sessions.map(\.id))
        let catalogIDs = Array(Set(requests.map(\.catalogExerciseUUID)))
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate {
            catalogIDs.contains($0.catalogExerciseUUID)
        })
        let exercises = try modelContext.fetch(descriptor).filter { sessionIDs.contains($0.sessionID) }
        let exercisesBySession = Dictionary(grouping: exercises, by: \.sessionID)
            .mapValues { Dictionary(grouping: $0, by: \.catalogExerciseUUID) }
        let setsByExercise = Dictionary(grouping: try repository.sessionSets(sessionExerciseIDs: Set(exercises.map(\.id))),
                                        by: \.sessionExerciseID)
        // Repeated slots share canonical history, but retain their own template-slot
        // preference. Sort and normalize each historical set collection just once.
        let snapshotsByExercise = setsByExercise.mapValues(Self.snapshots(sets:))
        var result: [UUID: WorkoutPreviousPerformanceResolution] = [:]
        for request in requests {
            var historySessions: [WorkoutPreviousPerformanceHistory.Session] = []
            for session in sessions {
                let matching = exercisesBySession[session.id]?[request.catalogExerciseUUID, default: []] ?? []
                let ordered = matching
                    .sorted {
                        let lhsMatches = request.templateExerciseID != nil && $0.templateExerciseID == request.templateExerciseID
                        let rhsMatches = request.templateExerciseID != nil && $1.templateExerciseID == request.templateExerciseID
                        if lhsMatches != rhsMatches { return lhsMatches }
                        if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                // Repeated exercise slots retain their own history when the slot still exists.
                let candidates = ordered.contains { request.templateExerciseID != nil && $0.templateExerciseID == request.templateExerciseID }
                    ? ordered.filter { $0.templateExerciseID == request.templateExerciseID } : ordered
                let snapshots = candidates.compactMap { snapshotsByExercise[$0.id] }
                    .filter { !$0.warmups.isEmpty || !$0.working.isEmpty }
                guard !snapshots.isEmpty else { continue }
                historySessions.append(.init(id: session.id, name: session.name,
                    date: session.endedAt ?? session.startedAt,
                    isPrimary: templateID == nil || session.templateID == templateID, candidates: snapshots))
            }
            let history = WorkoutPreviousPerformanceHistory(initialWarmupFlags: request.drafts.map(\.isWarmup),
                usesTemplate: templateID != nil, sessions: historySessions)
            result[request.id] = .remappable(history.resolve(warmupFlags: history.initialWarmupFlags), history)
        }
        return result
    }

    /// Keep ordinal gaps and every historical row, including rows added to the draft later.
    private static func snapshots(sets: [WorkoutSessionSet]) -> WorkoutPreviousPerformanceHistory.Sets {
        var warmups: [Int: WorkoutPreviousSetSnapshot] = [:]
        var working: [Int: WorkoutPreviousSetSnapshot] = [:]
        var warmupIndex = 0
        var workingIndex = 0
        for set in sets.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let ordinal = set.isWarmup ? warmupIndex : workingIndex
            if set.isWarmup { warmupIndex += 1 } else { workingIndex += 1 }
            guard set.isCompleted, let reps = set.actualReps, reps > 0 else { continue }
            let load = WorkoutLoggedLoadNormalization.resolved(actualWeight: set.actualWeight,
                actualLoadUnit: set.actualLoadUnit, targetLoadUnit: set.targetLoadUnit)
            let snapshot = WorkoutPreviousSetSnapshot(reps: reps, weight: load.weight, unit: load.unit)
            if set.isWarmup { warmups[ordinal] = snapshot } else { working[ordinal] = snapshot }
        }
        return .init(warmups: warmups, working: working)
    }
}
