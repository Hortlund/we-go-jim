import SwiftUI

struct ProfileCoachAnalysisSheet: View {
    let presentation: ProfileCoachPresentation
    let followUpSummaries: [CoachFollowUpKind: CoachNarrativeSummary]
    let loadingKinds: Set<CoachFollowUpKind>
    let runFollowUp: (CoachFollowUpKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                recapBanner
                contextGrid
                signalSection(
                    title: "Rising Lifts",
                    subtitle: "The strongest upward signals this week.",
                    signals: presentation.snapshot.topRisingSignals,
                    emptyMessage: "Nothing is clearly accelerating yet. Keep stacking consistent sessions.",
                    tint: WGJTheme.success
                )
                signalSection(
                    title: "Watchlist",
                    subtitle: "Lifts worth keeping an eye on next week.",
                    signals: presentation.snapshot.topWatchSignals,
                    emptyMessage: "No flat or fading lift stands out right now.",
                    tint: WGJTheme.accentGold
                )
                followUpsSection
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .accessibilityIdentifier("profile-coach-analysis-sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coach Brief")
                .font(.title2.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(presentation.baselineSubtitle)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private var recapBanner: some View {
        TrainingGuidanceBannerView(
            title: presentation.recap.headline,
            message: presentation.recap.body,
            tone: presentation.recapTone
        )
    }

    private var contextGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ProfileCoachContextTile(
                title: "Workouts",
                value: "\(presentation.snapshot.completedWorkoutCount)",
                detail: "logged this week",
                tint: WGJTheme.accentBlue
            )
            ProfileCoachContextTile(
                title: "Volume",
                value: formattedDelta(presentation.snapshot.totalVolumeDelta),
                detail: "vs baseline",
                tint: deltaTint(for: presentation.snapshot.totalVolumeDelta)
            )
            ProfileCoachContextTile(
                title: "Consistency",
                value: signedCount(presentation.snapshot.consistencyDelta),
                detail: "sessions vs baseline",
                tint: deltaTint(for: Double(presentation.snapshot.consistencyDelta))
            )
            ProfileCoachContextTile(
                title: "Baseline",
                value: "\(presentation.snapshot.baselineWeekCount)",
                detail: "weeks compared",
                tint: WGJTheme.accentCyan
            )
        }
    }

    private func signalSection(
        title: String,
        subtitle: String,
        signals: [WeeklyCoachSignal],
        emptyMessage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader(title, subtitle: subtitle)

            if signals.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                ForEach(signals) { signal in
                    ProfileCoachSignalRow(signal: signal, tint: tint)
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var followUpsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Ask Coach", subtitle: "Short follow-ups grounded in your saved sessions.")

            ForEach(presentation.snapshot.followUpKinds, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        runFollowUp(kind)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(followUpTint(for: kind))

                            Text(kind.buttonTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                                .fill(followUpTint(for: kind).opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                                        .stroke(followUpTint(for: kind).opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile-coach-follow-up-\(kind.rawValue)")

                    if loadingKinds.contains(kind) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Analyzing your recent sessions…")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    } else if let summary = followUpSummaries[kind] {
                        TrainingGuidanceBannerView(
                            title: summary.headline,
                            message: summary.body,
                            tone: followUpTone(for: kind, availabilityMode: summary.availabilityMode),
                            compact: true
                        )
                    }
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func formattedDelta(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(WGJFormatters.oneDecimalString(value))%"
    }

    private func signedCount(_ value: Int) -> String {
        if value > 0 {
            return "+\(value)"
        }
        return "\(value)"
    }

    private func deltaTint(for value: Double) -> Color {
        if value > 0 {
            return WGJTheme.success
        }
        if value < 0 {
            return WGJTheme.accentGold
        }
        return WGJTheme.accentCyan
    }

    private func followUpTint(for kind: CoachFollowUpKind) -> Color {
        switch kind {
        case .whatImproved:
            return WGJTheme.success
        case .whyFlat:
            return WGJTheme.accentGold
        case .whatChanged:
            return WGJTheme.accentCyan
        }
    }

    private func followUpTone(
        for kind: CoachFollowUpKind,
        availabilityMode: CoachNarrativeAvailabilityMode
    ) -> TrainingGuidanceTone {
        if availabilityMode == .fallback {
            return .caution
        }

        switch kind {
        case .whatImproved:
            return .success
        case .whyFlat:
            return .caution
        case .whatChanged:
            return .accent
        }
    }
}

private struct ProfileCoachContextTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)

            Text(detail)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(cornerRadius: WGJRadius.control)
    }
}

private struct ProfileCoachSignalRow: View {
    let signal: WeeklyCoachSignal
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(signal.exerciseName)
                    .font(.headline)
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer(minLength: 0)

                Text(deltaTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            Text(signal.summary)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var deltaTitle: String {
        let prefix = signal.deltaPercentage > 0 ? "+" : ""
        return "\(prefix)\(WGJFormatters.oneDecimalString(signal.deltaPercentage))%"
    }
}

private extension CoachFollowUpKind {
    var buttonTitle: String {
        switch self {
        case .whatImproved:
            return "What improved this week?"
        case .whyFlat:
            return "Why is a lift flat?"
        case .whatChanged:
            return "What changed from last week?"
        }
    }

    var systemImage: String {
        switch self {
        case .whatImproved:
            return "arrow.up.circle.fill"
        case .whyFlat:
            return "gauge.with.dots.needle.33percent"
        case .whatChanged:
            return "arrow.left.arrow.right.circle.fill"
        }
    }
}
