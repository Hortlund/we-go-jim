import Foundation
import SwiftData

/// Linear sweep after sorting. Used for restore, migration, and historical edits.
/// PRs are recomputed against visible history, including only workouts finished
/// before the evaluated workout began (the same cutoff as live completion).
nonisolated enum HistoryRecordRebuilder {
    private struct Peaks {
        var strength = 0.0
        var weight = 0.0
        var volume = 0.0
        var reps = 0

        mutating func consume(_ fact: CompletedSetFact) -> Bool {
            var record = false
            if fact.isWeightedMetric {
                if let value = fact.estimatedOneRepMaxKg, value > strength { strength = value; record = true }
                if let value = fact.normalizedWeightKg, value > weight { weight = value; record = true }
                if let value = fact.volumeKg, value > volume { volume = value; record = true }
            }
            if fact.reps > reps { reps = fact.reps; record = true }
            return record
        }
    }

    @discardableResult
    static func rebuild(in context: ModelContext) throws -> Int {
        try WGJPerformance.measure("history.records.rebuild") {
            let repository = WorkoutSessionRepository(modelContext: context)
            let sessions = try repository.completedSessions(includeArchived: true)
            let visible = Set(sessions.filter { $0.archivedAt == nil }.map(\.id))
            let facts = try HistoryProjectionRepository(modelContext: context).allFacts()
            let bySession = Dictionary(grouping: facts, by: \.sessionID)
            let orderedHistory = facts.filter { !$0.isWarmup && $0.parentSetID == nil && visible.contains($0.sessionID) }.sorted {
                $0.completedAt < $1.completedAt
            }
            let exerciseOrder = Dictionary(
                try context.fetch(FetchDescriptor<WorkoutSessionExercise>()).map { ($0.id, $0.sortOrder) },
                uniquingKeysWith: { first, _ in first }
            )
            var historyIndex = 0
            var prior: [String: Peaks] = [:]
            var changed = 0
            for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
                while historyIndex < orderedHistory.count && orderedHistory[historyIndex].completedAt < session.startedAt {
                    let fact = orderedHistory[historyIndex]
                    _ = prior[fact.catalogExerciseUUID, default: Peaks()].consume(fact)
                    historyIndex += 1
                }
                var local = prior
                var hits = 0
                let sessionFacts = bySession[session.id, default: []].filter { !$0.isWarmup }.sorted {
                    let a = exerciseOrder[$0.sessionExerciseID, default: 0]
                    let b = exerciseOrder[$1.sessionExerciseID, default: 0]
                    if a != b { return a < b }
                    if $0.setIndex != $1.setIndex { return $0.setIndex < $1.setIndex }
                    return $0.sessionSetID.uuidString < $1.sessionSetID.uuidString
                }
                for fact in sessionFacts where fact.parentSetID == nil {
                    if local[fact.catalogExerciseUUID, default: Peaks()].consume(fact) { hits += 1 }
                }
                let volume = sessionFacts.reduce(0) { $0 + ($1.volumeKg ?? 0) }
                let version = WorkoutMetricsService.currentSummaryMetricsVersion
                if session.prHitsCount != hits || session.totalVolume != volume || session.summaryMetricsVersion != version {
                    session.prHitsCount = hits
                    session.totalVolume = volume
                    session.summaryMetricsVersion = version
                    let projectionWasCurrent = session.projectionSourceUpdatedAt == session.updatedAt
                    session.updatedAt = .now
                    if projectionWasCurrent { session.projectionSourceUpdatedAt = session.updatedAt }
                    changed += 1
                }
            }
            return changed
        }
    }
}
