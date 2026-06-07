import SwiftUI

struct ActiveWorkoutTemplateSyncReviewSheet: View {
    let preview: WorkoutTemplateSyncPreview
    let onKeepTemplate: () -> Void
    let onUpdateTemplate: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if let editedWorkoutNotes = preview.editedWorkoutNotes {
                        section(
                            title: "Workout Notes",
                            subtitle: "Workout notes changed during this session."
                        ) {
                            summaryRow(
                                title: "Workout Notes",
                                details: editedWorkoutNotes.changes,
                                tint: WGJTheme.accentBlue
                            )
                        }
                    }

                    if !preview.addedCardioBlocks.isEmpty {
                        section(
                            title: "Added Cardio",
                            subtitle: "\(preview.addedCardioBlocks.count) cardio section" + (preview.addedCardioBlocks.count == 1 ? "" : "s") + " added to the workout"
                        ) {
                            ForEach(preview.addedCardioBlocks) { addition in
                                summaryRow(
                                    title: addition.phase.title,
                                    details: [addition.exerciseName, addition.summary],
                                    tint: WGJTheme.success
                                )
                            }
                        }
                    }

                    if !preview.removedCardioBlocks.isEmpty {
                        section(
                            title: "Removed Cardio",
                            subtitle: "\(preview.removedCardioBlocks.count) cardio section" + (preview.removedCardioBlocks.count == 1 ? "" : "s") + " removed from the template"
                        ) {
                            ForEach(preview.removedCardioBlocks) { removal in
                                summaryRow(
                                    title: removal.phase.title,
                                    details: [removal.exerciseName, removal.summary],
                                    tint: WGJTheme.danger
                                )
                            }
                        }
                    }

                    if !preview.editedCardioBlocks.isEmpty {
                        section(
                            title: "Edited Cardio",
                            subtitle: "Cardio phase settings that changed during the workout."
                        ) {
                            ForEach(preview.editedCardioBlocks) { edited in
                                summaryRow(
                                    title: "\(edited.phase.title) · \(edited.exerciseName)",
                                    details: edited.changes,
                                    tint: WGJTheme.accentGold
                                )
                            }
                        }
                    }

                    if !preview.addedExercises.isEmpty {
                        section(
                            title: "Added Exercises",
                            subtitle: "\(preview.addedExercises.count) new exercise" + (preview.addedExercises.count == 1 ? "" : "s")
                        ) {
                            ForEach(preview.addedExercises) { addition in
                                summaryRow(
                                    title: addition.exerciseName,
                                    details: [addition.summary],
                                    tint: WGJTheme.success
                                )
                            }
                        }
                    }

                    if !preview.removedExercises.isEmpty {
                        section(
                            title: "Removed Exercises",
                            subtitle: "\(preview.removedExercises.count) exercise" + (preview.removedExercises.count == 1 ? "" : "s") + " removed from the template"
                        ) {
                            ForEach(preview.removedExercises) { removal in
                                summaryRow(
                                    title: removal.exerciseName,
                                    details: [removal.summary],
                                    tint: WGJTheme.danger
                                )
                            }
                        }
                    }

                    if !preview.reorderedExercises.isEmpty {
                        section(
                            title: "Reordered Exercises",
                            subtitle: "The workout order changed for existing template exercises."
                        ) {
                            ForEach(preview.reorderedExercises) { reorder in
                                summaryRow(
                                    title: reorder.exerciseName,
                                    details: ["Position \(reorder.fromPosition) -> \(reorder.toPosition)"],
                                    tint: WGJTheme.accentBlue
                                )
                            }
                        }
                    }

                    if !preview.editedExercises.isEmpty {
                        section(
                            title: "Edited Settings",
                            subtitle: "Reusable exercise targets changed during this workout."
                        ) {
                            ForEach(preview.editedExercises) { edited in
                                summaryRow(
                                    title: edited.exerciseName,
                                    details: edited.changes,
                                    tint: WGJTheme.accentGold
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .wgjSheetSurface()
            .navigationTitle("Update Template")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("active-workout-template-review-sheet")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review workout changes")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
                .textCase(.uppercase)

            Text(preview.templateName)
                .font(.title2.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(preview.summary)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Update the template with these changes, or keep it as-is and save only this workout.")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .wgjCardContainer(strong: true)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(WGJTheme.outline.opacity(0.28))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    keepTemplateButton
                    updateTemplateButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    updateTemplateButton
                    keepTemplateButton
                }
            }
            .padding(16)
        }
        .background(WGJTheme.bgBase.opacity(0.98))
    }

    private var keepTemplateButton: some View {
        Button("Keep Template", action: onKeepTemplate)
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("active-workout-template-review-keep-button")
    }

    private var updateTemplateButton: some View {
        Button("Update Template", action: onUpdateTemplate)
            .buttonStyle(WGJPrimaryButtonStyle())
            .accessibilityIdentifier("active-workout-template-review-apply-button")
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: subtitle)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func summaryRow(
        title: String,
        details: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            ForEach(details, id: \.self) { detail in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint.opacity(0.72))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}
