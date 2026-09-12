import SwiftUI
import SwiftData

struct ActiveWorkoutCancelSection: View {
    let isCancelArmed: Bool
    let onArmCancel: () -> Void
    let onKeepWorkout: () -> Void
    let onDiscardWorkout: () -> Void

    var body: some View {
        Group {
            if isCancelArmed {
                cancelConfirmation
            } else {
                Button(action: onArmCancel) {
                    Label("Cancel Workout", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(WGJTheme.danger)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WGJTheme.field.opacity(0.74))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(WGJTheme.danger.opacity(0.38), lineWidth: 1)
                                )
                                .wgjRoundedGlass(
                                    cornerRadius: 12,
                                    tint: WGJTheme.danger.opacity(0.12),
                                    interactive: true
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("active-workout-cancel-button")
            }
        }
    }

    private var cancelConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WGJTheme.danger)

                Text("Discard this workout and all logged sets?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button("Keep Workout", action: onKeepWorkout)
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("active-workout-keep-button")

                Button("Discard Workout", action: onDiscardWorkout)
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .tint(WGJTheme.danger)
                    .accessibilityIdentifier("active-workout-discard-button")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-workout-cancel-confirmation")
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.field.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.danger.opacity(0.32), lineWidth: 1)
                )
                .wgjRoundedGlass(cornerRadius: 14, tint: WGJTheme.danger.opacity(0.14))
        )
    }
}
