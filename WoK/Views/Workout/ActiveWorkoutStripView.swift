import SwiftData
import SwiftUI

struct ActiveWorkoutStripView: View {
    let sessionID: UUID
    let onExpand: () -> Void

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
        Button(action: onExpand) {
            HStack(spacing: 10) {
                Circle()
                    .fill(WoKTheme.accentCyan)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session?.name ?? "Active Workout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WoKTheme.textPrimary)
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Elapsed \(elapsedText(now: context.date))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WoKTheme.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                Spacer()

                Label("Open", systemImage: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WoKTheme.accentBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(WoKTheme.accentBlue.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
            )
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

    private func elapsedText(now: Date) -> String {
        guard let startedAt = session?.startedAt else {
            return "00:00"
        }
        return WoKDurationFormatter.elapsedString(since: startedAt, now: now)
    }
}

#Preview {
    ActiveWorkoutStripView(sessionID: UUID(), onExpand: {})
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
