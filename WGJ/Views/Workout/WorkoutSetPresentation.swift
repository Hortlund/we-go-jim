import SwiftUI

extension View {
    func metricInputShell(isFocused: Bool) -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(isFocused ? WGJTheme.fieldStrong : WGJTheme.field.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(
                                isFocused ? WGJTheme.accentBlue.opacity(0.42) : WGJTheme.outline.opacity(0.72),
                                lineWidth: isFocused ? 1.4 : 1
                            )
                    }
                    .shadow(
                        color: isFocused ? WGJTheme.accentBlue.opacity(0.10) : WGJTheme.shadowSoft.opacity(0.42),
                        radius: isFocused ? 8 : 6,
                        x: 0,
                        y: isFocused ? 2 : 3
                    )
            }
    }
}

enum MetricFieldDisplayTone {
    case actual
    case ghost
}

struct MetricFieldDisplayState {
    let text: String
    let tone: MetricFieldDisplayTone
    var accessibilityIdentifier: String?
}

func metricDisplayText(_ state: MetricFieldDisplayState) -> some View {
    Text(state.text)
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .foregroundStyle(
            state.tone == .actual
                ? WGJTheme.textPrimary
                : WGJTheme.textTertiary.opacity(0.72)
        )
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .applyIfLet(state.accessibilityIdentifier) { view, identifier in
            view.accessibilityIdentifier(identifier)
        }
}

extension View {
    @ViewBuilder
    func applyIfLet<Value, Content: View>(
        _ value: Value?,
        @ViewBuilder transform: (Self, Value) -> Content
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

struct WorkoutSessionExerciseSetRowLabel {
    let badgeTitle: String
    let title: String
}

nonisolated struct WorkoutSetCompletionGatePresentation: Equatable {
    let title: String
    let detail: String
    let iconSystemName: String
}

nonisolated struct WorkoutSetCompletionControlPresentation: Equatable {
    let inlineButton: InlineButton
    let supplementalRow: SupplementalRow?

    struct InlineButton: Equatable {
        let label: String
        let systemImage: String
        let tone: Tone
        let targetIsCompleted: Bool

        static func make(
            isCompleted: Bool,
            completedLabel: String,
            incompleteLabel: String,
            isSetCompletionEnabled: Bool
        ) -> InlineButton {
            if isCompleted {
                return InlineButton(
                    label: completedLabel,
                    systemImage: "checkmark.circle.fill",
                    tone: .completed,
                    targetIsCompleted: false
                )
            }

            return InlineButton(
                label: incompleteLabel,
                systemImage: "checkmark.circle",
                tone: isSetCompletionEnabled ? .ready : .gated,
                targetIsCompleted: true
            )
        }
    }

    enum SupplementalRow: Equatable {
        case gateNotice(WorkoutSetCompletionGatePresentation)
    }

    enum Tone: Equatable {
        case ready
        case completed
        case gated
    }

    static func make(
        draft: WorkoutSessionSetDraft,
        manualCompletionMode: Bool,
        isSetCompletionEnabled: Bool,
        gatePresentation: WorkoutSetCompletionGatePresentation?,
        isGateRevealed: Bool
    ) -> WorkoutSetCompletionControlPresentation? {
        guard manualCompletionMode else {
            return nil
        }

        let inlineButton = InlineButton.make(
            isCompleted: draft.isCompleted,
            completedLabel: draft.isCycleCompleted ? "Mark set incomplete" : "Undo main set",
            incompleteLabel: "Complete set",
            isSetCompletionEnabled: isSetCompletionEnabled
        )

        let supplementalRow: SupplementalRow?
        if !isSetCompletionEnabled, isGateRevealed, let gatePresentation {
            supplementalRow = .gateNotice(gatePresentation)
        } else {
            supplementalRow = nil
        }

        return WorkoutSetCompletionControlPresentation(
            inlineButton: inlineButton,
            supplementalRow: supplementalRow
        )
    }
}

nonisolated struct WorkoutSetInlineHintPresentation: Equatable, Sendable {
    let weightGhostText: String?
    let repsGhostText: String?
    let aimText: String
    let statusText: String?
    let statusTone: WorkoutSetProgressTone
    let canApplyPrevious: Bool

    var statusLayoutText: String {
        statusText ?? "Matched last session"
    }

    var actionLayoutText: String {
        "Fill Last"
    }

    static func make(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        formatWeight: (Double) -> String = { WGJFormatters.decimalString($0) }
    ) -> WorkoutSetInlineHintPresentation? {
        guard previous != nil else {
            return nil
        }

        guard let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            formatWeight: formatWeight
        ) else {
            return nil
        }

        return WorkoutSetInlineHintPresentation(
            weightGhostText: weightGhostText(from: previous, formatWeight: formatWeight),
            repsGhostText: repsGhostText(from: previous),
            aimText: reference.aimValue,
            statusText: reference.statusText,
            statusTone: reference.statusTone,
            canApplyPrevious: reference.canReusePrevious
        )
    }

    static func weightGhostText(
        from previous: WorkoutPreviousSetSnapshot?,
        formatWeight: (Double) -> String
    ) -> String? {
        guard let previous else { return nil }

        if previous.unit == .bodyweight {
            return "BW"
        }

        guard let weight = previous.weight else { return nil }
        return formatWeight(weight)
    }

    static func repsGhostText(from previous: WorkoutPreviousSetSnapshot?) -> String? {
        previous?.reps.map(String.init)
    }
}

extension WorkoutSetCompletionControlPresentation.Tone {
    var tintColor: Color {
        switch self {
        case .ready:
            return WGJTheme.accentBlue
        case .completed:
            return WGJTheme.success
        case .gated:
            return WGJTheme.accentGold
        }
    }

    var fillColor: Color {
        tintColor.opacity(self == .completed ? 0.18 : 0.12)
    }

    var strokeColor: Color {
        tintColor.opacity(self == .completed ? 0.36 : 0.24)
    }
}

nonisolated enum WorkoutSetPreviousPerformanceApplicationResolver {
    static func resolve(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        mode: WorkoutPreviousPerformanceApplicationMode = .fillMissing
    ) -> WorkoutSessionSetDraft {
        draft.applyingPreviousPerformance(previous, mode: mode)
    }
}

extension WorkoutSessionSetDraft {
    nonisolated var showsLoggedPerformance: Bool {
        if actualWeight != nil || actualReps != nil {
            return true
        }

        return actualLoadUnit == .bodyweight && isCompleted
    }

    nonisolated func applyingPreviousPerformance(
        _ previous: WorkoutPreviousSetSnapshot?,
        mode: WorkoutPreviousPerformanceApplicationMode = .overwriteExisting
    ) -> WorkoutSessionSetDraft {
        guard let previous else { return self }

        var updatedDraft = self
        let shouldReplaceWeight = mode == .overwriteExisting || updatedDraft.actualWeight == nil
        let shouldReplaceReps = mode == .overwriteExisting || updatedDraft.actualReps == nil

        if shouldReplaceWeight, (previous.weight != nil || previous.unit == .bodyweight) {
            updatedDraft.actualWeight = previous.weight
            updatedDraft.actualLoadUnit = previous.unit
        }

        if shouldReplaceReps, previous.reps != nil {
            updatedDraft.actualReps = previous.reps
        }
        return updatedDraft
    }
}
