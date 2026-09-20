import Foundation
import SwiftData

nonisolated enum ExerciseHistorySummaryBuilder {
    static func entries(facts: [CompletedSetFact], cardio: [CompletedCardioFact] = []) -> [String: CompletedExerciseHistoryEntry] {
        let grouped = Dictionary(grouping: facts.filter { !$0.isWarmup }, by: \.catalogExerciseUUID)
        var result: [String: CompletedExerciseHistoryEntry] = grouped.compactMapValues { facts in
            guard let first = facts.first else { return nil }
            let weighted = facts.filter { $0.isWeightedMetric }
            let strongest = weighted.max { ($0.estimatedOneRepMaxKg ?? 0) < ($1.estimatedOneRepMaxKg ?? 0) }
            let heaviest = weighted.max { ($0.normalizedWeightKg ?? 0) < ($1.normalizedWeightKg ?? 0) }
            var entry = CompletedExerciseHistoryEntry(
                sessionID: first.sessionID, completedAt: first.completedAt, exerciseName: first.exerciseNameSnapshot,
                comparisonOneRepMax: strongest?.estimatedOneRepMaxKg,
                weightedOneRepMaxInKilograms: strongest?.estimatedOneRepMaxKg,
                weightedOneRepMaxUnit: strongest?.loadUnit ?? .kg,
                totalWeightedVolumeInKilograms: weighted.isEmpty ? nil : weighted.reduce(0) { $0 + ($1.volumeKg ?? 0) },
                weightedVolumeUnit: weighted.last?.loadUnit ?? .kg,
                maxWeightInKilograms: heaviest?.normalizedWeightKg, maxWeightUnit: heaviest?.loadUnit ?? .kg,
                maxReps: facts.map(\.reps).max(), totalReps: facts.reduce(0) { $0 + $1.reps },
                completedSetCount: facts.count
            )
            entry.bestWeight = strongest?.weight
            entry.bestReps = strongest?.reps
            entry.bestBodyweightReps = facts.filter { $0.loadUnit == .bodyweight }.map(\.reps).max()
            entry.muscleSummary = first.muscleSummarySnapshot
            return entry
        }
        for activity in cardio where activity.durationSeconds > 0 {
            var entry = result[activity.catalogExerciseUUID] ?? CompletedExerciseHistoryEntry(
                sessionID: activity.sessionID, completedAt: activity.completedAt, exerciseName: activity.exerciseName,
                comparisonOneRepMax: nil, weightedOneRepMaxInKilograms: nil, weightedOneRepMaxUnit: .kg,
                totalWeightedVolumeInKilograms: nil, weightedVolumeUnit: .kg,
                maxWeightInKilograms: nil, maxWeightUnit: .kg, maxReps: nil, totalReps: 0, completedSetCount: 0
            )
            entry.durationSeconds = (entry.durationSeconds ?? 0) + activity.durationSeconds
            if let distance = activity.distanceMeters, distance > 0 {
                entry.distanceMeters = (entry.distanceMeters ?? 0) + distance
            }
            result[activity.catalogExerciseUUID] = entry
        }
        return result
    }
}

/// Reads derived rows directly. Canonical fallback is restricted to dirty sessions
/// for the requested exercise and never mutates the context during a read.
nonisolated struct ExerciseHistoryRepository {
    let context: ModelContext

    func entries(for exerciseUUID: String, limit: Int? = nil, metric: ProfileExerciseTrendMetric? = nil) throws -> [CompletedExerciseHistoryEntry] {
        let completed = WorkoutSessionStatus.completed.rawValue
        let version = HistoryProjectionRepository.currentVersion
        let dirty = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
            $0.statusRaw == completed && ($0.projectionVersion < version || $0.projectionSourceUpdatedAt != $0.updatedAt)
        }))
        let kind: Int
        switch metric {
        case .oneRepMax: kind = 1
        case .maxWeight: kind = 2
        case .volume: kind = 3
        case .maxReps: kind = 4
        case nil: kind = 0
        }
        var descriptor = FetchDescriptor<ExerciseSessionSummary>(
            predicate: #Predicate {
                $0.catalogExerciseUUID == exerciseUUID && !$0.isArchived
                    && (kind == 0 || (kind == 1 && $0.oneRepMax != nil) || (kind == 2 && $0.maxWeight != nil)
                        || (kind == 3 && $0.volume != nil) || (kind == 4 && $0.maxReps != nil))
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = max(1, limit) + dirty.count }
        let summaries = try context.fetch(descriptor)
        var entries = try Dictionary(summaries.map {
            ($0.sessionID, try JSONDecoder().decode(CompletedExerciseHistoryEntry.self, from: $0.payload))
        }, uniquingKeysWith: { first, _ in first })

        let dirtyIDs = Set(dirty.map(\.id))
        if !dirtyIDs.isEmpty {
            let exercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate {
                $0.catalogExerciseUUID == exerciseUUID && dirtyIDs.contains($0.sessionID)
            }))
            let exerciseIDs = Set(exercises.map(\.id))
            let sets = exerciseIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionSet>(predicate: #Predicate {
                exerciseIDs.contains($0.sessionExerciseID)
            }))
            let setsByExercise = Dictionary(grouping: sets, by: \.sessionExerciseID)
            let setIDs = Set(sets.map(\.id))
            let stages = try WorkoutSessionRepository(modelContext: context).sessionDropStages(setIDs: setIDs)
            let stagesBySet = Dictionary(grouping: stages, by: \.sessionSetID)
            let cardio = try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>(predicate: #Predicate {
                $0.catalogExerciseUUID == exerciseUUID && dirtyIDs.contains($0.sessionID) && $0.isCompleted
            }))
            let cardioBySession = Dictionary(grouping: cardio, by: \.sessionID)
            let exercisesBySession = Dictionary(grouping: exercises, by: \.sessionID)
            let persisted = try context.fetch(FetchDescriptor<CompletedSetFact>(predicate: #Predicate {
                $0.catalogExerciseUUID == exerciseUUID && dirtyIDs.contains($0.sessionID)
            }))
            let persistedBySession = Dictionary(grouping: persisted, by: \.sessionID)
            for session in dirty {
                entries.removeValue(forKey: session.id)
                guard session.archivedAt == nil else { continue }
                let rows = exercisesBySession[session.id, default: []]
                let facts: [CompletedSetFact]
                if rows.isEmpty {
                    // Compatibility for projection-only imported histories.
                    facts = persistedBySession[session.id, default: []]
                } else {
                    facts = HistoryProjectionSnapshotBuilder.Source(session: session, exercises: rows.map {
                        ($0, setsByExercise[$0.id, default: []])
                    }, dropStagesBySetID: stagesBySet).projectedFacts().map { $0.makeModel() }
                }
                entries[session.id] = ExerciseHistorySummaryBuilder.entries(
                    facts: facts, cardio: cardioBySession[session.id, default: []].map { CompletedCardioFact(activity: $0, session: session) }
                )[exerciseUUID]
            }
        }
        let ordered = entries.values.filter { entry in
            guard let metric else { return true }
            switch metric {
            case .oneRepMax: return entry.weightedOneRepMaxInKilograms != nil
            case .maxWeight: return entry.maxWeightInKilograms != nil
            case .volume: return entry.totalWeightedVolumeInKilograms != nil
            case .maxReps: return entry.maxReps != nil
            }
        }.sorted {
            $0.completedAt == $1.completedAt ? $0.sessionID.uuidString < $1.sessionID.uuidString : $0.completedAt > $1.completedAt
        }
        return limit.map { Array(ordered.prefix(max(1, $0))) } ?? ordered
    }
}
