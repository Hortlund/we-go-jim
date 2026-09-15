import SwiftUI

struct TemplateStartPreviewSheet: View {
    let preview: StartWorkoutTemplatePreview
    let isStarting: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onExport: (TemplateTransferExportFormat) async throws -> URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingExportOptions = false
    @State private var shareSheetItem: TemplateTransferShareSheetItem?
    @State private var isExporting = false
    @State private var exportErrorMessage = ""
    @State private var showingExportError = false

    private var orderedExercises: [StartWorkoutTemplatePreview.Exercise] {
        preview.exercises
    }

    private var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<StartWorkoutTemplatePreview.Exercise>] {
        WorkoutExerciseDisplayGrouping.build(
            items: orderedExercises,
            membership: { $0.supersetMembership }
        )
    }

    private var plannedSetBreakdown: String {
        let working = "\(preview.totalPlannedWorkingSets) working"
        guard preview.totalPlannedWarmupSets > 0 else {
            return "\(working) set\(preview.totalPlannedWorkingSets == 1 ? "" : "s")"
        }
        return "\(working) · \(preview.totalPlannedWarmupSets) warm-up"
    }

    private var cardioCount: Int {
        preview.cardioBlocks.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    cardioSection(for: .warmUp)

                    cardioSection(for: .main)

                    exerciseSection

                    cardioSection(for: .finisher)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            editAction
                            startAction
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            startAction
                            editAction
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("template-preview-sheet")
            .overlay {
                if isStarting {
                    TemplateStartHandoffOverlay()
                        .transition(.opacity)
                }
            }
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: isStarting)
            .wgjGlassContainer(spacing: 16)
            .wgjSheetSurface()
            .navigationTitle("Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isStarting || isExporting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingExportOptions = true
                    } label: {
                        Label("Export / Share", systemImage: "square.and.arrow.up")
                    }
                    .confirmationDialog(
                        "Export / Share",
                        isPresented: $showingExportOptions,
                        titleVisibility: .visible
                    ) {
                        Button("WGJ Template File") {
                            exportPreview(format: .bundle)
                        }
                        Button("JSON") {
                            exportPreview(format: .json)
                        }
                        Button("Text") {
                            exportPreview(format: .text)
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Choose a format to export or share this item.")
                    }
                    .disabled(isStarting || isExporting)
                    .accessibilityIdentifier("template-preview-export-button")
                }
            }
        }
        .sheet(item: $shareSheetItem) { sheet in
            WGJActivityShareSheet(activityItems: [sheet.fileURL]) {
                cleanupExportedFile(at: sheet.fileURL)
            }
        }
        .alert("Template Export Error", isPresented: $showingExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isStarting || isExporting)
    }

    private func exportPreview(format: TemplateTransferExportFormat) {
        guard !isExporting else { return }

        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let fileURL = try await onExport(format)
                shareSheetItem = TemplateTransferShareSheetItem(fileURL: fileURL)
            } catch {
                exportErrorMessage = String(describing: error)
                showingExportError = true
            }
        }
    }

    private func cleanupExportedFile(at fileURL: URL) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @ViewBuilder
    private var exerciseSection: some View {
        if orderedExercises.isEmpty {
            WGJEmptyStateCard(
                title: "No exercises yet",
                message: "Edit the template to add exercises before starting from it.",
                icon: "list.bullet"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Exercise Order",
                    subtitle: "Everything in order before you start."
                )

                VStack(spacing: 0) {
                    ForEach(Array(exerciseDisplayGroups.enumerated()), id: \.element.id) { index, group in
                        previewExerciseGroup(group)

                        if index < exerciseDisplayGroups.count - 1 {
                            Rectangle()
                                .fill(WGJTheme.rowDivider.opacity(0.42))
                                .frame(height: 1)
                                .padding(.leading, 24)
                        }
                    }
                }
                .wgjCardContainer()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Template Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .textCase(.uppercase)

            Text(preview.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = preview.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    summaryMetricPills
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryMetricPills
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("template-preview-summary-card")
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    WGJTheme.cardStrong.opacity(0.9),
                                    WGJTheme.cardElevated.opacity(0.72),
                                    WGJTheme.accentBlue.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.86), lineWidth: 1)
                }
                .shadow(color: WGJTheme.shadowStrong.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }

    private var exerciseSummary: String {
        let count = preview.exerciseCount
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    @ViewBuilder
    private var summaryMetricPills: some View {
        WGJMetricPill(
            systemImage: "list.bullet",
            value: exerciseSummary,
            tint: WGJTheme.accentBlue
        )

        WGJMetricPill(
            systemImage: "number.square",
            value: plannedSetBreakdown,
            tint: WGJTheme.accentCyan
        )

        if cardioCount > 0 {
            WGJMetricPill(
                systemImage: "figure.run",
                value: "\(cardioCount) cardio",
                tint: WGJTheme.accentGold
            )
        }

        if let focusAreaSummary = preview.focusAreaSummary {
            WGJMetricPill(
                systemImage: "bolt.fill",
                value: focusAreaSummary,
                tint: WGJTheme.accentGold
            )
        }
    }

    @ViewBuilder
    private func previewExerciseGroup(
        _ group: WorkoutExerciseDisplayGroup<StartWorkoutTemplatePreview.Exercise>
    ) -> some View {
        switch group {
        case .single(let exercise, let index):
            previewExerciseRow(exercise, title: "\(index + 1)")
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        case .superset(let superset):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                    structureBadge("Rest after A2 \(formattedRest(superset.roundRestSeconds))", tint: WGJTheme.accentCyan)
                }

                previewExerciseRow(superset.first, title: SupersetExercisePosition.first.label)
                previewExerciseRow(superset.second, title: SupersetExercisePosition.second.label)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityIdentifier("template-preview-superset-group-\(superset.groupID.uuidString.lowercased())")
        }
    }

    private func previewExerciseRow(_ exercise: StartWorkoutTemplatePreview.Exercise, title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.exerciseName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-name")

                        if let descriptor = exercise.descriptor {
                            Text(descriptor)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        structureBadgeRow(for: exercise)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(primaryPrescriptionText(for: exercise))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        if let warmup = warmupPrescriptionText(for: exercise) {
                            Text(warmup)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WGJTheme.accentCyan)
                                .lineLimit(1)
                        }

                        if let secondary = secondaryPrescriptionText(for: exercise) {
                            Text(secondary)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                }

                if exercise.componentOptionCount > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        componentContainerSummary(for: exercise, title: title)

                        Text("Options: \(exercise.componentNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-options")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())")
    }

    private func componentContainerSummary(
        for exercise: StartWorkoutTemplatePreview.Exercise,
        title: String
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                componentSummaryChip(
                    title: "\(exercise.componentOptionCount) exercise options",
                    systemImage: "square.stack.3d.up.fill",
                    tint: WGJTheme.accentBlue
                )
                .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary")

                if let lastExerciseName = exercise.lastExerciseName {
                    componentSummaryChip(
                        title: "Last \(lastExerciseName)",
                        systemImage: "clock.arrow.circlepath",
                        tint: WGJTheme.accentGold
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-last")
                }

                if let nextExerciseName = exercise.nextExerciseName {
                    componentSummaryChip(
                        title: "Next \(nextExerciseName)",
                        systemImage: "arrow.right.circle.fill",
                        tint: WGJTheme.accentCyan
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-next")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                componentSummaryChip(
                    title: "\(exercise.componentOptionCount) exercise options",
                    systemImage: "square.stack.3d.up.fill",
                    tint: WGJTheme.accentBlue
                )
                .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary")

                if let lastExerciseName = exercise.lastExerciseName {
                    componentSummaryChip(
                        title: "Last \(lastExerciseName)",
                        systemImage: "clock.arrow.circlepath",
                        tint: WGJTheme.accentGold
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-last")
                }

                if let nextExerciseName = exercise.nextExerciseName {
                    componentSummaryChip(
                        title: "Next \(nextExerciseName)",
                        systemImage: "arrow.right.circle.fill",
                        tint: WGJTheme.accentCyan
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-next")
                }
            }
        }
    }

    private func componentSummaryChip(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private func structureBadgeRow(for exercise: StartWorkoutTemplatePreview.Exercise) -> some View {
        let presentation = WorkoutExerciseStructurePresentation(
            supersetMembership: exercise.supersetMembership,
            hasDropset: exercise.hasDropset
        )

        if presentation.isSuperset || presentation.hasDropset {
            HStack(spacing: 8) {
                if presentation.isSuperset {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                }
                if let position = presentation.supersetPosition {
                    structureBadge(position.label, tint: WGJTheme.accentCyan)
                }
                if presentation.hasDropset {
                    structureBadge("Dropset", tint: WGJTheme.accentGold)
                }
            }
        }
    }

    private func structureBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    @ViewBuilder
    private func cardioSection(for role: WorkoutCardioRole) -> some View {
        let cardioBlocks = preview.cardioBlocks.filter { $0.role == role }
        if !cardioBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    role.title,
                    subtitle: CardioLocalizedCopy.roleSubtitle(role)
                )

                ForEach(cardioBlocks) { cardioBlock in
                    WorkoutCardioActivityPlanCard(
                        activityName: cardioBlock.exerciseName,
                        role: cardioBlock.role,
                        descriptor: cardioBlock.descriptor,
                        goalKind: cardioBlock.goalKind,
                        targetDurationSeconds: cardioBlock.targetDurationSeconds,
                        targetDistanceMeters: cardioBlock.targetDistanceMeters,
                        preferredDistanceUnit: cardioBlock.preferredDistanceUnit,
                        accessibilityIdentifier: "template-preview-\(cardioBlock.role.rawValue)-\(cardioBlock.id)-card"
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private func primaryPrescriptionText(for exercise: StartWorkoutTemplatePreview.Exercise) -> String {
        let setCount = exercise.plannedWorkingSetCount
        if let repSummary = repRangeSummary(for: exercise) {
            return "\(setCount)x \(repSummary)"
        }

        return "\(setCount) working set" + (setCount == 1 ? "" : "s")
    }

    private func warmupPrescriptionText(for exercise: StartWorkoutTemplatePreview.Exercise) -> String? {
        let count = exercise.plannedWarmupSetCount
        return count > 0 ? "\(count) warm-up" : nil
    }

    private func secondaryPrescriptionText(for exercise: StartWorkoutTemplatePreview.Exercise) -> String? {
        guard exercise.restSeconds > 0 else { return nil }
        return "Rest \(formattedRest(exercise.restSeconds))"
    }

    private func repRangeSummary(for exercise: StartWorkoutTemplatePreview.Exercise) -> String? {
        switch (exercise.targetRepMin, exercise.targetRepMax) {
        case let (min?, max?) where min == max:
            return "\(min) reps"
        case let (min?, max?):
            return "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "Up to \(max)"
        default:
            return nil
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        guard seconds > 0 else { return "No rest" }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private var startAction: some View {
        Button {
            onStart()
        } label: {
            if isStarting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Starting Workout")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Start Workout")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .disabled(isStarting)
        .accessibilityIdentifier("template-preview-start-button")
    }

    private var editAction: some View {
        Button {
            dismiss()
            onEdit()
        } label: {
            Text("Edit Template")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
        .disabled(isStarting)
        .accessibilityIdentifier("template-preview-edit-button")
    }

}
