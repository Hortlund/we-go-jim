import Foundation
import XCTest
@testable import WGJ

final class WorkoutCalorieEstimatorTests: XCTestCase {
    func testStrengthOnlyEstimateUsesConservativeActiveCalories() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: []),
            .estimated(activeCalories: 105, version: 2)
        )
    }

    func testCardioAndStrengthEstimateDoesNotDoubleCountCardioTime() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: [1_800]),
            .estimated(activeCalories: 240, version: 2)
        )
    }

    func testFemaleEstimateUsesFemaleMifflinStJeorAdjustment() {
        XCTAssertEqual(
            estimate(sex: .female, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: []),
            .estimated(activeCalories: 110, version: 2)
        )
    }

    func testRepresentativeWorkoutUsesActivitySpecificCardioMETs() {
        let result = WorkoutCalorieEstimator.estimate(
            profile: WorkoutCalorieProfileSnapshot(
                sex: .male,
                dateOfBirth: date(year: 1996, month: 1, day: 1),
                heightCentimeters: 193,
                bodyWeightKilograms: 90,
                showsCalorieEstimates: true
            ),
            facts: WorkoutCalorieFacts(
                durationSeconds: 7_200,
                completedWorkingSetCount: 10,
                completedCardioActivities: [
                    WorkoutCalorieCardioFact(
                        durationSeconds: 20 * 60,
                        catalogExerciseUUID: "seed-bike",
                        exerciseName: "Bike"
                    ),
                    WorkoutCalorieCardioFact(
                        durationSeconds: 5 * 60,
                        catalogExerciseUUID: "seed-crosstrainer",
                        exerciseName: "Crosstrainer"
                    ),
                ]
            ),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result, .estimated(activeCalories: 255, version: 2))
    }

    func testProfileOnlyTreadmillUsesRunningMETAtRunningSpeed() {
        let result = estimate(
            sex: .male,
            kg: 80,
            cm: 180,
            duration: 600,
            sets: 0,
            activities: [
                WorkoutCalorieCardioFact(
                    durationSeconds: 600,
                    exerciseName: "Treadmill",
                    trackingProfile: .treadmill,
                    distanceMeters: 2_000
                ),
            ]
        )

        XCTAssertEqual(result, .estimated(activeCalories: 115, version: 2))
    }

    func testInclineRaisesNamedAndSpeedInferredRunningEstimates() {
        let namedRun = estimate(
            sex: .male,
            kg: 80,
            cm: 180,
            duration: 600,
            sets: 0,
            activities: [
                WorkoutCalorieCardioFact(
                    durationSeconds: 600,
                    exerciseName: "Treadmill Run",
                    trackingProfile: .treadmill,
                    distanceMeters: 2_000,
                    inclinePercent: 10
                ),
            ]
        )
        let inferredRun = estimate(
            sex: .male,
            kg: 80,
            cm: 180,
            duration: 600,
            sets: 0,
            activities: [
                WorkoutCalorieCardioFact(
                    durationSeconds: 600,
                    exerciseName: "Treadmill",
                    trackingProfile: .treadmill,
                    distanceMeters: 2_000,
                    inclinePercent: 10
                ),
            ]
        )

        XCTAssertEqual(namedRun, .estimated(activeCalories: 155, version: 2))
        XCTAssertEqual(inferredRun, namedRun)
    }

    func testInclineRaisesWalkingEstimate() {
        let flat = estimate(
            sex: .male,
            kg: 80,
            cm: 180,
            duration: 1_800,
            sets: 0,
            activities: [
                WorkoutCalorieCardioFact(
                    durationSeconds: 1_800,
                    exerciseName: "Treadmill Walk",
                    trackingProfile: .treadmill,
                    distanceMeters: 2_500
                ),
            ]
        )
        let incline = estimate(
            sex: .male,
            kg: 80,
            cm: 180,
            duration: 1_800,
            sets: 0,
            activities: [
                WorkoutCalorieCardioFact(
                    durationSeconds: 1_800,
                    exerciseName: "Treadmill Walk",
                    trackingProfile: .treadmill,
                    distanceMeters: 2_500,
                    inclinePercent: 10
                ),
            ]
        )

        XCTAssertEqual(flat, .estimated(activeCalories: 120, version: 2))
        XCTAssertEqual(incline, .estimated(activeCalories: 280, version: 2))
    }

    func testMissingSexIsReported() {
        var profile = validProfile()
        profile.sex = nil

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.missing(.sex)])
    }

    func testMissingDateOfBirthIsReported() {
        var profile = validProfile()
        profile.dateOfBirth = nil

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.missing(.dateOfBirth)])
    }

    func testMissingHeightIsReported() {
        var profile = validProfile()
        profile.heightCentimeters = nil

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.missing(.height)])
    }

    func testMissingBodyWeightIsReported() {
        var profile = validProfile()
        profile.bodyWeightKilograms = nil

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.missing(.bodyWeight)])
    }

    func testFutureBirthDateIsInvalid() {
        var profile = validProfile()
        profile.dateOfBirth = date(year: 2026, month: 1, day: 2)

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.dateOfBirth)])
    }

    func testUnderageBirthDateIsInvalid() {
        var profile = validProfile()
        profile.dateOfBirth = date(year: 2008, month: 1, day: 2)

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.dateOfBirth)])
    }

    func testOverageBirthDateIsInvalid() {
        var profile = validProfile()
        profile.dateOfBirth = date(year: 1925, month: 1, day: 1)

        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.dateOfBirth)])
    }

    func testHeightValidationAcceptsInclusiveBoundaries() {
        var profile = validProfile()
        profile.heightCentimeters = 120
        XCTAssertTrue(profile.validationIssues(referenceDate: referenceDate, calendar: calendar).isEmpty)

        profile.heightCentimeters = 230
        XCTAssertTrue(profile.validationIssues(referenceDate: referenceDate, calendar: calendar).isEmpty)
    }

    func testHeightValidationRejectsValuesOutsideBoundaries() {
        var profile = validProfile()
        profile.heightCentimeters = 119.999
        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.height)])

        profile.heightCentimeters = 230.001
        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.height)])
    }

    func testBodyWeightValidationAcceptsInclusiveBoundaries() {
        var profile = validProfile()
        profile.bodyWeightKilograms = 35
        XCTAssertTrue(profile.validationIssues(referenceDate: referenceDate, calendar: calendar).isEmpty)

        profile.bodyWeightKilograms = 300
        XCTAssertTrue(profile.validationIssues(referenceDate: referenceDate, calendar: calendar).isEmpty)
    }

    func testBodyWeightValidationRejectsValuesOutsideBoundaries() {
        var profile = validProfile()
        profile.bodyWeightKilograms = 34.999
        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.bodyWeight)])

        profile.bodyWeightKilograms = 300.001
        XCTAssertEqual(profile.validationIssues(referenceDate: referenceDate, calendar: calendar), [.invalid(.bodyWeight)])
    }

    func testDisabledPreferenceReturnsDisabledForValidProfile() {
        var profile = validProfile()
        profile.showsCalorieEstimates = false

        XCTAssertEqual(
            WorkoutCalorieEstimator.estimate(
                profile: profile,
                facts: WorkoutCalorieFacts(
                    durationSeconds: 3_600,
                    completedWorkingSetCount: 10,
                    completedCardioDurationsSeconds: []
                ),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            .disabled
        )
    }

    func testStrengthSetCapLimitsActivityToThreeMinutesPerSet() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 7_200, sets: 10, cardio: []),
            .estimated(activeCalories: 105, version: 2)
        )
    }

    func testStrengthMinuteCapLimitsActivityToThreeHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 86_400, sets: 100, cardio: []),
            .estimated(activeCalories: 655, version: 2)
        )
    }

    func testCardioBlockCapLimitsEachCompletedBlockToThreeHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 0, cardio: [14_400]),
            .estimated(activeCalories: 785, version: 2)
        )
    }

    func testCardioTotalCapLimitsCompletedCardioToFourHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 0, cardio: [10_800, 10_800, 10_800]),
            .estimated(activeCalories: 1_045, version: 2)
        )
    }

    func testCappedAwayCardioTimeCannotBecomeStrengthTime() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 10, cardio: [14_400]),
            .estimated(activeCalories: 785, version: 2)
        )
    }

    func testCompletedCardioCanExceedSessionDuration() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 0, cardio: [7_200]),
            .estimated(activeCalories: 520, version: 2)
        )
    }

    func testNoActivityStoresAnEvaluationWithoutEstimate() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 0, cardio: []),
            .evaluatedWithoutEstimate(version: 2)
        )
    }

    func testResultsBelowFiveKilocaloriesAreEvaluatedWithoutEstimate() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 60, sets: 1, cardio: []),
            .evaluatedWithoutEstimate(version: 2)
        )
    }

    private func estimate(
        sex: CalorieEstimateSex,
        kg: Double,
        cm: Double,
        duration: Int,
        sets: Int,
        cardio: [Int]
    ) -> WorkoutCalorieEstimateResult {
        estimate(
            sex: sex,
            kg: kg,
            cm: cm,
            duration: duration,
            sets: sets,
            activities: cardio.map { WorkoutCalorieCardioFact(durationSeconds: $0) }
        )
    }

    private func estimate(
        sex: CalorieEstimateSex,
        kg: Double,
        cm: Double,
        duration: Int,
        sets: Int,
        activities: [WorkoutCalorieCardioFact]
    ) -> WorkoutCalorieEstimateResult {
        WorkoutCalorieEstimator.estimate(
            profile: WorkoutCalorieProfileSnapshot(
                sex: sex,
                dateOfBirth: date(year: 1996, month: 1, day: 1),
                heightCentimeters: cm,
                bodyWeightKilograms: kg,
                showsCalorieEstimates: true
            ),
            facts: WorkoutCalorieFacts(
                durationSeconds: duration,
                completedWorkingSetCount: sets,
                completedCardioActivities: activities
            ),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private func validProfile() -> WorkoutCalorieProfileSnapshot {
        WorkoutCalorieProfileSnapshot(
            sex: .male,
            dateOfBirth: date(year: 1996, month: 1, day: 1),
            heightCentimeters: 180,
            bodyWeightKilograms: 80,
            showsCalorieEstimates: true
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var referenceDate: Date {
        date(year: 2026, month: 1, day: 1)
    }
}
