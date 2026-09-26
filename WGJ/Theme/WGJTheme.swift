import SwiftUI
import UIKit

// Values are cached per palette; reading a token observes the selected theme.
struct WGJPalette {
    var bgBase = Color(UIColor.dynamic(light: 0xF4F7FA, dark: 0x0A1016))
    var bgElevated = Color(UIColor.dynamic(light: 0xE6EDF4, dark: 0x111922))
    var bgFloating = Color(UIColor.dynamic(light: 0xDDE7F0, dark: 0x18232E))

    var card = Color(UIColor.dynamic(light: 0xFFFFFF, dark: 0x16202A))
    var cardStrong = Color(UIColor.dynamic(light: 0xF8FBFD, dark: 0x1B2733))
    var cardElevated = Color(UIColor.dynamic(light: 0xEEF4F9, dark: 0x22303D))
    var field = Color(UIColor.dynamic(light: 0xEEF3F8, dark: 0x111A23))
    var fieldStrong = Color(UIColor.dynamic(light: 0xE6EDF4, dark: 0x18232E))
    var destructiveField = Color(UIColor.dynamic(light: 0xFBEDEE, dark: 0x2C181B))

    var textPrimary = Color(UIColor.dynamic(light: 0x0D1520, dark: 0xF5F7FA))
    var textSecondary = Color(UIColor.dynamic(light: 0x566476, dark: 0xA4AFBC))
    var textTertiary = Color(UIColor.dynamic(light: 0x7F8A98, dark: 0x7B8795))
    var textInverse = Color(UIColor.dynamic(light: 0xFFFFFF, dark: 0x0B1016))

    var accentBlue = Color(UIColor.dynamic(light: 0x1E86FF, dark: 0x6DB5FF))
    var accentCyan = Color(UIColor.dynamic(light: 0x2CB8D9, dark: 0x7CE3EF))
    var accentPurple = Color(UIColor.dynamic(light: 0xA4B5FF, dark: 0x9FB0FF))
    var accentGold = Color(UIColor.dynamic(light: 0xB48A2D, dark: 0xE0C56B))
    var success = Color(UIColor.dynamic(light: 0x1A9D6F, dark: 0x62D8A6))
    var warning = Color(UIColor.dynamic(light: 0xC58A2E, dark: 0xE6BE73))
    var danger = Color(UIColor.dynamic(light: 0xD65A5A, dark: 0xFF8484))
}

enum WGJTheme {
    static var usesMatteSurfaces: Bool { WGJThemePreferences.shared.selected.usesMatteSurfaces }

    static func headingFont(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        WGJThemePreferences.shared.selected.headingFont(style, weight: weight)
    }

    static var bgBase: Color { WGJThemePreferences.shared.selected.palette.bgBase }
    static var bgElevated: Color { WGJThemePreferences.shared.selected.palette.bgElevated }
    static var bgFloating: Color { WGJThemePreferences.shared.selected.palette.bgFloating }
    static var card: Color { WGJThemePreferences.shared.selected.palette.card }
    static var cardStrong: Color { WGJThemePreferences.shared.selected.palette.cardStrong }
    static var cardElevated: Color { WGJThemePreferences.shared.selected.palette.cardElevated }
    static var field: Color { WGJThemePreferences.shared.selected.palette.field }
    static var fieldStrong: Color { WGJThemePreferences.shared.selected.palette.fieldStrong }
    static var destructiveField: Color { WGJThemePreferences.shared.selected.palette.destructiveField }
    static var textPrimary: Color { WGJThemePreferences.shared.selected.palette.textPrimary }
    static var textSecondary: Color { WGJThemePreferences.shared.selected.palette.textSecondary }
    static var textTertiary: Color { WGJThemePreferences.shared.selected.palette.textTertiary }
    static var textInverse: Color { WGJThemePreferences.shared.selected.palette.textInverse }
    static var accentBlue: Color { WGJThemePreferences.shared.selected.palette.accentBlue }
    static var accentCyan: Color { WGJThemePreferences.shared.selected.palette.accentCyan }
    static var accentPurple: Color { WGJThemePreferences.shared.selected.palette.accentPurple }
    static var accentGold: Color { WGJThemePreferences.shared.selected.palette.accentGold }
    static var success: Color { WGJThemePreferences.shared.selected.palette.success }
    static var warning: Color { WGJThemePreferences.shared.selected.palette.warning }
    static var danger: Color { WGJThemePreferences.shared.selected.palette.danger }

    static let outline = Color.white.opacity(0.18)
    static let outlineStrong = Color.white.opacity(0.24)
    static let shadowSoft = Color.black.opacity(0.10)
    static let shadowStrong = Color.black.opacity(0.18)
    static var rowDivider: Color { (usesMatteSurfaces ? textSecondary : accentBlue).opacity(0.20) }

    static var accent: Color { accentBlue }

    static var appHeroGradient: LinearGradient {
        LinearGradient(
            colors: [
                usesMatteSurfaces ? card : Color.white.opacity(0.34),
                usesMatteSurfaces ? card : accentBlue.opacity(0.12),
                usesMatteSurfaces ? card : accentPurple.opacity(0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var headerOverlayGradient: LinearGradient {
        LinearGradient(
            colors: [
                usesMatteSurfaces ? card : Color.white.opacity(0.24),
                usesMatteSurfaces ? card : accentBlue.opacity(0.10),
                usesMatteSurfaces ? card : accentCyan.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var screenBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                bgBase,
                usesMatteSurfaces ? bgBase : bgElevated,
                usesMatteSurfaces ? bgBase : accentBlue.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum WGJSpacing {
    static let page: CGFloat = 16
    static let section: CGFloat = 18
    static let card: CGFloat = 14
    static let control: CGFloat = 12
}

enum WGJRadius {
    static let card: CGFloat = 20
    static let control: CGFloat = 14
    static let pill: CGFloat = 999
}

enum WGJMotion {
    static func disclosureAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.24, extraBounce: 0.02)
    }

    static func cardAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.28, extraBounce: 0.03)
    }

    static func quickAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.22, extraBounce: 0.02)
    }

    static func overlayAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.26, extraBounce: 0.04)
    }

    static func activeWorkoutPresentationAnimation(reduceMotion: Bool) -> Animation {
        // A full-screen surface should settle once, without spring overshoot.
        .easeOut(duration: reduceMotion ? 0.01 : 0.42)
    }

    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity),
            removal: reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
        )
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.995, anchor: .top))
        )
    }
}

private struct WGJGlassContainerModifier: ViewModifier {
    let spacing: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        // iOS 26 glass rendering currently blanks key workout text on device,
        // so keep the existing material-based styling path until that is isolated.
        let _ = spacing
        content
    }
}

private enum WGJButtonTone {
    case primary
    case secondary
    case destructive
}

private struct WGJCardModifier: ViewModifier {
    let strong: Bool
    let cornerRadius: CGFloat

    private var fillColor: Color {
        if WGJTheme.usesMatteSurfaces { return strong ? WGJTheme.cardStrong : WGJTheme.card }
        return strong ? WGJTheme.cardStrong.opacity(0.98) : WGJTheme.card.opacity(0.94)
    }

    private var strokeColor: Color {
        strong ? WGJTheme.outline.opacity(0.52) : WGJTheme.outline.opacity(0.34)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    }
            }
    }
}

private struct WGJGlassButtonBackground: View {
    let tone: WGJButtonTone
    let isPressed: Bool

    private var fill: AnyShapeStyle {
        switch tone {
        case .primary:
            if WGJTheme.usesMatteSurfaces {
                return AnyShapeStyle(WGJTheme.accent.opacity(isPressed ? 0.85 : 1))
            }
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        WGJTheme.accentBlue.opacity(isPressed ? 0.88 : 0.98),
                        WGJTheme.accentCyan.opacity(isPressed ? 0.74 : 0.84),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary:
            return AnyShapeStyle(WGJTheme.fieldStrong.opacity(isPressed ? 0.98 : 0.92))
        case .destructive:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        WGJTheme.danger.opacity(isPressed ? 0.82 : 0.92),
                        WGJTheme.danger.opacity(isPressed ? 0.66 : 0.76),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var overlayFill: Color {
        if WGJTheme.usesMatteSurfaces { return .clear }
        switch tone {
        case .primary:
            return Color.white.opacity(0.04)
        case .secondary:
            return WGJTheme.card.opacity(isPressed ? 0.10 : 0.06)
        case .destructive:
            return WGJTheme.destructiveField.opacity(isPressed ? 0.12 : 0.06)
        }
    }

    private var stroke: Color {
        switch tone {
        case .primary:
            return Color.white.opacity(0.18)
        case .secondary:
            return WGJTheme.outline.opacity(0.86)
        case .destructive:
            return WGJTheme.danger.opacity(0.32)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(overlayFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}

extension UIColor {
    nonisolated static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        }
    }

    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct WGJAdaptiveControlLabelModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let minimumScaleFactor: CGFloat

    init(minimumScaleFactor: CGFloat = 0.8) {
        self.minimumScaleFactor = minimumScaleFactor
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        } else {
            content
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)
                .allowsTightening(true)
        }
    }
}

struct WGJPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textInverse)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                WGJGlassButtonBackground(tone: .primary, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WGJCompactPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textInverse)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                WGJGlassButtonBackground(tone: .primary, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WGJCompactGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                WGJGlassButtonBackground(tone: .secondary, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct WGJGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                WGJGlassButtonBackground(tone: .secondary, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct WGJSelectableButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? WGJTheme.textInverse : WGJTheme.textPrimary)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                WGJGlassButtonBackground(
                    tone: isSelected ? .primary : .secondary,
                    isPressed: configuration.isPressed
                )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WGJDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .modifier(WGJAdaptiveControlLabelModifier())
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                WGJGlassButtonBackground(tone: .destructive, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WGJIconButtonStyle: ButtonStyle {
    var tint: Color = WGJTheme.textPrimary
    var background: Color = WGJTheme.card
    var outline: Color = WGJTheme.outline

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(background.opacity(configuration.isPressed ? 0.78 : 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(outline.opacity(0.70), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct WGJChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? WGJTheme.textInverse : WGJTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(WGJTheme.accentBlue) : AnyShapeStyle(WGJTheme.fieldStrong))
                .overlay {
                    Capsule()
                        .fill(isSelected ? WGJTheme.accentCyan.opacity(0.20) : WGJTheme.card.opacity(0.10))
                }
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.16) : WGJTheme.outline.opacity(0.42), lineWidth: 1)
                }
            }
    }
}

struct WGJSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(WGJTheme.headingFont(.headline, weight: .semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
    }
}

struct WGJCompactSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(WGJTheme.headingFont(.subheadline))
                .foregroundStyle(WGJTheme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

struct WGJActionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(_ title: String, subtitle: String? = nil) where Trailing == EmptyView {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            WGJSectionHeader(title, subtitle: subtitle)
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct WGJRootHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let titleAccessibilityIdentifier: String?
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        titleAccessibilityIdentifier: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.trailing = trailing()
    }

    init(_ title: String, subtitle: String? = nil) where Trailing == EmptyView {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }

    init(
        _ title: String,
        subtitle: String? = nil,
        titleAccessibilityIdentifier: String?
    ) where Trailing == EmptyView {
        self.init(
            title,
            subtitle: subtitle,
            titleAccessibilityIdentifier: titleAccessibilityIdentifier
        ) {
            EmptyView()
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                rootTitle

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)
            trailing
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var rootTitle: some View {
        let titleText = Text(title)
            .font(WGJTheme.headingFont(.largeTitle))
            .foregroundStyle(WGJTheme.textPrimary)
            .wgjSingleLineText(scale: 0.82)

        if let titleAccessibilityIdentifier {
            titleText.accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            titleText
        }
    }
}

struct WGJMetricPill: View {
    let systemImage: String
    let value: String
    var tint: Color = WGJTheme.textSecondary
    var allowsTextWrapping = false

    var body: some View {
        Label {
            Text(value)
                .lineLimit(allowsTextWrapping ? 2 : 1)
                .minimumScaleFactor(allowsTextWrapping ? 0.82 : 1)
                .fixedSize(horizontal: false, vertical: allowsTextWrapping)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(WGJTheme.cardStrong.opacity(0.94))
                .overlay {
                    Capsule()
                        .stroke(WGJTheme.outline.opacity(0.38), lineWidth: 1)
                }
        }
    }
}

struct WGJEmptyStateCard<Actions: View>: View {
    let title: String
    let message: String
    let icon: String?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        message: String,
        icon: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(WGJTheme.cardElevated.opacity(0.9))
                    }
            }

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)

            actions
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }
}

struct WGJNavigationTile<Destination: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let accessibilityID: String?
    @ViewBuilder let destination: Destination

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        accessibilityID: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.accessibilityID = accessibilityID
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.82)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .wgjCardContainer()
        }
        .buttonStyle(.plain)
        .modifier(WGJOptionalAccessibilityIdentifier(id: accessibilityID))
    }
}

private struct WGJOptionalAccessibilityIdentifier: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id, !id.isEmpty {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

struct WGJTransientBanner: View {
    enum Style {
        case floating
        case topDocked
    }

    let title: String
    let message: String?
    var icon: String = "checkmark.circle.fill"
    var tint: Color = WGJTheme.success
    var style: Style = .floating
    var topInset: CGFloat = 0
    var showsActivity = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(tint.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .wgjSingleLineText(scale: 0.82)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .wgjSingleLineText(scale: 0.8)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, style == .topDocked ? 20 : 14)
        .padding(.top, style == .topDocked ? topInset + 12 : 14)
        .padding(.bottom, style == .topDocked ? 16 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsActivity {
                WGJActivityRunner(tint: tint)
                    .padding(.horizontal, style == .topDocked ? 20 : 14)
                    .padding(.bottom, 4)
            }
        }
        .background {
            bannerShape
                .fill(WGJTheme.cardStrong.opacity(style == .topDocked ? 0.94 : 0.96))
                .overlay {
                    bannerShape.fill(bannerTintOverlay)
                }
                .overlay {
                    bannerStroke
                }
                .shadow(
                    color: style == .topDocked ? tint.opacity(0.10) : .clear,
                    radius: style == .topDocked ? 24 : 0,
                    x: 0,
                    y: style == .topDocked ? 14 : 0
                )
        }
    }

    @ViewBuilder
    private var bannerStroke: some View {
        switch style {
        case .floating:
            bannerShape
                .stroke(tint.opacity(0.26), lineWidth: 1)
        case .topDocked:
            EmptyView()
        }
    }

    private var bannerTintOverlay: Color {
        switch style {
        case .floating:
            return tint.opacity(0.10)
        case .topDocked:
            return tint.opacity(0.06)
        }
    }

    private var bannerShape: UnevenRoundedRectangle {
        switch style {
        case .floating:
            return UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18,
                    bottomLeading: 18,
                    bottomTrailing: 18,
                    topTrailing: 18
                ),
                style: .continuous
            )
        case .topDocked:
            return UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 28,
                    bottomTrailing: 28,
                    topTrailing: 0
                ),
                style: .continuous
            )
        }
    }
}

extension View {
    func wgjGlassContainer(spacing: CGFloat? = nil) -> some View {
        modifier(WGJGlassContainerModifier(spacing: spacing))
    }

    func wgjScreenBackground() -> some View {
        background {
            WGJTheme.bgBase.ignoresSafeArea()
        }
    }

    func wgjTintedScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .wgjScreenBackground()
    }

    @ViewBuilder
    func wgjNavigationChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            toolbarBackground(WGJTheme.bgBase, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    func wgjTabChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            toolbarBackground(WGJTheme.bgBase, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }

    func wgjCardContainer(strong: Bool = false, cornerRadius: CGFloat = WGJRadius.card) -> some View {
        modifier(WGJCardModifier(strong: strong, cornerRadius: cornerRadius))
    }

    func wgjPillField(
        verticalPadding: CGFloat = 11,
        horizontalPadding: CGFloat = 12
    ) -> some View {
        padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.42), lineWidth: 1)
                    }
            }
    }

    func wgjSheetSurface() -> some View {
        wgjScreenBackground()
            .wgjNavigationChrome()
            .presentationDragIndicator(.visible)
    }

    func wgjSingleLineText(scale: CGFloat = 0.82) -> some View {
        modifier(WGJAdaptiveControlLabelModifier(minimumScaleFactor: scale))
            .truncationMode(.tail)
    }

    @ViewBuilder
    func wgjRoundedGlass(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let _ = cornerRadius
        let _ = tint
        let _ = interactive
        self
    }

    @ViewBuilder
    func wgjCapsuleGlass(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let _ = tint
        let _ = interactive
        self
    }

    @ViewBuilder
    func wgjCircleGlass(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let _ = tint
        let _ = interactive
        self
    }
}
