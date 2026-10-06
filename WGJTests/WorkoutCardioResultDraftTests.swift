import XCTest
@testable import WGJ

final class WorkoutCardioResultDraftTests: XCTestCase {
    func testDurationAtIntegerOverflowBoundaryIsRejected() {
        for text in [String(Double(Int.max / 60)), "1e100", "inf", "nan"] {
            XCTAssertNil(WorkoutCardioResultDurationCodec.durationSeconds(
                fromMinutesText: text, locale: Locale(identifier: "en_US")
            ))
        }
        let safeMinutes = Double(Int.max / 60).nextDown
        XCTAssertEqual(WorkoutCardioResultDurationCodec.durationSeconds(
            fromMinutesText: String(safeMinutes), locale: Locale(identifier: "en_US")
        ), Int(exactly: (safeMinutes * 60).rounded()))
    }

    func testTinyEnteredDistanceCanRenderSummaryWithoutOverflow() throws {
        for profile in [WorkoutCardioTrackingProfile.walkRun, .rower] {
            let result = try WorkoutCardioResultValidator.validated(
                .fixture(actualDurationSeconds: 600, distanceText: "0.00000000000000000001", trackingProfile: profile),
                locale: Locale(identifier: "en_US")
            )
            let summary = WorkoutCardioResultSummaryFormatter.summary(result, profile: profile)
            XCTAssertTrue(summary.metrics.contains { $0.kind == .duration })
            XCTAssertTrue(summary.metrics.contains { $0.kind == .distance })
            XCTAssertFalse(summary.metrics.contains { $0.kind == .pace || $0.kind == .rowingPace })
        }
    }

    func testDurationOnlyResultIsValid() throws {
        let result = try WorkoutCardioResultValidator.validated(
            .fixture(actualDurationSeconds: 900)
        )

        XCTAssertEqual(result.actualDurationSeconds, 900)
        XCTAssertNil(result.actualDistanceMeters)
    }

    func testDistanceOnlyResultIsValidAndConvertsToCanonicalMeters() throws {
        let result = try WorkoutCardioResultValidator.validated(
            .fixture(distanceText: "3.1", distanceUnit: .miles)
        )

        XCTAssertNil(result.actualDurationSeconds)
        XCTAssertEqual(
            try XCTUnwrap(result.actualDistanceMeters),
            WorkoutDistanceUnit.miles.meters(from: 3.1),
            accuracy: 0.000_001
        )
        XCTAssertEqual(result.preferredDistanceUnit, .miles)
    }

    func testManualResultRequiresDurationOrDistance() {
        XCTAssertThrowsError(try WorkoutCardioResultValidator.validated(.fixture())) {
            XCTAssertEqual(
                $0 as? WorkoutCardioResultValidationError,
                .missingDurationAndDistance
            )
        }
    }

    func testZeroOrNegativeDistanceIsAbsentWhenDurationExists() throws {
        for text in ["0", "-5"] {
            let result = try WorkoutCardioResultValidator.validated(
                .fixture(actualDurationSeconds: 600, distanceText: text)
            )
            XCTAssertNil(result.actualDistanceMeters)
        }
    }

    func testNegativeDurationIsRejected() {
        XCTAssertThrowsError(
            try WorkoutCardioResultValidator.validated(
                .fixture(actualDurationSeconds: -1, distanceText: "1")
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioResultValidationError, .negativeDuration)
        }
    }

    func testInvalidDistanceTextIsRejectedWithoutNormalizingTheDraft() {
        let draft = WorkoutCardioResultDraft.fixture(
            actualDurationSeconds: 600,
            distanceText: "not a distance"
        )

        XCTAssertThrowsError(try WorkoutCardioResultValidator.validated(draft)) {
            XCTAssertEqual($0 as? WorkoutCardioResultValidationError, .invalidDistance)
        }
        XCTAssertEqual(draft.distanceText, "not a distance")
    }

    func testContextualDetailsClampInclineAndRejectNegativeResistance() throws {
        let treadmill = try WorkoutCardioResultValidator.validated(
            .fixture(
                actualDurationSeconds: 600,
                inclineText: "125",
                resistanceLevelText: "8",
                trackingProfile: .treadmill
            )
        )
        XCTAssertEqual(treadmill.inclinePercent, 100)
        XCTAssertNil(treadmill.resistanceLevel)

        XCTAssertThrowsError(
            try WorkoutCardioResultValidator.validated(
                .fixture(
                    actualDurationSeconds: 600,
                    resistanceLevelText: "-0.5",
                    trackingProfile: .rower
                )
            )
        ) {
            XCTAssertEqual($0 as? WorkoutCardioResultValidationError, .negativeResistanceLevel)
        }
    }

    func testUnchangedDistanceTextAndUnitPreserveOriginalCanonicalMeters() throws {
        let originalMeters = 1_234.567_890_123_456_7
        let draft = WorkoutCardioResultDraft(
            actualDurationSeconds: 600,
            actualDistanceMeters: originalMeters,
            distanceUnit: .miles,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: "",
            trackingProfile: .walkRun
        )

        let result = try WorkoutCardioResultValidator.validated(draft)

        XCTAssertEqual(result.actualDistanceMeters, originalMeters)
    }

    func testActualDurationOverTwentyFourHoursRoundTripsWithoutClamping() {
        let seconds = 49 * 60 * 60 + 37
        let text = WorkoutCardioResultDurationCodec.durationMinutesText(seconds: seconds)

        XCTAssertEqual(
            WorkoutCardioResultDurationCodec.durationSeconds(
                fromMinutesText: text,
                locale: Locale(identifier: "en_US")
            ),
            seconds
        )
        XCTAssertGreaterThan(Double(text) ?? 0, 24 * 60)
    }

    func testGPSDistanceUsesTwoDecimalPlacesAndPreservesOriginalMeasurement() throws {
        let meters = 637.2240977908418
        for (identifier, expected, edited) in [
            ("en_US", "0.64", "0.75"),
            ("sv_SE", "0,64", "0,75"),
            ("ar_EG", "٠٫٦٤", "٠٫٧٥"),
            ("fa_IR", "۰٫۶۴", "۰٫۷۵")
        ] {
            let locale = Locale(identifier: identifier)
            var draft = WorkoutCardioResultDraft(
                actualDurationSeconds: 1_682,
                actualDistanceMeters: meters,
                distanceUnit: .kilometers,
                inclinePercent: nil,
                resistanceLevel: nil,
                notes: "",
                trackingProfile: .walkRun,
                locale: locale
            )
            XCTAssertEqual(draft.distanceText, expected)
            draft.notes = "Nice walk"
            XCTAssertEqual(
                try WorkoutCardioResultValidator.validated(draft, locale: locale).actualDistanceMeters,
                meters
            )
            draft.distanceUnit = .miles
            XCTAssertEqual(
                try WorkoutCardioResultValidator.validated(draft, locale: locale).actualDistanceMeters,
                WorkoutDistanceUnit.miles.meters(from: 0.64)
            )
            draft.distanceUnit = .kilometers
            draft.distanceText = edited
            XCTAssertEqual(
                try WorkoutCardioResultValidator.validated(draft, locale: locale).actualDistanceMeters,
                750
            )
        }
    }

    func testDistanceFormattingAcrossUnitsOmitsUnnecessaryDecimalsAndGrouping() {
        let locale = Locale(identifier: "en_US")
        for (meters, unit, expected) in [
            (637.2240977908418, WorkoutDistanceUnit.miles, "0.4"),
            (637.2240977908418, .meters, "637.22"),
            (5_000.0, .kilometers, "5"),
            (1_234_567.8, .kilometers, "1234.57")
        ] {
            XCTAssertEqual(
                WorkoutCardioResultDraft.distanceText(meters: meters, unit: unit, locale: locale),
                expected
            )
        }
    }

    func testDistanceRoundedToZeroStillPreservesTheSourceMeasurement() throws {
        var draft = WorkoutCardioResultDraft(
            actualDurationSeconds: nil,
            actualDistanceMeters: 0.1,
            distanceUnit: .kilometers,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: "",
            trackingProfile: .walkRun,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(draft.distanceText, "0")
        XCTAssertEqual(try WorkoutCardioResultValidator.validated(draft).actualDistanceMeters, 0.1)

        draft.distanceText = ""
        XCTAssertThrowsError(try WorkoutCardioResultValidator.validated(draft)) {
            XCTAssertEqual($0 as? WorkoutCardioResultValidationError, .missingDurationAndDistance)
        }
    }

    func testActualDurationManualEntrySupportsMoreThanTwentyFourHours() {
        XCTAssertEqual(
            WorkoutCardioResultDurationCodec.durationSeconds(
                fromMinutesText: "2880.5",
                locale: Locale(identifier: "en_US")
            ),
            172_830
        )
    }
}

private extension WorkoutCardioResultDraft {
    static func fixture(
        actualDurationSeconds: Int? = nil,
        distanceText: String = "",
        distanceUnit: WorkoutDistanceUnit = .kilometers,
        inclineText: String = "",
        resistanceLevelText: String = "",
        notes: String = "",
        trackingProfile: WorkoutCardioTrackingProfile = .machineDistance
    ) -> Self {
        Self(
            actualDurationSeconds: actualDurationSeconds,
            distanceText: distanceText,
            distanceUnit: distanceUnit,
            inclineText: inclineText,
            resistanceLevelText: resistanceLevelText,
            notes: notes,
            trackingProfile: trackingProfile
        )
    }
}
