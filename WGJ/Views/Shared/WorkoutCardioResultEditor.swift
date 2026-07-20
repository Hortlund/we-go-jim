import SwiftUI

struct WorkoutCardioResultEditor: View {
    @Environment(\.dismiss) private var dismiss

    let activityName: String
    let onSave: (ValidatedWorkoutCardioResult) async throws -> Void

    @State private var draft: WorkoutCardioResultDraft
    @State private var durationMinutesText: String
    @State private var showsDetails: Bool
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(
        activityName: String,
        draft: WorkoutCardioResultDraft,
        onSave: @escaping (ValidatedWorkoutCardioResult) async throws -> Void
    ) {
        self.activityName = activityName
        self.onSave = onSave
        self._draft = State(initialValue: draft)
        self._durationMinutesText = State(
            initialValue: draft.actualDurationSeconds.map {
                WorkoutCardioSetupNumericCodec.durationMinutesText(seconds: $0)
            } ?? ""
        )
        self._showsDetails = State(
            initialValue: !draft.inclineText.isEmpty
                || !draft.resistanceLevelText.isEmpty
                || !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    resultInputs
                    derivedMetrics
                    details

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WGJTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cardio-result-validation-error")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjScreenBackground()
            .wgjMinimalKeyboardToolbar()
            .navigationTitle("Cardio Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save Result") {
                        save()
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("cardio-result-save-button")
                }
            }
        }
        .wgjSheetSurface()
        .interactiveDismissDisabled(isSaving)
    }

    private var resultInputs: some View {
        VStack(alignment: .leading, spacing: 18) {
            WGJSectionHeader(
                activityName,
                subtitle: "Log at least a duration or distance."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                HStack(spacing: 10) {
                    TextField("Minutes", text: $durationMinutesText)
                        .keyboardType(.decimalPad)
                        .wgjPillField()
                        .accessibilityLabel("Duration in minutes")
                        .accessibilityIdentifier("cardio-result-duration-field")

                    Text("min")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Distance (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                HStack(spacing: 10) {
                    TextField("Distance", text: $draft.distanceText)
                        .keyboardType(.decimalPad)
                        .wgjPillField()
                        .accessibilityIdentifier("cardio-result-distance-field")

                    Picker("Distance unit", selection: $draft.distanceUnit) {
                        ForEach(WorkoutDistanceUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("cardio-result-distance-unit-picker")
                }
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var derivedMetrics: some View {
        let summary = previewSummary
        if summary.metrics.contains(where: { ["Pace", "Avg Speed", "500 m Pace"].contains($0.title) }) {
            VStack(alignment: .leading, spacing: 12) {
                WGJSectionHeader(
                    "Calculated",
                    subtitle: "Updates from your duration and distance."
                )
                resultMetrics(summary.metrics.filter {
                    ["Pace", "Avg Speed", "500 m Pace"].contains($0.title)
                })
            }
            .padding(16)
            .wgjCardContainer(strong: true)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsDetails.toggle()
                }
            } label: {
                HStack {
                    Label(
                        showsDetails ? "Hide detail" : "Add detail",
                        systemImage: "slider.horizontal.3"
                    )
                    Spacer()
                    Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WGJTheme.accentBlue)
            .accessibilityIdentifier("cardio-result-detail-toggle")

            if showsDetails {
                if draft.trackingProfile.supportsIncline {
                    detailField(
                        title: "Incline",
                        placeholder: "Percent",
                        suffix: "%",
                        text: $draft.inclineText,
                        accessibilityIdentifier: "cardio-result-incline-field"
                    )
                }

                if draft.trackingProfile.supportsResistanceOrLevel {
                    detailField(
                        title: draft.trackingProfile == .stairClimber ? "Level" : "Resistance",
                        placeholder: "Optional",
                        suffix: nil,
                        text: $draft.resistanceLevelText,
                        accessibilityIdentifier: "cardio-result-resistance-field"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)

                    TextField("How did it feel?", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .wgjPillField()
                        .accessibilityIdentifier("cardio-result-notes-field")
                }
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private func detailField(
        title: String,
        placeholder: String,
        suffix: String?,
        text: Binding<String>,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .wgjPillField()
                    .accessibilityIdentifier(accessibilityIdentifier)

                if let suffix {
                    Text(suffix)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
        }
    }

    private var previewSummary: WorkoutCardioResultSummary {
        guard let candidate = candidateDraft(),
              let result = try? WorkoutCardioResultValidator.validated(candidate) else {
            return WorkoutCardioResultSummary(metrics: [], notes: nil)
        }
        return WorkoutCardioResultSummaryFormatter.summary(
            result,
            profile: candidate.trackingProfile
        )
    }

    private func candidateDraft() -> WorkoutCardioResultDraft? {
        var candidate = draft
        let durationText = durationMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if durationText.isEmpty {
            candidate.actualDurationSeconds = nil
        } else {
            guard let seconds = WorkoutCardioSetupNumericCodec.durationSeconds(
                fromMinutesText: durationText,
                locale: .current
            ) else {
                return nil
            }
            candidate.actualDurationSeconds = seconds
        }
        return candidate
    }

    private func resultMetrics(_ metrics: [WorkoutCardioResultSummary.Metric]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(metrics) { metric in
                WGJMetricPill(
                    systemImage: metric.systemImage,
                    value: metric.value,
                    tint: WGJTheme.accentCyan
                )
                .accessibilityLabel("\(metric.title), \(metric.value)")
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let candidate = candidateDraft() else {
            validationMessage = "Enter a valid duration in minutes, or leave it empty."
            return
        }

        do {
            let result = try WorkoutCardioResultValidator.validated(candidate)
            isSaving = true
            Task { @MainActor in
                do {
                    try await onSave(result)
                    dismiss()
                } catch {
                    isSaving = false
                    validationMessage = error.localizedDescription
                }
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct WorkoutCardioResultSummaryCard<Actions: View>: View {
    let role: WorkoutCardioRole
    let exerciseName: String
    let descriptor: String?
    let summary: WorkoutCardioResultSummary
    let statusText: String
    let isCompleted: Bool
    let footnote: String?
    let actions: Actions

    init(
        role: WorkoutCardioRole,
        exerciseName: String,
        descriptor: String?,
        summary: WorkoutCardioResultSummary,
        statusText: String,
        isCompleted: Bool,
        footnote: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.role = role
        self.exerciseName = exerciseName
        self.descriptor = descriptor
        self.summary = summary
        self.statusText = statusText
        self.isCompleted = isCompleted
        self.footnote = footnote
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: role.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(roleTint)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(roleTint.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(roleTint)
                        .textCase(.uppercase)
                    Text(exerciseName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                    if let descriptor, !descriptor.isEmpty {
                        Text(descriptor)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WGJMetricPill(
                    systemImage: isCompleted ? "checkmark.circle.fill" : "clock.fill",
                    value: statusText,
                    tint: isCompleted ? WGJTheme.success : WGJTheme.warning
                )
            }

            if summary.metrics.isEmpty {
                Text("No measured result.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(summary.metrics) { metric in
                        WGJMetricPill(
                            systemImage: metric.systemImage,
                            value: metric.value,
                            tint: metricTint(metric)
                        )
                        .accessibilityLabel("\(metric.title), \(metric.value)")
                    }
                }
            }

            if let notes = summary.notes {
                Label(notes, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(strong: true)
    }

    private var roleTint: Color {
        switch role {
        case .warmUp:
            return WGJTheme.accentBlue
        case .main:
            return WGJTheme.accentCyan
        case .finisher:
            return WGJTheme.accentGold
        }
    }

    private func metricTint(_ metric: WorkoutCardioResultSummary.Metric) -> Color {
        switch metric.title {
        case "Pace", "Avg Speed", "500 m Pace":
            return WGJTheme.accentCyan
        case "Incline", "Resistance", "Level":
            return WGJTheme.accentGold
        default:
            return WGJTheme.textSecondary
        }
    }
}

extension WorkoutCardioResultSummaryCard where Actions == EmptyView {
    init(
        role: WorkoutCardioRole,
        exerciseName: String,
        descriptor: String?,
        summary: WorkoutCardioResultSummary,
        statusText: String,
        isCompleted: Bool,
        footnote: String? = nil
    ) {
        self.init(
            role: role,
            exerciseName: exerciseName,
            descriptor: descriptor,
            summary: summary,
            statusText: statusText,
            isCompleted: isCompleted,
            footnote: footnote
        ) {
            EmptyView()
        }
    }
}
