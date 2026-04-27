import Foundation

enum HistoryDetailExpansionPolicy {
    static func initialExpansionState(orderedExerciseIDs: [UUID]) -> [UUID: Bool] {
        Dictionary(
            orderedExerciseIDs.map { ($0, false) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

enum HistoryExerciseHydrationPlanner {
    static func initialLocalStateExerciseIDs(
        orderedExerciseIDs: [UUID],
        expandedExerciseIDs: [UUID: Bool],
        includeCollapsedRows: Bool = false,
        limit: Int? = 1
    ) -> Set<UUID> {
        let eligibleExerciseIDs = includeCollapsedRows
            ? Set(orderedExerciseIDs)
            : Set(orderedExerciseIDs.filter { expandedExerciseIDs[$0] == true })

        return WorkoutExerciseHydrationPlanner.orderedExerciseIDsToHydrate(
            orderedExerciseIDs: orderedExerciseIDs,
            eligibleExerciseIDs: eligibleExerciseIDs,
            limit: limit
        )
    }

    static func pendingExerciseIDs(
        orderedExerciseIDs: [UUID],
        expandedExerciseIDs: [UUID: Bool],
        hydratedExerciseIDs: Set<UUID>
    ) -> Set<UUID> {
        let eligibleExerciseIDs = Set(
            orderedExerciseIDs.filter { exerciseID in
                expandedExerciseIDs[exerciseID] == true && !hydratedExerciseIDs.contains(exerciseID)
            }
        )

        return WorkoutExerciseHydrationPlanner.orderedExerciseIDsToHydrate(
            orderedExerciseIDs: orderedExerciseIDs,
            eligibleExerciseIDs: eligibleExerciseIDs
        )
    }
}
