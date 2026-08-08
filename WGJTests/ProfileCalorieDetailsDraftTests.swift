import XCTest
@testable import WGJ

final class ProfileCalorieDetailsDraftTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    func testRegionalHeightUnitDefaultsToFeetAndInchesForUSLocale() {
        XCTAssertEqual(
            ProfileHeightDisplayUnit.regionalDefault(locale: Locale(identifier: "en_US")),
            .feetAndInches
        )
    }

    func testRegionalHeightUnitDefaultsToCentimetersForMetricLocale() {
        XCTAssertEqual(
            ProfileHeightDisplayUnit.regionalDefault(locale: Locale(identifier: "sv_SE")),
            .centimeters
        )
    }

    func testOneHundredEightyCentimetersRoundTripsThroughFeetAndInches() throws {
        let draft = ProfileCalorieDetailsDraft(
            snapshot: snapshot(heightCentimeters: 180),
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(draft.heightFeetText, "5")
        XCTAssertEqual(draft.heightInchesText, "10.87")

        let canonical = try canonicalSnapshot(from: draft)
        XCTAssertEqual(try XCTUnwrap(canonical.heightCentimeters), 180, accuracy: 0.01)
    }

    func testEightyKilogramsRoundTripsThroughPounds() throws {
        let draft = ProfileCalorieDetailsDraft(
            snapshot: snapshot(bodyWeightKilograms: 80),
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .lb,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(draft.bodyWeightText, "176.37")

        let canonical = try canonicalSnapshot(from: draft)
        XCTAssertEqual(try XCTUnwrap(canonical.bodyWeightKilograms), 80, accuracy: 0.01)
    }

    func testUnchangedFormattedInputsPreserveOriginalCanonicalPrecision() throws {
        let draft = ProfileCalorieDetailsDraft(
            snapshot: snapshot(
                heightCentimeters: 180.123_456,
                bodyWeightKilograms: 80.123_456
            ),
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .lb,
            locale: Locale(identifier: "en_US")
        )

        let canonical = try canonicalSnapshot(from: draft)

        XCTAssertEqual(canonical.heightCentimeters, 180.123_456)
        XCTAssertEqual(canonical.bodyWeightKilograms, 80.123_456)
    }

    func testNonfiniteStoredCanonicalValuesStayEditableAndProduceFieldErrors() {
        let draft = ProfileCalorieDetailsDraft(
            snapshot: snapshot(
                heightCentimeters: .infinity,
                bodyWeightKilograms: .nan
            ),
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .lb,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(draft.heightFeetText, "")
        XCTAssertEqual(draft.heightInchesText, "")
        XCTAssertEqual(draft.bodyWeightText, "")

        let error = canonicalError(from: draft)
        XCTAssertTrue(error.contains(.height))
        XCTAssertTrue(error.contains(.bodyWeight))
    }

    func testEmptyOptionalInputsProduceNilCanonicalValues() throws {
        let draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .lb,
            locale: Locale(identifier: "en_US")
        )

        let canonical = try canonicalSnapshot(from: draft, showsCalorieEstimates: false)

        XCTAssertNil(canonical.sex)
        XCTAssertNil(canonical.dateOfBirth)
        XCTAssertNil(canonical.heightCentimeters)
        XCTAssertNil(canonical.bodyWeightKilograms)
        XCTAssertFalse(canonical.showsCalorieEstimates)
    }

    func testEnteredNonnumericHeightAndWeightProduceFieldErrors() {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
        draft.heightCentimetersText = "tall"
        draft.bodyWeightText = "heavy"

        let error = canonicalError(from: draft)

        XCTAssertTrue(error.contains(.height))
        XCTAssertTrue(error.contains(.bodyWeight))
        XCTAssertFalse(error.contains(.dateOfBirth))
    }

    func testIncompleteFeetAndInchesTreatsTheBlankComponentAsZero() throws {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
        draft.heightFeetText = "5"

        let canonical = try canonicalSnapshot(from: draft)

        XCTAssertEqual(try XCTUnwrap(canonical.heightCentimeters), 152.4, accuracy: 0.01)
    }

    func testTwelveOrMoreEnteredInchesProducesHeightError() {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .feetAndInches,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
        draft.heightFeetText = "5"
        draft.heightInchesText = "12"

        XCTAssertTrue(canonicalError(from: draft).contains(.height))
    }

    func testUSHeightDisplayBoundariesSnapToCanonicalLimits() throws {
        for (feet, inches, expectedCentimeters) in [
            ("3", "11.24", 120.0),
            ("7", "6.55", 230.0),
        ] {
            var draft = ProfileCalorieDetailsDraft(
                heightDisplayUnit: .feetAndInches,
                preferredWeightUnit: .kg,
                locale: Locale(identifier: "en_US")
            )
            draft.heightFeetText = feet
            draft.heightInchesText = inches

            let canonical = try canonicalSnapshot(from: draft)

            XCTAssertEqual(canonical.heightCentimeters, expectedCentimeters)
        }
    }

    func testUSHeightValuesOutsideDisplayedBoundariesRemainInvalid() {
        for (feet, inches) in [("3", "11.23"), ("7", "6.56")] {
            var draft = ProfileCalorieDetailsDraft(
                heightDisplayUnit: .feetAndInches,
                preferredWeightUnit: .kg,
                locale: Locale(identifier: "en_US")
            )
            draft.heightFeetText = feet
            draft.heightInchesText = inches

            XCTAssertTrue(canonicalError(from: draft).contains(.height))
        }
    }

    func testPoundDisplayBoundariesSnapToCanonicalLimits() throws {
        for (pounds, expectedKilograms) in [("77.16", 35.0), ("661.39", 300.0)] {
            var draft = ProfileCalorieDetailsDraft(
                heightDisplayUnit: .centimeters,
                preferredWeightUnit: .lb,
                locale: Locale(identifier: "en_US")
            )
            draft.bodyWeightText = pounds

            let canonical = try canonicalSnapshot(from: draft)

            XCTAssertEqual(canonical.bodyWeightKilograms, expectedKilograms)
        }
    }

    func testPoundValuesOutsideDisplayedBoundariesRemainInvalid() {
        for pounds in ["77.15", "661.40"] {
            var draft = ProfileCalorieDetailsDraft(
                heightDisplayUnit: .centimeters,
                preferredWeightUnit: .lb,
                locale: Locale(identifier: "en_US")
            )
            draft.bodyWeightText = pounds

            XCTAssertTrue(canonicalError(from: draft).contains(.bodyWeight))
        }
    }

    func testHeightValidationIncludesOneHundredTwentyAndTwoHundredThirtyCentimeters() throws {
        for value in [120.0, 230.0] {
            var draft = metricDraft()
            draft.heightCentimetersText = String(value)

            let canonical = try canonicalSnapshot(from: draft)

            XCTAssertEqual(try XCTUnwrap(canonical.heightCentimeters), value, accuracy: 0.000_001)
        }
    }

    func testHeightValidationRejectsValuesOutsideInclusiveBounds() {
        for value in [119.99, 230.01] {
            var draft = metricDraft()
            draft.heightCentimetersText = String(value)

            XCTAssertTrue(canonicalError(from: draft).contains(.height))
        }
    }

    func testWeightValidationIncludesThirtyFiveAndThreeHundredKilograms() throws {
        for value in [35.0, 300.0] {
            var draft = metricDraft()
            draft.bodyWeightText = String(value)

            let canonical = try canonicalSnapshot(from: draft)

            XCTAssertEqual(try XCTUnwrap(canonical.bodyWeightKilograms), value, accuracy: 0.000_001)
        }
    }

    func testWeightValidationRejectsValuesOutsideInclusiveBounds() {
        for value in [34.99, 300.01] {
            var draft = metricDraft()
            draft.bodyWeightText = String(value)

            XCTAssertTrue(canonicalError(from: draft).contains(.bodyWeight))
        }
    }

    func testAgeValidationIncludesEighteenAndOneHundredYears() throws {
        for dateOfBirth in [date(year: 2008, month: 1, day: 1), date(year: 1926, month: 1, day: 1)] {
            var draft = metricDraft()
            draft.dateOfBirth = dateOfBirth

            let canonical = try canonicalSnapshot(from: draft)

            XCTAssertEqual(canonical.dateOfBirth, dateOfBirth)
        }
    }

    func testAgeValidationRejectsUnderEighteenAndOverOneHundredYears() {
        for dateOfBirth in [date(year: 2008, month: 1, day: 2), date(year: 1925, month: 1, day: 1)] {
            var draft = metricDraft()
            draft.dateOfBirth = dateOfBirth

            XCTAssertTrue(canonicalError(from: draft).contains(.dateOfBirth))
        }
    }

    func testFutureDateOfBirthProducesDateFieldError() {
        var draft = metricDraft()
        draft.dateOfBirth = date(year: 2026, month: 1, day: 2)

        XCTAssertTrue(canonicalError(from: draft).contains(.dateOfBirth))
    }

    func testDerivedAgeUsesTheProvidedReferenceDateAndCalendar() {
        var draft = metricDraft()
        draft.dateOfBirth = date(year: 1996, month: 1, day: 2)

        XCTAssertEqual(
            draft.ageYears(referenceDate: referenceDate, calendar: calendar),
            29
        )
    }

    func testCommaDecimalInputUsesDraftLocale() throws {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "sv_SE")
        )
        draft.heightCentimetersText = "180,5"
        draft.bodyWeightText = "80,25"

        let canonical = try canonicalSnapshot(from: draft)

        XCTAssertEqual(try XCTUnwrap(canonical.heightCentimeters), 180.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(canonical.bodyWeightKilograms), 80.25, accuracy: 0.000_001)
    }

    func testLocaleNativeArabicDigitsAndDecimalSeparatorParse() throws {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "ar_EG")
        )
        draft.heightCentimetersText = "١٨٠٫٥"
        draft.bodyWeightText = "٨٠٫٢٥"

        let canonical = try canonicalSnapshot(from: draft)

        XCTAssertEqual(canonical.heightCentimeters, 180.5)
        XCTAssertEqual(canonical.bodyWeightKilograms, 80.25)
    }

    func testValidLocalizedDecimalAndGroupingParseAsWholeStrings() throws {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
        draft.heightCentimetersText = "0,180.5"
        draft.bodyWeightText = "0,080.25"

        let canonical = try canonicalSnapshot(from: draft)

        XCTAssertEqual(canonical.heightCentimeters, 180.5)
        XCTAssertEqual(canonical.bodyWeightKilograms, 80.25)
    }

    func testMalformedUSGroupingIsRejectedRatherThanReinterpreted() {
        var draft = ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
        draft.heightCentimetersText = "1,80"
        draft.bodyWeightText = "8,0"

        let error = canonicalError(from: draft)

        XCTAssertTrue(error.contains(.height))
        XCTAssertTrue(error.contains(.bodyWeight))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func metricDraft() -> ProfileCalorieDetailsDraft {
        ProfileCalorieDetailsDraft(
            heightDisplayUnit: .centimeters,
            preferredWeightUnit: .kg,
            locale: Locale(identifier: "en_US")
        )
    }

    private func snapshot(
        heightCentimeters: Double? = nil,
        bodyWeightKilograms: Double? = nil
    ) -> WorkoutCalorieProfileSnapshot {
        WorkoutCalorieProfileSnapshot(
            sex: nil,
            dateOfBirth: nil,
            heightCentimeters: heightCentimeters,
            bodyWeightKilograms: bodyWeightKilograms,
            showsCalorieEstimates: true
        )
    }

    private func canonicalSnapshot(
        from draft: ProfileCalorieDetailsDraft,
        showsCalorieEstimates: Bool = true
    ) throws -> WorkoutCalorieProfileSnapshot {
        try draft.canonicalSnapshot(
            showsCalorieEstimates: showsCalorieEstimates,
            referenceDate: referenceDate,
            calendar: calendar
        ).get()
    }

    private func canonicalError(
        from draft: ProfileCalorieDetailsDraft
    ) -> ProfileCalorieDetailsDraftError {
        switch draft.canonicalSnapshot(
            showsCalorieEstimates: true,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
        case .success:
            XCTFail("Expected draft validation to fail")
            return ProfileCalorieDetailsDraftError(invalidFields: [])
        case let .failure(error):
            return error
        }
    }
}
