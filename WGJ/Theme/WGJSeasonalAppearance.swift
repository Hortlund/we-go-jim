import SwiftUI
import UIKit

/// Refresh without rebuilding the app root or disturbing an active workout.
struct WGJSeasonalAppearanceModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var clockRevision = 0

    func body(content: Content) -> some View {
        content
            .task(id: "\(scenePhase)-\(clockRevision)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    WGJThemePreferences.shared.refreshSeason()
                    let now = Date.now
                    let nextDay = ChristmasThemeSeason.localCalendar.dateInterval(of: .day, for: now)?.end
                        ?? now.addingTimeInterval(3600)
                    do {
                        try await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSince(now))))
                    } catch { return }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                WGJThemePreferences.shared.refreshSeason()
                clockRevision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                WGJThemePreferences.shared.refreshSeason()
                clockRevision += 1
            }
    }
}

/// Static winter texture avoids constant animation while logging or scrolling.
struct WGJChristmasBackground: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<38 {
                let x = CGFloat((index * 73 + 19) % 397) / 397 * size.width
                let y = CGFloat((index * 113 + 37) % 811) / 811 * size.height
                let radius: CGFloat = index.isMultiple(of: 3) ? 2 : 1
                let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(WGJTheme.textPrimary.opacity(0.22)))
            }
            for index in 0..<7 {
                var symbol = context.resolve(Image(systemName: "snowflake"))
                symbol.shading = .color(WGJTheme.textPrimary.opacity(0.16))
                context.draw(symbol, in: CGRect(
                    x: CGFloat((index * 137 + 45) % 397) / 397 * size.width,
                    y: CGFloat((index * 193 + 73) % 811) / 811 * size.height,
                    width: 15, height: 15
                ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WGJChristmasGarland: View {
    var body: some View {
        Canvas { context, size in
            let centerY: CGFloat = 9
            var wire = Path()
            wire.move(to: CGPoint(x: 0, y: 2))
            wire.addQuadCurve(to: CGPoint(x: size.width, y: 2), control: CGPoint(x: size.width / 2, y: 24))
            context.stroke(wire, with: .color(WGJChristmasStyle.pineLight), lineWidth: 2)
            for index in 0..<Int(size.width / 9) {
                let x = CGFloat(index) * 9
                var needles = Path()
                needles.move(to: CGPoint(x: x - 5, y: centerY - 8))
                needles.addLine(to: CGPoint(x: x + 6, y: centerY + 2))
                needles.addLine(to: CGPoint(x: x - 4, y: centerY + 9))
                context.stroke(needles, with: .color(WGJChristmasStyle.pineLight.opacity(0.8)), lineWidth: 2)
            }
            for index in 0..<7 {
                let x = (CGFloat(index) + 0.5) * size.width / 7
                let drop: CGFloat = index.isMultiple(of: 2) ? 10 : 18
                let color = index.isMultiple(of: 2) ? WGJChristmasStyle.gold : WGJChristmasStyle.cranberry
                context.stroke(Path(CGRect(x: x, y: centerY, width: 0.5, height: drop)), with: .color(WGJChristmasStyle.gold.opacity(0.6)), lineWidth: 0.5)
                context.fill(Path(ellipseIn: CGRect(x: x - 6, y: centerY + drop - 3, width: 12, height: 12)), with: .color(color))
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: centerY + drop - 1, width: 3, height: 3)), with: .color(.white.opacity(0.7)))
            }
        }
        .frame(height: 39)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WGJChristmasWelcome: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                greeting
                WGJChristmasTreeArtwork().frame(width: 120, height: 154)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 4) {
                    greeting.frame(maxWidth: .infinity, alignment: .leading)
                    WGJChristmasTreeArtwork().frame(width: 115, height: 148)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WGJChristmasStyle.ribbonGradient)
        .overlay(alignment: .bottom) { WGJChristmasCandyStripe().frame(height: 6) }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(WGJChristmasStyle.gold.opacity(0.65), lineWidth: 1))
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Merry Liftmas!")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(WGJChristmasStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
            Text("It’s the bulkiest season!")
                .font(.subheadline)
                .foregroundStyle(WGJChristmasStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
