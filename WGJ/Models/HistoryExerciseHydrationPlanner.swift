import Foundation

enum HistoryExerciseHydrationPlanner {
    static func pendingExerciseIDs(
        orderedExerciseIDs: [UUID],
        expandedExerciseIDs: [UUID: Bool],
        hydratedExerciseIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(
            orderedExerciseIDs.filter { exerciseID in
                expandedExerciseIDs[exerciseID] == true && !hydratedExerciseIDs.contains(exerciseID)
            }
        )
    }
}
