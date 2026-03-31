import Foundation

enum WGJFormatters {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let oneDecimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func decimalString(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func oneDecimalString(_ value: Double) -> String {
        oneDecimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func integerString(_ value: Double) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    static func parseLocalizedDecimal(_ text: String) -> Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = normalizedLocalizedDecimalText(text, separator: separator)

        guard !normalized.isEmpty else { return nil }
        if let parsed = decimalFormatter.number(from: normalized)?.doubleValue {
            return parsed
        }

        guard normalized.hasSuffix(separator) else { return nil }
        let trimmed = String(normalized.dropLast(separator.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return decimalFormatter.number(from: trimmed)?.doubleValue
    }

    private static func normalizedLocalizedDecimalText(_ text: String, separator: String) -> String {
        text
            .replacingOccurrences(of: ",", with: separator)
            .replacingOccurrences(of: ".", with: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
