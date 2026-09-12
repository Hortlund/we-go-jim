import XCTest
@testable import WGJ

final class LocalizedFiniteNumberParserTests: XCTestCase {
    func testLocaleSeparatorsAndCanonicalDecimalText() {
        let cases: [(String, String, Double)] = [
            ("1,234.5", "en_US", 1_234.5),
            ("1.234,5", "de_DE", 1_234.5),
            ("1\u{00a0}234,5", "sv_SE", 1_234.5),
            ("1234.5", "de_DE", 1_234.5),
            (" -2,5 ", "sv_SE", -2.5),
            ("0", "en_US", 0),
        ]
        for (text, locale, expected) in cases {
            XCTAssertEqual(LocalizedFiniteNumberParser.parse(text, locale: Locale(identifier: locale)), expected)
        }
    }

    func testEmptyMalformedAndNonFiniteNumbersAreRejected() {
        for text in ["", " \n ", "abc", "1.2.3", "NaN", "inf", "-inf", "1e999"] {
            XCTAssertNil(LocalizedFiniteNumberParser.parse(text, locale: Locale(identifier: "en_US")))
        }
    }

    func testPlannedAndActualDurationsKeepDifferentLimits() {
        let locale = Locale(identifier: "sv_SE")
        XCTAssertEqual(WorkoutCardioSetupNumericCodec.durationSeconds(fromMinutesText: "2880,5", locale: locale), 86_400)
        XCTAssertEqual(WorkoutCardioResultDurationCodec.durationSeconds(fromMinutesText: "2880,5", locale: locale), 172_830)
        XCTAssertNil(WorkoutCardioSetupNumericCodec.distanceMeters(from: "-1", unit: .kilometers, locale: locale))
    }
}
