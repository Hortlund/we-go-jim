import Foundation

enum HistoryExerciseHydrationPlanner {
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
