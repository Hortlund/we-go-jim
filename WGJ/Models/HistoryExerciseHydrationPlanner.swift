import Foundation

enum HistoryExerciseHydrationPlanner {
    static func initialLocalStateExerciseIDs(
        orderedExerciseIDs: [UUID],
        expandedExerciseIDs: [UUID: Bool],
        limit: Int = 1
    ) -> Set<UUID> {
        WorkoutExerciseHydrationPlanner.orderedExerciseIDsToHydrate(
            orderedExerciseIDs: orderedExerciseIDs,
            eligibleExerciseIDs: Set(orderedExerciseIDs.filter { expandedExerciseIDs[$0] == true }),
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
