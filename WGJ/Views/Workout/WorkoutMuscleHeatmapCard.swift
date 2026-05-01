import MuscleMap
import SwiftUI

struct WorkoutMuscleHeatmapCard: View {
    let title: String
    let subtitle: String
    let snapshot: WorkoutMuscleHeatmapSnapshot
    let emptyMessage: String

    private var topRegionText: String {
        guard !snapshot.topRegionNames.isEmpty else {
            return "No muscle data"
        }
        return snapshot.topRegionNames.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: subtitle)

            if snapshot.entries.isEmpty {
                mapPair

                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Most worked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)

                    Spacer(minLength: 8)

                    Text(topRegionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .multilineTextAlignment(.trailing)
                }

                mapPair
            }
        }
        .padding(14)
        .wgjCardContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-muscle-heatmap-card")
    }

    private var mapPair: some View {
        HStack(spacing: 12) {
            bodyMap(side: .front, label: "Front")
            bodyMap(side: .back, label: "Back")
        }
    }

    private func bodyMap(side: BodySide, label: String) -> some View {
        VStack(spacing: 8) {
            configuredBody(side: side)
                .frame(height: 190)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.field.opacity(0.62))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WGJTheme.outline.opacity(0.28), lineWidth: 1)
                        }
                )
                .accessibilityLabel("\(label) workout muscle heatmap")

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private func configuredBody(side: BodySide) -> BodyView {
        snapshot.entries.reduce(
            BodyView(gender: .male, side: side, style: .wgjWorkoutHeatmap).showSubGroups()
        ) { body, entry in
            guard let muscle = entry.region.muscleMapMuscle else { return body }
            return body.highlight(
                muscle,
                color: WGJTheme.accentBlue,
                opacity: 0.22 + (0.68 * entry.intensity)
            )
        }
    }
}

private extension BodyViewStyle {
    static let wgjWorkoutHeatmap = BodyViewStyle(
        defaultFillColor: WGJTheme.cardElevated.opacity(0.92),
        strokeColor: WGJTheme.outline.opacity(0.42),
        strokeWidth: 0.5,
        selectionColor: WGJTheme.accentBlue,
        selectionStrokeColor: WGJTheme.accentCyan.opacity(0.92),
        selectionStrokeWidth: 1.1,
        headColor: WGJTheme.cardElevated.opacity(0.92),
        hairColor: WGJTheme.textSecondary.opacity(0.38)
    )
}

private extension ExerciseBodyMapRegion {
    var muscleMapMuscle: Muscle? {
        Muscle(rawValue: rawValue)
    }
}
