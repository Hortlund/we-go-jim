import SwiftData
import XCTest
@testable import WGJ

final class TrainingJourneyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        value.firstWeekday = 2
        return value
    }

    private func date(_ day: Int, month: Int = 3, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func workout(_ day: Int, month: Int = 3, duration: Int = 1_800,
                         strength: Bool = true, activities: [JourneyActivity] = []) -> JourneyWorkout {
        .init(id: UUID(), name: "Workout", date: date(day, month: month), durationSeconds: duration,
            hasStrength: strength, hasCardio: !activities.isEmpty, activities: activities)
    }

    private func activity(_ meters: Double, exercise: String = "walk", onFoot: Bool = true) -> JourneyActivity {
        .init(id: UUID(), exerciseID: exercise, name: "Outdoor Walk", distanceMeters: meters,
            durationSeconds: 1_800, isWalkRun: onFoot, isOutdoor: true)
    }

    private func build(_ workouts: [JourneyWorkout], exercises: [JourneyExercise] = [],
                       unit: WorkoutDistanceUnit = .kilometers) -> TrainingJourneySnapshot {
        TrainingJourneyBuilder.build(workouts: workouts, exercises: exercises, distanceUnit: unit,
            calendar: calendar, now: date(3, month: 10))
    }

    func testEmptyHistoryHasNoInventedMilestones() {
        let snapshot = build([])
        XCTAssertEqual(snapshot.workoutCount, 0)
        XCTAssertEqual(snapshot.activeDays, 0)
        XCTAssertNil(snapshot.firstWorkoutDate)
        XCTAssertTrue(snapshot.milestones.isEmpty)
        XCTAssertEqual(snapshot.years.first?.months.count, 12)
    }

    func testLifetimeTotalsAndMilestonesAreChronologicalAndDeterministic() {
        let workouts = (1...26).map { workout($0, duration: $0 == 1 ? -100 : 600) }
        let snapshot = build(workouts.shuffled())
        XCTAssertEqual(snapshot.workoutCount, 26)
        XCTAssertEqual(snapshot.durationSeconds, 25 * 600)
        XCTAssertEqual(snapshot.firstWorkoutDate, workouts[0].date)
        let milestones = snapshot.milestones.filter { $0.kind == .workouts }
        XCTAssertEqual(milestones.map(\.sessionID), [workouts[24].id, workouts[9].id])
        XCTAssertEqual(snapshot.milestones.map(\.id), build(workouts.reversed()).milestones.map(\.id))
        XCTAssertEqual(snapshot.milestones.last?.kind, .beginning)
    }

    func testCalendarGroupsSameDayAndPreservesDSTAndLeapDay() throws {
        let sessions = [workout(29, month: 3), workout(29, month: 3, strength: false, activities: [activity(2_000)])]
        let snapshot = build(sessions)
        XCTAssertEqual(snapshot.activeDays, 1)
        let march = try XCTUnwrap(snapshot.years.first?.months[2])
        XCTAssertEqual(march.days.count, 31)
        let day = march.days[28]
        XCTAssertEqual(day.workoutCount, 2)
        XCTAssertTrue(day.hasStrength)
        XCTAssertTrue(day.hasCardio)
        XCTAssertEqual(march.days[29].date, calendar.startOfDay(for: date(30)))
        let leapDate = date(29, month: 2, year: 2024)
        let leap = JourneyWorkout(id: UUID(), name: "Leap day", date: leapDate, durationSeconds: 0,
            hasStrength: true, hasCardio: false, activities: [])
        let year = try XCTUnwrap(build([leap]).years.first { calendar.component(.year, from: $0.date) == 2024 })
        XCTAssertEqual(year.months[1].days.count, 29)
        XCTAssertEqual(year.months[1].workouts.first?.id, leap.id)
        XCTAssertEqual(build([leap]).years.map { calendar.component(.year, from: $0.date) }, [2026, 2025, 2024])
        XCTAssertTrue(build([leap]).years[1].months.allSatisfy { $0.workouts.isEmpty })
    }

    func testHebrewCalendarIncludesFinalMonthAndLeapMonth() throws {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = calendar.timeZone
        let recordedDates = [date(15, month: 9, year: 2025), date(15, month: 3, year: 2024)]
        XCTAssertEqual(hebrew.component(.month, from: recordedDates[0]), 13)
        let snapshot = calendarSnapshot(recordedDates, calendar: hebrew)
        let leapYearStart = try XCTUnwrap(hebrew.dateInterval(of: .year, for: recordedDates[1])?.start)
        let leapYear = try XCTUnwrap(snapshot.years.first { $0.id == leapYearStart })
        XCTAssertEqual(leapYear.months.count, 13)
        assertCalendarIncludesEveryWorkout(snapshot)
    }

    func testChineseCalendarKeepsLeapMonthDistinct() throws {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = calendar.timeZone
        let recordedDates = [date(1, month: 3, year: 2023), date(1, month: 4, year: 2023)]
        XCTAssertEqual(chinese.component(.month, from: recordedDates[0]), chinese.component(.month, from: recordedDates[1]))
        XCTAssertEqual(chinese.dateComponents([.month], from: recordedDates[1]).isLeapMonth, true)
        let snapshot = calendarSnapshot(recordedDates, calendar: chinese)
        let yearStart = try XCTUnwrap(chinese.dateInterval(of: .year, for: recordedDates[0])?.start)
        let year = try XCTUnwrap(snapshot.years.first { $0.id == yearStart })
        XCTAssertEqual(year.months.count, 13)
        XCTAssertEqual(Set(year.months.map(\.id)).count, 13)
        XCTAssertEqual(year.months.filter { !$0.workouts.isEmpty }.count, 2)
        assertCalendarIncludesEveryWorkout(snapshot)
    }

    func testJapaneseCalendarPreservesHistoryAcrossEraTransition() throws {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = calendar.timeZone
        japanese.locale = Locale(identifier: "en_US")
        let recordedDates = [date(1, month: 9, year: 2018), date(30, month: 4, year: 2019),
            date(1, month: 5, year: 2019), date(31, month: 12, year: 2019)]
        let snapshot = calendarSnapshot(recordedDates, calendar: japanese)
        XCTAssertEqual(snapshot.years.map { calendar.component(.year, from: $0.date) }, Array((2018...2026).reversed()))
        let transitionYear = try XCTUnwrap(snapshot.years.first { calendar.component(.year, from: $0.date) == 2019 })
        XCTAssertEqual(transitionYear.months.count, 12)
        XCTAssertEqual(transitionYear.months.flatMap(\.workouts).count, 3)
        XCTAssertTrue(transitionYear.title.contains("Heisei"))
        XCTAssertTrue(transitionYear.title.contains("Reiwa"))
        assertCalendarIncludesEveryWorkout(snapshot)
    }

    func testJapaneseYearsWithSameNumberHaveDistinctIdentities() throws {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = calendar.timeZone
        japanese.locale = Locale(identifier: "en_US")
        let snapshot = calendarSnapshot([date(1, month: 9, year: 1990), date(1, month: 9, year: 2020)], calendar: japanese)
        let repeatedYears = snapshot.years.filter { japanese.component(.year, from: $0.date) == 2 }
        XCTAssertEqual(repeatedYears.count, 2)
        XCTAssertEqual(Set(repeatedYears.map(\.id)).count, 2)
        XCTAssertEqual(Set(repeatedYears.map(\.title)).count, 2)
        assertCalendarIncludesEveryWorkout(snapshot)
    }

    private func calendarSnapshot(_ dates: [Date], calendar: Calendar) -> TrainingJourneySnapshot {
        let workouts = dates.map {
            JourneyWorkout(id: UUID(), name: "Training", date: $0, durationSeconds: 600,
                hasStrength: true, hasCardio: false, activities: [])
        }
        return TrainingJourneyBuilder.build(workouts: workouts, exercises: [], calendar: calendar, now: date(3, month: 10))
    }

    private func assertCalendarIncludesEveryWorkout(_ snapshot: TrainingJourneySnapshot, file: StaticString = #filePath, line: UInt = #line) {
        let months = snapshot.years.flatMap(\.months)
        let workouts = months.flatMap(\.workouts)
        XCTAssertEqual(workouts.count, snapshot.workoutCount, file: file, line: line)
        XCTAssertEqual(Set(workouts.map(\.id)).count, snapshot.workoutCount, file: file, line: line)
        XCTAssertEqual(months.flatMap(\.days).reduce(0) { $0 + $1.workoutCount }, snapshot.workoutCount, file: file, line: line)
        XCTAssertEqual(Set(snapshot.years.map(\.id)).count, snapshot.years.count, file: file, line: line)
    }

    func testEveryStrengthRecordUsesLifetimeBaselineAndExcludesDeletedSessions() throws {
        let workouts = (1...5).map { workout($0) }
        let values = [50.0, 52.5, 55, 54, 61]
        let exercise = JourneyExercise(id: "bench", name: "Bench", isReps: false, usesAddedWeight: false,
            performances: zip(workouts, values).map { .init(sessionID: $0.0.id, date: $0.0.date, value: $0.1) })
        let events = build(workouts, exercises: [exercise]).milestones.filter { $0.kind == .strength }
        XCTAssertEqual(events.map(\.sessionID), [workouts[4].id, workouts[2].id, workouts[1].id])
        XCTAssertEqual(events.last?.chart.first?.value, 50)
        XCTAssertEqual(events.first?.chart.last?.value, 61)
        let afterDeletion = build(Array(workouts.dropFirst(3)), exercises: [exercise])
        let event = try XCTUnwrap(afterDeletion.milestones.first { $0.kind == .strength })
        XCTAssertEqual(event.chart.first?.value, 54)
        XCTAssertEqual(event.chart.count, 2)
    }

    func testChartSamplingKeepsBaselineAndMilestoneAndRepsUseSeparateUnits() throws {
        let workouts = (0..<200).map { index in
            JourneyWorkout(id: UUID(), name: "Push-ups", date: date(1).addingTimeInterval(Double(index) * 86_400),
                durationSeconds: 60, hasStrength: true, hasCardio: false, activities: [])
        }
        let exercise = JourneyExercise(id: "push-up", name: "Push-up", isReps: true, usesAddedWeight: false,
            performances: workouts.enumerated().map { .init(sessionID: $0.element.id, date: $0.element.date, value: Double($0.offset + 5)) })
        let event = try XCTUnwrap(build(workouts, exercises: [exercise]).milestones.first { $0.kind == .strength })
        XCTAssertLessThanOrEqual(event.chart.count, 24)
        XCTAssertEqual(event.chart.first?.value, 5)
        XCTAssertEqual(event.chart.last?.value, 204)
        XCTAssertEqual(event.chartUnit, "reps")
    }

    func testOnFootTotalIgnoresMachinesAndInvalidValuesAndEveryDistanceRecordAppears() {
        let workouts = [
            workout(1, activities: [activity(1_000)]),
            workout(2, activities: [activity(1_040), activity(50_000, exercise: "bike", onFoot: false)]),
            workout(3, activities: [activity(1_080), activity(.nan), activity(-100)]),
            workout(4, activities: [activity(1_120)]),
        ]
        let snapshot = build(workouts)
        XCTAssertEqual(snapshot.walkRunDistanceMeters, 4_240)
        let records = snapshot.milestones.filter { $0.id.hasPrefix("cardio-pr-distance-") }
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.first?.sessionID, workouts[3].id)
    }

    func testDistanceMilestonesUseMilesAndCoalesceThresholdsCrossedInOneWorkout() throws {
        let session = workout(1, activities: [activity(WorkoutDistanceUnit.miles.meters(from: 120))])
        let snapshot = build([session], unit: .miles)
        let milestones = snapshot.milestones.filter { $0.id.hasPrefix("total-distance-") }
        XCTAssertEqual(milestones.count, 1)
        XCTAssertTrue(try XCTUnwrap(milestones.first).id.contains("miles-100"))
        XCTAssertEqual(build([session], unit: .meters).milestones.filter { $0.id.hasPrefix("total-distance-") }.count, 1)
    }

    func testActiveDaysTrainingHoursAndOtherCardioCelebrateDistinctMilestones() {
        let workouts = (1...30).map { workout($0, duration: 3_600, activities: [activity(2_000, exercise: "bike", onFoot: false)]) }
        let snapshot = build(workouts + [workout(30, duration: 0)])
        XCTAssertEqual(snapshot.activeDays, 30)
        XCTAssertEqual(snapshot.otherCardioDistanceMeters, 60_000)
        XCTAssertEqual(snapshot.walkRunDistanceMeters, 0)
        XCTAssertEqual(snapshot.milestones.filter { $0.id == "active-days-30" }.count, 1)
        XCTAssertEqual(snapshot.milestones.first { $0.id == "training-hours-10" }?.sessionID, workouts[9].id)
        XCTAssertEqual(snapshot.milestones.filter { $0.id.hasPrefix("other-distance-") }.count, 2)
    }

    func testLargeHistoryKeepsRecordChartsBoundedAndCountsEveryWorkout() {
        let workouts = (0..<10_000).map { index in
            JourneyWorkout(id: UUID(), name: "Training", date: date(1).addingTimeInterval(Double(index) * 43_200),
                durationSeconds: 600, hasStrength: true, hasCardio: false, activities: [])
        }
        let exercise = JourneyExercise(id: "bench", name: "Bench", isReps: false, usesAddedWeight: false,
            performances: workouts.enumerated().map { .init(sessionID: $0.element.id, date: $0.element.date,
                value: 50 + Double($0.offset) / 100) })
        let snapshot = build(workouts, exercises: [exercise])
        XCTAssertEqual(snapshot.workoutCount, 10_000)
        XCTAssertEqual(snapshot.years.flatMap(\.months).flatMap(\.workouts).count, 10_000)
        let records = snapshot.milestones.filter { $0.personalRecord != nil }
        XCTAssertEqual(records.count, 9_999)
        XCTAssertTrue(records.allSatisfy { $0.chart.count <= 24 })
    }

    func testConsistencyCountsWeeksRatherThanSessionsAndResetsAtGaps() {
        let start = date(2) // Monday
        let workouts = [0, 0, 1, 2, 3, 5, 6, 7, 8].map { week in
            JourneyWorkout(id: UUID(), name: "Training", date: calendar.date(byAdding: .weekOfYear, value: week, to: start)!,
                durationSeconds: 60, hasStrength: true, hasCardio: false, activities: [])
        }
        let events = build(workouts).milestones.filter { $0.kind == .consistency }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.date, calendar.date(byAdding: .weekOfYear, value: 3, to: start))
    }
}

@MainActor
final class TrainingJourneyLoaderTests: XCTestCase {
    func testBodyweightRecordsStaySeparateFromWeightedSetsAndAssistance() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "Journey-load-context-\(UUID())")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for (index, reps) in [8, 10, 20].enumerated() {
            let workout = session(in: context, day: index + 1, kilograms: 10)
            let exercise = try XCTUnwrap(workout.exercises?.first)
            exercise.catalogExerciseUUID = "pull-up"
            exercise.exerciseNameSnapshot = "Pull-Up"
            let set = try XCTUnwrap(exercise.sets?.first)
            set.actualReps = reps
            if index < 2 { set.actualLoadUnit = .bodyweight }
        }
        let catalog = ExerciseCatalogItem(remoteUUID: "pull-up", displayName: "Pull-Up", equipmentSummary: "Bodyweight",
            loadTrackingRaw: ExerciseLoadKind.addedWeight.rawValue)
        context.insert(catalog)
        try context.saveWithRecoveryProtection()
        let loaded = try TrainingJourneyLoader.load(context: context)
        let events = loaded.milestones.filter { $0.kind == .strength }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.chart.map(\.value), [8, 10])
        XCTAssertEqual(events.first?.chartUnit, "reps")
        XCTAssertFalse(context.hasChanges)

        catalog.loadTrackingRaw = ExerciseLoadKind.assistance.rawValue
        try context.saveWithRecoveryProtection()
        XCTAssertFalse(try TrainingJourneyLoader.load(context: context).milestones.contains { $0.kind == .strength })
        XCTAssertFalse(context.hasChanges)
    }

    func testLoaderReadsCanonicalDirtyHistoryAndHonorsVisibilityWithoutWrites() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "Journey-\(UUID())")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let first = session(in: context, day: 1, kilograms: 50)
        let second = session(in: context, day: 2, kilograms: 60)
        let archived = session(in: context, day: 3, kilograms: 100)
        archived.archivedAt = .now
        let active = session(in: context, day: 4, kilograms: 200)
        active.status = .active
        let activity = WorkoutSessionCardioBlock(sessionID: second.id, phase: .preWorkout,
            catalogExerciseUUID: "seed-outdoor-walk", exerciseNameSnapshot: "Outdoor Walk", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "", trackingProfile: .walkRun, targetDurationSeconds: 0,
            actualDurationSeconds: 600, actualDistanceMeters: 2_000, isCompleted: true, session: second)
        context.insert(activity)
        second.cardioBlocks = [activity]
        let profile = UserProfile(displayName: "Athlete")
        profile.preferredWeightUnit = .lb
        context.insert(profile)
        try context.saveWithRecoveryProtection()
        let loaded = try TrainingJourneyLoader.load(context: context)
        XCTAssertEqual(loaded.workoutCount, 2)
        XCTAssertEqual(loaded.walkRunDistanceMeters, 2_000)
        let event = try XCTUnwrap(loaded.milestones.first { $0.kind == .strength })
        XCTAssertEqual(event.sessionID, second.id)
        XCTAssertEqual(try XCTUnwrap(event.chart.last).value, 60 / 0.45359237, accuracy: 0.001)
        XCTAssertEqual(event.chartUnit, "lb")
        XCTAssertEqual(loaded.milestones.last?.sessionID, first.id)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSessionSummary>()), 0)

        second.archivedAt = .now
        try context.saveWithRecoveryProtection()
        let hidden = try TrainingJourneyLoader.load(context: context)
        XCTAssertEqual(hidden.workoutCount, 1)
        XCTAssertEqual(hidden.walkRunDistanceMeters, 0)
        XCTAssertFalse(hidden.milestones.contains { $0.kind == .strength })
        XCTAssertFalse(context.hasChanges)
    }

    func testCelebrationsUseCatalogMusclesAndCompletedCyclingWithoutWrites() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "Journey-celebrations-\(UUID())")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let workout = session(in: context, day: 1, kilograms: 50)
        let muscle = MuscleGroup(remoteID: 5, name: "Quadriceps", nameEn: "Quadriceps")
        let catalog = ExerciseCatalogItem(remoteUUID: "bench", displayName: "Custom leg exercise")
        context.insert(muscle)
        context.insert(catalog)
        catalog.primaryMuscles = [muscle]
        let bike = WorkoutSessionCardioBlock(sessionID: workout.id, phase: .preWorkout,
            catalogExerciseUUID: "seed-bike", exerciseNameSnapshot: "Bike", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "", trackingProfile: .machineDistance, targetDurationSeconds: 0,
            actualDurationSeconds: 10_000, actualDistanceMeters: 100_000, isCompleted: true, session: workout)
        context.insert(bike)
        workout.cardioBlocks = [bike]
        try context.saveWithRecoveryProtection()
        let loaded = try TrainingJourneyLoader.load(context: context)
        XCTAssertTrue(loaded.milestones.contains { $0.id == "celebration-leg-day" })
        XCTAssertTrue(loaded.milestones.contains { $0.id == "celebration-cycling-100km" })
        XCTAssertTrue(loaded.milestones.contains { $0.id == "celebration-mixed" })
        XCTAssertFalse(context.hasChanges)
        workout.archivedAt = .now
        try context.saveWithRecoveryProtection()
        let hidden = try TrainingJourneyLoader.load(context: context)
        XCTAssertTrue(hidden.milestones.isEmpty)
        XCTAssertTrue(hidden.insights.facts.isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    private func session(in context: ModelContext, day: Int, kilograms: Double) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        let session = WorkoutSession(name: "Upper", status: .completed, startedAt: date,
            endedAt: date.addingTimeInterval(600), durationSeconds: 600)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 8,
            actualWeight: kilograms, isCompleted: true, sessionExercise: exercise)
        let warmup = WorkoutSessionSet(sessionExerciseID: exercise.id, isWarmup: true, actualReps: 1,
            actualWeight: 500, isCompleted: true, sessionExercise: exercise)
        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        context.insert(warmup)
        session.exercises = [exercise]
        exercise.sets = [set, warmup]
        return session
    }
}
