import SwiftUI

struct PrivacyOverviewView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Privacy", subtitle: "Review what the app stores and where to publish your hosted policy.")

                if let privacyPolicyURL = AppRuntimeConfig.privacyPolicyURL {
                    VStack(alignment: .leading, spacing: 12) {
                        WGJSectionHeader("Hosted Policy", subtitle: privacyPolicyURL.absoluteString)

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
                        title: "Hosted policy still needed",
                        message: "The app is ready to link a hosted privacy policy, but you still need to publish a real URL in App Store Connect before submission.",
                        icon: "doc.text.magnifyingglass"
                    )
                }

                privacyCard(
                    title: "Data used in the app",
                    lines: [
                        "Profile data like display name, avatar, and weekly goal.",
                        "Workout history, templates, custom exercises, and widget choices.",
                        "Bros circle membership, workout feed posts, PR posts, reactions, reports, and block-list data.",
                    ]
                )

                privacyCard(
                    title: "Where it lives",
                    lines: [
                        "Workouts, templates, and profile data sync with iCloud when available.",
                        "The exercise catalog stays local to the device, with image files cached on-device.",
                        "Blocked bros and social outbox items stay local so moderation and retries work offline.",
                    ]
                )

                privacyCard(
                    title: "Your controls",
                    lines: [
                        "You can use the app locally without Bros if iCloud is unavailable.",
                        "You can report members or feed posts from Bros.",
                        "You can delete all app data from Settings at any time.",
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
