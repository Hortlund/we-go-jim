import Observation
import SwiftUI
import UIKit

enum WGJAppTheme: String, CaseIterable, Identifiable {
    case original
    case mintCondition
    case wheyTooPurple
    case sunsOutGunsOut
    case electricStrength
    case christmas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .christmas: String(localized: "Sleigh Day")
        case .original: String(localized: "WGJ Original")
        case .mintCondition: String(localized: "Mint Condition")
        case .wheyTooPurple: String(localized: "Whey Too Purple")
        case .sunsOutGunsOut: String(localized: "Sun’s Out, Guns Out")
        case .electricStrength: String(localized: "Electric Strength")
        }
    }

    var subtitle: String {
        switch self {
        case .christmas: String(localized: "Deck the halls. Lift the weights. Only in December.")
        case .original: String(localized: "The classic. Cool blues, strong foundations.")
        case .mintCondition: String(localized: "Fresh mint. Fresh set. Same heavy weights.")
        case .wheyTooPurple: String(localized: "A little extra on the lavender gains.")
        case .sunsOutGunsOut: String(localized: "Golden-hour energy for every rep.")
        case .electricStrength: String(localized: "Carbon. Chalk. Electric lime. Built for your next best.")
        }
    }

    var symbol: String {
        switch self {
        case .christmas: "snowflake"
        case .original: "dumbbell.fill"
        case .mintCondition: "leaf.fill"
        case .wheyTooPurple: "sparkles"
        case .sunsOutGunsOut: "sun.max.fill"
        case .electricStrength: "bolt.fill"
        }
    }

    var palette: WGJPalette {
        switch self {
        case .christmas: Self.christmasPalette
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
        if self == .christmas { return Font.system(style, design: .rounded, weight: weight) }
        return self == .electricStrength
            ? Font.system(style, weight: .heavy).width(.condensed)
            : Font.system(style, weight: weight)
    }

    private static let christmasPalette: WGJPalette = {
        var palette = makePalette(
            lightBase: 0xFBF6E9, darkBase: 0x06180F,
            lightSurface: 0xE9EDDE, darkSurface: 0x102C1C,
            lightRaised: 0xDCE5CF, darkRaised: 0x1D3D28,
            primary: (0x825719, 0xF3CA6C), secondary: (0x825719, 0xFFE5A3),
            tertiary: (0xA31D32, 0xFF6675)
        )
        palette.textPrimary = Color(UIColor.dynamic(light: 0x162C23, dark: 0xFFF8E7))
        palette.textSecondary = Color(UIColor.dynamic(light: 0x4D6055, dark: 0xB7CDBE))
        palette.accentGold = Color(UIColor.dynamic(light: 0x826019, dark: 0xF5D58C))
        return palette
    }()

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
    // Avoid the iOS <=26.2 isolated-deinit crash: swiftlang/swift#88036.
    nonisolated deinit { }

    static let shared = WGJThemePreferences(now: {
        #if DEBUG
        // Test-only clock; production always follows the device's local date.
        if ProcessInfo.processInfo.arguments.contains("UITEST_IN_MEMORY_STORE"),
           let value = ProcessInfo.processInfo.environment["UITEST_THEME_DATE"],
           let date = ISO8601DateFormatter().date(from: value) { return date }
        #endif
        return .now
    })
    static let storageKey = "appearance.theme"
    static let regularThemeStorageKey = "appearance.regularTheme"
    static let christmasYearStorageKey = "appearance.christmasYear"

    private(set) var selected: WGJAppTheme
    private(set) var isChristmasAvailable: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar

    var availableThemes: [WGJAppTheme] {
        WGJAppTheme.allCases.filter { $0 != .christmas || isChristmasAvailable }
    }

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now },
        calendar: @escaping () -> Calendar = { ChristmasThemeSeason.localCalendar }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        selected = defaults.string(forKey: Self.storageKey)
            .flatMap(WGJAppTheme.init(rawValue:)) ?? .original
        isChristmasAvailable = ChristmasThemeSeason.isAvailable(on: now(), calendar: calendar())
        refreshSeason()
    }

    func refreshSeason() {
        let available = ChristmasThemeSeason.isAvailable(on: now(), calendar: calendar())
        if isChristmasAvailable != available { isChristmasAvailable = available }
        let year = calendar().component(.year, from: now())
        if selected == .christmas && (!available || defaults.integer(forKey: Self.christmasYearStorageKey) != year) {
            let previous = defaults.string(forKey: Self.regularThemeStorageKey)
                .flatMap(WGJAppTheme.init(rawValue:)) ?? .original
            persist(previous == .christmas ? .original : previous)
        }
    }

    func select(_ theme: WGJAppTheme) {
        refreshSeason()
        guard theme != .christmas || isChristmasAvailable, selected != theme else { return }
        if theme == .christmas {
            defaults.set(selected.rawValue, forKey: Self.regularThemeStorageKey)
            defaults.set(calendar().component(.year, from: now()), forKey: Self.christmasYearStorageKey)
        }
        persist(theme)
    }

    private func persist(_ theme: WGJAppTheme) {
        defaults.set(theme.rawValue, forKey: Self.storageKey)
        selected = theme
    }
}

/// December means the Gregorian month in the device's local time zone,
/// regardless of the user's preferred display calendar. No year cutoff.
enum ChristmasThemeSeason {
    nonisolated static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    nonisolated static func isAvailable(on date: Date, calendar: Calendar = localCalendar) -> Bool {
        calendar.component(.month, from: date) == 12
    }
}
