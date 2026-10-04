import Foundation

nonisolated struct CardioRoutePoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let segment: Int
}

/// Live routes use a local journal. Completed routes can join WGJ's cloud backup;
/// coordinates never enter widgets or Health export payloads.
nonisolated struct CardioRoute: Codable, Equatable, Sendable {
    let sessionID: UUID
    let activityID: UUID
    var points: [CardioRoutePoint] = []
    var distanceMeters: Double = 0
    var revision: UInt64 = 0
    var segment: Int = 0
    var isRecording = false
    // Includes valid fixes filtered out as stationary noise, so filtering cannot
    // turn a continuous stream of fixes into an apparent signal gap.
    private var lastValidFixTimestamp: Date? = nil

    func validateForBackup() throws {
        guard !isRecording, distanceMeters.isFinite, distanceMeters >= 0, segment >= 0,
              points.allSatisfy({
                  $0.latitude.isFinite && (-90...90).contains($0.latitude)
                    && $0.longitude.isFinite && (-180...180).contains($0.longitude)
                    && $0.horizontalAccuracy.isFinite && (0...35).contains($0.horizontalAccuracy)
                    && $0.segment >= 0 && $0.segment <= segment
                    && $0.timestamp.timeIntervalSinceReferenceDate.isFinite
              }) else { throw BackupArchiveError.corruptChunk }
        for (previous, next) in zip(points, points.dropFirst()) {
            guard next.timestamp > previous.timestamp, next.segment >= previous.segment else {
                throw BackupArchiveError.corruptChunk
            }
        }
    }

    mutating func beginSegment() {
        lastValidFixTimestamp = nil
        segment += 1
        isRecording = true
        revision += 1
    }

    mutating func stop() {
        lastValidFixTimestamp = nil
        isRecording = false
        revision += 1
    }

    /// Reject stale/inaccurate fixes and GPS jumps. Never join pauses or signal gaps.
    @discardableResult
    mutating func append(
        latitude: Double, longitude: Double, timestamp: Date,
        accuracy: Double, now: Date, recordingStartedAt: Date,
        maximumSpeedMetersPerSecond: Double = 12
    ) -> Bool {
        guard isRecording,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              accuracy.isFinite, (0...35).contains(accuracy),
              timestamp >= recordingStartedAt,
              (-5...15).contains(now.timeIntervalSince(timestamp)) else { return false }

        let previousFixTimestamp = lastValidFixTimestamp ?? points.last?.timestamp
        if let previousFixTimestamp, timestamp <= previousFixTimestamp { return false }
        lastValidFixTimestamp = timestamp

        if let previous = points.last {
            guard timestamp > previous.timestamp else { return false }
            if previous.segment == segment {
                let seconds = timestamp.timeIntervalSince(previous.timestamp)
                let distance = Self.distance(
                    latitude, longitude, previous.latitude, previous.longitude
                )
                let fixGap = timestamp.timeIntervalSince(previousFixTimestamp ?? previous.timestamp)
                if fixGap > 30 || distance / seconds > maximumSpeedMetersPerSecond {
                    // Reacquire an anchor without inventing travel through a GPS gap.
                    segment += 1
                } else {
                    let noiseFloor = max(5, min(15, (accuracy + previous.horizontalAccuracy) * 0.25))
                    guard distance >= noiseFloor else { return false }
                    distanceMeters += distance
                }
            }
        }
        points.append(.init(
            latitude: latitude, longitude: longitude, timestamp: timestamp,
            horizontalAccuracy: accuracy, segment: segment
        ))
        revision += 1
        return true
    }

    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let deltaLatitude = (lat2 - lat1) * radians
        let deltaLongitude = (lon2 - lon1) * radians
        let a = pow(sin(deltaLatitude / 2), 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * pow(sin(deltaLongitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

nonisolated enum CardioRecordingPolicy {
    static func standaloneActivityID(in session: ActiveWorkoutRuntimeSession) -> UUID? {
        guard session.exercises.isEmpty, session.cardioBlocks.count == 1,
              let activity = session.cardioBlocks.first, usesSessionScreen(activity) else { return nil }
        return activity.id
    }

    static func usesSessionScreen(_ activity: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        let profile = WorkoutCardioTrackingProfileResolver.resolved(
            storedProfile: activity.trackingProfile,
            catalogExerciseUUID: activity.catalogExerciseUUID,
            exerciseName: activity.exerciseNameSnapshot, hasDistance: activity.actualDistanceMeters != nil
        )
        return recordsGPS(activity) || profile == .walkRun || profile == .treadmill
    }

    static func recordsGPS(_ activity: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        // Explicit outdoor identity is required: a generic/custom walk must not
        // unexpectedly collect a person's location.
        recordsGPS(catalogExerciseUUID: activity.catalogExerciseUUID)
    }

    static func recordsGPS(catalogExerciseUUID: String) -> Bool {
        ["seed-outdoor-walk", "seed-outdoor-run", "seed-outdoor-bike"].contains(catalogExerciseUUID)
    }

    static func maximumSpeedMetersPerSecond(for activity: ActiveWorkoutRuntimeCardioBlock) -> Double {
        activity.catalogExerciseUUID == "seed-outdoor-bike" ? 35 : 12
    }

    static func symbol(for activity: ActiveWorkoutRuntimeCardioBlock) -> String {
        if activity.catalogExerciseUUID == "seed-outdoor-bike" { return "figure.outdoor.cycle" }
        return activity.catalogExerciseUUID.contains("run") ? "figure.run" : "figure.walk"
    }
}
