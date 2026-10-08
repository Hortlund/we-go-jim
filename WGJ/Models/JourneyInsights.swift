import Foundation

nonisolated struct JourneyNextMilestone: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let progress: Double
}

nonisolated struct JourneyFact: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
}

nonisolated struct JourneyYearHighlights: Identifiable, Sendable {
    let id: Date
    let title: String
    let facts: [JourneyFact]
    let moments: [String]
}

nonisolated struct JourneyInsights: Sendable {
    var facts: [JourneyFact] = []
    var nextMilestones: [JourneyNextMilestone] = []
    var years: [JourneyYearHighlights] = []
}
