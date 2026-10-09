import SwiftUI

struct TermsSafetyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Terms & Safety", subtitle: "Use WGJ as a workout log, not as medical, legal, or professional advice.")

                if let termsURL = AppRuntimeConfig.termsURL {
                    VStack(alignment: .leading, spacing: 12) {
                        WGJSectionHeader("Terms Website", subtitle: termsURL.absoluteString)

                        Button {
                            openURL(termsURL)
                        } label: {
                            Label("Open Terms Website", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                    }
                    .padding(14)
                    .wgjCardContainer(strong: true)
                }

                termsCard(
                    title: "Your responsibility",
                    lines: [
                        "Train at your own risk and use your own judgment before starting, changing, or continuing any workout.",
                        "Stop exercising and seek qualified medical help if you feel pain, dizziness, shortness of breath, or anything that feels unsafe.",
                        "Talk to a doctor or qualified professional before training if you have an injury, condition, medication concern, or health question.",
                    ]
                )

                termsCard(
                    title: "What WGJ does",
                    lines: [
                        "WGJ helps you log workouts, organize templates, review history, and track profile progress.",
                        "Training guidance, previous-performance hints, achievement goals, personal records, yearly recaps, charts, and coach summaries are informational only.",
                        "WGJ does not diagnose, treat, prevent, or cure any medical condition and does not replace professional coaching or medical advice.",
                    ]
                )

                termsCard(
                    title: "Estimates and outdoor recording",
                    lines: [
                        "Calorie estimates are approximate calculations from the details you enter and your logged activity, not sensor measurements.",
                        "Outdoor walk, run, and bike routes, distance, and pace depend on GPS permission, signal quality, and device behavior. WGJ is not a navigation or emergency service.",
                        "Achievement goals are optional history-based milestones, not prescribed training targets. Use your own judgment about effort and recovery.",
                    ]
                )

                termsCard(
                    title: "Health, sharing, and backup",
                    lines: [
                        "Apple Health export is optional. Later edits or deletions in WGJ do not change workouts or calories already saved to Health; manage those records in the Health app.",
                        "Live Activities may show workout details on the Lock Screen. Shared workout, route, milestone, and personal-record images may reveal training details or places you visited.",
                        "Cloud backup stores snapshots rather than merging devices. Restoring or choosing Use This Device’s Data can replace saved data; review the confirmation before continuing.",
                    ]
                )

                termsCard(
                    title: "No guarantees",
                    lines: [
                        "Fitness results, strength progress, backup availability, notifications, support response times, and app uptime are not guaranteed.",
                        "You are responsible for checking logged weights, reps, timers, and templates before relying on them.",
                        "CloudKit backup depends on Apple iCloud, CloudKit, network status, account availability, and continued service availability.",
                    ]
                )

                termsCard(
                    title: "Support and removal",
                    lines: [
                        "WGJ is an independent hobby project, so support is best-effort and response times are not guaranteed.",
                        "Use Support for app issues, privacy questions, and data-deletion follow-up.",
                        "Delete My Data in Settings deletes the cloud backup before clearing local user data. Cloud deletion errors stop the operation, and local cleanup failures are reported. Shared copies and exported Health records remain outside this deletion.",
                    ]
                )
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Terms & Safety")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func termsCard(title: String, lines: [String]) -> some View {
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
        TermsSafetyView()
    }
}
