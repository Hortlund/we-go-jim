import SwiftData
import XCTest
@testable import WGJ

final class BirthdayCelebrationTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMatchesBirthdayEveryYearWithoutAnAgeRequirement() {
        let birth = date("1990-09-27T12:00:00Z")
        for year in [2026, 2027, 2099] {
            XCTAssertTrue(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("\(year)-09-27T00:00:00Z"), calendar: calendar))
            XCTAssertFalse(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("\(year)-09-28T00:00:00Z"), calendar: calendar))
        }
        XCTAssertFalse(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: nil, on: .now))
        XCTAssertFalse(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: date("2099-09-27T12:00:00Z"), on: birth))
    }

    func testLeapDayUsesFebruary28OnlyInNonLeapYears() {
        let birth = date("2000-02-29T12:00:00Z")
        for (day, expected) in [("2027-02-28", true), ("2028-02-28", false), ("2028-02-29", true), ("2027-03-01", false)] {
            XCTAssertEqual(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("\(day)T12:00:00Z"), calendar: calendar), expected)
        }
    }

    func testUsesLocalDayAtMidnight() {
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: 3600)!
        let birth = date("1990-09-27T12:00:00Z")
        XCTAssertFalse(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("2026-09-26T22:59:59Z"), calendar: local))
        XCTAssertTrue(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("2026-09-26T23:00:00Z"), calendar: local))
        XCTAssertFalse(BirthdayCelebrationPolicy.isBirthday(dateOfBirth: birth, on: date("2026-09-27T23:00:00Z"), calendar: local))
    }

    @MainActor
    func testConfettiAndDismissalPersistPerProfileAndYear() throws {
        let suite = "BirthdayCelebrationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let occasion = BirthdayOccasion(profileID: UUID(), year: 2026, displayName: "Andreas")
        let preferences = BirthdayCelebrationPreferences(defaults: defaults)
        XCTAssertTrue(preferences.claimConfetti(occasion))
        let reloaded = BirthdayCelebrationPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.claimConfetti(occasion))
        preferences.dismiss(occasion)
        XCTAssertTrue(reloaded.isDismissed(occasion))
        XCTAssertFalse(reloaded.claimConfetti(occasion))
        let nextYear = BirthdayOccasion(profileID: occasion.profileID, year: 2027, displayName: "Andreas")
        XCTAssertFalse(reloaded.isDismissed(nextYear))
        XCTAssertTrue(reloaded.claimConfetti(nextYear))
        XCTAssertTrue(reloaded.claimConfetti(BirthdayOccasion(profileID: UUID(), year: 2026, displayName: "")))
    }

    func testGreetingUsesNameWithoutDisplayingAge() throws {
        let occasion = try XCTUnwrap(BirthdayCelebrationPolicy.occasion(profileID: UUID(), displayName: "  Andreas  ",
            dateOfBirth: date("1990-09-27T12:00:00Z"), on: date("2026-09-27T12:00:00Z"), calendar: calendar))
        XCTAssertEqual(occasion.greeting, "Happy birthday, Andreas!")
        XCTAssertEqual(BirthdayOccasion(profileID: UUID(), year: 2026, displayName: "Athlete").greeting, "Happy birthday!")
    }
}
