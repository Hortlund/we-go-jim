import Foundation
import SwiftData
import SwiftUI

struct ActiveWorkoutStripView: View {
    @Environment(ActiveWorkoutCoordinator.self) private var activeWorkoutCoordinator
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sessionID: UUID
    let onExpand: () -> Void

    init(sessionID: UUID, onExpand: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onExpand = onExpand
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let status = statusPresentation(now: timeline.date)

            Button(action: onExpand) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilityLabelContent(status: status)
                    } else {
                        standardLabelContent(status: status)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .wgjCardContainer(strong: true, cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("active-workout-strip")
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.height < -18 {
                            onExpand()
                        }
                    }
            )
            .padding(.horizontal, 12)
        }
    }

    private var workoutTitle: some View {
        Text(session?.name ?? "Workout in progress")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
    }

    private func standardLabelContent(status: ActiveWorkoutStripStatusPresentation) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(WGJTheme.success)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                workoutTitle.wgjSingleLineText(scale: 0.84)

                Text(status.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status.statusTint)
                    .monospacedDigit()
                    .wgjSingleLineText(scale: 0.84)
            }

            Spacer()

            WGJMetricPill(systemImage: status.pillIcon, value: status.pillText, tint: status.pillTint)
        }
    }

    private func accessibilityLabelContent(status: ActiveWorkoutStripStatusPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            workoutTitle
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(status.compactStatusText)
                    .foregroundStyle(status.statusTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(status.statusText)

                Spacer(minLength: 0)

                Image(systemName: "chevron.up")
                    .foregroundStyle(WGJTheme.accentBlue)
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.medium))
        }
    }

    private var session: ActiveWorkoutRuntimeSession? {
        guard activeWorkoutCoordinator.storedSnapshot?.session.id == sessionID else {
            return nil
        }
        return activeWorkoutCoordinator.storedSnapshot?.session
    }

    private func elapsedText(now: Date) -> String {
        guard let startedAt = session?.startedAt else {
            return "00:00"
        }
        return WGJDurationFormatter.elapsedString(since: startedAt, now: now)
    }

    private func statusPresentation(now: Date) -> ActiveWorkoutStripStatusPresentation {
        if let remaining = restTimerState.restTimerRemaining(at: now) {
            let restText = formattedRest(remaining)
            let compactStatusText = "Rest \(restText)"
            let context = restTimerState.restTimerContextLabel()

            return ActiveWorkoutStripStatusPresentation(
                statusText: context.map { "\(compactStatusText) · \($0)" } ?? compactStatusText,
                compactStatusText: compactStatusText,
                statusTint: WGJTheme.success,
                pillText: restText,
                pillIcon: "timer",
                pillTint: WGJTheme.success
            )
        }

        let statusText = "Elapsed \(elapsedText(now: now))"
        return ActiveWorkoutStripStatusPresentation(
            statusText: statusText,
            compactStatusText: statusText,
            statusTint: WGJTheme.textSecondary,
            pillText: "Open",
            pillIcon: "chevron.up",
            pillTint: WGJTheme.accentBlue
        )
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct ActiveWorkoutStripStatusPresentation {
    let statusText: String
    let compactStatusText: String
    let statusTint: Color
    let pillText: String
    let pillIcon: String
    let pillTint: Color
}

#Preview {
    let session = ActiveWorkoutRuntimeSession(name: "Preview Workout")
    ActiveWorkoutStripView(sessionID: session.id, onExpand: {})
        .environment(ActiveWorkoutPresentationState())
        .environment(ActiveWorkoutCoordinator.preview(session: session))
        .environment(RestTimerState())
        .wgjPreviewModelContainer()
}
