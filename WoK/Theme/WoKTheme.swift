import SwiftUI
import UIKit

enum WoKTheme {
    static let bgBase = Color(UIColor.dynamic(light: 0xF1F5FF, dark: 0x0C1120))
    static let bgElevated = Color(UIColor.dynamic(light: 0xE5ECFF, dark: 0x141B30))

    static let card = Color(UIColor.dynamic(light: 0xFFFFFF, dark: 0x1E273B))
    static let cardStrong = Color(UIColor.dynamic(light: 0xEEF3FF, dark: 0x25324A))
    static let field = Color(UIColor.dynamic(light: 0xE8EEFF, dark: 0x121A2B))

    static let textPrimary = Color(UIColor.dynamic(light: 0x101729, dark: 0xF3F6FF))
    static let textSecondary = Color(UIColor.dynamic(light: 0x4C5772, dark: 0x9EABCA))

    static let accentPurple = Color(UIColor.dynamic(light: 0x764CFF, dark: 0x9B80FF))
    static let accentBlue = Color(UIColor.dynamic(light: 0x2398FF, dark: 0x4BACFF))
    static let accentCyan = Color(UIColor.dynamic(light: 0x6ADCFD, dark: 0x7EE8FF))
    static let accentGold = Color(UIColor.dynamic(light: 0xB0841E, dark: 0xD9B858))
    static let danger = Color(UIColor.dynamic(light: 0xD94747, dark: 0xFF6B6B))

    static let accent = accentBlue

    static let appHeroGradient = LinearGradient(
        colors: [accentCyan, accentBlue, accentPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headerOverlayGradient = LinearGradient(
        colors: [
            accentBlue.opacity(0.36),
            accentPurple.opacity(0.32),
            accentCyan.opacity(0.20),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let screenBackgroundGradient = LinearGradient(
        colors: [
            bgBase,
            bgElevated,
            accentPurple.opacity(0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rowDivider = accentBlue.opacity(0.55)
}

private struct WoKCardModifier: ViewModifier {
    let strong: Bool
    let cornerRadius: CGFloat

    private var material: AnyShapeStyle {
        AnyShapeStyle(strong ? .regularMaterial : .ultraThinMaterial)
    }

    private var tint: Color {
        strong ? WoKTheme.cardStrong.opacity(0.68) : WoKTheme.card.opacity(0.54)
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(WoKTheme.accentBlue.opacity(strong ? 0.30 : 0.20), lineWidth: 1)
                    )
            )
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

struct WoKPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [WoKTheme.accentBlue, WoKTheme.accentPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(configuration.isPressed ? 0.86 : 1)
            )
    }
}

struct WoKGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WoKTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WoKTheme.field.opacity(configuration.isPressed ? 0.82 : 0.66))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(WoKTheme.accentBlue.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

struct WoKChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : WoKTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [WoKTheme.accentBlue, WoKTheme.accentPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [WoKTheme.field.opacity(0.72), WoKTheme.field.opacity(0.58)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(WoKTheme.accentBlue.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                    )
            )
    }
}

struct WoKSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WoKTheme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)
            }
        }
    }
}

struct WoKRootHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    init(_ title: String) where Trailing == EmptyView {
        self.init(title) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WoKTheme.textPrimary)
            Spacer(minLength: 10)
            trailing
        }
    }
}

extension View {
    func wokScreenBackground() -> some View {
        background(WoKTheme.screenBackgroundGradient.ignoresSafeArea())
    }

    func wokTintedScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(WoKTheme.screenBackgroundGradient.ignoresSafeArea())
    }

    func wokNavigationChrome() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    func wokTabChrome() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }

    func wokCardContainer(strong: Bool = false, cornerRadius: CGFloat = 16) -> some View {
        modifier(WoKCardModifier(strong: strong, cornerRadius: cornerRadius))
    }

    func wokPillField() -> some View {
        padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WoKTheme.field.opacity(0.62))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WoKTheme.accentBlue.opacity(0.20), lineWidth: 1)
                    )
            )
    }
}
