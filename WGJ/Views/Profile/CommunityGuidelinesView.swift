import SwiftUI

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Community Guidelines", subtitle: "Bros is for private training updates, not abuse, spam, or unsafe content.")

                guidelineCard(
                    title: "Keep it training-focused",
                    lines: [
                        "Use Bros for workout sessions, PRs, reactions, and gym-related progress.",
                        "Do not use names, workout titles, custom exercise names, avatars, or posts for harassment, slurs, threats, sexual content, hate, spam, or private information.",
                    ]
                )

                guidelineCard(
                    title: "Respect the circle",
                    lines: [
                        "Do not impersonate other people or post misleading achievements.",
                        "Do not pressure, threaten, bully, shame, stalk, or encourage members to train through unsafe pain or injury.",
                        "You are responsible for the content you create and share in Bros.",
                    ]
                )

                guidelineCard(
                    title: "Use moderation tools",
                    lines: [
                        "Report members or posts that break these rules or create a safety concern.",
                        "Block bros you do not want to see in your circle feed or roster.",
                        "Circle owners can remove members when needed.",
                    ]
                )

                guidelineCard(
                    title: "What happens next",
                    lines: [
                        "Reported content can be reviewed by support.",
                        "Abuse, unsafe content, or repeated rule violations can lead to removal from a circle, support follow-up, or future moderation action.",
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
