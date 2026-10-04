import Foundation

nonisolated struct WorkoutLiveActivityProjection: Equatable, Sendable {
    let sessionID: UUID
    let state: WorkoutActivityAttributes.ContentState

    static func make(snapshot: ActiveWorkoutStoredSnapshot?, route: CardioRoute?, at date: Date = .now,
                     includesReadyCardio: Bool = false) -> Self? {
        guard let snapshot else { return nil }
        let session = snapshot.session
        // A lone activity has its own clock. Mixed workouts keep the session clock.
        if let id = CardioRecordingPolicy.standaloneActivityID(in: session),
           let activity = session.cardioBlocks.first(where: { $0.id == id }) {
            guard activity.timerState != .idle || activity.isCompleted || includesReadyCardio else { return nil }
            let elapsed = activity.isCompleted ? activity.actualDurationSeconds ?? 0
                : WorkoutCardioTimerCoordinator.elapsedSeconds(for: activity, at: date)
            let matchingRoute = route?.sessionID == session.id && route?.activityID == activity.id ? route : nil
            let meters = activity.isCompleted ? activity.actualDistanceMeters
                : matchingRoute?.distanceMeters ?? activity.actualDistanceMeters
            let unit = activity.preferredDistanceUnit ?? .kilometers
            let profile = WorkoutCardioTrackingProfileResolver.resolved(storedProfile: activity.trackingProfile,
                catalogExerciseUUID: activity.catalogExerciseUUID, exerciseName: activity.exerciseNameSnapshot,
                hasDistance: meters != nil)
            let metrics = WorkoutCardioMetricsCalculator.calculate(durationSeconds: elapsed, distanceMeters: meters,
                displayUnit: unit, profile: profile)
            let running = !activity.isCompleted && activity.timerState == .running
            return Self(sessionID: session.id, state: .init(
                title: String(activity.exerciseNameSnapshot.prefix(80)),
                symbol: CardioRecordingPolicy.symbol(for: activity),
                isCardio: true,
                status: activity.isCompleted ? "Completed" : running ? "In progress" : activity.timerState == .idle ? "Ready to start" : "Paused",
                timerStart: running ? activity.timerSegmentStartedAt?.addingTimeInterval(-Double(activity.timerAccumulatedSeconds)) : nil,
                elapsedSeconds: elapsed,
                distance: meters.map { "\(unit.value(fromMeters: $0).formatted(.number.precision(.fractionLength(2)))) \(unit.symbol)" },
                pace: metrics.paceSecondsPerDisplayUnit.map { "\(durationText(Int($0.rounded()))) /\(unit.symbol)" },
                progress: nil, restEndsAt: nil,
                averageSpeed: profile == .machineDistance
                    ? metrics.averageSpeedPerHour.map { "\($0.formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)/h" } ?? "—"
                    : nil
            ))
        }
        let sets = session.exercises.flatMap(\.setDrafts)
        let completed = sets.filter(\.isCycleCompleted).count
        return Self(sessionID: session.id, state: .init(
            title: String(session.name.prefix(80)), symbol: "dumbbell.fill", isCardio: false,
            status: "Workout in progress", timerStart: session.startedAt, elapsedSeconds: 0,
            distance: nil, pace: nil,
            progress: sets.isEmpty ? "\(session.exercises.count) exercises" : "\(completed)/\(sets.count) sets",
            restEndsAt: snapshot.restTimer.flatMap { $0.endsAt > date ? $0.endsAt : nil }
        ))
    }

    static func durationText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
