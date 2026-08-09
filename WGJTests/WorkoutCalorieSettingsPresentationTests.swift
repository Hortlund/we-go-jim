import Foundation
import XCTest
@testable import WGJ

final class WorkoutCalorieSettingsPresentationTests: XCTestCase {
    func testCompleteEnabledProfileIsAvailableAndEffectivelyOn() {
        let presentation = makePresentation(
            profile: completeProfile(showsCalorieEstimates: true)
        )

        XCTAssertTrue(presentation.isAvailable)
        XCTAssertTrue(presentation.storedPreference)
        XCTAssertTrue(presentation.effectiveToggleValue)
        XCTAssertEqual(presentation.missingFieldTitles, [])
    }

    func testCompleteDisabledProfileIsAvailableAndEffectivelyOff() {
        let presentation = makePresentation(
            profile: completeProfile(showsCalorieEstimates: false)
        )

        XCTAssertTrue(presentation.isAvailable)
        XCTAssertFalse(presentation.storedPreference)
        XCTAssertFalse(presentation.effectiveToggleValue)
        XCTAssertEqual(presentation.missingFieldTitles, [])
    }

    func testIncompleteEnabledProfilePreservesStoredPreferenceWhileEffectivelyOff() {
        let presentation = makePresentation(
            profile: WorkoutCalorieProfileSnapshot(
                sex: .female,
                dateOfBirth: date(year: 1995, month: 6, day: 15),
                heightCentimeters: 500,
                bodyWeightKilograms: 68,
                showsCalorieEstimates: true
            )
        )

        XCTAssertFalse(presentation.isAvailable)
        XCTAssertTrue(presentation.storedPreference)
        XCTAssertFalse(presentation.effectiveToggleValue)
        XCTAssertEqual(presentation.missingFieldTitles, ["Height"])
    }

    func testMissingFieldTitlesFollowProfileInputOrder() {
        let presentation = makePresentation(
            profile: WorkoutCalorieProfileSnapshot(
                sex: nil,
                dateOfBirth: nil,
                heightCentimeters: nil,
                bodyWeightKilograms: nil,
                showsCalorieEstimates: true
            )
        )

        XCTAssertEqual(
            presentation.missingFieldTitles,
            ["Sex used for estimate", "Date of birth", "Height", "Body weight"]
        )
    }

    private func makePresentation(
        profile: WorkoutCalorieProfileSnapshot
    ) -> WorkoutCalorieSettingsPresentation {
        WorkoutCalorieSettingsPresentation(
            profile: profile,
            referenceDate: date(year: 2026, month: 8, day: 8),
            calendar: calendar
        )
    }

    private func completeProfile(
        showsCalorieEstimates: Bool
    ) -> WorkoutCalorieProfileSnapshot {
        WorkoutCalorieProfileSnapshot(
            sex: .male,
            dateOfBirth: date(year: 1990, month: 2, day: 12),
            heightCentimeters: 180,
            bodyWeightKilograms: 82,
            showsCalorieEstimates: showsCalorieEstimates
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
