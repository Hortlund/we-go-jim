import Foundation
import SwiftData

/// Dashboard reads session headers and one row per performed exercise, not every set.
nonisolated struct DashboardMetricsRepository {
    let context: ModelContext
    let calendar: Calendar

    func snapshot() throws -> MetricsSnapshotCache {
        let repository = WorkoutSessionRepository(modelContext: context)
        let sessions = try repository.completedSessions()
        let visible = Set(sessions.map(\.id))
        let dirty = sessions.filter {
            $0.projectionVersion != HistoryProjectionRepository.currentVersion || $0.projectionSourceUpdatedAt != $0.updatedAt
        }
        let dirtyIDs = Set(dirty.map(\.id))
        let rows = try context.fetch(FetchDescriptor<ExerciseSessionSummary>(predicate: #Predicate { !$0.isArchived }))
        var entries: [(String, CompletedExerciseHistoryEntry)] = try rows.compactMap { row in
            guard visible.contains(row.sessionID), !dirtyIDs.contains(row.sessionID) else { return nil }
            return (row.catalogExerciseUUID, try JSONDecoder().decode(CompletedExerciseHistoryEntry.self, from: row.payload))
        }
        if !dirtyIDs.isEmpty {
            let exercises = try repository.sessionExercises(sessionIDs: dirtyIDs)
            let sets = try repository.sessionSets(sessionExerciseIDs: Set(exercises.map(\.id)))
            let stages = try repository.sessionDropStages(setIDs: Set(sets.map(\.id)))
            let setsByExercise = Dictionary(grouping: sets, by: \.sessionExerciseID)
            let exercisesBySession = Dictionary(grouping: exercises, by: \.sessionID)
            let stagesBySet = Dictionary(grouping: stages, by: \.sessionSetID)
            let persisted = try context.fetch(FetchDescriptor<CompletedSetFact>(predicate: #Predicate { dirtyIDs.contains($0.sessionID) }))
            let persistedBySession = Dictionary(grouping: persisted, by: \.sessionID)
            let activities = try repository.sessionCardioBlocks(sessionIDs: dirtyIDs).filter(\.isCompleted)
            let activitiesBySession = Dictionary(grouping: activities, by: \.sessionID)
            for session in dirty {
                let exercises = exercisesBySession[session.id, default: []]
                let facts = exercises.isEmpty ? persistedBySession[session.id, default: []] : HistoryProjectionSnapshotBuilder.Source(
                    session: session, exercises: exercises.map { ($0, setsByExercise[$0.id, default: []]) },
                    dropStagesBySetID: stagesBySet
                ).projectedFacts().map { $0.makeModel() }
                let cardio = activitiesBySession[session.id, default: []].map { CompletedCardioFact(activity: $0, session: session) }
                entries.append(contentsOf: ExerciseHistorySummaryBuilder.entries(facts: facts, cardio: cardio).map { ($0.key, $0.value) })
            }
        }

        let mappings = try WorkoutMuscleHeatmapBuilder.catalogMappings(modelContext: context, catalogExerciseUUIDs: Set(entries.map(\.0)))
        var best: [String: WorkoutPRRecord] = [:]
        var bodyweight: [String: BodyweightExerciseBestRecord] = [:]
        var frequency: [String: CollectedExerciseFrequency] = [:]
        var history: [String: [CompletedExerciseHistoryEntry]] = [:]
        var muscles: [Date: [ExerciseBodyMapRegion: Double]] = [:]
        for (exercise, entry) in entries {
            history[exercise, default: []].append(entry)
            let old = frequency[exercise]
            frequency[exercise] = CollectedExerciseFrequency(
                exerciseName: old.map { $0.lastPerformedAt > entry.completedAt ? $0.exerciseName : entry.exerciseName } ?? entry.exerciseName,
                sessionCount: (old?.sessionCount ?? 0) + 1,
                lastPerformedAt: max(old?.lastPerformedAt ?? .distantPast, entry.completedAt)
            )
            if let weight = entry.bestWeight, let reps = entry.bestReps, let value = entry.weightedOneRepMaxInKilograms {
                let old = best[exercise]
                let oldValue = old.map { WorkoutPerformanceMath.normalizedLoadInKilograms($0.estimatedOneRepMax, unit: $0.loadUnit) } ?? -1
                if value > oldValue || (value == oldValue && entry.completedAt > (old?.achievedAt ?? .distantPast)) {
                    best[exercise] = WorkoutPRRecord(id: exercise, catalogExerciseUUID: exercise,
                        exerciseName: entry.exerciseName, estimatedOneRepMax: WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps),
                        weight: weight, reps: reps, loadUnit: entry.weightedOneRepMaxUnit, achievedAt: entry.completedAt)
                }
            }
            if let reps = entry.bestBodyweightReps {
                let old = bodyweight[exercise]
                if reps > (old?.reps ?? 0) || (reps == old?.reps && entry.completedAt > (old?.achievedAt ?? .distantPast)) {
                    bodyweight[exercise] = BodyweightExerciseBestRecord(catalogExerciseUUID: exercise, exerciseName: entry.exerciseName, reps: reps, achievedAt: entry.completedAt)
                }
            }
            let week = weekStart(entry.completedAt)
            let scores = WorkoutMuscleHeatmapBuilder.scores(forCatalogExerciseUUID: exercise, catalogMappings: mappings, fallbackMuscleSummary: entry.muscleSummary)
            for (region, score) in scores { muscles[week, default: [:]][region, default: 0] += score * Double(entry.completedSetCount) }
        }
        for key in history.keys { history[key]?.sort { $0.completedAt > $1.completedAt } }
        var countsByWeek: [Date: Int] = [:]
        var countsByDay: [Date: Int] = [:]
        for session in sessions {
            let date = session.endedAt ?? session.startedAt
            countsByWeek[weekStart(date), default: 0] += 1
            countsByDay[calendar.startOfDay(for: date), default: 0] += 1
        }
        return MetricsSnapshotCache(
            completedSessionCount: sessions.count, bestPRByExercise: best, bestBodyweightByExercise: bodyweight,
            countsByWeek: countsByWeek, countsByDay: countsByDay, muscleScoresByWeek: muscles,
            exerciseFrequencyByUUID: frequency, exerciseHistoryByUUID: history,
            totalDurationSeconds: sessions.reduce(0) { $0 + max(0, $1.durationSeconds) },
            totalPRHits: sessions.reduce(0) { $0 + max(0, $1.prHitsCount) },
            firstWorkoutDate: sessions.map { $0.endedAt ?? $0.startedAt }.min()
        )
    }

    private func weekStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }
}
