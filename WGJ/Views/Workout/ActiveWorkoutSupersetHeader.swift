import SwiftUI
import SwiftData

struct ActiveWorkoutSupersetHeader: View {
    let roundRestSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                structureChip("Superset", tint: WGJTheme.accentBlue)
                structureChip(SupersetExercisePosition.first.label, tint: WGJTheme.accentCyan)
                structureChip(SupersetExercisePosition.second.label, tint: WGJTheme.accentCyan)
            }

            Text("Complete A1, move straight into A2, then rest \(formattedRest(roundRestSeconds)).")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
