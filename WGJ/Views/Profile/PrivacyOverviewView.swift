import SwiftUI

struct PrivacyOverviewView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Privacy", subtitle: "Review what WGJ stores, backs up, and lets you delete.")

                if let privacyPolicyURL = AppRuntimeConfig.privacyPolicyURL {
                    VStack(alignment: .leading, spacing: 12) {
                        WGJSectionHeader("Privacy Policy", subtitle: privacyPolicyURL.absoluteString)

                        Button {
                            openURL(privacyPolicyURL)
                        } label: {
                            Label("Open Privacy Policy", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                    }
                    .padding(14)
                    .wgjCardContainer(strong: true)
                } else {
                    WGJEmptyStateCard(
                        title: "Privacy policy unavailable",
                        message: "The privacy policy link is not available right now. Contact support with privacy questions.",
                        icon: "doc.text.magnifyingglass"
                    )
                }

                privacyCard(
                    title: "Data WGJ uses",
                    lines: [
                        "Profile details such as display name, avatar, weekly goal, preferences, and dashboard widget choices.",
                        "Workout history, active-workout drafts, templates, folders, custom exercises, notes, timers, and training summaries.",
                        "Local projections used for profile stats, widgets, history, and workout summaries.",
                    ]
                )

                privacyCard(
                    title: "Where it lives",
                    lines: [
                        "Core workout, template, exercise, history, and profile features work locally on your device.",
                        "When iCloud is available, WGJ may export a best-effort CloudKit backup after workout completion or template saves.",
                        "Active-workout drafts stay local while the workout is active.",
                    ]
                )

                privacyCard(
                    title: "Your controls",
                    lines: [
                        "You can use WGJ locally when iCloud or CloudKit is unavailable.",
                        "You can delete local app data from Settings.",
                        "Cloud backup failures do not block local saves.",
                    ]
                )
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.24))
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
        PrivacyOverviewView()
    }
}
