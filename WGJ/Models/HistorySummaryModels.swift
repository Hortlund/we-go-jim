import Foundation
import SwiftData

@Model
final class ExerciseSessionSummary {
    #Index<ExerciseSessionSummary>([\.catalogExerciseUUID, \.completedAt], [\.sessionID])
    @Attribute(.unique) var key: String = ""
    var sessionID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var completedAt: Date = Date()
    var isArchived: Bool = false
    var sourceUpdatedAt: Date = Date()
    var payload: Data = Data()
    var oneRepMax: Double?
    var maxWeight: Double?
    var volume: Double?
    var maxReps: Int?

    init(entry: CompletedExerciseHistoryEntry, exerciseUUID: String, session: WorkoutSession) throws {
        key = "\(session.id.uuidString)|\(exerciseUUID)"
        sessionID = session.id
        catalogExerciseUUID = exerciseUUID
        completedAt = entry.completedAt
        isArchived = session.archivedAt != nil
        sourceUpdatedAt = session.updatedAt
        payload = try BackupArchiveCodec.json(entry)
        oneRepMax = entry.weightedOneRepMaxInKilograms
        maxWeight = entry.maxWeightInKilograms
        volume = entry.totalWeightedVolumeInKilograms
        maxReps = entry.maxReps
    }
}

@Model
final class HistoryProjectionCheckpoint {
    @Attribute(.unique) var key: String = "history"
    var version: Int = 0
    init(version: Int) { self.version = version }
}

@Model
final class CompletedCardioFact {
    #Index<CompletedCardioFact>([\.catalogExerciseUUID, \.completedAt], [\.sessionID])
    @Attribute(.unique) var activityID: UUID = UUID()
    var sessionID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var exerciseName: String = ""
    var completedAt: Date = Date()
    var isArchived: Bool = false
    var durationSeconds: Double = 0
    var distanceMeters: Double?

    init(activity: WorkoutSessionCardioBlock, session: WorkoutSession) {
        activityID = activity.id
        sessionID = session.id
        catalogExerciseUUID = activity.catalogExerciseUUID
        exerciseName = activity.exerciseNameSnapshot
        completedAt = session.endedAt ?? session.startedAt
        isArchived = session.archivedAt != nil
        durationSeconds = Double(activity.actualDurationSeconds ?? 0)
        distanceMeters = activity.actualDistanceMeters
    }
}
