import SwiftUI
import SwiftData

struct ActiveWorkoutExerciseLoadingCard: View, Equatable {
    let exerciseAccessibilityIdentifier: String
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exerciseIndexTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentCyan)

                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .wgjSingleLineText(scale: 0.8)
                        .accessibilityIdentifier(exerciseAccessibilityIdentifier)

                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)

                    Text("Loading sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(WGJTheme.field)
                                .overlay(
                                    Capsule()
                                        .stroke(WGJTheme.outline.opacity(0.24), lineWidth: 1)
                                )
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(WGJTheme.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WGJTheme.field)
                    )
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private var summaryLine: String {
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        if !category.isEmpty {
            return category
        }

        return "Track the working sets below."
    }
}
