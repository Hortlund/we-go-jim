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
        for theme in WGJAppTheme.allCases {
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
