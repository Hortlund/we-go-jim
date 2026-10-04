#if DEBUG
import Foundation

/// A recovered, paused activity exercises the real finish/save flow without
/// relying on simulator GPS timing. Restricted to explicit in-memory UI tests.
nonisolated enum CardioRecordingUITestScenario {
    static func seedIfRequested() throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITEST_IN_MEMORY_STORE"),
              arguments.contains("UITEST_SEED_PAUSED_OUTDOOR_CARDIO") else { return }
        let bike = arguments.contains("UITEST_OUTDOOR_BIKE")
        let hasRoute = !arguments.contains("UITEST_NO_GPS_DISTANCE")
        var activity = ActiveWorkoutRuntimeCardioBlock(phase: .postWorkout, role: .main,
            catalogExerciseUUID: bike ? "seed-outdoor-bike" : "seed-outdoor-walk",
            exerciseNameSnapshot: bike ? "Outdoor Bike" : "Outdoor Walk",
            categorySnapshot: "Cardio", muscleSummarySnapshot: "",
            trackingProfile: bike ? .machineDistance : .walkRun,
            goalKind: .open, targetDurationSeconds: 0, preferredDistanceUnit: .kilometers,
            timerState: .paused, timerAccumulatedSeconds: 603)
        if arguments.contains("UITEST_COMPLETED_MANUAL_OUTDOOR_CARDIO") {
            activity.timerState = .idle
            activity.isCompleted = true
            activity.actualDurationSeconds = 603
            activity.actualDistanceMeters = 2_500
        }
        let session = ActiveWorkoutRuntimeSession(name: activity.exerciseNameSnapshot,
            startedAt: .now.addingTimeInterval(-603), cardioBlocks: [activity])
        let snapshot = ActiveWorkoutStoredSnapshot(session: session, presentationMode: .collapsed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = ActiveWorkoutSnapshotStore.defaultSnapshotURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        var route = CardioRoute(sessionID: session.id, activityID: activity.id)
        if hasRoute {
            let start = session.startedAt
            route.beginSegment()
            for (latitude, seconds) in [(59.3293, 0.0), (59.3303, 20.0), (59.3313, 40.0)] {
                let date = start.addingTimeInterval(seconds)
                _ = route.append(latitude: latitude, longitude: 18.0686, timestamp: date,
                    accuracy: 5, now: date, recordingStartedAt: start)
            }
            route.distanceMeters = 2_345.6789
            route.stop()
        }
        try CardioRouteFiles().write(route)
    }
}
#endif
