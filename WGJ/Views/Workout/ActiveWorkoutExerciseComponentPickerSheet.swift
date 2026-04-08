import SwiftUI

struct ActiveWorkoutExerciseComponentPickerDraft: Identifiable, Equatable {
    let exerciseID: UUID
    let resolution: ExerciseComponentRotationResolution

    var id: UUID { exerciseID }
}

struct ActiveWorkoutExerciseComponentSummaryView: View {
    let resolution: ExerciseComponentRotationResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lastPerformedComponent = resolution.lastPerformedComponent {
                summaryChip(
                    title: "Last",
                    value: lastPerformedComponent.exerciseNameSnapshot,
                    tint: WGJTheme.accentGold
                )
            }

            summaryChip(
                title: "Next",
                value: resolution.suggestedComponent.exerciseNameSnapshot,
                tint: WGJTheme.accentBlue
            )

            if resolution.hasOverride {
                Text("Override active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.success)
            }
        }
    }

    private func summaryChip(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

struct ActiveWorkoutExerciseComponentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: ActiveWorkoutExerciseComponentPickerDraft
    let onSelect: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WGJSectionHeader(
                        "Choose Exercise",
                        subtitle: draft.resolution.hasOverride
                            ? "You can keep the override or switch back to the suggested option."
                            : "Pick another option for this slot without changing the template."
                    )

                    ActiveWorkoutExerciseComponentSummaryView(resolution: draft.resolution)

                    ForEach(draft.resolution.availableComponents) { component in
                        componentRow(component)
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("active-workout-component-picker-sheet")
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle("Exercise Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("active-workout-component-picker-close-button")
                }
            }
        }
    }

    private func componentRow(_ component: ExerciseComponentSnapshot) -> some View {
        let isSelected = component.catalogExerciseUUID == draft.resolution.selectedComponent.catalogExerciseUUID
        let isSuggested = component.catalogExerciseUUID == draft.resolution.suggestedComponent.catalogExerciseUUID

        return Button {
            onSelect(component.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(component.exerciseNameSnapshot)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        if let descriptor = descriptor(for: component) {
                            Text(descriptor)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WGJTheme.success)
                    }
                }

                HStack(spacing: 8) {
                    if isSuggested {
                        badge("Suggested", tint: WGJTheme.accentBlue)
                    }

                    if let lastPerformedComponent = draft.resolution.lastPerformedComponent,
                       lastPerformedComponent.catalogExerciseUUID == component.catalogExerciseUUID {
                        badge("Last done", tint: WGJTheme.accentGold)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WGJTheme.fieldStrong.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isSelected ? WGJTheme.success.opacity(0.45) : WGJTheme.outline.opacity(0.55),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("active-workout-component-option-\(component.catalogExerciseUUID)")
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
    }

    private func descriptor(for component: ExerciseComponentSnapshot) -> String? {
        let trimmedMuscleSummary = component.muscleSummarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = component.categorySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }
}
