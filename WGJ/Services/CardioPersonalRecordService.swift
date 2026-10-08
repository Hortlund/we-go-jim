import Foundation
import SwiftData

/// One chronological calculation shared by Journey and workout completion.
/// Baselines and comparisons stay within the same exercise and tracking profile.
nonisolated enum CardioPersonalRecordService {
    private struct Key: Hashable {
        let exerciseID: String
        let profile: WorkoutCardioTrackingProfile
    }

    static func activity(_ block: WorkoutSessionCardioBlock) -> JourneyActivity {
        let profile = WorkoutCardioTrackingProfileResolver.resolved(storedProfile: block.trackingProfile,
            catalogExerciseUUID: block.catalogExerciseUUID, exerciseName: block.exerciseNameSnapshot,
            hasDistance: (block.actualDistanceMeters ?? 0) > 0)
        return JourneyActivity(id: block.id, exerciseID: block.catalogExerciseUUID,
            name: block.exerciseNameSnapshot, distanceMeters: block.actualDistanceMeters ?? 0,
            durationSeconds: max(0, block.actualDurationSeconds ?? 0),
            isWalkRun: profile == .walkRun || profile == .treadmill,
            isOutdoor: CardioRecordingPolicy.recordsGPS(catalogExerciseUUID: block.catalogExerciseUUID),
            trackingProfile: profile,
            isCycling: ["seed-bike", "seed-outdoor-bike", "seed-assault-bike-sprint"].contains(block.catalogExerciseUUID))
    }

    static func records(sessionID: UUID, context: ModelContext) throws -> [WorkoutCompletionPersonalRecord] {
        let repository = WorkoutSessionRepository(modelContext: context)
        let current = try repository.sessionCardioBlocks(sessionID: sessionID).filter(\.isCompleted)
        let exerciseIDs = Set(current.map(\.catalogExerciseUUID))
        guard !exerciseIDs.isEmpty, let session = try repository.session(id: sessionID) else { return [] }
        let cutoff = session.endedAt ?? session.startedAt
        let sessions = try repository.completedSessions().filter { ($0.endedAt ?? $0.startedAt) <= cutoff }
        let ids = sessions.map(\.id)
        let exercises = Array(exerciseIDs)
        let descriptor = FetchDescriptor<WorkoutSessionCardioBlock>(predicate: #Predicate {
            $0.isCompleted && ids.contains($0.sessionID) && exercises.contains($0.catalogExerciseUUID)
        })
        let bySession = Dictionary(grouping: try context.fetch(descriptor), by: \.sessionID)
        let workouts = sessions.map {
            JourneyWorkout(id: $0.id, name: $0.name, date: $0.endedAt ?? $0.startedAt,
                durationSeconds: $0.durationSeconds, hasStrength: false, hasCardio: true,
                activities: bySession[$0.id, default: []].map(activity))
        }
        let unit = try ProfileRepository(modelContext: context).currentProfile()?.preferredDistanceUnit
            ?? .regionalDefault(locale: .current)
        return milestones(workouts: workouts, unit: unit)
            .filter { $0.sessionID == sessionID }.compactMap(\.personalRecord)
    }

    static func milestones(workouts: [JourneyWorkout], unit: WorkoutDistanceUnit) -> [JourneyMilestone] {
        var longest: [Key: Double] = [:]
        var fastest: [Key: Double] = [:]
        var result: [JourneyMilestone] = []
        let ordered = workouts.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        for workout in ordered {
            let valid = workout.activities.filter {
                $0.distanceMeters.isFinite && $0.distanceMeters > 0
                    && $0.trackingProfile != .timeOnly && $0.trackingProfile != .stairClimber
            }
            let groups = Dictionary(grouping: valid) { Key(exerciseID: $0.exerciseID, profile: $0.trackingProfile) }
            for key in groups.keys.sorted(by: {
                $0.exerciseID == $1.exerciseID ? $0.profile.rawValue < $1.profile.rawValue : $0.exerciseID < $1.exerciseID
            }) {
                let activities = groups[key, default: []].sorted { $0.id.uuidString < $1.id.uuidString }
                guard let farthest = activities.max(by: { $0.distanceMeters < $1.distanceMeters }) else { continue }
                if let previous = longest[key], farthest.distanceMeters > previous + 0.001 {
                    let comparison = distanceTexts(record: farthest.distanceMeters, previous: previous, unit: unit)
                    result.append(event(workout, activity: farthest, metric: "distance",
                        title: String(localized: "Longest distance"), value: comparison.record,
                        detail: String(localized: "Previous best: \(comparison.previous).")))
                }
                longest[key] = max(longest[key] ?? 0, farthest.distanceMeters)
                // Whole-activity average, never an instantaneous GPS speed or an inferred split.
                // A 1 km minimum keeps tiny warm-ups and accidental timer stops out of speed records.
                let timed = activities.filter { $0.distanceMeters >= 1_000 && $0.durationSeconds > 0 }
                func speed(_ activity: JourneyActivity) -> Double { activity.distanceMeters / Double(activity.durationSeconds) }
                if let quickest = timed.max(by: { speed($0) < speed($1) }) {
                    let value = speed(quickest)
                    if let previous = fastest[key], value > previous + 0.000001 {
                        let comparison = speedTexts(record: value, previous: previous, unit: unit)
                        result.append(event(workout, activity: quickest, metric: "speed",
                            title: String(localized: "Fastest average speed"), value: comparison.record,
                            detail: String(localized: "Previous best: \(comparison.previous).") + " "
                                + String(localized: "\(JourneyFormatting.distance(quickest.distanceMeters, unit: unit)) in \(JourneyFormatting.time(quickest.durationSeconds)).")))
                    }
                    fastest[key] = max(fastest[key] ?? 0, value)
                }
            }
        }
        return result
    }

    private static func distanceTexts(record: Double, previous: Double, unit: WorkoutDistanceUnit)
        -> (record: String, previous: String) {
        comparisonTexts(record: unit.value(fromMeters: record), previous: unit.value(fromMeters: previous),
            suffix: unit.symbol, initialPlaces: 1)
    }

    private static func speedTexts(record: Double, previous: Double, unit: WorkoutDistanceUnit)
        -> (record: String, previous: String) {
        let speedUnit: WorkoutDistanceUnit = unit == .miles ? .miles : .kilometers
        return comparisonTexts(record: speedUnit.value(fromMeters: record * 3_600),
            previous: speedUnit.value(fromMeters: previous * 3_600), suffix: "\(speedUnit.symbol)/h", initialPlaces: 2)
    }

    private static func comparisonTexts(record: Double, previous: Double, suffix: String, initialPlaces: Int)
        -> (record: String, previous: String) {
        // Increase precision only when rounding hides the improvement. Seven
        // places distinguish both PR tolerances in all supported display units.
        var places = initialPlaces
        while true {
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...places))
            let recordText = record.formatted(format)
            let previousText = previous.formatted(format)
            if recordText != previousText || places == 7 {
                return ("\(recordText) \(suffix)", "\(previousText) \(suffix)")
            }
            places += 1
        }
    }

    private static func event(_ workout: JourneyWorkout, activity: JourneyActivity, metric: String,
                              title: String, value: String, detail: String) -> JourneyMilestone {
        let id = "cardio-pr-\(metric)-\(activity.id)"
        let record = WorkoutCompletionPersonalRecord(id: id, exerciseName: activity.name,
            performanceText: "\(title) · \(value)", detailText: detail)
        return JourneyMilestone(id: id, sessionID: workout.id, date: workout.date, kind: .cardio,
            title: "\(activity.name) · \(title)", detail: "\(value) · \(detail)",
            activityID: activity.isOutdoor ? activity.id : nil, personalRecord: record,
            recordKey: "cardio-\(activity.exerciseID)-\(activity.trackingProfile.rawValue)-\(metric)")
    }
}
