import SwiftUI

struct WorkoutExerciseDropStageCardView: View, Equatable {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    let exerciseName: String
    let setIndex: Int
    let stageIndex: Int
    let stage: WorkoutSessionDropStageDraft
    let isEditingEnabled: Bool
    let isCompletionEnabled: Bool
    let onToggleCompletion: () -> Void
    let onRepsChanged: (String) -> Void
    let onWeightChanged: (String) -> Void
    let onLoadUnitChanged: (TemplateLoadUnit) -> Void
    let onDelete: () -> Void
    let keyboardDismissToken: ActiveWorkoutKeyboardDismissToken
    let onCommitPendingInput: () -> Void
    let onInputFocusChange: (Bool) -> Void

    @State private var repsText: String
    @State private var weightText: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case reps
    }

    init(
        exerciseName: String,
        setIndex: Int,
        stageIndex: Int,
        stage: WorkoutSessionDropStageDraft,
        isEditingEnabled: Bool,
        isCompletionEnabled: Bool,
        onToggleCompletion: @escaping () -> Void,
        onRepsChanged: @escaping (String) -> Void,
        onWeightChanged: @escaping (String) -> Void,
        onLoadUnitChanged: @escaping (TemplateLoadUnit) -> Void,
        onDelete: @escaping () -> Void,
        keyboardDismissToken: ActiveWorkoutKeyboardDismissToken = ActiveWorkoutKeyboardDismissToken(),
        onCommitPendingInput: @escaping () -> Void = {},
        onInputFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.stageIndex = stageIndex
        self.stage = stage
        self.isEditingEnabled = isEditingEnabled
        self.isCompletionEnabled = isCompletionEnabled
        self.onToggleCompletion = onToggleCompletion
        self.onRepsChanged = onRepsChanged
        self.onWeightChanged = onWeightChanged
        self.onLoadUnitChanged = onLoadUnitChanged
        self.onDelete = onDelete
        self.keyboardDismissToken = keyboardDismissToken
        self.onCommitPendingInput = onCommitPendingInput
        self.onInputFocusChange = onInputFocusChange
        _repsText = State(initialValue: stage.actualReps.map(String.init) ?? "")
        _weightText = State(initialValue: stage.actualWeight.map(WGJFormatters.decimalString) ?? "")
    }

    static func == (lhs: WorkoutExerciseDropStageCardView, rhs: WorkoutExerciseDropStageCardView) -> Bool {
        lhs.setIndex == rhs.setIndex
            && lhs.stageIndex == rhs.stageIndex
            && lhs.stage == rhs.stage
            && lhs.isEditingEnabled == rhs.isEditingEnabled
            && lhs.isCompletionEnabled == rhs.isCompletionEnabled
            && lhs.keyboardDismissToken == rhs.keyboardDismissToken
    }

    var body: some View {
        let completionButton = WorkoutSetCompletionControlPresentation.InlineButton.make(
            isCompleted: stage.isCompleted,
            completedLabel: "Undo drop \(stageIndex + 1)",
            incompleteLabel: "Complete drop \(stageIndex + 1)",
            isSetCompletionEnabled: isCompletionEnabled
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop \(stageIndex + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    if let targetSummary {
                        Text(targetSummary)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }

                Spacer()

                if stage.isCompleted {
                    Text("Done")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WGJTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WGJTheme.success.opacity(0.12))
                        )
                }

                if isEditingEnabled {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-delete-button")
                }
            }

            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    weightField
                    repsFieldWithCompletionControl(completionButton)
                }
            } else {
                HStack(spacing: 10) {
                    weightField
                    repsFieldWithCompletionControl(completionButton)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            stage.isCompleted ? WGJTheme.success.opacity(0.24) : WGJTheme.outline.opacity(0.18),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)")
        .onChange(of: stage.actualReps) { _, newValue in
            guard focusedField != .reps else { return }
            let resolved = newValue.map(String.init) ?? ""
            guard repsText != resolved else { return }
            repsText = resolved
        }
        .onChange(of: stage.actualWeight) { _, newValue in
            guard focusedField != .weight else { return }
            let resolved = newValue.map(WGJFormatters.decimalString) ?? ""
            guard weightText != resolved else { return }
            weightText = resolved
        }
        .onChange(of: focusedField) { oldValue, newValue in
            onInputFocusChange(newValue != nil)
            guard oldValue != nil, newValue == nil else { return }
            commitLocalText()
            onCommitPendingInput()
        }
        .onChange(of: keyboardDismissToken) { _, _ in
            guard focusedField != nil else { return }
            commitLocalText()
            onCommitPendingInput()
            focusedField = nil
            onInputFocusChange(false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: newPhase) else { return }
            guard focusedField != nil else { return }
            commitLocalText()
            onCommitPendingInput()
            focusedField = nil
            onInputFocusChange(false)
        }
        .onDisappear {
            commitLocalText()
            onCommitPendingInput()
            onInputFocusChange(false)
        }
    }

    private var weightField: some View {
        HStack(spacing: 8) {
            TextField("Weight", text: Binding(
                get: { weightText },
                set: { newValue in
                    weightText = newValue
                    onWeightChanged(newValue)
                }
            ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .wgjPillField()
                .focused($focusedField, equals: .weight)
                .disabled(!isEditingEnabled)
                .accessibilityLabel(weightAccessibility.label)
                .accessibilityValue(weightAccessibility.value)
                .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-weight-field")

            WGJActionMenuButton("Drop Load Unit", titleVisibility: .hidden) {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        commitLocalText()
                        onCommitPendingInput()
                        onLoadUnitChanged(unit)
                    }
                }
            } label: {
                Text(stage.actualLoadUnit.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
            .disabled(!isEditingEnabled)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-load-unit-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repsField: some View {
        TextField("Reps", text: Binding(
            get: { repsText },
            set: { newValue in
                repsText = newValue
                onRepsChanged(newValue)
            }
        ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .wgjPillField()
            .focused($focusedField, equals: .reps)
            .disabled(!isEditingEnabled)
            .accessibilityLabel(repsAccessibility.label)
            .accessibilityValue(repsAccessibility.value)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-reps-field")
    }

    private var weightAccessibility: WorkoutMetricAccessibilityDescriptor {
        WorkoutMetricAccessibilityPolicy.field(
            exerciseName: exerciseName,
            setNumber: setIndex + 1,
            dropStageNumber: stageIndex + 1,
            metric: .weight,
            value: weightText,
            unit: stage.actualLoadUnit.shortLabel
        )
    }

    private var repsAccessibility: WorkoutMetricAccessibilityDescriptor {
        WorkoutMetricAccessibilityPolicy.field(
            exerciseName: exerciseName,
            setNumber: setIndex + 1,
            dropStageNumber: stageIndex + 1,
            metric: .reps,
            value: repsText,
            unit: nil
        )
    }

    private func repsFieldWithCompletionControl(
        _ presentation: WorkoutSetCompletionControlPresentation.InlineButton
    ) -> some View {
        HStack(spacing: 8) {
            repsField

            Button {
                commitLocalText()
                onCommitPendingInput()
                onToggleCompletion()
            } label: {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(presentation.tone.tintColor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(presentation.tone.fillColor)
                            .overlay(
                                Circle()
                                    .stroke(presentation.tone.strokeColor, lineWidth: 1)
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 48, height: 44)
            .disabled(!isEditingEnabled || !isCompletionEnabled)
            .accessibilityLabel(presentation.label)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-completion-button")
        }
    }

    private func commitLocalText() {
        let resolvedWeightText = stage.actualWeight.map(WGJFormatters.decimalString) ?? ""
        if weightText != resolvedWeightText {
            onWeightChanged(weightText)
        }

        let resolvedRepsText = stage.actualReps.map(String.init) ?? ""
        if repsText != resolvedRepsText {
            onRepsChanged(repsText)
        }
    }

    private var targetSummary: String? {
        let repsText = stage.targetReps.map { "\($0) reps" }
        let weightText: String?
        if let targetWeight = stage.targetWeight {
            weightText = "\(WGJFormatters.decimalString(targetWeight)) \(stage.targetLoadUnit.shortLabel)"
        } else if stage.targetLoadUnit == .bodyweight {
            weightText = TemplateLoadUnit.bodyweight.shortLabel
        } else {
            weightText = nil
        }

        switch (weightText, repsText) {
        case let (weight?, reps?):
            return "Target \(weight) x \(reps)"
        case let (weight?, nil):
            return "Target \(weight)"
        case let (nil, reps?):
            return "Target \(reps)"
        case (nil, nil):
            return nil
        }
    }
}

