import Foundation
import XCTest
@testable import WGJ

final class WorkoutCalorieEstimatorTests: XCTestCase {
    func testStrengthOnlyEstimateUsesConservativeActiveCalories() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: []),
            .estimated(activeCalories: 35, version: 1)
        )
    }

    func testCardioAndStrengthEstimateDoesNotDoubleCountCardioTime() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: [1_800]),
            .estimated(activeCalories: 110, version: 1)
        )
    }

    func testFemaleEstimateUsesFemaleMifflinStJeorAdjustment() {
        XCTAssertEqual(
            estimate(sex: .female, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: []),
            .estimated(activeCalories: 30, version: 1)
        )
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
            .estimated(activeCalories: 35, version: 1)
        )
    }

    func testStrengthMinuteCapLimitsActivityToThreeHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 86_400, sets: 100, cardio: []),
            .estimated(activeCalories: 220, version: 1)
        )
    }

    func testCardioBlockCapLimitsEachCompletedBlockToThreeHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 0, cardio: [14_400]),
            .estimated(activeCalories: 445, version: 1)
        )
    }

    func testCardioTotalCapLimitsCompletedCardioToFourHours() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 0, cardio: [10_800, 10_800, 10_800]),
            .estimated(activeCalories: 590, version: 1)
        )
    }

    func testCappedAwayCardioTimeCannotBecomeStrengthTime() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 14_400, sets: 10, cardio: [14_400]),
            .estimated(activeCalories: 445, version: 1)
        )
    }

    func testCompletedCardioCanExceedSessionDuration() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 0, cardio: [7_200]),
            .estimated(activeCalories: 295, version: 1)
        )
    }

    func testNoActivityStoresAnEvaluationWithoutEstimate() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 0, cardio: []),
            .evaluatedWithoutEstimate(version: 1)
        )
    }

    func testResultsBelowFiveKilocaloriesAreEvaluatedWithoutEstimate() {
        XCTAssertEqual(
            estimate(sex: .male, kg: 80, cm: 180, duration: 60, sets: 1, cardio: []),
            .evaluatedWithoutEstimate(version: 1)
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
                completedCardioDurationsSeconds: cardio
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
