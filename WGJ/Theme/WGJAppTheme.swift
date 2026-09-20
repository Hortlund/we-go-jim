import Observation
import SwiftUI
import UIKit

enum WGJAppTheme: String, CaseIterable, Identifiable {
    case original
    case mintCondition
    case wheyTooPurple
    case sunsOutGunsOut
    case electricStrength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "WGJ Original")
        case .mintCondition: String(localized: "Mint Condition")
        case .wheyTooPurple: String(localized: "Whey Too Purple")
        case .sunsOutGunsOut: String(localized: "Sun’s Out, Guns Out")
        case .electricStrength: String(localized: "Electric Strength")
        }
    }

    var subtitle: String {
        switch self {
        case .original: String(localized: "The classic. Cool blues, strong foundations.")
        case .mintCondition: String(localized: "Fresh mint. Fresh set. Same heavy weights.")
        case .wheyTooPurple: String(localized: "A little extra on the lavender gains.")
        case .sunsOutGunsOut: String(localized: "Golden-hour energy for every rep.")
        case .electricStrength: String(localized: "Carbon. Chalk. Electric lime. Built for your next best.")
        }
    }

    var symbol: String {
        switch self {
        case .original: "dumbbell.fill"
        case .mintCondition: "leaf.fill"
        case .wheyTooPurple: "sparkles"
        case .sunsOutGunsOut: "sun.max.fill"
        case .electricStrength: "bolt.fill"
        }
    }

    var palette: WGJPalette {
        switch self {
        case .original: Self.originalPalette
        case .mintCondition: Self.mintPalette
        case .wheyTooPurple: Self.purplePalette
        case .sunsOutGunsOut: Self.sunsetPalette
        case .electricStrength: Self.electricPalette
        }
    }

    var usesMatteSurfaces: Bool { self == .electricStrength }

    func headingFont(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        // System condensed type preserves Dynamic Type and language coverage.
        self == .electricStrength
            ? Font.system(style, weight: .heavy).width(.condensed)
            : Font.system(style, weight: weight)
    }

    private static let originalPalette = WGJPalette()
    private static let mintPalette = makePalette(
        lightBase: 0xF0F8F5, darkBase: 0x091713,
        lightSurface: 0xE1F0E9, darkSurface: 0x142A23,
        lightRaised: 0xD3E8DF, darkRaised: 0x203C32,
        primary: (0x087B60, 0x80E3BC), secondary: (0x147E83, 0x94DBD8),
        tertiary: (0x779749, 0xC5DCA0)
    )
    private static let purplePalette = makePalette(
        lightBase: 0xF7F3FC, darkBase: 0x151020,
        lightSurface: 0xEDE4F6, darkSurface: 0x261D36,
        lightRaised: 0xE1D6EF, darkRaised: 0x372A48,
        primary: (0x7751BD, 0xC9ACFF), secondary: (0x92508B, 0xEABCE6),
        tertiary: (0x6466AD, 0xB5BBFA)
    )
    private static let sunsetPalette = makePalette(
        lightBase: 0xFCF5EF, darkBase: 0x1B120F,
        lightSurface: 0xF5E7DA, darkSurface: 0x30221C,
        lightRaised: 0xEED8C5, darkRaised: 0x453126,
        primary: (0xAB552C, 0xFFB58C), secondary: (0x94651D, 0xF1CF8C),
        tertiary: (0xAE6370, 0xE9ABB5)
    )
    private static let electricPalette: WGJPalette = {
        var palette = makePalette(
            lightBase: 0xF3F6EF, darkBase: 0x101510,
            lightSurface: 0xE8EDE2, darkSurface: 0x1C241B,
            lightRaised: 0xDCE3D5, darkRaised: 0x2A3427,
            primary: (0x4E6810, 0xD2FF5A), secondary: (0x536A2D, 0xB6D97A),
            tertiary: (0x5C6B52, 0xA7B1A3)
        )
        palette.textPrimary = Color(UIColor.dynamic(light: 0x101510, dark: 0xF3F6EF))
        palette.textSecondary = Color(UIColor.dynamic(light: 0x505D49, dark: 0xA7B1A3))
        palette.textInverse = Color(UIColor.dynamic(light: 0xF3F6EF, dark: 0x101510))
        return palette
    }()

    private static func makePalette(
        lightBase: UInt32, darkBase: UInt32,
        lightSurface: UInt32, darkSurface: UInt32,
        lightRaised: UInt32, darkRaised: UInt32,
        primary: (UInt32, UInt32), secondary: (UInt32, UInt32), tertiary: (UInt32, UInt32)
    ) -> WGJPalette {
        var palette = WGJPalette()
        palette.bgBase = Color(UIColor.dynamic(light: lightBase, dark: darkBase))
        palette.bgElevated = Color(UIColor.dynamic(light: lightSurface, dark: darkSurface))
        palette.bgFloating = Color(UIColor.dynamic(light: lightRaised, dark: darkRaised))
        palette.card = Color(UIColor.dynamic(light: 0xFFFFFF, dark: darkSurface))
        palette.cardStrong = Color(UIColor.dynamic(light: lightBase, dark: darkSurface))
        palette.cardElevated = Color(UIColor.dynamic(light: lightSurface, dark: darkRaised))
        palette.field = Color(UIColor.dynamic(light: lightSurface, dark: darkBase))
        palette.fieldStrong = Color(UIColor.dynamic(light: lightRaised, dark: darkRaised))
        palette.accentBlue = Color(UIColor.dynamic(light: primary.0, dark: primary.1))
        palette.accentCyan = Color(UIColor.dynamic(light: secondary.0, dark: secondary.1))
        palette.accentPurple = Color(UIColor.dynamic(light: tertiary.0, dark: tertiary.1))
        // Status colors retain their meaning across themes.
        return palette
    }
}

/// Device appearance is independent of workout data and CloudKit backups.
/// Computed WGJTheme tokens read this observable selection directly, so existing
/// screens update without recreating their identity or losing navigation/drafts.
@MainActor
@Observable
final class WGJThemePreferences {
    static let shared = WGJThemePreferences()
    static let storageKey = "appearance.theme"

    private(set) var selected: WGJAppTheme
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selected = defaults.string(forKey: Self.storageKey)
            .flatMap(WGJAppTheme.init(rawValue:)) ?? .original
    }

    func select(_ theme: WGJAppTheme) {
        guard selected != theme else { return }
        defaults.set(theme.rawValue, forKey: Self.storageKey)
        selected = theme
    }
}
