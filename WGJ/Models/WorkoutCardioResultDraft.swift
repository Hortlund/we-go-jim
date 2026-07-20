import Foundation

nonisolated struct WorkoutCardioResultDraft: Equatable, Sendable {
    var actualDurationSeconds: Int?
    var distanceText: String
    var distanceUnit: WorkoutDistanceUnit
    var inclineText: String
    var resistanceLevelText: String
    var notes: String
    var trackingProfile: WorkoutCardioTrackingProfile

    private let originalDistanceMeters: Double?
    private let originalDistanceText: String?
    private let originalDistanceUnit: WorkoutDistanceUnit?

    init(
        actualDurationSeconds: Int?,
        distanceText: String,
        distanceUnit: WorkoutDistanceUnit,
        inclineText: String,
        resistanceLevelText: String,
        notes: String,
        trackingProfile: WorkoutCardioTrackingProfile
    ) {
        self.actualDurationSeconds = actualDurationSeconds
        self.distanceText = distanceText
        self.distanceUnit = distanceUnit
        self.inclineText = inclineText
        self.resistanceLevelText = resistanceLevelText
        self.notes = notes
        self.trackingProfile = trackingProfile
        self.originalDistanceMeters = nil
        self.originalDistanceText = nil
        self.originalDistanceUnit = nil
    }

    init(
        actualDurationSeconds: Int?,
        actualDistanceMeters: Double?,
        distanceUnit: WorkoutDistanceUnit,
        inclinePercent: Double?,
        resistanceLevel: Double?,
        notes: String,
        trackingProfile: WorkoutCardioTrackingProfile
    ) {
        let distanceText = actualDistanceMeters.map {
            WorkoutCardioSetupNumericCodec.distanceText(meters: $0, unit: distanceUnit)
        } ?? ""

        self.actualDurationSeconds = actualDurationSeconds
        self.distanceText = distanceText
        self.distanceUnit = distanceUnit
        self.inclineText = Self.numericText(inclinePercent)
        self.resistanceLevelText = Self.numericText(resistanceLevel)
        self.notes = notes
        self.trackingProfile = trackingProfile
        self.originalDistanceMeters = actualDistanceMeters
        self.originalDistanceText = distanceText
        self.originalDistanceUnit = distanceUnit
    }

    fileprivate var unchangedOriginalDistanceMeters: Double? {
        guard distanceText == originalDistanceText,
              distanceUnit == originalDistanceUnit,
              let originalDistanceMeters,
              originalDistanceMeters.isFinite,
              originalDistanceMeters > 0 else {
            return nil
        }
        return originalDistanceMeters
    }

    private static func numericText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(value)
    }
}

nonisolated struct ValidatedWorkoutCardioResult: Equatable, Sendable {
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit
    let inclinePercent: Double?
    let resistanceLevel: Double?
    let notes: String
}

nonisolated struct ActiveWorkoutCardioResultSavePlan: Equatable, Sendable {
    nonisolated enum PersistenceBoundary: Equatable, Sendable {
        case committedSnapshot
    }

    let session: ActiveWorkoutRuntimeSession
    let persistenceBoundary: PersistenceBoundary

    static func make(
        session: ActiveWorkoutRuntimeSession,
        activityID: UUID,
        result: ValidatedWorkoutCardioResult,
        at date: Date = .now
    ) throws -> ActiveWorkoutCardioResultSavePlan {
        var updatedSession = session
        guard let index = updatedSession.cardioBlocks.firstIndex(where: { $0.id == activityID }) else {
            throw WorkoutCardioTimerError.activityNotFound
        }

        updatedSession.cardioBlocks[index].actualDurationSeconds = result.actualDurationSeconds
        updatedSession.cardioBlocks[index].actualDistanceMeters = result.actualDistanceMeters
        updatedSession.cardioBlocks[index].preferredDistanceUnit = result.preferredDistanceUnit
        updatedSession.cardioBlocks[index].inclinePercent = result.inclinePercent
        updatedSession.cardioBlocks[index].resistanceLevel = result.resistanceLevel
        updatedSession.cardioBlocks[index].cardioNotes = result.notes
        updatedSession.cardioBlocks[index].updatedAt = date
        updatedSession.touch(date: date)

        return ActiveWorkoutCardioResultSavePlan(
            session: updatedSession,
            persistenceBoundary: .committedSnapshot
        )
    }
}

nonisolated enum WorkoutCardioResultValidationError: LocalizedError, Equatable, Sendable {
    case negativeDuration
    case invalidDistance
    case missingDurationAndDistance
    case invalidIncline
    case invalidResistanceLevel
    case negativeResistanceLevel

    var errorDescription: String? {
        switch self {
        case .negativeDuration:
            return "Duration cannot be negative."
        case .invalidDistance:
            return "Enter a valid distance, or leave it empty."
        case .missingDurationAndDistance:
            return "Enter a duration or distance."
        case .invalidIncline:
            return "Enter a valid incline percentage."
        case .invalidResistanceLevel:
            return "Enter a valid resistance or level."
        case .negativeResistanceLevel:
            return "Resistance or level cannot be negative."
        }
    }
}

nonisolated enum WorkoutCardioResultValidator {
    static func validated(
        _ draft: WorkoutCardioResultDraft,
        locale: Locale = .current
    ) throws -> ValidatedWorkoutCardioResult {
        if let duration = draft.actualDurationSeconds, duration < 0 {
            throw WorkoutCardioResultValidationError.negativeDuration
        }
        let duration = draft.actualDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
        let distance = try parsedDistance(draft, locale: locale)
        guard duration != nil || distance != nil else {
            throw WorkoutCardioResultValidationError.missingDurationAndDistance
        }

        return ValidatedWorkoutCardioResult(
            actualDurationSeconds: duration,
            actualDistanceMeters: distance,
            preferredDistanceUnit: draft.distanceUnit,
            inclinePercent: try incline(for: draft, locale: locale),
            resistanceLevel: try resistanceLevel(for: draft, locale: locale),
            notes: draft.notes
        )
    }

    private static func parsedDistance(
        _ draft: WorkoutCardioResultDraft,
        locale: Locale
    ) throws -> Double? {
        let text = draft.distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let displayValue = parsedNumber(text, locale: locale) else {
            throw WorkoutCardioResultValidationError.invalidDistance
        }
        guard displayValue > 0 else { return nil }

        if let originalMeters = draft.unchangedOriginalDistanceMeters {
            return originalMeters
        }

        let meters = draft.distanceUnit.meters(from: displayValue)
        guard meters.isFinite else {
            throw WorkoutCardioResultValidationError.invalidDistance
        }
        return meters
    }

    private static func incline(
        for draft: WorkoutCardioResultDraft,
        locale: Locale
    ) throws -> Double? {
        guard draft.trackingProfile == .treadmill else { return nil }
        let text = draft.inclineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = parsedNumber(text, locale: locale), value.isFinite else {
            throw WorkoutCardioResultValidationError.invalidIncline
        }
        return min(100, max(0, value))
    }

    private static func resistanceLevel(
        for draft: WorkoutCardioResultDraft,
        locale: Locale
    ) throws -> Double? {
        guard draft.trackingProfile.supportsResistanceOrLevel else { return nil }
        let text = draft.resistanceLevelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = parsedNumber(text, locale: locale), value.isFinite else {
            throw WorkoutCardioResultValidationError.invalidResistanceLevel
        }
        guard value >= 0 else {
            throw WorkoutCardioResultValidationError.negativeResistanceLevel
        }
        return value
    }

    private static func parsedNumber(_ text: String, locale: Locale) -> Double? {
        var normalized = text
        normalized.removeAll(where: \Character.isWhitespace)
        guard !normalized.isEmpty else { return nil }

        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        if decimalSeparator == "." {
            if groupingSeparator != "." {
                normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
            }
        } else if normalized.contains(decimalSeparator) {
            if groupingSeparator != decimalSeparator {
                normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
            }
            normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        } else if groupingSeparator != "." {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }

        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

nonisolated extension WorkoutCardioTrackingProfile {
    var supportsIncline: Bool {
        self == .treadmill
    }

    var supportsResistanceOrLevel: Bool {
        switch self {
        case .machineDistance, .rower, .stairClimber:
            return true
        case .walkRun, .treadmill, .timeOnly:
            return false
        }
    }
}

nonisolated enum WorkoutCardioTrackingProfileResolver {
    static func resolved(
        storedProfile: WorkoutCardioTrackingProfile?,
        identity: String,
        hasDistance: Bool
    ) -> WorkoutCardioTrackingProfile {
        if let storedProfile {
            return storedProfile
        }

        let normalizedIdentity = identity.lowercased()
        if normalizedIdentity.contains("treadmill") {
            return .treadmill
        }
        if normalizedIdentity.contains("rower")
            || normalizedIdentity.contains("rowing")
            || normalizedIdentity.contains("row-machine") {
            return .rower
        }
        if normalizedIdentity.contains("stair") {
            return .stairClimber
        }
        if normalizedIdentity.contains("outdoor")
            || normalizedIdentity.contains("walk")
            || normalizedIdentity.contains("run") {
            return .walkRun
        }
        if normalizedIdentity.contains("bike")
            || normalizedIdentity.contains("cycle")
            || normalizedIdentity.contains("cross")
            || normalizedIdentity.contains("elliptical") {
            return .machineDistance
        }
        return hasDistance ? .machineDistance : .timeOnly
    }
}

nonisolated struct WorkoutCardioResultSummary: Equatable, Sendable {
    nonisolated struct Metric: Identifiable, Equatable, Sendable {
        let title: String
        let value: String
        let systemImage: String

        var id: String { title }
    }

    let metrics: [Metric]
    let notes: String?
}

nonisolated enum WorkoutCardioResultSummaryFormatter {
    static func summary(
        durationSeconds: Int?,
        distanceMeters: Double?,
        displayUnit: WorkoutDistanceUnit,
        profile: WorkoutCardioTrackingProfile,
        inclinePercent: Double?,
        resistanceLevel: Double?,
        notes: String
    ) -> WorkoutCardioResultSummary {
        let validDuration = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
        let validDistance = distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let calculated = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: validDuration,
            distanceMeters: validDistance,
            displayUnit: displayUnit,
            profile: profile
        )
        var metrics: [WorkoutCardioResultSummary.Metric] = []

        switch profile {
        case .walkRun, .treadmill:
            if let pace = calculated.paceSecondsPerDisplayUnit {
                metrics.append(.init(
                    title: "Pace",
                    value: "\(paceText(seconds: pace)) /\(displayUnit.symbol)",
                    systemImage: "figure.run"
                ))
            }
        case .machineDistance:
            if let speed = calculated.averageSpeedPerHour {
                metrics.append(.init(
                    title: "Avg Speed",
                    value: speedText(speed, unit: displayUnit),
                    systemImage: "speedometer"
                ))
            }
        case .rower:
            if let pace = calculated.rowingPaceSecondsPer500Meters {
                metrics.append(.init(
                    title: "500 m Pace",
                    value: "\(paceText(seconds: pace)) /500 m",
                    systemImage: "figure.rower"
                ))
            }
        case .stairClimber, .timeOnly:
            break
        }

        if profile == .stairClimber,
           let resistanceLevel,
           resistanceLevel.isFinite,
           resistanceLevel >= 0 {
            metrics.append(.init(
                title: "Level",
                value: numberText(resistanceLevel),
                systemImage: "dial.medium.fill"
            ))
        }

        if let validDuration {
            metrics.append(.init(
                title: "Duration",
                value: durationText(seconds: validDuration),
                systemImage: "clock.fill"
            ))
        }
        if let validDistance {
            metrics.append(.init(
                title: "Distance",
                value: distanceText(meters: validDistance, unit: displayUnit),
                systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill"
            ))
        }

        if (profile == .walkRun || profile == .treadmill),
           let speed = calculated.averageSpeedPerHour {
            metrics.append(.init(
                title: "Avg Speed",
                value: speedText(speed, unit: displayUnit),
                systemImage: "speedometer"
            ))
        }

        if profile.supportsIncline, let inclinePercent, inclinePercent.isFinite {
            metrics.append(.init(
                title: "Incline",
                value: "\(numberText(min(100, max(0, inclinePercent))))%",
                systemImage: "angle"
            ))
        }
        if profile.supportsResistanceOrLevel,
           profile != .stairClimber,
           let resistanceLevel,
           resistanceLevel.isFinite,
           resistanceLevel >= 0 {
            metrics.append(.init(
                title: "Resistance",
                value: numberText(resistanceLevel),
                systemImage: "dial.medium.fill"
            ))
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutCardioResultSummary(
            metrics: metrics,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }

    static func summary(_ result: ValidatedWorkoutCardioResult, profile: WorkoutCardioTrackingProfile) -> WorkoutCardioResultSummary {
        summary(
            durationSeconds: result.actualDurationSeconds,
            distanceMeters: result.actualDistanceMeters,
            displayUnit: result.preferredDistanceUnit,
            profile: profile,
            inclinePercent: result.inclinePercent,
            resistanceLevel: result.resistanceLevel,
            notes: result.notes
        )
    }

    private static func durationText(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        if remainingSeconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private static func distanceText(meters: Double, unit: WorkoutDistanceUnit) -> String {
        "\(numberText(unit.value(fromMeters: meters))) \(unit.symbol)"
    }

    private static func paceText(seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600) / 60
        let seconds = rounded % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static func speedText(_ speed: Double, unit: WorkoutDistanceUnit) -> String {
        let unitText: String
        switch unit {
        case .kilometers:
            unitText = "km/h"
        case .miles:
            unitText = "mph"
        case .meters:
            unitText = "m/h"
        }
        return "\(numberText(speed)) \(unitText)"
    }

    private static func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
