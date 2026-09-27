import Foundation
import Observation

nonisolated struct BirthdayOccasion: Equatable, Identifiable, Sendable {
    let profileID: UUID
    let year: Int
    let displayName: String
    var id: String { "\(profileID.uuidString)-\(year)" }

    var greeting: String {
        displayName.isEmpty || displayName == "Athlete"
            ? String(localized: "Happy birthday!")
            : String(localized: "Happy birthday, \(displayName)!")
    }
}

nonisolated enum BirthdayCelebrationPolicy {
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func isBirthday(dateOfBirth: Date?, on date: Date, calendar: Calendar = localCalendar) -> Bool {
        guard let dateOfBirth, dateOfBirth < date else { return false }
        let birth = calendar.dateComponents([.month, .day], from: dateOfBirth)
        let today = calendar.dateComponents([.month, .day], from: date)
        var day = birth.day
        // Celebrate leap-day birthdays on February 28 in non-leap years.
        if birth.month == 2, birth.day == 29, today.month == 2,
           calendar.range(of: .day, in: .month, for: date)?.count == 28 {
            day = 28
        }
        return birth.month == today.month && day == today.day
    }

    static func occasion(profileID: UUID, displayName: String, dateOfBirth: Date?,
                         on date: Date, calendar: Calendar = localCalendar) -> BirthdayOccasion? {
        guard isBirthday(dateOfBirth: dateOfBirth, on: date, calendar: calendar) else { return nil }
        return BirthdayOccasion(profileID: profileID, year: calendar.component(.year, from: date),
                                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Cosmetic preferences stay on this device, separate from the profile and backup data.
@MainActor @Observable
final class BirthdayCelebrationPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    private var revision = 0

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    nonisolated deinit { }

    func isDismissed(_ occasion: BirthdayOccasion) -> Bool {
        _ = revision
        return defaults.integer(forKey: key("dismissed", occasion)) == occasion.year
    }

    func dismiss(_ occasion: BirthdayOccasion) {
        defaults.set(occasion.year, forKey: key("dismissed", occasion))
        revision += 1
    }

    func claimConfetti(_ occasion: BirthdayOccasion) -> Bool {
        guard !isDismissed(occasion), defaults.integer(forKey: key("celebrated", occasion)) != occasion.year else { return false }
        defaults.set(occasion.year, forKey: key("celebrated", occasion))
        return true
    }

    private func key(_ kind: String, _ occasion: BirthdayOccasion) -> String {
        "birthday.\(kind).\(occasion.profileID.uuidString)"
    }
}
