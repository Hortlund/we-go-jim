import SwiftUI

struct AppThemePickerView: View {
    var preferences: WGJThemePreferences = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Find your lifting vibe", subtitle: "Same workout. A fresh coat of gains.")

                ForEach(WGJAppTheme.allCases) { theme in
                    Button {
                        preferences.select(theme)
                    } label: {
                        AppThemePreviewCard(theme: theme, isSelected: preferences.selected == theme)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(theme.title)
                    .accessibilityValue(preferences.selected == theme ? String(localized: "Selected") : "")
                    .accessibilityHint(theme.subtitle)
                    .accessibilityAddTraits(preferences.selected == theme ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("app-theme-\(theme.rawValue)")
                }

                Text("Applies instantly and is remembered on this device. WGJ Original is the default.")
                    .font(.footnote)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            .padding(WGJSpacing.page)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("App Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppThemePreviewCard: View {
    let theme: WGJAppTheme
    let isSelected: Bool

    private var palette: WGJPalette { theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: theme.symbol)
                    .font(.title2)
                    .foregroundStyle(palette.accentBlue)
                    .frame(width: 44, height: 44)
                    .background(palette.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(theme.title)
                        .font(theme.headingFont(.headline, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(theme.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? palette.accentBlue : palette.textSecondary)
            }

            // An actual surface/accent sample, independent of the active theme.
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GOOD FORM. GREAT GAINS.")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                    Text("One more rep.")
                        .font(theme.headingFont(.title3))
                        .foregroundStyle(palette.textPrimary)
                    HStack(spacing: 6) {
                        swatch(palette.accentBlue)
                        swatch(palette.accentCyan)
                        swatch(palette.accentPurple)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "dumbbell.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.textInverse)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(colors: [palette.accentBlue, theme.usesMatteSurfaces ? palette.accentBlue : palette.accentCyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
            }
            .padding(16)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(palette.bgBase, in: RoundedRectangle(cornerRadius: WGJRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: WGJRadius.card)
                .strokeBorder(isSelected ? palette.accentBlue : palette.textSecondary.opacity(0.25),
                              lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: WGJRadius.card))
    }

    private func swatch(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 26, height: 6)
    }
}

#Preview("Theme palettes") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(WGJAppTheme.allCases) { theme in
                AppThemePreviewCard(theme: theme, isSelected: theme == .original)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large type") {
    AppThemePreviewCard(theme: .sunsOutGunsOut, isSelected: true)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
