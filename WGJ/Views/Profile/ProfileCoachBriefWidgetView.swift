import SwiftUI

nonisolated struct ProfileCoachPresentation: Equatable, Sendable {
    let snapshot: WeeklyCoachInsightSnapshot
    let recap: CoachNarrativeSummary

    var baselineSubtitle: String {
        if snapshot.baselineWeekCount > 0 {
            return "This week against your last \(snapshot.baselineWeekCount) weeks"
        }
        return "This week against your recent baseline"
    }

    var risingSignalTitle: String? {
        snapshot.topRisingSignals.first.map { "Trending Up: \($0.exerciseName)" }
    }

    var watchSignalTitle: String? {
        snapshot.topWatchSignals.first.map { "Watchlist: \($0.exerciseName)" }
    }

    var recapTone: TrainingGuidanceTone {
        switch recap.availabilityMode {
        case .generated:
            return .accent
        case .fallback:
            return .caution
        }
    }
}

struct ProfileCoachBriefWidgetView: View {
    let presentation: ProfileCoachPresentation
    let openAnalysis: () -> Void

    var body: some View {
        Button(action: openAnalysis) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    WGJSectionHeader("Coach Brief", subtitle: presentation.baselineSubtitle)

                    Spacer(minLength: 0)

                    availabilityBadge
                }

                TrainingGuidanceBannerView(
                    title: presentation.recap.headline,
                    message: presentation.recap.body,
                    tone: presentation.recapTone,
                    compact: true
                )

                if let risingSignalTitle = presentation.risingSignalTitle {
                    ProfileCoachSignalChip(
                        title: risingSignalTitle,
                        tint: WGJTheme.success
                    )
                }

                if let watchSignalTitle = presentation.watchSignalTitle {
                    ProfileCoachSignalChip(
                        title: watchSignalTitle,
                        tint: WGJTheme.accentGold
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wgjCardContainer()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-coach-brief-widget-button")
    }

    private var availabilityBadge: some View {
        Text(presentation.recap.availabilityMode == .generated ? "AI" : "Local")
            .font(.caption2.weight(.bold))
            .foregroundStyle(presentation.recap.availabilityMode == .generated ? WGJTheme.accentCyan : WGJTheme.accentGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        presentation.recap.availabilityMode == .generated
                            ? WGJTheme.accentCyan.opacity(0.12)
                            : WGJTheme.accentGold.opacity(0.12)
                    )
            )
    }
}

private struct ProfileCoachSignalChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(tint.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}
