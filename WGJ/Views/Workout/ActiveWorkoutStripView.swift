import SwiftData
import SwiftUI

struct ActiveWorkoutStripView: View {
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState

    let sessionID: UUID
    let onExpand: () -> Void

    @Query private var sessions: [ActiveWorkoutDraftSession]

    init(sessionID: UUID, onExpand: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onExpand = onExpand
        _sessions = Query(filter: #Predicate { session in
            session.id == sessionID
        })
    }

    private var session: ActiveWorkoutDraftSession? {
        sessions.first
    }

    var body: some View {
        Group {
            if let session {
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
                                Text(session.name)
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
            }
        }
        .task(id: session?.id) {
            await reconcileSessionLifecycleIfNeeded()
        }
    }

    @MainActor
    private func reconcileSessionLifecycleIfNeeded() async {
        guard session != nil else {
            activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
            return
        }
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
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ], inMemory: true)
}
