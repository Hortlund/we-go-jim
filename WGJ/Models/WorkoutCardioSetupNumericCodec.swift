import Foundation

nonisolated enum WorkoutCardioSetupNumericCodec {
    static func durationMinutesText(seconds: Int) -> String {
        let safeSeconds = max(0, min(24 * 60 * 60, seconds))
        guard safeSeconds % 60 != 0 else {
            return String(safeSeconds / 60)
        }
        return canonicalText(Double(safeSeconds) / 60)
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
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.removeAll(where: \.isWhitespace)
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

        guard let value = Double(normalized), value.isFinite, value > 0 else {
            return nil
        }
        return value
    }
}
