import SwiftUI

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Community Guidelines", subtitle: "Bros is for private lifting updates, not spam, abuse, or unsafe behavior.")

                guidelineCard(
                    title: "Keep it training-focused",
                    lines: [
                        "Use Bros for workouts, PRs, and gym-related updates.",
                        "Do not use names, workout titles, or custom exercise names for harassment, slurs, or explicit content.",
                    ]
                )

                guidelineCard(
                    title: "Respect the circle",
                    lines: [
                        "Do not impersonate other people or post misleading achievements.",
                        "Do not pressure, threaten, or bully members in your circle.",
                    ]
                )

                guidelineCard(
                    title: "Use moderation tools",
                    lines: [
                        "Report members or posts that break these rules.",
                        "Block bros you do not want to see in your circle feed.",
                        "Circle owners can remove members when needed.",
                    ]
                )

                guidelineCard(
                    title: "What happens next",
                    lines: [
                        "Reported content can be reviewed through the support channel configured for the app.",
                        "Repeated abuse can lead to removal from a circle or future moderation action.",
                    ]
                )
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Guidelines")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guidelineCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(WGJTheme.accentGold.opacity(0.28))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textPrimary)
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }
}

#Preview {
    NavigationStack {
        CommunityGuidelinesView()
    }
}
