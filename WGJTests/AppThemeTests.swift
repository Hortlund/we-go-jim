import Observation
import SwiftUI
import UIKit
import XCTest
@testable import WGJ

final class AppThemeTests: XCTestCase {
    @MainActor
    func testMissingAndUnknownPreferencesUseOriginal() throws {
        let name = "AppThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(WGJThemePreferences(defaults: defaults).selected, .original)
        defaults.set("a-future-theme", forKey: WGJThemePreferences.storageKey)
        XCTAssertEqual(WGJThemePreferences(defaults: defaults).selected, .original)
    }

    @MainActor
    func testSelectionSurvivesNewPreferencesInstanceAndCanReset() throws {
        let name = "AppThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = WGJThemePreferences(defaults: defaults)
        for theme in WGJAppTheme.allCases where theme != .christmas {
            preferences.select(theme)
            XCTAssertEqual(WGJThemePreferences(defaults: defaults).selected, theme)
        }
        preferences.select(.original)
        XCTAssertEqual(WGJThemePreferences(defaults: defaults).selected, .original)
    }

    @MainActor
    func testSharedTokensTrackThemeChangesWithoutReplacingViewIdentity() {
        let preferences = WGJThemePreferences.shared
        let previous = preferences.selected
        defer { preferences.select(previous) }
        preferences.select(.original)
        let originalAccent = WGJTheme.accent
        let changed = expectation(description: "Token read observes theme selection")
        withObservationTracking {
            _ = WGJTheme.accent
            _ = WGJTheme.bgBase
        } onChange: {
            changed.fulfill()
        }
        preferences.select(.mintCondition)
        XCTAssertNotEqual(WGJTheme.accent, originalAccent)
        XCTAssertEqual(WGJTheme.accent, WGJAppTheme.mintCondition.palette.accentBlue)
        wait(for: [changed], timeout: 1)
    }

    @MainActor
    func testNewPalettesKeepReadableTextAndButtonContrast() {
        for theme in WGJAppTheme.allCases where theme != .original {
            let palette = theme.palette
            for style in [UIUserInterfaceStyle.light, .dark] {
                for surface in [palette.bgBase, palette.card, palette.cardElevated] {
                    XCTAssertGreaterThanOrEqual(contrast(palette.textPrimary, surface, style), 4.5, "\(theme) primary text")
                    XCTAssertGreaterThanOrEqual(contrast(palette.textSecondary, surface, style), 4.5, "\(theme) secondary text")
                }
                for accent in [palette.accentBlue, palette.accentCyan] {
                    XCTAssertGreaterThanOrEqual(contrast(palette.textInverse, accent, style), 4.5, "\(theme) button text")
                }
            }
        }
    }

    @MainActor
    func testChristmasRibbonAndExclusiveCardKeepReadableContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for background in [WGJChristmasStyle.cranberry, WGJChristmasStyle.deepRed] {
                XCTAssertGreaterThanOrEqual(contrast(WGJChristmasStyle.cream, background, style), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(WGJChristmasStyle.gold, background, style), 4.5)
            }
        }
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testChristmasReturnsEveryDecemberWithoutYearLimit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for year in [2026, 2027, 2032, 2099, 2400] {
            XCTAssertFalse(ChristmasThemeSeason.isAvailable(on: date("\(year)-11-30T23:59:59Z"), calendar: calendar))
            XCTAssertTrue(ChristmasThemeSeason.isAvailable(on: date("\(year)-12-01T00:00:00Z"), calendar: calendar))
            XCTAssertTrue(ChristmasThemeSeason.isAvailable(on: date("\(year)-12-31T23:59:59Z"), calendar: calendar))
            XCTAssertFalse(ChristmasThemeSeason.isAvailable(on: date("\(year + 1)-01-01T00:00:00Z"), calendar: calendar))
        }
    }

    func testChristmasFollowsLocalTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        XCTAssertTrue(ChristmasThemeSeason.isAvailable(on: date("2026-11-30T23:00:00Z"), calendar: calendar))
        XCTAssertFalse(ChristmasThemeSeason.isAvailable(on: date("2026-12-31T23:00:00Z"), calendar: calendar))
        calendar.timeZone = TimeZone(secondsFromGMT: -28800)!
        XCTAssertFalse(ChristmasThemeSeason.isAvailable(on: date("2026-12-01T07:59:59Z"), calendar: calendar))
        XCTAssertTrue(ChristmasThemeSeason.isAvailable(on: date("2027-01-01T07:59:59Z"), calendar: calendar))
    }

    @MainActor
    func testChristmasExpiresAndRequiresChoosingAgainNextYear() throws {
        let name = "AppThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var clock = date("2026-11-15T12:00:00Z")
        let preferences = WGJThemePreferences(defaults: defaults, now: { clock })
        preferences.select(.mintCondition)
        preferences.select(.christmas)
        XCTAssertEqual(preferences.selected, .mintCondition)
        XCTAssertFalse(preferences.availableThemes.contains(.christmas))

        clock = date("2026-12-15T12:00:00Z")
        preferences.refreshSeason()
        XCTAssertTrue(preferences.availableThemes.contains(.christmas))
        XCTAssertEqual(preferences.selected, .mintCondition, "December never opts you in")
        preferences.select(.christmas)
        XCTAssertEqual(preferences.selected, .christmas)
        XCTAssertEqual(WGJThemePreferences(defaults: defaults, now: { clock }).selected, .christmas)

        clock = date("2027-01-15T12:00:00Z")
        preferences.refreshSeason()
        XCTAssertEqual(preferences.selected, .mintCondition)
        XCTAssertFalse(preferences.availableThemes.contains(.christmas))
        XCTAssertEqual(WGJThemePreferences(defaults: defaults, now: { clock }).selected, .mintCondition)

        clock = date("2027-12-15T12:00:00Z")
        preferences.refreshSeason()
        XCTAssertTrue(preferences.availableThemes.contains(.christmas))
        XCTAssertEqual(preferences.selected, .mintCondition)
        preferences.select(.christmas)
        XCTAssertEqual(preferences.selected, .christmas)

        // Even if the app was closed all year, the next December is a fresh opt-in.
        clock = date("2028-12-15T12:00:00Z")
        XCTAssertEqual(WGJThemePreferences(defaults: defaults, now: { clock }).selected, .mintCondition)
    }

    @MainActor
    func testColdLaunchOutsideDecemberRestoresRegularThemeAndManualChoiceWins() throws {
        let name = "AppThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var clock = date("2026-12-15T12:00:00Z")
        let preferences = WGJThemePreferences(defaults: defaults, now: { clock })
        preferences.select(.electricStrength)
        preferences.select(.christmas)
        clock = date("2027-01-15T12:00:00Z")
        XCTAssertEqual(WGJThemePreferences(defaults: defaults, now: { clock }).selected, .electricStrength)

        clock = date("2027-12-15T12:00:00Z")
        preferences.select(.christmas)
        preferences.select(.wheyTooPurple)
        clock = date("2028-01-15T12:00:00Z")
        preferences.refreshSeason()
        XCTAssertEqual(preferences.selected, .wheyTooPurple)
    }

    @MainActor
    private func contrast(_ foreground: Color, _ background: Color, _ style: UIUserInterfaceStyle) -> Double {
        func luminance(_ color: Color) -> Double {
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
