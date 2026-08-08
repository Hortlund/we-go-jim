import Foundation
import XCTest
@testable import WGJ

final class WorkoutCardioSetupTests: XCTestCase {
    func testTimeGoalRequiresPositiveDurationAndClearsDistance() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .warmUp,
            goalKind: .time,
            durationMinutesText: "10",
            distanceText: "5",
            distanceUnit: .kilometers,
            trackingProfile: .treadmill
        ))

        XCTAssertEqual(result.targetDurationSeconds, 600)
        XCTAssertNil(result.targetDistanceMeters)
    }

    func testDistanceGoalRequiresPositiveDistanceAndClearsDuration() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .main,
            goalKind: .distance,
            durationMinutesText: "10",
            distanceText: "5",
            distanceUnit: .kilometers,
            trackingProfile: .walkRun
        ))

        XCTAssertEqual(result.targetDurationSeconds, 0)
        XCTAssertEqual(result.targetDistanceMeters, 5_000)
    }

    func testOpenGoalClearsBothTargets() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .finisher,
            goalKind: .open,
            durationMinutesText: "20",
            distanceText: "3.1",
            distanceUnit: .miles,
            trackingProfile: .machineDistance
        ))

        XCTAssertEqual(result.targetDurationSeconds, 0)
        XCTAssertNil(result.targetDistanceMeters)
        XCTAssertEqual(result.preferredDistanceUnit, .miles)
    }

    func testInvalidTimeGoalReturnsDurationInlineValidationError() {
        XCTAssertThrowsError(try WorkoutCardioSetupValidator.validated(.init(
            role: .warmUp,
            goalKind: .time,
            durationMinutesText: "0",
            distanceText: "",
            distanceUnit: .kilometers,
            trackingProfile: .timeOnly
        ))) { error in
            XCTAssertEqual(error as? WorkoutCardioSetupValidationError, .durationMustBePositive)
            XCTAssertEqual(error.localizedDescription, "Enter a duration greater than 0 minutes.")
        }
    }

    func testInvalidDistanceGoalReturnsDistanceInlineValidationError() {
        XCTAssertThrowsError(try WorkoutCardioSetupValidator.validated(.init(
            role: .main,
            goalKind: .distance,
            durationMinutesText: "",
            distanceText: "not a distance",
            distanceUnit: .meters,
            trackingProfile: .rower
        ))) { error in
            XCTAssertEqual(
                error as? WorkoutCardioSetupValidationError,
                .distanceMustBePositive(unit: .meters)
            )
            XCTAssertEqual(error.localizedDescription, "Enter a distance greater than 0 meters.")
        }
    }

    func testEnglishGroupingSeparatorParsesFiveThousandMeters() throws {
        let result = try WorkoutCardioSetupValidator.validated(
            distanceDraft(text: "5,000"),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(result.targetDistanceMeters, 5_000)
    }

    func testSwedishDecimalAndWhitespaceGroupingParseWithCurrentLocaleRules() throws {
        let locale = Locale(identifier: "sv_SE")

        let decimal = try WorkoutCardioSetupValidator.validated(
            distanceDraft(text: "5,000"),
            locale: locale
        )
        let grouped = try WorkoutCardioSetupValidator.validated(
            distanceDraft(text: "5\u{00A0}000,5"),
            locale: locale
        )

        XCTAssertEqual(decimal.targetDistanceMeters, 5)
        XCTAssertEqual(grouped.targetDistanceMeters, 5_000.5)
    }

    func testCanonicalUngroupedDistanceParsesInSwedishLocale() throws {
        let result = try WorkoutCardioSetupValidator.validated(
            distanceDraft(text: "5000.5"),
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(result.targetDistanceMeters, 5_000.5)
    }

    func testDurationEditTextPreservesNinetySeconds() throws {
        try assertDurationEditRoundTrip(seconds: 90)
    }

    func testDurationEditTextPreservesNonWholeMinuteSeconds() throws {
        try assertDurationEditRoundTrip(seconds: 61)
    }

    func testDurationEditTextIsConciseForTimerResults() throws {
        let text = WorkoutCardioSetupNumericCodec.durationMinutesText(seconds: 86)

        XCTAssertEqual(text, "1.43")
        try assertDurationEditRoundTrip(seconds: 86)
    }

    func testDistanceEditTextIsUngroupedAndPreservesCanonicalMeters() throws {
        let locale = Locale(identifier: "en_US")
        let original = try WorkoutCardioSetupValidator.validated(
            WorkoutCardioSetupDraft(
                role: .main,
                goalKind: .distance,
                durationMinutesText: "",
                distanceText: "3.141592653589793",
                distanceUnit: .miles,
                trackingProfile: .walkRun
            ),
            locale: locale
        )
        let originalMeters = try XCTUnwrap(original.targetDistanceMeters)

        let editText = WorkoutCardioSetupNumericCodec.distanceText(
            meters: originalMeters,
            unit: .miles
        )
        let reopened = try WorkoutCardioSetupValidator.validated(
            WorkoutCardioSetupDraft(
                role: .main,
                goalKind: .distance,
                durationMinutesText: "",
                distanceText: editText,
                distanceUnit: .miles,
                trackingProfile: .walkRun
            ),
            locale: locale
        )

        XCTAssertFalse(editText.contains(","))
        XCTAssertEqual(reopened.targetDistanceMeters, originalMeters)
    }

    func testLegacyTemplateEditInfersRowerProfileAndRoundTripsIt() throws {
        let legacy = TemplateCardioBlockDraft(
            phase: .preWorkout,
            role: .main,
            catalogExerciseUUID: "seed-row-machine",
            exerciseNameSnapshot: "Rowing Machine",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: nil,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 2_000,
            preferredDistanceUnit: .meters
        )

        let draft = WorkoutCardioSetupDraft(templateCardio: legacy)
        let validated = try WorkoutCardioSetupValidator.validated(draft)

        XCTAssertEqual(draft.trackingProfile, .rower)
        XCTAssertEqual(validated.trackingProfile, .rower)
    }

    private func assertDurationEditRoundTrip(seconds: Int) throws {
        let editText = WorkoutCardioSetupNumericCodec.durationMinutesText(seconds: seconds)
        let result = try WorkoutCardioSetupValidator.validated(
            WorkoutCardioSetupDraft(
                role: .warmUp,
                goalKind: .time,
                durationMinutesText: editText,
                distanceText: "",
                distanceUnit: .kilometers,
                trackingProfile: .timeOnly
            ),
            locale: Locale(identifier: "sv_SE")
        )

        XCTAssertEqual(result.targetDurationSeconds, seconds)
    }

    private func distanceDraft(text: String) -> WorkoutCardioSetupDraft {
        WorkoutCardioSetupDraft(
            role: .main,
            goalKind: .distance,
            durationMinutesText: "",
            distanceText: text,
            distanceUnit: .meters,
            trackingProfile: .machineDistance
        )
    }
}
