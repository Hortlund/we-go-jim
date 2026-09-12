import Foundation

/// Locale-aware finite numbers. Positivity, bounds, and unit conversion belong to callers.
nonisolated enum LocalizedFiniteNumberParser {
    static func parse(_ text: String, locale: Locale) -> Double? {
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
