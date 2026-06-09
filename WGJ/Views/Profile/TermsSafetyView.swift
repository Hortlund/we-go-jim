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
                        "WGJ helps you log workouts, organize templates, review history, and track profile progress.",
                        "Training guidance, previous-performance hints, goals, charts, and summaries are informational only.",
                        "WGJ does not diagnose, treat, prevent, or cure any medical condition and does not replace professional coaching or medical advice.",
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
                        "You can delete your local app data from Settings.",
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
