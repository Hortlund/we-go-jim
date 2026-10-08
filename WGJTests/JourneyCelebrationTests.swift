import XCTest
@testable import WGJ

final class JourneyCelebrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 1, _ day: Int = 1) -> Date {
        calendar.date(from: .init(year: year, month: month, day: day, hour: 12))!
    }
    private func workout(_ date: Date, duration: Int = 1_800, activities: [JourneyActivity] = [],
                         exercises: [JourneyCompletedExercise] = []) -> JourneyWorkout {
        .init(id: UUID(), name: "Training", date: date, durationSeconds: duration,
            hasStrength: !exercises.isEmpty, hasCardio: !activities.isEmpty, activities: activities,
            completedExercises: exercises)
    }
    private func activity(_ id: String = "walk", distance: Double, profile: WorkoutCardioTrackingProfile = .walkRun,
                          cycling: Bool = false, duration: Int = 3_600) -> JourneyActivity {
        .init(id: UUID(), exerciseID: id, name: id, distanceMeters: distance, durationSeconds: duration,
            isWalkRun: profile == .walkRun, isOutdoor: false, trackingProfile: profile, isCycling: cycling)
    }
    private func build(_ workouts: [JourneyWorkout], exercises: [JourneyExercise] = [], now: Date? = nil,
                       unit: WorkoutDistanceUnit = .kilometers) -> TrainingJourneySnapshot {
        TrainingJourneyBuilder.build(workouts: workouts, exercises: exercises, distanceUnit: unit,
            calendar: calendar, now: now ?? date(2027))
    }
    private func event(_ id: String, in snapshot: TrainingJourneySnapshot) -> JourneyMilestone? {
        snapshot.milestones.first { $0.id == "celebration-\(id)" }
    }

    func testAnniversaryRequiresWorkoutAndComebackUsesCalendarDays() throws {
        let first = workout(date(2024, 2, 29))
        let before = workout(date(2025, 2, 27))
        let anniversary = workout(date(2025, 2, 28))
        XCTAssertNil(event("anniversary-1", in: build([first], now: date(2026))))
        let result = build([first, before, anniversary])
        XCTAssertEqual(event("anniversary-1", in: result)?.sessionID, anniversary.id)
        XCTAssertNotNil(event("comeback-\(before.id)", in: result))
        XCTAssertNil(event("comeback-\(anniversary.id)", in: result))
        XCTAssertEqual(result.milestones.filter { $0.id.hasPrefix("celebration-new-year-") }.count, 1)
    }

    func testMonthAwardsCountDistinctDaysAndWaitUntilMonthCloses() throws {
        let january = (1...5).flatMap { day in [workout(date(2026, 1, day)), workout(date(2026, 1, day))] }
        let february = (1...10).map { workout(date(2026, 2, $0)) }
        let open = build(january + february, now: date(2026, 2, 28))
        XCTAssertTrue([january[8].id, january[9].id].contains(event("rhythm-5", in: open)!.sessionID))
        XCTAssertNil(event("rhythm-15", in: open))
        XCTAssertFalse(open.milestones.contains { $0.id.hasPrefix("celebration-best-month-") })
        let closed = build(january + february, now: date(2026, 3, 1))
        let record = try XCTUnwrap(closed.milestones.first { $0.id.hasPrefix("celebration-best-month-") })
        XCTAssertEqual(record.sessionID, february.last?.id)
        XCTAssertEqual(record.unlockedAt, calendar.dateInterval(of: .month, for: date(2026, 2, 1))?.end)
        XCTAssertEqual(closed.insights.facts.first { $0.id == "month" }?.value.contains("10 days"), true)
    }

    func testDistanceComparisonsAndSportTotalsDoNotDuplicate100Km() throws {
        let sessions = [workout(date(), activities: [activity(distance: 21_097.5)]),
            workout(date(2026, 1, 2), activities: [activity(distance: 78_902.5),
                activity("bike", distance: 100_000, profile: .machineDistance, cycling: true),
                activity("row", distance: 50_000, profile: .rower),
                activity("stairs", distance: 1_000_000, profile: .stairClimber)])]
        let snapshot = build(sessions)
        XCTAssertNotNil(event("foot-21097", in: snapshot))
        XCTAssertNotNil(event("foot-42195", in: snapshot))
        XCTAssertNil(event("foot-100000", in: snapshot))
        XCTAssertEqual(snapshot.milestones.first { $0.id == "total-distance-kilometers-100.0" }?.playfulTitle,
            "You've walked into another postcode")
        XCTAssertNotNil(event("cycling-100km", in: snapshot))
        XCTAssertNotNil(event("rowing-50km", in: snapshot))
        XCTAssertNotNil(event("foot-100000", in: build(sessions, unit: .miles)))
        XCTAssertEqual(snapshot.walkRunDistanceMeters, 100_000)
    }

    func testVarietyLegsAndMixedUseCompletedExerciseIdentity() {
        let sessions = [workout(date(), activities: [activity(distance: 1_000)], exercises: [
            .init(id: "squat", name: "Squat", isLegExercise: true), .init(id: "press", name: "Press"),
            .init(id: "press", name: "Press")])]
        let snapshot = build(sessions)
        XCTAssertNotNil(event("variety-3", in: snapshot))
        XCTAssertNil(event("variety-5", in: snapshot))
        XCTAssertNotNil(event("leg-day", in: snapshot))
        XCTAssertNotNil(event("mixed", in: snapshot))
        XCTAssertEqual(snapshot.milestones.first { $0.id == "first-cardio-walk" }?.playfulTitle, "Side quest unlocked")
        XCTAssertNil(event("leg-day", in: build([workout(date(), exercises: [.init(id: "unknown", name: "Legs?")])])))
    }

    func testPRCollectionsSequelImprovementAndMontageDoNotInflatePRs() {
        let sessions = (1...5).map { workout(date(2026, 1, $0), activities: [activity(distance: 1_000)]) }
        let exercises = (1...3).map { index in
            JourneyExercise(id: "exercise-\(index)", name: "Exercise \(index)", isReps: index == 3, usesAddedWeight: false,
                performances: zip(sessions, [10.0, 12.5, 15, 20, 21]).map { .init(sessionID: $0.0.id, date: $0.0.date, value: $0.1) })
        }
        // Set strength flags through real completed exercise metadata.
        let mixed = sessions.map { session -> JourneyWorkout in
            .init(id: session.id, name: session.name, date: session.date, durationSeconds: session.durationSeconds,
                hasStrength: true, hasCardio: true, activities: session.activities,
                completedExercises: [.init(id: "exercise-1", name: "Exercise 1")])
        }
        let snapshot = build(mixed, exercises: exercises)
        XCTAssertEqual(snapshot.milestones.filter { $0.personalRecord != nil }.count, 12)
        XCTAssertEqual(event("pr-printer", in: snapshot)?.sessionID, sessions[1].id)
        XCTAssertEqual(event("sequel", in: snapshot)?.sessionID, sessions[2].id)
        XCTAssertEqual(event("records-10", in: snapshot)?.sessionID, sessions[4].id)
        XCTAssertEqual(event("improvement-exercise-1-100", in: snapshot)?.sessionID, sessions[3].id)
        XCTAssertNotNil(event("montage", in: snapshot))
        XCTAssertNil(event("montage", in: build(mixed, exercises: exercises, now: date(2026, 1, 31))))
        XCTAssertEqual(snapshot.milestones.filter { $0.playfulTitle == "Gravity filed a complaint" }.count, 1)
        XCTAssertEqual(snapshot.milestones.filter { $0.playfulTitle == "Same human. More horsepower." }.count, 1)
        XCTAssertTrue(snapshot.insights.years[0].facts.contains { $0.value.contains("110%") })
    }

    func testSequelDoesNotIgnoreInterveningNonRecordSession() {
        let sessions = (1...4).map { workout(date(2026, 1, $0)) }
        let exercise = JourneyExercise(id: "lift", name: "Lift", isReps: false, usesAddedWeight: false,
            performances: zip(sessions, [10.0, 20, 15, 30]).map { .init(sessionID: $0.0.id, date: $0.0.date, value: $0.1) })
        XCTAssertNil(event("sequel", in: build(sessions, exercises: [exercise])))
    }

    func testNextUpAndYearComparisonUseDistinctDaysAndSameDate() {
        let sessions = [workout(date(2025, 1, 1)), workout(date(2025, 3, 1)), workout(date(2025, 12, 1)),
            workout(date()), workout(date()), workout(date(2026, 2, 1))]
        let result = build(sessions, now: date(2026, 3, 1))
        XCTAssertEqual(result.insights.facts.first { $0.id == "year-comparison" }?.value.hasPrefix("2 / 2"), true)
        XCTAssertEqual(result.insights.nextMilestones.count, 3)
        XCTAssertTrue(result.insights.nextMilestones.allSatisfy { $0.progress >= 0 && $0.progress < 1 })
        XCTAssertEqual(result.insights.years.count, 2)
    }

    func testYearHighlightsKeepSmallCardioImprovementsVisible() throws {
        let sessions = [workout(date(), activities: [activity(distance: 10_000, duration: 3_600)]),
            workout(date(2026, 1, 2), activities: [activity(distance: 10_000, duration: 3_599)])]
        let year = try XCTUnwrap(build(sessions).insights.years.first)
        let improvement = try XCTUnwrap(year.facts.first { $0.id.hasPrefix("improvement-") })
        XCTAssertFalse(improvement.value.hasPrefix("+0%"))
        XCTAssertTrue(improvement.title.contains("average speed"))
    }

    func testGoalCatalogIncludesClearedAndFutureTargetsWithoutInventingPRs() throws {
        let result = build([workout(date(), duration: 90_000, activities: [activity(distance: 150_000)])])
        let goals = result.achievementGoals
        XCTAssertEqual(Set(goals.map(\.id)).count, goals.count)
        XCTAssertTrue(try XCTUnwrap(goals.first { $0.id == "beginning" }).isEarned)
        XCTAssertTrue(try XCTUnwrap(goals.first { $0.id == "training-hours-10" }).isEarned)
        XCTAssertTrue(try XCTUnwrap(goals.first { $0.id == "training-hours-24" }).isEarned)
        XCTAssertTrue(try XCTUnwrap(goals.first { $0.id == "foot-distance-10" }).isEarned)
        XCTAssertTrue(try XCTUnwrap(goals.first { $0.id == "foot-distance-100" }).isEarned)
        XCTAssertFalse(try XCTUnwrap(goals.first { $0.id == "speed-pr" }).isEarned)
        XCTAssertFalse(try XCTUnwrap(goals.first { $0.id == "distance-pr" }).isEarned)
        XCTAssertEqual(try XCTUnwrap(goals.first { $0.id == "workouts-10" }).progress, 0.1)
        for id in ["celebration-mixed", "celebration-leg-day", "celebration-variety-10", "consistency-52",
                   "celebration-rhythm-20", "best-month", "cycling-100km", "rowing-50km", "bodyweight-pr",
                   "improvement-100", "celebration-pr-printer", "celebration-sequel", "celebration-montage",
                   "celebration-anniversary-10", "new-year", "comeback"] {
            XCTAssertNotNil(goals.first { $0.id == id }, id)
        }
        XCTAssertTrue(goals.compactMap(\.progress).allSatisfy { (0...1).contains($0) })
        XCTAssertTrue(build([]).achievementGoals.allSatisfy { !$0.isEarned })
    }

    func testGoalCatalogTracksRecordFamiliesAndRecomputesAfterHistoryRemoval() throws {
        let sessions = [workout(date(), activities: [activity(distance: 1_000)]),
            workout(date(2026, 1, 2), activities: [activity(distance: 2_000)])]
        let exercises = [JourneyExercise(id: "press-weight", name: "Press", isReps: false, usesAddedWeight: false,
            performances: zip(sessions, [10.0, 20]).map { .init(sessionID: $0.0.id, date: $0.0.date, value: $0.1) })]
        let earnedIDs = Set(build(sessions, exercises: exercises).achievementGoals.filter(\.isEarned).map(\.id))
        XCTAssertTrue(earnedIDs.isSuperset(of: ["strength-pr", "distance-pr", "speed-pr", "improvement-100", "celebration-pr-printer"]))
        let remaining = build([sessions[1]], exercises: exercises).achievementGoals.filter(\.isEarned).map(\.id)
        XCTAssertFalse(remaining.contains("strength-pr"))
        XCTAssertFalse(remaining.contains("distance-pr"))
        XCTAssertFalse(remaining.contains("improvement-100"))
    }

    func testGoalSeriesAdvanceAndKeepEveryEarlierAndLaterTarget() throws {
        let sessions = (0..<50).map { workout(date().addingTimeInterval(Double($0) * 3_600)) }
        let snapshot = build(sessions)
        let series = JourneyAchievementCatalog.series(snapshot.achievementGoals)
        let workouts = try XCTUnwrap(series.first { $0.id == "workouts" })
        XCTAssertEqual(workouts.nextGoal?.id, "workouts-100")
        XCTAssertEqual(workouts.latestCleared?.id, "workouts-50")
        XCTAssertEqual(workouts.clearedCount, 3)
        XCTAssertEqual(workouts.goals.count, 10)
        XCTAssertEqual(workouts.goals.first?.id, "workouts-10")
        XCTAssertEqual(workouts.goals.last?.id, "workouts-10000")
        XCTAssertEqual(series.flatMap(\.goals).count, snapshot.achievementGoals.count)
        XCTAssertEqual(Set(series.flatMap(\.goals).map(\.id)), Set(snapshot.achievementGoals.map(\.id)))
        XCTAssertLessThan(series.count, snapshot.achievementGoals.count)

        let before = JourneyAchievementCatalog.series(build(Array(sessions.dropLast())).achievementGoals)
        XCTAssertEqual(before.first { $0.id == "workouts" }?.nextGoal?.id, "workouts-50")
        let empty = JourneyAchievementCatalog.series(build([]).achievementGoals)
        XCTAssertEqual(empty.first { $0.id == "workouts" }?.nextGoal?.id, "workouts-10")
        XCTAssertTrue(empty.allSatisfy { $0.latestCleared == nil })

        let completed = try XCTUnwrap(series.first { $0.id == "beginning" })
        XCTAssertNil(completed.nextGoal)
        XCTAssertEqual(completed.currentGoal?.id, "beginning")
    }

    func testGoalSeriesKeepUnitSpecificTargetsAndCompletedLadders() throws {
        for unit in [WorkoutDistanceUnit.kilometers, .miles] {
            let snapshot = build([workout(date(), activities: [activity(distance: 200_000)])], unit: unit)
            let series = JourneyAchievementCatalog.series(snapshot.achievementGoals)
            let adventures = try XCTUnwrap(series.first { $0.id == "foot-adventures" })
            XCTAssertNil(adventures.nextGoal)
            XCTAssertEqual(adventures.clearedCount, unit == .miles ? 3 : 2)
            XCTAssertEqual(adventures.currentGoal?.id, adventures.goals.last?.id)
            XCTAssertEqual(series.filter { $0.id == "foot-distance" }.count, 1)
            XCTAssertEqual(series.filter { $0.id == "other-distance" }.count, 1)
        }
    }

    func testFunCaptionsReuseExistingAwardsAndHistoryOrderIsStable() {
        let sessions = (0..<100).map { index in
            workout(calendar.date(byAdding: .weekOfYear, value: index, to: date(2024))!, duration: 3_600)
        }
        let result = build(sessions)
        for id in ["workouts-100", "consistency-10", "consistency-52", "training-hours-24"] {
            XCTAssertEqual(result.milestones.filter { $0.id == id }.count, 1)
            XCTAssertNotNil(result.milestones.first { $0.id == id }?.playfulTitle)
        }
        XCTAssertEqual(result.milestones.map(\.id), build(sessions.reversed()).milestones.map(\.id))
        XCTAssertEqual(result.insights.facts.first { $0.id == "streak" }?.value, "100 weeks")
    }
}

@MainActor
final class JourneyCelebrationPreferencesTests: XCTestCase {
    func testBackfillIsQuietNewAwardsOnlyCelebrateOnceAndScopesAreSeparate() throws {
        let suite = "JourneyCelebrationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = JourneyCelebrationPreferences(defaults: defaults)
        let now = Date()
        func event(_ id: String, date: Date) -> JourneyMilestone {
            .init(id: id, sessionID: UUID(), date: date, kind: .celebration, title: "Milestone", detail: "Detail")
        }
        let old = event("old", date: now.addingTimeInterval(-30 * 86_400))
        let fresh = event("fresh", date: now.addingTimeInterval(-60))
        XCTAssertEqual(preferences.claim([old], scope: "a", now: now), 0)
        XCTAssertEqual(preferences.claim([old, fresh], scope: "a", now: now), 1)
        XCTAssertEqual(preferences.claim([old, fresh], scope: "a", now: now), 0)
        XCTAssertEqual(preferences.claim([], scope: "a", now: now), 0)
        XCTAssertEqual(preferences.claim([fresh], scope: "a", now: now), 0)
        XCTAssertEqual(preferences.claim([fresh], scope: "b", now: now), 1)
    }
}

@MainActor
final class JourneyMilestoneShareTests: XCTestCase {
    func testLongMilestoneRendersWithCelebratoryCaption() throws {
        let presentation = PersonalRecordSharePresentation(record: .init(id: "milestone",
            exerciseName: "A month of strength, cardio and PRs",
            performanceText: "", detailText: "October 2026. Strength sessions, cardio adventures and personal records, all in one month."),
            achievedAtText: "31 October 2026", isMilestone: true, playfulTitle: "Main character training montage")
        let image = try XCTUnwrap(TrainingShareImageRenderer.render(PersonalRecordShareCard(presentation: presentation)))
        XCTAssertEqual(image.cgImage?.width, 1_080)
        XCTAssertEqual(image.cgImage?.height, 1_920)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Branded milestone with celebratory caption"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
