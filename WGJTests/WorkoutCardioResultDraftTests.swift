import XCTest
@testable import WGJ

final class WorkoutCardioResultDraftTests: XCTestCase {
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
