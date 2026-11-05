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

        guard let value = Double(asciiDecimalDigits(in: normalized)), value.isFinite else { return nil }
        return value
    }

    static func optionalWholeNumber(_ text: String, fallback: Int?, maximum: Int = .max) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = asciiDecimalDigits(in: trimmed)
        guard normalized.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(normalized) else { return fallback }
        return min(maximum, value)
    }

    private static func asciiDecimalDigits(in text: String) -> String {
        // FormatStyle can emit native digits. Restrict conversion to decimal
        // digits so superscripts and other numeric symbols stay invalid.
        text.unicodeScalars.map { scalar in
            if scalar.properties.generalCategory == .decimalNumber,
               let digit = scalar.properties.numericValue {
                return String(Int(digit))
            }
            return String(scalar)
        }.joined()
    }
}
