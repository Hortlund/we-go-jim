import Foundation
import SwiftData

nonisolated struct WorkoutMuscleHeatmapSnapshot: Equatable, Sendable {
    let entries: [WorkoutMuscleHeatmapEntry]
    let topRegionNames: [String]

    static let empty = WorkoutMuscleHeatmapSnapshot(entries: [], topRegionNames: [])
}

nonisolated struct WorkoutMuscleHeatmapEntry: Identifiable, Equatable, Sendable {
    let region: ExerciseBodyMapRegion
    let score: Double
    let intensity: Double

    var id: ExerciseBodyMapRegion { region }
}

nonisolated struct WorkoutMuscleHeatmapCatalogMapping {
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
}

nonisolated enum WorkoutMuscleHeatmapBuilder {
    static func catalogMappings(modelContext: ModelContext) throws -> [String: WorkoutMuscleHeatmapCatalogMapping] {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let exercises = try modelContext.fetch(descriptor)
        return Dictionary(
            exercises.map { exercise in
                (
                    exercise.remoteUUID,
                    WorkoutMuscleHeatmapCatalogMapping(
                        primaryMuscleIDs: Set(exercise.primaryMuscles.map(\.remoteID)),
                        secondaryMuscleIDs: Set(exercise.secondaryMuscles.map(\.remoteID))
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func snapshot(scores: [ExerciseBodyMapRegion: Double]) -> WorkoutMuscleHeatmapSnapshot {
        let nonZeroScores = scores.filter { $0.value > 0 }
        guard !nonZeroScores.isEmpty else {
            return .empty
        }

        let maxScore = max(nonZeroScores.values.max() ?? 1, 1)
        let entries = nonZeroScores
            .map { region, score in
                WorkoutMuscleHeatmapEntry(
                    region: region,
                    score: score,
                    intensity: min(max(score / maxScore, 0), 1)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.region.displayName.localizedStandardCompare(rhs.region.displayName) == .orderedAscending
            }

        return WorkoutMuscleHeatmapSnapshot(
            entries: entries,
            topRegionNames: entries.prefix(3).map(\.region.displayName)
        )
    }

    static func scores(
        for exercise: WorkoutSessionExercise,
        catalogMappings: [String: WorkoutMuscleHeatmapCatalogMapping]
    ) -> [ExerciseBodyMapRegion: Double] {
        let completedSetCount = completedWorkingSetCount(for: exercise)
        guard completedSetCount > 0 else { return [:] }

        let perSetScores = scores(
            forCatalogExerciseUUID: exercise.catalogExerciseUUID,
            catalogMappings: catalogMappings,
            fallbackMuscleSummary: exercise.muscleSummarySnapshot
        )
        guard !perSetScores.isEmpty else { return [:] }

        return perSetScores.mapValues { $0 * Double(completedSetCount) }
    }

    static func scores(
        forCatalogExerciseUUID catalogExerciseUUID: String,
        catalogMappings: [String: WorkoutMuscleHeatmapCatalogMapping],
        fallbackMuscleSummary: String?
    ) -> [ExerciseBodyMapRegion: Double] {
        if let mapping = catalogMappings[catalogExerciseUUID] {
            return ExerciseBodyMapRegionMapper.regionScores(
                primaryMuscleIDs: mapping.primaryMuscleIDs,
                secondaryMuscleIDs: mapping.secondaryMuscleIDs
            )
        }

        let fallbackIDs = muscleIDs(fromSummary: fallbackMuscleSummary)
        guard !fallbackIDs.isEmpty else { return [:] }
        return ExerciseBodyMapRegionMapper.regionScores(
            primaryMuscleIDs: fallbackIDs,
            secondaryMuscleIDs: []
        )
    }

    private static func completedWorkingSetCount(for exercise: WorkoutSessionExercise) -> Int {
        (exercise.sets ?? []).filter { set in
            guard set.isCompleted, !set.isWarmup else {
                return false
            }
            return (set.actualReps ?? 0) > 0
        }.count
    }

    private static func muscleIDs(fromSummary summary: String?) -> Set<Int> {
        guard let summary else { return [] }
        let normalized = summary.lowercased()
        var ids: Set<Int> = []
        let mappings: [(tokens: [String], id: Int)] = [
            (["biceps"], 1),
            (["shoulders", "shoulder", "deltoids", "delts"], 2),
            (["chest", "pecs", "pectorals"], 3),
            (["back", "lats", "latissimus", "rhomboids", "lower back", "upper back"], 4),
            (["quadriceps", "quads"], 5),
            (["hamstrings", "hamstring"], 6),
            (["glutes", "gluteal"], 7),
            (["triceps"], 8),
            (["calves", "calf"], 9),
            (["abs", "core", "abdominals", "obliques"], 10),
            (["forearms", "forearm"], 11),
            (["traps", "trapezius"], 12),
            (["adductors", "adductor"], 13),
            (["abductors", "abductor"], 14),
        ]

        for mapping in mappings where mapping.tokens.contains(where: { normalized.contains($0) }) {
            ids.insert(mapping.id)
        }
        return ids
    }
}
