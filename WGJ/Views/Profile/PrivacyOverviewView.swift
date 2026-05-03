import SwiftUI

struct PrivacyOverviewView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Privacy", subtitle: "Review what WGJ stores, syncs, and lets you delete.")

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
                        title: "Privacy policy needed",
                        message: "A public privacy policy URL is required in App Store Connect and should remain reachable from inside the app.",
                        icon: "doc.text.magnifyingglass"
                    )
                }

                privacyCard(
                    title: "Data WGJ uses",
                    lines: [
                        "Profile details such as display name, avatar, weekly goal, preferences, and dashboard widget choices.",
                        "Workout history, active-workout drafts, templates, folders, custom exercises, notes, timers, and training summaries.",
                        "Bros circle membership, invite status, workout feed posts, PR posts, reactions, reports, and block-list data.",
                    ]
                )

                privacyCard(
                    title: "Where it lives",
                    lines: [
                        "Core workout, template, exercise, and profile features work locally on your device.",
                        "When iCloud is available, supported profile, workout, template, and Bros data may sync through Apple's iCloud and CloudKit services.",
                        "The bundled exercise catalog, cached exercise images, blocked bros, and pending social outbox items stay on-device unless a sync action is needed.",
                    ]
                )

                privacyCard(
                    title: "Your controls",
                    lines: [
                        "You can use WGJ locally when iCloud or Bros is unavailable.",
                        "You can report members or feed posts, block members locally, and contact support about privacy or moderation concerns.",
                        "You can delete local app data and request deletion of your own synced Bros data from Settings at any time.",
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
