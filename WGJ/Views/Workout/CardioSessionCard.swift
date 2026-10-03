import SwiftUI

/// Entry back into the dedicated recorder; timer ticks stay inside this card.
struct CardioSessionCard: View {
    let activity: ActiveWorkoutRuntimeCardioBlock
    let onOpen: () -> Void
    let onEditPlan: () -> Void
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: activity.catalogExerciseUUID.contains("run") ? "figure.run" : "figure.walk")
                    .font(.title).foregroundStyle(WGJTheme.accentBlue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.exerciseNameSnapshot).font(.title3.weight(.semibold))
                    Text(CardioRecordingPolicy.recordsGPS(activity) ? "GPS distance & route" : "Timer · Add distance afterward")
                        .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                WGJActionMenuButton("Cardio Actions") {
                    Button("Set a Goal", action: onEditPlan)
                    Button("Change Activity", action: onChange)
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
            }
            if activity.isCompleted {
                Text(ActiveWorkoutCardioPresentation.make(activity: activity).resultText ?? String(localized: "Completed"))
                    .font(.headline).foregroundStyle(WGJTheme.success)
            } else if activity.timerState != .idle {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ActiveWorkoutCardioPresentation.make(activity: activity, at: context.date).elapsedText)
                        .font(.largeTitle.monospacedDigit().weight(.bold)).foregroundStyle(WGJTheme.accentCyan)
                }
            } else if activity.goalKind != .open {
                Text(ActiveWorkoutCardioPresentation.make(activity: activity).goalText)
                    .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            }
            Button(action: onOpen) {
                Label(activity.isCompleted ? "View Activity" : activity.timerState == .idle ? "Start Activity" : "Open Recording", systemImage: activity.isCompleted ? "checkmark.circle" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJPrimaryButtonStyle())
            .accessibilityIdentifier("cardio-session-open-button")
        }
        .padding(18).wgjCardContainer(strong: true)
        .accessibilityIdentifier("active-workout-cardio-\(activity.id)-card")
    }
}
