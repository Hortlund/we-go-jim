import Foundation

nonisolated enum CardioSessionStarter {
    static func configuredSession(
        from emptySession: ActiveWorkoutRuntimeSession,
        selection: ExerciseCatalogSelection,
        distanceUnit: WorkoutDistanceUnit
    ) -> ActiveWorkoutRuntimeSession {
        var session = emptySession
        session.name = selection.displayName
        session.cardioBlocks = [ActiveWorkoutRuntimeCardioBlock(
            phase: .postWorkout, role: .main,
            catalogExerciseUUID: selection.remoteUUID,
            exerciseNameSnapshot: selection.displayName,
            categorySnapshot: selection.categoryName,
            muscleSummarySnapshot: selection.primaryMuscleNames,
            trackingProfile: WorkoutCardioTrackingProfileResolver.resolved(
                storedProfile: selection.cardioTrackingProfile, catalogExerciseUUID: selection.remoteUUID,
                exerciseName: selection.displayName, hasDistance: false
            ),
            goalKind: .open, targetDurationSeconds: 0, preferredDistanceUnit: distanceUnit
        )]
        session.touch()
        return session
    }
}
