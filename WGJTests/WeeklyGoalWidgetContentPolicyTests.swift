import XCTest
@testable import WGJ

final class WeeklyGoalWidgetContentPolicyTests: XCTestCase {
    func testWeeklyGoalCalendarUsesMondayStartInUserTimeZone() throws {
        let calendar = WeeklyGoalWeekPolicy.calendar(
            timeZone: try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        )
        let sundayNight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 28,
            hour: 23,
            minute: 59
        )))
        let expectedWeekStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 22,
            hour: 0,
            minute: 0
        )))
        let expectedNextWeekStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 29,
            hour: 0,
            minute: 0
        )))

        XCTAssertEqual(calendar.firstWeekday, 2)
        XCTAssertEqual(WeeklyGoalWeekPolicy.weekStart(for: sundayNight, calendar: calendar), expectedWeekStart)
        XCTAssertEqual(WeeklyGoalWeekPolicy.nextWeekStart(after: sundayNight, calendar: calendar), expectedNextWeekStart)
    }

    func testResolvedSnapshotRollsOverAtLocalMondayMidnight() throws {
        let calendar = try makeMondayCalendar(timeZoneIdentifier: "Europe/Stockholm")
        let previousWeekStart = try XCTUnwrap(calendar.date(from: DateComponents(
            weekday: 2,
            weekOfYear: 26,
            yearForWeekOfYear: 2026
        )))
        let rolloverDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 29,
            hour: 0,
            minute: 0
        )))
        let expectedCurrentWeekStart = rolloverDate
        let expectedCurrentWeekEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: expectedCurrentWeekStart))
        let staleSnapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 3,
            weeklyGoal: 4,
            weekStart: previousWeekStart,
            recentWeeks: [
                WeeklyGoalWidgetWeek(
                    weekStart: previousWeekStart,
                    completedWorkouts: 3,
                    goal: 4
                ),
            ],
            calendar: calendar,
            generatedAt: previousWeekStart
        )

        let resolved = WeeklyGoalWidgetContentPolicy.resolvedSnapshot(
            staleSnapshot,
            asOf: rolloverDate,
            calendar: calendar
        )

        XCTAssertEqual(resolved.completedWorkouts, 0)
        XCTAssertEqual(resolved.weeklyGoal, 4)
        XCTAssertEqual(resolved.weekStart, expectedCurrentWeekStart)
        XCTAssertEqual(resolved.weekEnd, expectedCurrentWeekEnd)
        XCTAssertEqual(resolved.recentWeeks.map(\.weekStart), [previousWeekStart, expectedCurrentWeekStart])
        XCTAssertEqual(resolved.recentWeeks.map(\.completedWorkouts), [3, 0])
    }

    func testResolvedSnapshotKeepsCurrentWeekBeforeLocalMondayMidnight() throws {
        let calendar = try makeMondayCalendar(timeZoneIdentifier: "Europe/Stockholm")
        let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(
            weekday: 2,
            weekOfYear: 26,
            yearForWeekOfYear: 2026
        )))
        let beforeRolloverDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 28,
            hour: 23,
            minute: 59
        )))
        let snapshot = WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 3,
            weeklyGoal: 4,
            weekStart: weekStart,
            recentWeeks: [
                WeeklyGoalWidgetWeek(
                    weekStart: weekStart,
                    completedWorkouts: 3,
                    goal: 4
                ),
            ],
            calendar: calendar,
            generatedAt: weekStart
        )

        let resolved = WeeklyGoalWidgetContentPolicy.resolvedSnapshot(
            snapshot,
            asOf: beforeRolloverDate,
            calendar: calendar
        )

        XCTAssertEqual(resolved, snapshot)
    }

    private func makeMondayCalendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}
