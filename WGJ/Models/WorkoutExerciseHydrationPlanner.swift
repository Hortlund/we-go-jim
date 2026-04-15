import Foundation

enum WorkoutExerciseHydrationPlanner {
    static func orderedExerciseIDsToHydrate(
        orderedExerciseIDs: [UUID],
        eligibleExerciseIDs: Set<UUID>,
        limit: Int? = nil
    ) -> Set<UUID> {
        guard !eligibleExerciseIDs.isEmpty else { return [] }

        let orderedMatches = orderedExerciseIDs.filter { eligibleExerciseIDs.contains($0) }
        guard let limit else {
            return Set(orderedMatches)
        }

        return Set(orderedMatches.prefix(max(0, limit)))
    }
}
