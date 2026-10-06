import SwiftUI

struct WorkoutCardioResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let activityName: String
    let recordedDurationSeconds: Int?
    let recordedDistanceMeters: Double?
    let isOutdoorActivity: Bool
    private let initialDurationSeconds: Int?
    private let initialDistanceMeters: Double?
    let onSave: (ValidatedWorkoutCardioResult) async throws -> Void

    @State private var draft: WorkoutCardioResultDraft
    @State private var durationMinutesText: String
    @State private var showsDetails: Bool
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var editingRecordedDuration = false
    @State private var editingRecordedDistance = false

    init(
        activityName: String,
        draft: WorkoutCardioResultDraft,
        recordedDurationSeconds: Int? = nil,
        recordedDistanceMeters: Double? = nil,
        isOutdoorActivity: Bool = false,
        onSave: @escaping (ValidatedWorkoutCardioResult) async throws -> Void
    ) {
        self.activityName = activityName
        self.recordedDurationSeconds = recordedDurationSeconds
        self.recordedDistanceMeters = recordedDistanceMeters
        self.isOutdoorActivity = isOutdoorActivity
        self.initialDurationSeconds = recordedDurationSeconds ?? draft.actualDurationSeconds
        self.initialDistanceMeters = recordedDistanceMeters ?? draft.unchangedOriginalDistanceMeters
        self.onSave = onSave
        self._draft = State(initialValue: draft)
        self._durationMinutesText = State(
            initialValue: (recordedDurationSeconds ?? draft.actualDurationSeconds).map {
                WorkoutCardioResultDurationCodec.durationMinutesText(seconds: $0)
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
                    activityHeading
                    resultInputs
                    if isOutdoorActivity { notesInputs } else { details }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WGJTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cardio-result-validation-error")
                    }
                }
                .padding(20)
                .disabled(isSaving)
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .scrollDismissesKeyboard(.interactively)
            .wgjScreenBackground()
            .navigationTitle(isOutdoorActivity && recordedDurationSeconds != nil ? "Summary" : "Cardio Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .wgjSheetSurface()
        .interactiveDismissDisabled(isSaving)
    }

    private var activityHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activityName)
                .font(WGJTheme.headingFont(.largeTitle))
                .foregroundStyle(WGJTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(resultSubtitle)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var resultInputs: some View {
        VStack(alignment: .leading, spacing: 20) {
            durationInput
            Divider().overlay(WGJTheme.rowDivider)
            distanceInput
            derivedMetrics
        }
        .padding(20)
        .wgjCardContainer()
    }

    private var durationInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metricLabel(String(localized: "Duration"), systemImage: "clock")
                Spacer()
                if initialDurationSeconds != nil, !editingRecordedDuration {
                    editButton(label: String(localized: "Edit recorded time")) {
                        editingRecordedDuration = true
                    }
                }
            }

            if let initialDurationSeconds, !editingRecordedDuration {
                Text(Duration.seconds(initialDurationSeconds).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WGJTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cardio-result-recorded-duration")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Minutes", text: $durationMinutesText)
                        .keyboardType(.decimalPad)
                        .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                        .accessibilityLabel("Duration in minutes")
                        .accessibilityIdentifier("cardio-result-duration-field")
                    Text("min")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var distanceInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metricLabel(
                    recordedDistanceMeters != nil && !editingRecordedDistance
                        ? String(localized: "GPS distance") : String(localized: "Distance"),
                    systemImage: recordedDistanceMeters != nil ? "location" : "point.topleft.down.to.point.bottomright.curvepath"
                )
                Spacer()
                if initialDistanceMeters != nil, !editingRecordedDistance {
                    editButton(label: String(localized: "Edit recorded distance")) {
                        editingRecordedDistance = true
                    }
                }
            }

            if let initialDistanceMeters, !editingRecordedDistance {
                Text("\(WorkoutCardioResultDraft.distanceText(meters: initialDistanceMeters, unit: draft.distanceUnit)) \(draft.distanceUnit.symbol)")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WGJTheme.accentCyan)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cardio-result-recorded-distance")
            } else {
                distanceInputs
            }
        }
    }

    private func metricLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(WGJTheme.textSecondary)
    }

    private func editButton(label: String, action: @escaping () -> Void) -> some View {
        Button("Edit", action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(label)
    }

    private var saveBar: some View {
        Button(action: save) {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(WGJTheme.primaryButtonText)
                } else {
                    Image(systemName: "checkmark")
                }
                Text(saveButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .disabled(isSaving)
        .accessibilityIdentifier("cardio-result-save-button")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(WGJTheme.bgBase)
    }

    private var saveButtonTitle: String {
        if isSaving { return String(localized: "Saving…") }
        return isOutdoorActivity && recordedDurationSeconds != nil
            ? String(localized: "Save Activity") : String(localized: "Save Result")
    }

    private var resultSubtitle: String {
        if isOutdoorActivity, recordedDurationSeconds != nil {
            if recordedDistanceMeters != nil, !editingRecordedDistance {
                return String(localized: "Time and distance recorded.")
            }
            if !draft.distanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editingRecordedDistance {
                return String(localized: "Time recorded. Review your distance below.")
            }
            return String(localized: "Time recorded. No GPS distance was recorded; add it manually if you know it.")
        }
        if initialDurationSeconds != nil || initialDistanceMeters != nil {
            return String(localized: "Review your result before saving.")
        }
        return String(localized: "Log at least a duration or distance.")
    }

    private var distanceInputs: some View {
        HStack(spacing: 10) {
            TextField("Distance", text: $draft.distanceText)
                .keyboardType(.decimalPad)
                .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                .accessibilityLabel("Distance")
                .accessibilityIdentifier("cardio-result-distance-field")

            WGJActionMenuButton("Distance unit", usesPlainButtonStyle: false) {
                ForEach(WorkoutDistanceUnit.allCases) { unit in
                    Button(unit.symbol) { draft.distanceUnit = unit }
                }
            } label: {
                Label(draft.distanceUnit.symbol, systemImage: "chevron.down")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Distance unit")
            .accessibilityValue(draft.distanceUnit.symbol)
            .accessibilityIdentifier("cardio-result-distance-unit-picker")
        }
    }

    @ViewBuilder
    private var derivedMetrics: some View {
        let summary = previewSummary
        if summary.metrics.contains(where: { $0.kind.isDerived }) {
            Divider().overlay(WGJTheme.rowDivider)
            resultMetrics(summary.metrics.filter(\.kind.isDerived))
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
                        showsDetails
                            ? String(localized: "Hide detail")
                            : String(localized: "Add detail"),
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
                        title: String(localized: "Incline"),
                        placeholder: String(localized: "Percent"),
                        suffix: "%",
                        text: $draft.inclineText,
                        accessibilityIdentifier: "cardio-result-incline-field"
                    )
                }

                if draft.trackingProfile.supportsResistanceOrLevel {
                    detailField(
                        title: draft.trackingProfile == .stairClimber
                            ? String(localized: "Level")
                            : String(localized: "Resistance"),
                        placeholder: String(localized: "Optional"),
                        suffix: nil,
                        text: $draft.resistanceLevelText,
                        accessibilityIdentifier: "cardio-result-resistance-field"
                    )
                }

                noteField
            }
        }
        .padding(16)
        .wgjCardContainer()
    }

    private var notesInputs: some View {
        noteField
            .padding(20)
            .wgjCardContainer()
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes (optional)", systemImage: "text.alignleft")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WGJTheme.textSecondary)
            TextField("How did it feel?", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
                .font(.body)
                .padding(.top, 6)
                .accessibilityIdentifier("cardio-result-notes-field")
        }
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
        if let initialDurationSeconds, !editingRecordedDuration {
            candidate.actualDurationSeconds = initialDurationSeconds
        } else if durationText.isEmpty {
            candidate.actualDurationSeconds = nil
        } else {
            guard let seconds = WorkoutCardioResultDurationCodec.durationSeconds(
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
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: 140), spacing: 16)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    metricLabel(metric.title, systemImage: metric.systemImage)
                    Text(metric.value)
                        .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WGJTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    WorkoutMetricAccessibilityPolicy.cardioMetric(
                        label: metric.title,
                        value: metric.accessibilityValue,
                        semantic: metric.accessibilitySemantic
                    )
                )
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let candidate = candidateDraft() else {
            validationMessage = String(
                localized: "Enter a valid duration in minutes, or leave it empty."
            )
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(metricRows.enumerated()), id: \.offset) { _, row in
                        if row.count == 2 {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(row) { metric in
                                        metricPill(metric)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(row) { metric in
                                        metricPill(metric)
                                    }
                                }
                            }
                        } else {
                            ForEach(row) { metric in
                                metricPill(metric)
                            }
                        }
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
        .wgjCardContainer()
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
        switch metric.kind {
        case .pace, .averageSpeed, .rowingPace:
            return WGJTheme.accentCyan
        case .incline, .resistance, .level:
            return WGJTheme.accentGold
        case .duration, .distance:
            return WGJTheme.textSecondary
        }
    }

    private var metricRows: [[WorkoutCardioResultSummary.Metric]] {
        stride(from: 0, to: summary.metrics.count, by: 2).map { startIndex in
            Array(summary.metrics[startIndex..<min(startIndex + 2, summary.metrics.count)])
        }
    }

    private func metricPill(_ metric: WorkoutCardioResultSummary.Metric) -> some View {
        WGJMetricPill(
            systemImage: metric.systemImage,
            value: metric.value,
            tint: metricTint(metric)
        )
        .accessibilityLabel(
            WorkoutMetricAccessibilityPolicy.cardioMetric(
                label: metric.title,
                value: metric.accessibilityValue,
                semantic: metric.accessibilitySemantic
            )
        )
    }
}

private extension WorkoutCardioResultSummary.Metric.Kind {
    var isDerived: Bool {
        switch self {
        case .pace, .averageSpeed, .rowingPace:
            return true
        case .level, .duration, .distance, .incline, .resistance:
            return false
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

#Preview("GPS result · Dark") {
    WorkoutCardioResultEditor(
        activityName: "Outdoor Walk",
        draft: WorkoutCardioResultDraft(
            actualDurationSeconds: 1_682,
            actualDistanceMeters: 637.2240977908418,
            distanceUnit: .kilometers,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: "",
            trackingProfile: .walkRun
        ),
        recordedDurationSeconds: 1_682,
        recordedDistanceMeters: 637.2240977908418,
        isOutdoorActivity: true,
        onSave: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Manual result · Large text") {
    WorkoutCardioResultEditor(
        activityName: "Treadmill",
        draft: WorkoutCardioResultDraft(
            actualDurationSeconds: nil,
            actualDistanceMeters: nil,
            distanceUnit: .miles,
            inclinePercent: nil,
            resistanceLevel: nil,
            notes: "",
            trackingProfile: .treadmill
        ),
        onSave: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility1)
    .preferredColorScheme(.light)
}
