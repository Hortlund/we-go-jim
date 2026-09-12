import SwiftUI
import SwiftData

struct ActiveWorkoutActivityTimerDock: View {
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutRuntimeSession
    let onDismissRestTimer: () -> Void

    var body: some View {
        let isRestTimerActive = restTimerState.restTimerEndsAt != nil
        let dockAccent = isRestTimerActive ? WGJTheme.success : WGJTheme.accentCyan
        let fillOpacity = isRestTimerActive ? 0.16 : 0.12
        let strokeOpacity = isRestTimerActive ? 0.28 : 0.22

        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = restTimerState.restTimerRemaining(at: timeline.date)
            let isResting = remaining != nil
            let accent = isResting ? WGJTheme.success : WGJTheme.accentCyan
            let secondaryText = isResting
                ? restTimerState.restTimerContextLabel() ?? "Recover before the next set"
                : "Workout in progress"
            let primaryValue = isResting
                ? formattedRest(remaining ?? 0)
                : WGJDurationFormatter.elapsedString(since: session.startedAt, now: timeline.date)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isResting ? "Rest Timer" : "Elapsed Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)

                    Text(secondaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.84)
                }
                Spacer(minLength: 12)
                Text(primaryValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .wgjSingleLineText(scale: 0.84)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(isResting ? "active-workout-rest-timer" : "active-workout-elapsed-timer")
                    .accessibilityLabel(Text(primaryValue))
                    .accessibilityValue(Text(primaryValue))

                if isResting {
                    Button {
                        onDismissRestTimer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(
                        WGJIconButtonStyle(
                            tint: WGJTheme.textSecondary,
                            background: WGJTheme.cardStrong,
                            outline: WGJTheme.outline
                        )
                    )
                    .accessibilityLabel("Dismiss rest timer")
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel(accessibilityLabel(isResting: isResting, primaryValue: primaryValue, secondaryText: secondaryText))
            .allowsHitTesting(isResting)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    dockAccent.opacity(fillOpacity),
                                    WGJTheme.cardStrong.opacity(0.80),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(dockAccent.opacity(strokeOpacity), lineWidth: 1)
                }
                .shadow(color: WGJTheme.shadowStrong.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(isResting: Bool, primaryValue: String, secondaryText: String) -> String {
        isResting
            ? "Rest timer \(primaryValue). \(secondaryText)"
            : "Elapsed time \(primaryValue)"
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
