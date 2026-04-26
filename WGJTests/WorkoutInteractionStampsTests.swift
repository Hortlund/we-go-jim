import Foundation
import Testing
@testable import WGJ

struct WorkoutInteractionStampsTests {
    @Test
    func activeWorkoutStampToleratesDuplicateExerciseIDs() {
        let exerciseID = UUID()
        let entries = [
            ActiveWorkoutExerciseInteractionStamp.Entry(
                id: exerciseID,
                catalogExerciseUUID: "bench",
                restSeconds: 90,
                targetRepMin: 8,
                targetRepMax: 10,
                supersetGroupID: nil,
                supersetPositionRaw: nil
            ),
            ActiveWorkoutExerciseInteractionStamp.Entry(
                id: exerciseID,
                catalogExerciseUUID: "bench",
                restSeconds: 120,
                targetRepMin: 8,
                targetRepMax: 10,
                supersetGroupID: nil,
                supersetPositionRaw: nil
            )
        ]

        let stamp = ActiveWorkoutExerciseInteractionStamp(entries: entries)

        #expect(stamp.exerciseIDs == [exerciseID])
        #expect(stamp.changedExerciseIDs(comparedTo: nil) == [exerciseID])
    }
}
