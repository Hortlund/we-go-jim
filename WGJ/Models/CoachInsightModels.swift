import Foundation

nonisolated enum CoachFollowUpKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case whatImproved
    case whyFlat
    case whatChanged
}

nonisolated enum CoachNarrativeAvailabilityMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case generated
    case fallback
}
