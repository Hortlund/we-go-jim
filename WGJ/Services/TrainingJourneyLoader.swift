import Foundation
import SwiftData

nonisolated enum TrainingJourneyLoader {
    static func load(context: ModelContext, calendar: Calendar = .current, now: Date = .now) throws -> TrainingJourneySnapshot {
        let repository = WorkoutSessionRepository(modelContext: context)
        let sessions = try repository.completedSessions(includeArchived: false)
        let visible = Set(sessions.map(\.id))
        let activities = try repository.sessionCardioBlocks(sessionIDs: visible).filter(\.isCompleted)
        let bySession = Dictionary(grouping: activities, by: \.sessionID)
        let metrics = try DashboardMetricsRepository(context: context, calendar: calendar).snapshot(
            request: DashboardMetricsRequest(calendar: calendar, records: false, frequency: false,
                history: true, allMuscleWeeks: false))
        let exerciseIDs = Set(metrics.exerciseHistoryByUUID.keys)
        let added = try ExerciseLoadContextRepository.addedWeightIDs(for: exerciseIDs, in: context)
        let assisted = try ExerciseLoadContextRepository.assistanceIDs(for: exerciseIDs, in: context)
        let strengthSessions = Set(metrics.exerciseHistoryByUUID.values.flatMap { entries in
            entries.filter { $0.completedSetCount > 0 }.map(\.sessionID)
        })
        let workouts = sessions.map { session in
            JourneyWorkout(id: session.id, name: session.name, date: session.endedAt ?? session.startedAt,
                durationSeconds: session.durationSeconds, hasStrength: strengthSessions.contains(session.id),
                hasCardio: !bySession[session.id, default: []].isEmpty,
                activities: bySession[session.id, default: []].map { activity in
                    let profile = WorkoutCardioTrackingProfileResolver.resolved(storedProfile: activity.trackingProfile,
                        catalogExerciseUUID: activity.catalogExerciseUUID, exerciseName: activity.exerciseNameSnapshot,
                        hasDistance: (activity.actualDistanceMeters ?? 0) > 0)
                    return JourneyActivity(id: activity.id, exerciseID: activity.catalogExerciseUUID,
                        name: activity.exerciseNameSnapshot, distanceMeters: activity.actualDistanceMeters ?? 0,
                        durationSeconds: max(0, activity.actualDurationSeconds ?? 0),
                        isWalkRun: profile == .walkRun || profile == .treadmill,
                        isOutdoor: CardioRecordingPolicy.recordsGPS(catalogExerciseUUID: activity.catalogExerciseUUID))
                })
        }
        var exercises: [JourneyExercise] = []
        for (id, entries) in metrics.exerciseHistoryByUUID where !assisted.contains(id) {
            guard let name = entries.first?.exerciseName else { continue }
            let weights = entries.compactMap { entry -> JourneyPerformance? in
                guard let value = entry.maxWeightInKilograms, entry.completedSetCount > 0 else { return nil }
                return .init(sessionID: entry.sessionID, date: entry.completedAt, value: value)
            }
            exercises.append(.init(id: "\(id)-weight", name: name, isReps: false,
                usesAddedWeight: added.contains(id), performances: weights))
            let reps = entries.compactMap { entry -> JourneyPerformance? in
                // Only explicitly bodyweight sets are comparable for rep records.
                // A missing resistance load is not evidence of a bodyweight set.
                guard let value = entry.bestBodyweightReps else { return nil }
                return .init(sessionID: entry.sessionID, date: entry.completedAt, value: Double(value))
            }
            exercises.append(.init(id: "\(id)-reps", name: name, isReps: true, usesAddedWeight: false, performances: reps))
        }
        let profile = try ProfileRepository(modelContext: context).currentProfile()
        return TrainingJourneyBuilder.build(workouts: workouts, exercises: exercises,
            distanceUnit: profile?.preferredDistanceUnit ?? .regionalDefault(locale: .current),
            loadUnit: profile?.preferredLoadUnit ?? .kg, calendar: calendar, now: now)
    }
}
