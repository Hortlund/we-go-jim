import Foundation

/// Local cosmetic state only. Never touches workout storage or CloudKit.
@MainActor
final class JourneyCelebrationPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func claim(_ events: [JourneyMilestone], scope: String, now: Date = .now) -> Int {
        let key = "journey.celebrated.v1.\(scope)"
        let saved = defaults.stringArray(forKey: key)
        let seen = Set(saved ?? [])
        let current = Set(events.map(\.id))
        let combined = seen.union(current)
        if saved == nil || combined != seen { defaults.set(combined.sorted(), forKey: key) }
        // On first use, quietly backfill old history. Later imports/edits also never shower old badges.
        let window: TimeInterval = saved == nil ? 24 * 3_600 : 7 * 24 * 3_600
        return events.filter {
            let earned = $0.unlockedAt ?? $0.date
            return !seen.contains($0.id) && earned <= now && now.timeIntervalSince(earned) <= window
        }.count
    }
}
