import MuscleMap
import SwiftUI

struct ExerciseBodyMapFilterSheet: View {
    let availableMuscles: [ExerciseBodyMapFilterOption]
    let selectedMuscleID: Int?
    let onSelect: (Int) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var selectedMuscleName: String {
        guard let selectedMuscleID,
              let muscle = availableMuscles.first(where: { $0.id == selectedMuscleID })
        else {
            return "Any Body Part"
        }
        return muscle.name
    }

    private var selectedMuscles: Set<Muscle> {
        guard let selectedMuscleID else { return [] }
        let spec = ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: [selectedMuscleID],
            secondaryMuscleIDs: []
        )
        return Set(spec.primaryRegions.compactMap(\.muscleMapMuscleForFilter))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Filter Body Part")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        Text(selectedMuscleName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    HStack(spacing: 12) {
                        bodyMap(side: .front, label: "Front")
                        bodyMap(side: .back, label: "Back")
                    }

                    Button {
                        onClear()
                    } label: {
                        Label("Any Body Part", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("exercises-muscle-map-filter-clear")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Body Parts")
                            .font(.headline)
                            .foregroundStyle(WGJTheme.textPrimary)

                        LazyVStack(spacing: 4) {
                            ForEach(availableMuscles) { muscle in
                                Button {
                                    onSelect(muscle.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(muscle.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(WGJTheme.textPrimary)

                                        Spacer(minLength: 8)

                                        if selectedMuscleID == muscle.id {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(WGJTheme.accentBlue)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(
                                                selectedMuscleID == muscle.id
                                                    ? WGJTheme.accentBlue.opacity(0.12)
                                                    : WGJTheme.field.opacity(0.72)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("exercises-muscle-map-filter-\(muscle.id)")
                            }
                        }
                    }
                    .padding(14)
                    .wgjCardContainer(strong: true)
                }
                .padding(16)
            }
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle("Body Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("exercises-muscle-map-filter-sheet")
    }

    private func bodyMap(side: BodySide, label: String) -> some View {
        VStack(spacing: 8) {
            BodyView(gender: .male, side: side, style: .wgjExerciseFilter)
                .selected(selectedMuscles)
                .showSubGroups()
                .onMuscleSelected { muscle, _ in
                    select(muscle)
                }
                .frame(height: 238)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WGJTheme.field.opacity(0.82))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(WGJTheme.outline.opacity(0.35), lineWidth: 1)
                        }
                }
                .accessibilityIdentifier("exercises-muscle-map-filter-\(label.lowercased())")

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private func select(_ muscle: Muscle) {
        guard let muscleID = ExerciseBodyMapRegionMapper.catalogMuscleID(
                muscleMapRawValue: muscle.rawValue,
                parentMuscleMapRawValue: muscle.parentGroup?.rawValue,
                availableMuscles: availableMuscles
              )
        else {
            return
        }
        onSelect(muscleID)
    }
}

private extension BodyViewStyle {
    static let wgjExerciseFilter = BodyViewStyle(
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
    var muscleMapMuscleForFilter: Muscle? {
        Muscle(rawValue: rawValue)
    }
}
