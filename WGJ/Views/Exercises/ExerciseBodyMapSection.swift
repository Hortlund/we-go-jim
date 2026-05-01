import MuscleMap
import SwiftUI

struct ExerciseBodyMapSection: View {
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    var showsTitle = true

    private var highlightSpec: ExerciseBodyMapHighlightSpec {
        ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: primaryMuscleIDs,
            secondaryMuscleIDs: secondaryMuscleIDs
        )
    }

    private var primaryMuscles: [Muscle] {
        highlightSpec.primaryRegions.compactMap(\.muscleMapMuscle).sortedByDisplayOrder
    }

    private var secondaryMuscles: [Muscle] {
        highlightSpec.secondaryRegions.compactMap(\.muscleMapMuscle).sortedByDisplayOrder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text("Muscle map")
                    .font(.headline)
                    .foregroundStyle(WGJTheme.textPrimary)
            }

            HStack(spacing: 12) {
                bodyMap(side: .front, label: "Front")
                bodyMap(side: .back, label: "Back")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise-body-map-section")
    }

    private func bodyMap(side: BodySide, label: String) -> some View {
        VStack(spacing: 8) {
            configuredBody(side: side)
                .frame(height: 210)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WGJTheme.field.opacity(0.82))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(WGJTheme.outline.opacity(0.35), lineWidth: 1)
                        }
                )
                .accessibilityLabel("\(label) muscle map")

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private func configuredBody(side: BodySide) -> BodyView {
        BodyView(gender: .male, side: side, style: .wgjExerciseDetail)
            .highlight(secondaryMuscles, color: WGJTheme.accentBlue, opacity: 0.28)
            .highlight(primaryMuscles, color: WGJTheme.accentBlue, opacity: 0.88)
            .showSubGroups()
    }
}

private extension BodyViewStyle {
    static let wgjExerciseDetail = BodyViewStyle(
        defaultFillColor: WGJTheme.cardElevated.opacity(0.95),
        strokeColor: WGJTheme.outline.opacity(0.45),
        strokeWidth: 0.55,
        selectionColor: WGJTheme.accentBlue,
        selectionStrokeColor: WGJTheme.accentBlue.opacity(0.95),
        selectionStrokeWidth: 1.25,
        headColor: WGJTheme.cardElevated.opacity(0.95),
        hairColor: WGJTheme.textSecondary.opacity(0.45)
    )
}

private extension ExerciseBodyMapRegion {
    var muscleMapMuscle: Muscle? {
        Muscle(rawValue: rawValue)
    }
}

private extension Array where Element == Muscle {
    var sortedByDisplayOrder: [Muscle] {
        sorted { lhs, rhs in
            let lhsIndex = Muscle.allCases.firstIndex(of: lhs) ?? .max
            let rhsIndex = Muscle.allCases.firstIndex(of: rhs) ?? .max
            return lhsIndex < rhsIndex
        }
    }
}
