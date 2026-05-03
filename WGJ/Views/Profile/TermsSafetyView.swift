import SwiftUI

struct TermsSafetyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Terms & Safety", subtitle: "Use WGJ as a workout log, not as medical, legal, or professional advice.")

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
                        "WGJ helps you log workouts, organize templates, review history, and share limited training updates with your private Bros circle.",
                        "Training guidance, previous-performance hints, goals, charts, and summaries are informational only.",
                        "WGJ does not diagnose, treat, prevent, or cure any medical condition and does not replace professional coaching or medical advice.",
                    ]
                )

                termsCard(
                    title: "No guarantees",
                    lines: [
                        "Fitness results, strength progress, sync availability, notifications, social features, support response times, and app uptime are not guaranteed.",
                        "You are responsible for checking logged weights, reps, timers, templates, and shared content before relying on them.",
                        "Cloud sync and Bros depend on Apple iCloud, CloudKit, network status, account availability, member behavior, and continued service availability.",
                        "Features may change, break, be limited, or be discontinued, especially where they depend on external services.",
                    ]
                )

                termsCard(
                    title: "Bros content",
                    lines: [
                        "You are responsible for the names, posts, reactions, and other content you create or share.",
                        "Do not post harassment, threats, sexual content, hate, spam, private information, or unsafe training instructions.",
                        "Reports, blocks, removals, and support review may be used to protect users and the service.",
                    ]
                )

                termsCard(
                    title: "Liability limit",
                    lines: [
                        "To the maximum extent allowed by law, WGJ is provided as-is and without warranties.",
                        "To the maximum extent allowed by law, the developer is not responsible for injuries, training decisions, lost data, missed notifications, sync delays, user content, indirect damages, or lost profits arising from app use.",
                        "Nothing here limits rights that cannot legally be limited in your country or region.",
                    ]
                )

                termsCard(
                    title: "Support and removal",
                    lines: [
                        "WGJ is an independent hobby project, so support is best-effort and response times are not guaranteed.",
                        "Use Support for app issues, privacy questions, purchase help, moderation reports, or review follow-up.",
                        "Privacy, purchase, safety, and moderation issues should still be sent through Support so they can be handled when required.",
                        "You can delete your local app data and request removal of your own synced Bros data from Settings.",
                        "Access to Bros or other social features may be limited when required for safety, abuse prevention, or service integrity.",
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
