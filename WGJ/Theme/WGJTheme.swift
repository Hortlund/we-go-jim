import SwiftUI
import UIKit

enum WGJTheme {
    static let bgBase = Color(UIColor.dynamic(light: 0xF4F7FA, dark: 0x0A1016))
    static let bgElevated = Color(UIColor.dynamic(light: 0xE6EDF4, dark: 0x111922))
    static let bgFloating = Color(UIColor.dynamic(light: 0xDDE7F0, dark: 0x18232E))

    static let card = Color(UIColor.dynamic(light: 0xFFFFFF, dark: 0x16202A))
    static let cardStrong = Color(UIColor.dynamic(light: 0xF8FBFD, dark: 0x1B2733))
    static let cardElevated = Color(UIColor.dynamic(light: 0xEEF4F9, dark: 0x22303D))
    static let field = Color(UIColor.dynamic(light: 0xEEF3F8, dark: 0x111A23))
    static let fieldStrong = Color(UIColor.dynamic(light: 0xE6EDF4, dark: 0x18232E))
    static let destructiveField = Color(UIColor.dynamic(light: 0xFBEDEE, dark: 0x2C181B))

    static let textPrimary = Color(UIColor.dynamic(light: 0x0D1520, dark: 0xF5F7FA))
    static let textSecondary = Color(UIColor.dynamic(light: 0x566476, dark: 0xA4AFBC))
    static let textTertiary = Color(UIColor.dynamic(light: 0x7F8A98, dark: 0x7B8795))
    static let textInverse = Color(UIColor.dynamic(light: 0xFFFFFF, dark: 0x0B1016))

    static let accentBlue = Color(UIColor.dynamic(light: 0x1E86FF, dark: 0x6DB5FF))
    static let accentCyan = Color(UIColor.dynamic(light: 0x2CB8D9, dark: 0x7CE3EF))
    static let accentPurple = Color(UIColor.dynamic(light: 0xA4B5FF, dark: 0x9FB0FF))
    static let accentGold = Color(UIColor.dynamic(light: 0xB48A2D, dark: 0xE0C56B))
    static let success = Color(UIColor.dynamic(light: 0x1A9D6F, dark: 0x62D8A6))
    static let warning = Color(UIColor.dynamic(light: 0xC58A2E, dark: 0xE6BE73))
    static let danger = Color(UIColor.dynamic(light: 0xD65A5A, dark: 0xFF8484))

    static let outline = Color.white.opacity(0.18)
    static let outlineStrong = Color.white.opacity(0.24)
    static let shadowSoft = Color.black.opacity(0.10)
    static let shadowStrong = Color.black.opacity(0.18)
    static let rowDivider = accentBlue.opacity(0.20)

    static let accent = accentBlue

    static let appHeroGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.34),
            accentBlue.opacity(0.12),
            accentPurple.opacity(0.07),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headerOverlayGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.24),
            accentBlue.opacity(0.10),
            accentCyan.opacity(0.08),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let screenBackgroundGradient = LinearGradient(
        colors: [
            bgBase,
            bgElevated,
            accentBlue.opacity(0.04),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.42, extraBounce: 0.04)
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
        strong ? WGJTheme.cardStrong.opacity(0.98) : WGJTheme.card.opacity(0.94)
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

    private var glassTint: Color {
        switch tone {
        case .primary:
            return WGJTheme.accentBlue.opacity(0.18)
        case .secondary:
            return WGJTheme.card.opacity(0.14)
        case .destructive:
            return WGJTheme.danger.opacity(0.16)
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

private extension UIColor {
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct WGJPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textInverse)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .frame(minHeight: 40)
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .frame(minHeight: 40)
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                WGJGlassButtonBackground(tone: .secondary, isPressed: configuration.isPressed)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct WGJDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
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
                .font(.headline.weight(.semibold))
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
                .font(.subheadline.weight(.bold))
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
            .font(.largeTitle.weight(.bold))
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

    func wgjPillField() -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
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
            .wgjMinimalKeyboardToolbar()
            .presentationDragIndicator(.visible)
    }

    func wgjSingleLineText(scale: CGFloat = 0.82) -> some View {
        lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(scale)
            .allowsTightening(true)
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
