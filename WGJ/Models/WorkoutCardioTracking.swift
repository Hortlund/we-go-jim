import Foundation

nonisolated enum WorkoutCardioRole: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case warmUp
    case main
    case finisher

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .warmUp:
            return 0
        case .main:
            return 1
        case .finisher:
            return 2
        }
    }
}

nonisolated enum WorkoutCardioGoalKind: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case time
    case distance
    case open

    var id: String { rawValue }
}

nonisolated enum WorkoutDistanceUnit: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case kilometers
    case miles
    case meters

    var id: String { rawValue }

    var symbol: String {
        unitLength.symbol
    }

    func meters(from value: Double) -> Double {
        Measurement(value: value, unit: unitLength)
            .converted(to: .meters)
            .value
    }

    func value(fromMeters meters: Double) -> Double {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: unitLength)
            .value
    }

    nonisolated static func regionalDefault(locale: Locale) -> WorkoutDistanceUnit {
        switch locale.measurementSystem {
        case .us, .uk:
            return .miles
        default:
            return .kilometers
        }
    }

    private var unitLength: UnitLength {
        switch self {
        case .kilometers:
            return .kilometers
        case .miles:
            return .miles
        case .meters:
            return .meters
        }
    }
}

nonisolated enum WorkoutCardioTrackingProfile: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case walkRun
    case treadmill
    case machineDistance
    case rower
    case stairClimber
    case timeOnly

    var id: String { rawValue }
}

nonisolated enum WorkoutCardioTimerState: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case idle
    case running
    case paused

    var id: String { rawValue }
}

nonisolated struct WorkoutCardioMetricResult: Equatable, Sendable {
    let paceSecondsPerDisplayUnit: Double?
    let averageSpeedPerHour: Double?
    let rowingPaceSecondsPer500Meters: Double?

    static let empty = Self(
        paceSecondsPerDisplayUnit: nil,
        averageSpeedPerHour: nil,
        rowingPaceSecondsPer500Meters: nil
    )
}

nonisolated enum WorkoutCardioMetricsCalculator {
    static func calculate(
        durationSeconds: Int?,
        distanceMeters: Double?,
        displayUnit: WorkoutDistanceUnit,
        profile: WorkoutCardioTrackingProfile
    ) -> WorkoutCardioMetricResult {
        guard let durationSeconds, durationSeconds > 0,
              let distanceMeters, distanceMeters.isFinite, distanceMeters > 0 else {
            return .empty
        }

        let duration = TimeInterval(durationSeconds)
        let displayDistance = displayUnit.value(fromMeters: distanceMeters)
        let hours = duration / 3_600
        let pace = duration / displayDistance
        let speed = displayDistance / hours
        let rowPace = duration * 500 / distanceMeters

        return .init(
            paceSecondsPerDisplayUnit: [.walkRun, .treadmill].contains(profile) ? displayablePace(pace) : nil,
            averageSpeedPerHour: profile == .timeOnly || profile == .stairClimber || profile == .rower ? nil : finitePositive(speed),
            rowingPaceSecondsPer500Meters: profile == .rower ? displayablePace(rowPace) : nil
        )
    }

    private static func finitePositive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func displayablePace(_ value: Double) -> Double? {
        // Tiny distances can overflow division or the whole-second formatter.
        guard value > 0, Int(exactly: value.rounded()) != nil else { return nil }
        return value
    }
}
