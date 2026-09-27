import Foundation

/// Cosmetic, local-only surprises. No workout values or training rules depend on these.
nonisolated enum GymEasterEggPolicy {
    static let unlockedKey = "wgj.gymBro.unlocked"
    static let enabledKey = "wgj.gymBro.enabled"
    static let searchMessage = String(localized: "No results. We go jim.")
    static let restMessage = String(localized: "Bro is negotiating with the next set.")
    static let warmupMessage = String(localized: "Respect the empty bar. It was here before you.")

    enum Completion: Equatable, Sendable {
        case lightWeight, stairs, sitting, heavyCircles, lore, gravity, reracked, oneMoreSet

        var message: String {
            switch self {
            case .lightWeight: String(localized: "LIGHT WEIGHT, BABY!")
            case .stairs: String(localized: "Workout saved. Stairs are now your enemy.")
            case .sitting: String(localized: "Good luck sitting down tomorrow.")
            case .heavyCircles: String(localized: "Heavy circles moved successfully.")
            case .lore: String(localized: "The lore continues.")
            case .gravity: String(localized: "You vs. gravity. Rematch pending.")
            case .reracked: String(localized: "All that work just to put the weights back.")
            case .oneMoreSet: String(localized: "One more set. Famous last words.")
            }
        }
    }

    static func searchMatches(_ query: String) -> Bool {
        ["motivation", "excuses"].contains(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isLegDay(scores: [ExerciseBodyMapRegion: Double]) -> Bool {
        let legs: Set<ExerciseBodyMapRegion> = [.quadriceps, .hamstring, .gluteal, .calves, .adductors]
        let total = scores.values.reduce(0, +)
        let lowerBody = scores.filter { legs.contains($0.key) }.values.reduce(0, +)
        return total > 0 && lowerBody / total >= 0.6
    }

    static func completion(sessionID: UUID, workingSets: Int, hasWeightPR: Bool,
                           isLegDay: Bool, gymBroMode: Bool) -> Completion? {
        guard workingSets > 0 else { return nil }
        let roll = seed(sessionID)
        if hasWeightPR && roll % 4 == 0 { return .lightWeight }
        if isLegDay && workingSets >= 3 && roll % 3 == 0 {
            return roll % 2 == 0 ? .stairs : .sitting
        }
        guard gymBroMode || roll % 5 == 0 else { return nil }
        let messages: [Completion] = [.heavyCircles, .lore, .gravity, .reracked, .oneMoreSet]
        return messages[Int((roll / 7) % UInt64(messages.count))]
    }

    static func canRevealRest(completedRest: RestTimerSnapshot?, sessionStartedAt: Date, now: Date) -> Bool {
        guard let rest = completedRest, let source = rest.sourceSetID,
              rest.endsAt >= sessionStartedAt else { return false }
        let overrun = now.timeIntervalSince(rest.endsAt)
        return overrun >= 180 && overrun < 900 && seed(source) % 3 == 0
    }

    /// Stable across launches: reopening a recap must not reroll its joke.
    private static func seed(_ id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

nonisolated struct GymLogoTapProgress {
    private(set) var count = 0
    private var lastTap: Date?

    mutating func tap(at date: Date = .now) -> Bool {
        if let lastTap, date.timeIntervalSince(lastTap) > 3 { count = 0 }
        lastTap = date
        count += 1
        guard count == 7 else { return false }
        count = 0
        return true
    }
}
