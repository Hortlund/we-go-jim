import SwiftUI
import SwiftData

struct ActiveWorkoutSupersetHeader: View {
    let nextStepLabel: String?
    let nextExerciseName: String?
    let isResting: Bool
    let onShowNextSet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                structureChip("Superset", tint: WGJTheme.accentBlue)
                structureChip(SupersetExercisePosition.first.label, tint: WGJTheme.accentCyan)
                structureChip(SupersetExercisePosition.second.label, tint: WGJTheme.accentCyan)
            }

            if let nextStepLabel {
                Button(action: onShowNextSet) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(isResting ? "Rest, then" : "Go to") \(nextStepLabel)")
                                .font(.subheadline.weight(.semibold))
                            if let nextExerciseName {
                                Text(nextExerciseName)
                                    .font(.caption)
                                    .foregroundStyle(WGJTheme.textPrimary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.down.circle")
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WGJTheme.accentCyan)
                .accessibilityIdentifier("workout-superset-go-to-next-set")
            } else {
                Text("Superset complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func structureChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}
