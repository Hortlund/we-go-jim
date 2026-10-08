import XCTest
@testable import WGJ

final class TrainingYearRecapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func workout(_ date: Date, duration: Int = 600, activities: [JourneyActivity] = []) -> JourneyWorkout {
        .init(id: UUID(), name: "Training", date: date, durationSeconds: duration,
              hasStrength: true, hasCardio: !activities.isEmpty, activities: activities)
    }

    private func activity(_ meters: Double, onFoot: Bool = true) -> JourneyActivity {
        .init(id: UUID(), exerciseID: onFoot ? "walk" : "bike", name: "Activity",
              distanceMeters: meters, durationSeconds: 600, isWalkRun: onFoot, isOutdoor: true)
    }

    private func recaps(_ workouts: [JourneyWorkout], calendar: Calendar? = nil, now: Date? = nil) -> [TrainingYearRecap] {
        let calendar = calendar ?? self.calendar
        let now = now ?? date(2026, 10, 3)
        let snapshot = TrainingJourneyBuilder.build(workouts: workouts, exercises: [], calendar: calendar, now: now)
        return TrainingYearRecapBuilder.build(snapshot, calendar: calendar, now: now)
    }

    func testTotalsUseOnlySelectedYearAndDistinctDays() throws {
        let workouts = [workout(date(2025, 12, 31), duration: 9_000, activities: [activity(30_000)]),
            workout(date(2026, 1, 1), duration: 1_800, activities: [activity(2_000)]),
            workout(date(2026, 1, 1), duration: 600), workout(date(2026, 3, 29), duration: -100)]
        let recap = try XCTUnwrap(recaps(workouts).first)
        XCTAssertEqual(recap.yearTitle, "2026")
        XCTAssertEqual(recap.workoutCount, 3)
        XCTAssertEqual(recap.activeDays, 2)
        XCTAssertEqual(recap.durationSeconds, 2_400)
        XCTAssertEqual(recap.walkRunDistanceMeters, 2_000)
        XCTAssertEqual(recap.trainingWeeks, 2)
        XCTAssertEqual(recap.months.map(\.workoutCount).reduce(0, +), 3)
        XCTAssertEqual(recap.busiestMonth, "January")
        XCTAssertEqual(recap.busiestMonthWorkoutCount, 2)
    }

    func testDistanceExcludesMachinesAndInvalidValues() throws {
        let workouts = [workout(date(2026, 3, 1), activities: [activity(1_000), activity(9_000, onFoot: false),
            activity(.nan), activity(-500), activity(.infinity)])]
        XCTAssertEqual(try XCTUnwrap(recaps(workouts).first).walkRunDistanceMeters, 1_000)
    }

    func testEmptyYearsAreOmittedAndCurrentYearIsMarkedAsInProgress() throws {
        XCTAssertTrue(recaps([]).isEmpty)
        let result = recaps([workout(date(2024, 2, 29)), workout(date(2026, 1, 1))])
        XCTAssertEqual(result.map(\.yearTitle), ["2026", "2024"])
        XCTAssertTrue(result[0].isYearInProgress)
        XCTAssertFalse(result[1].isYearInProgress)
        let finished = recaps([workout(date(2026, 1, 1))], now: date(2027, 1, 1))
        XCTAssertFalse(try XCTUnwrap(finished.first).isYearInProgress)
    }

    func testMilestonesAndHighlightsStayWithinYear() throws {
        let old = workout(date(2025, 3, 1))
        let current = workout(date(2026, 3, 1))
        let exercise = JourneyExercise(id: "bench", name: "Bench", isReps: false, usesAddedWeight: false,
            performances: [.init(sessionID: old.id, date: old.date, value: 50),
                .init(sessionID: current.id, date: current.date, value: 70)])
        let snapshot = TrainingJourneyBuilder.build(workouts: [old, current], exercises: [exercise],
            calendar: calendar, now: date(2026, 10, 3))
        let result = TrainingYearRecapBuilder.build(snapshot, calendar: calendar, now: date(2026, 10, 3))
        // PR, anniversary, comeback, first workout of the year, and 25% improvement.
        XCTAssertEqual(result[0].milestoneCount, 5)
        XCTAssertTrue(try XCTUnwrap(result[0].highlight).contains("Bench"))
        XCTAssertEqual(result[1].milestoneCount, 1)
        XCTAssertEqual(result[1].highlight, "Your first workout")
    }

    func testBusiestMonthTiesAreStableAndAllCalendarMonthsRemain() throws {
        let workouts = [workout(date(2026, 3, 1)), workout(date(2026, 1, 1))]
        XCTAssertEqual(recaps(workouts).first?.busiestMonth, recaps(workouts.reversed()).first?.busiestMonth)
        XCTAssertEqual(recaps(workouts).first?.busiestMonth, "January")
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = calendar.timeZone
        let leap = try XCTUnwrap(recaps([workout(date(2024, 3, 15))], calendar: hebrew).first)
        XCTAssertEqual(leap.months.count, 13)
        XCTAssertEqual(leap.months.reduce(0) { $0 + $1.workoutCount }, 1)
        XCTAssertEqual(Set(leap.months.map(\.id)).count, 13)
    }

    func testCardioPRHighlightWinsOverLaterWorkoutMilestone() throws {
        for metric in ["distance", "speed"] {
            let firstActivity = JourneyActivity(id: UUID(), exerciseID: "run", name: "Outdoor Run",
                distanceMeters: 1_000, durationSeconds: 600, isWalkRun: true, isOutdoor: true)
            let recordActivity = JourneyActivity(id: UUID(), exerciseID: "run", name: "Outdoor Run",
                distanceMeters: metric == "distance" ? 2_000 : 1_000,
                durationSeconds: metric == "distance" ? 1_200 : 500, isWalkRun: true, isOutdoor: true)
            let workouts = [workout(date(2026, 1, 1), activities: [firstActivity]),
                workout(date(2026, 1, 2), activities: [recordActivity])]
                + (3...10).map { workout(date(2026, 1, $0)) }
            let now = date(2026, 10, 3)
            let snapshot = TrainingJourneyBuilder.build(workouts: workouts, exercises: [], calendar: calendar, now: now)
            let record = try XCTUnwrap(snapshot.milestones.first { $0.personalRecord != nil })
            XCTAssertEqual(record.id, "cardio-pr-\(metric)-\(recordActivity.id)")
            XCTAssertEqual(snapshot.milestones.first { $0.id == "workouts-10" }?.sessionID, workouts.last?.id)
            let recap = try XCTUnwrap(TrainingYearRecapBuilder.build(snapshot, calendar: calendar, now: now).first)
            XCTAssertEqual(recap.highlight, record.title)
        }
    }

    @MainActor
    func testRecapRendersAtStoryResolutionWithLongLabelsAndThirteenMonths() throws {
        let months = (0..<13).map { index in
            TrainingYearRecap.Month(date: date(2026, 1, 1).addingTimeInterval(Double(index) * 86_400),
                label: "Month \(index + 1)", workoutCount: index * 2)
        }
        let recap = TrainingYearRecap(yearStart: date(2026, 1, 1), yearTitle: "31 Heisei – 1 Reiwa",
            isYearInProgress: false, workoutCount: 148, activeDays: 132, durationSeconds: 64 * 3_600,
            walkRunDistanceMeters: 182_400, distanceUnit: .kilometers, trainingWeeks: 42, milestoneCount: 18,
            months: months, busiestMonth: "September", busiestMonthWorkoutCount: 24,
            highlight: "Barbell Bench Press with a deliberately long exercise name · 100 kg")
        let image = try XCTUnwrap(TrainingYearRecapRenderer.render(recap))
        XCTAssertEqual(image.cgImage?.width, 1_080)
        XCTAssertEqual(image.cgImage?.height, 1_920)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Year recap with long labels and thirteen months"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
