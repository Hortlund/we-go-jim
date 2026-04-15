import Foundation

nonisolated enum ReviewTextKind {
    case displayName
    case workoutName
    case exerciseName
    case templateName
    case folderName

    var fieldLabel: String {
        switch self {
        case .displayName:
            return "Display name"
        case .workoutName:
            return "Workout name"
        case .exerciseName:
            return "Exercise name"
        case .templateName:
            return "Template name"
        case .folderName:
            return "Folder name"
        }
    }

    var fallbackValue: String {
        switch self {
        case .displayName:
            return "Athlete"
        case .workoutName, .templateName:
            return "Workout"
        case .exerciseName:
            return "Exercise"
        case .folderName:
            return "Program"
        }
    }

    var maxLength: Int {
        switch self {
        case .displayName:
            return 32
        case .workoutName, .templateName, .folderName:
            return 60
        case .exerciseName:
            return 72
        }
    }
}

nonisolated enum ReviewModerationError: LocalizedError, Equatable {
    case emptyField(String)
    case tooLong(String, Int)
    case disallowedContent(String)

    var errorDescription: String? {
        switch self {
        case .emptyField(let label):
            return "\(label) is required."
        case .tooLong(let label, let limit):
            return "\(label) must be \(limit) characters or fewer."
        case .disallowedContent(let label):
            return "\(label) can't include profanity, slurs, links, or contact details."
        }
    }
}

nonisolated enum ReviewModerationService {
    private static let blockedTerms: [String] = [
        "asshole",
        "bastard",
        "bitch",
        "bullshit",
        "cunt",
        "dick",
        "douche",
        "fag",
        "faggot",
        "fuck",
        "motherfucker",
        "nigger",
        "porn",
        "pussy",
        "retard",
        "shit",
        "slut",
        "whore",
    ]

    private static let blockedFragments: [String] = [
        "discord.gg/",
        "http://",
        "https://",
        "onlyfans",
        "snapchat",
        "telegram",
        "www.",
    ]

    static func validateUserInput(_ text: String, kind: ReviewTextKind) throws -> String {
        let cleaned = normalized(text)
        guard !cleaned.isEmpty else {
            throw ReviewModerationError.emptyField(kind.fieldLabel)
        }

        guard cleaned.count <= kind.maxLength else {
            throw ReviewModerationError.tooLong(kind.fieldLabel, kind.maxLength)
        }

        guard !containsDisallowedContent(cleaned) else {
            throw ReviewModerationError.disallowedContent(kind.fieldLabel)
        }

        return cleaned
    }

    static func sanitizedForSharing(_ text: String, kind: ReviewTextKind) -> String {
        let cleaned = normalized(text)
        guard !cleaned.isEmpty else {
            return kind.fallbackValue
        }

        guard cleaned.count <= kind.maxLength else {
            return kind.fallbackValue
        }

        guard !containsDisallowedContent(cleaned) else {
            return kind.fallbackValue
        }

        return cleaned
    }

    static func containsDisallowedContent(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if blockedFragments.contains(where: lowered.contains) {
            return true
        }

        if containsLinkLikeContent(in: text) {
            return true
        }

        let normalizedStream = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return blockedTerms.contains { term in
            normalizedStream.contains(term)
        }
    }

    private static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsLinkLikeContent(in text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: nsRange) != nil
    }
}
