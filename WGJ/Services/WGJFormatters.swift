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
        let normalized = text
            .replacingOccurrences(of: ",", with: separator)
            .replacingOccurrences(of: ".", with: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        return decimalFormatter.number(from: normalized)?.doubleValue
    }
}
