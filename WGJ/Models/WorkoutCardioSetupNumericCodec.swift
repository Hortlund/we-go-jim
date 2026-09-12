import Foundation

nonisolated enum WorkoutCardioSetupNumericCodec {
    static func durationMinutesText(seconds: Int) -> String {
        let safeSeconds = max(0, min(24 * 60 * 60, seconds))
        guard safeSeconds % 60 != 0 else {
            return String(safeSeconds / 60)
        }
        let roundedMinutes = (Double(safeSeconds) / 60 * 100).rounded() / 100
        return canonicalText(roundedMinutes)
    }

    static func distanceText(meters: Double, unit: WorkoutDistanceUnit) -> String {
        guard meters.isFinite, meters > 0 else { return "" }

        let initialValue = unit.value(fromMeters: meters)
        var lowerValue = initialValue
        var upperValue = initialValue
        for _ in 0..<16 {
            for candidate in [lowerValue, upperValue] where candidate.isFinite && candidate > 0 {
                let text = canonicalText(candidate)
                guard let parsed = Double(text) else { continue }
                if unit.meters(from: parsed) == meters {
                    return text
                }
            }
            lowerValue = lowerValue.nextDown
            upperValue = upperValue.nextUp
        }

        return canonicalText(initialValue)
    }

    static func durationSeconds(
        fromMinutesText text: String,
        locale: Locale
    ) -> Int? {
        guard let minutes = positiveNumber(from: text, locale: locale) else {
            return nil
        }
        let cappedMinutes = min(minutes, Double(24 * 60))
        return max(1, Int((cappedMinutes * 60).rounded()))
    }

    static func distanceMeters(
        from text: String,
        unit: WorkoutDistanceUnit,
        locale: Locale
    ) -> Double? {
        guard let distance = positiveNumber(from: text, locale: locale) else {
            return nil
        }
        let meters = unit.meters(from: distance)
        return meters.isFinite && meters > 0 ? meters : nil
    }

    private static func canonicalText(_ value: Double) -> String {
        String(value)
    }

    private static func positiveNumber(from text: String, locale: Locale) -> Double? {
        guard let value = LocalizedFiniteNumberParser.parse(text, locale: locale), value > 0 else {
            return nil
        }
        return value
    }
}

/// Actual results intentionally use an uncapped codec. Planned targets remain
/// bounded by `WorkoutCardioSetupNumericCodec`, while imported or manually
/// entered results can represent multi-day activities without data loss.
nonisolated enum WorkoutCardioResultDurationCodec {
    static func durationMinutesText(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        guard safeSeconds % 60 != 0 else {
            return String(safeSeconds / 60)
        }
        let roundedMinutes = (Double(safeSeconds) / 60 * 100).rounded() / 100
        return String(roundedMinutes)
    }

    static func durationSeconds(
        fromMinutesText text: String,
        locale: Locale
    ) -> Int? {
        guard let minutes = LocalizedFiniteNumberParser.parse(text, locale: locale),
              minutes > 0,
              minutes <= Double(Int.max / 60) else {
            return nil
        }
        let seconds = (minutes * 60).rounded()
        // Double(Int.max) rounds up beyond Int's range on 64-bit devices.
        guard seconds >= 1, let exactSeconds = Int(exactly: seconds) else {
            return nil
        }
        return exactSeconds
    }
}
