import Combine
import SwiftData
import SwiftUI

struct ActiveWorkoutStripView: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    let sessionID: UUID
    let onExpand: () -> Void

    private let restTimerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Query private var sessions: [WorkoutSession]

    init(sessionID: UUID, onExpand: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onExpand = onExpand
        _sessions = Query(filter: #Predicate { session in
            session.id == sessionID
        })
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    var body: some View {
        Group {
            if let session, session.status == .active {
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

                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(statusText(now: context.date))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(restTimerAccent(now: context.date))
                                    .monospacedDigit()
                                    .wgjSingleLineText(scale: 0.84)
                            }
                        }

                        Spacer()

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            WGJMetricPill(
                                systemImage: restTimerPillIcon(now: context.date),
                                value: restTimerPillText(now: context.date),
                                tint: restTimerPillTint(now: context.date)
                            )
                        }
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
        }
        .onReceive(restTimerTick) { date in
            coordinator.handleRestTimerExpirationIfNeeded(at: date)
        }
        .task(id: session?.statusRaw) {
            await reconcileSessionLifecycleIfNeeded()
        }
    }

    @MainActor
    private func reconcileSessionLifecycleIfNeeded() async {
        guard let session, session.status == .active else {
            coordinator.clearActiveWorkout()
            return
        }
    }

    private func elapsedText(now: Date) -> String {
        guard let startedAt = session?.startedAt else {
            return "00:00"
        }
        return WGJDurationFormatter.elapsedString(since: startedAt, now: now)
    }

    private func statusText(now: Date) -> String {
        if let remaining = coordinator.restTimerRemaining(at: now) {
            let prefix = "Rest \(formattedRest(remaining))"
            if let context = coordinator.restTimerContextLabel() {
                return "\(prefix) · \(context)"
            }
            return prefix
        }

        return "Elapsed \(elapsedText(now: now))"
    }

    private func restTimerPillText(now: Date) -> String {
        if let remaining = coordinator.restTimerRemaining(at: now) {
            return formattedRest(remaining)
        }

        return "Open"
    }

    private func restTimerPillIcon(now: Date) -> String {
        coordinator.restTimerRemaining(at: now) == nil ? "chevron.up" : "timer"
    }

    private func restTimerPillTint(now: Date) -> Color {
        guard coordinator.restTimerRemaining(at: now) != nil else {
            return WGJTheme.accentBlue
        }
        return WGJTheme.success
    }

    private func restTimerAccent(now: Date) -> Color {
        guard coordinator.restTimerRemaining(at: now) != nil else {
            return WGJTheme.textSecondary
        }
        return WGJTheme.success
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    ActiveWorkoutStripView(sessionID: UUID(), onExpand: {})
        .environment(ActiveWorkoutCoordinator())
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
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ], inMemory: true)
}
