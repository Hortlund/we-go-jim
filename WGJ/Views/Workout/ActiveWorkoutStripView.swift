import Foundation
import SwiftData
import SwiftUI

struct ActiveWorkoutStripView: View {
    @Environment(RestTimerState.self) private var restTimerState

    let sessionID: UUID
    let onExpand: () -> Void

    @State private var session: ActiveWorkoutRuntimeSession?

    init(sessionID: UUID, onExpand: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onExpand = onExpand
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = statusPresentation(now: context.date)

            Button(action: onExpand) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(WGJTheme.success)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session?.name ?? "Workout in progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .wgjSingleLineText(scale: 0.84)

                        Text(status.statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(status.statusTint)
                            .monospacedDigit()
                            .wgjSingleLineText(scale: 0.84)
                    }

                    Spacer()

                    WGJMetricPill(
                        systemImage: status.pillIcon,
                        value: status.pillText,
                        tint: status.pillTint
                    )
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
        .background {
            WorkoutRestTimerExpiryObserver()
        }
        .task(id: sessionID) {
            await loadSnapshot()
        }
    }

    @MainActor
    private func loadSnapshot() async {
        guard let snapshot = try? await ActiveWorkoutSnapshotStore.shared.load(),
              snapshot.id == sessionID else {
            session = nil
            return
        }
        session = snapshot
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
            let statusText: String
            if let context = restTimerState.restTimerContextLabel() {
                statusText = "Rest \(restText) · \(context)"
            } else {
                statusText = "Rest \(restText)"
            }

            return ActiveWorkoutStripStatusPresentation(
                statusText: statusText,
                statusTint: WGJTheme.success,
                pillText: restText,
                pillIcon: "timer",
                pillTint: WGJTheme.success
            )
        }

        return ActiveWorkoutStripStatusPresentation(
            statusText: "Elapsed \(elapsedText(now: now))",
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
    let statusTint: Color
    let pillText: String
    let pillIcon: String
    let pillTint: Color
}

#Preview {
    ActiveWorkoutStripView(sessionID: UUID(), onExpand: {})
        .environment(ActiveWorkoutPresentationState())
        .environment(RestTimerState())
        .modelContainer(for: [
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ], inMemory: true)
}
