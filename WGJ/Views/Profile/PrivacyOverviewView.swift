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
                        "Optional calorie-estimation details: sex, date of birth, height, and body weight, plus the resulting workout calorie estimates.",
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
                    title: "Outdoor routes",
                    lines: [
                        "Location is used only while recording an outdoor walk or run, including with your screen locked. Pausing or finishing stops GPS recording.",
                        "Live routes are saved on this device. Completed routes are included in WGJ’s private iCloud backup and restored with your workouts. Route coordinates are not exported to Apple Health.",
                        "Apple Maps displays your route. Deleting a workout or deleting WGJ data also removes its locally recorded route.",
                    ]
                )

                privacyCard(
                    title: "Apple Health",
                    lines: [
                        "Apple Health export is optional. When enabled, WGJ saves newly completed workouts and, with a separate opt-in, available estimated active calories.",
                        "WGJ checks only its own previously exported workouts to recover interrupted saves. It does not request access to other apps' Apple Health data.",
                        "Pending exports and recovery records stay on this device and are excluded from WGJ's CloudKit backup and iCloud device backups.",
                        "Turn export off in Settings or revoke access in the Health app. Editing or deleting WGJ data does not change records already saved to Health; manage those records in the Health app.",
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
