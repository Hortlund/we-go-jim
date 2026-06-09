import SwiftUI

struct ActiveWorkoutCardioPhaseCard<HeaderActions: View>: View {
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let descriptor: String?
    let targetDurationSeconds: Int
    let statusText: String?
    let statusTint: Color
    let footnote: String?
    let isCompleted: Bool
    let canComplete: Bool
    let completionTitle: String
    let completionAccessibilityLabel: String
    let undoAccessibilityLabel: String
    let completionAccessibilityIdentifier: String?
    let accessibilityIdentifier: String?
    let onToggleCompletion: () -> Void
    let headerActions: HeaderActions

    init(
        phase: WorkoutCardioPhase,
        exerciseName: String,
        descriptor: String?,
        targetDurationSeconds: Int,
        statusText: String? = nil,
        statusTint: Color = WGJTheme.textSecondary,
        footnote: String? = nil,
        isCompleted: Bool,
        canComplete: Bool,
        completionTitle: String,
        completionAccessibilityLabel: String,
        undoAccessibilityLabel: String,
        completionAccessibilityIdentifier: String? = nil,
        accessibilityIdentifier: String? = nil,
        onToggleCompletion: @escaping () -> Void,
        @ViewBuilder headerActions: () -> HeaderActions
    ) {
        self.phase = phase
        self.exerciseName = exerciseName
        self.descriptor = descriptor
        self.targetDurationSeconds = targetDurationSeconds
        self.statusText = statusText
        self.statusTint = statusTint
        self.footnote = footnote
        self.isCompleted = isCompleted
        self.canComplete = canComplete
        self.completionTitle = completionTitle
        self.completionAccessibilityLabel = completionAccessibilityLabel
        self.undoAccessibilityLabel = undoAccessibilityLabel
        self.completionAccessibilityIdentifier = completionAccessibilityIdentifier
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onToggleCompletion = onToggleCompletion
        self.headerActions = headerActions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(phase.title.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(headerTint)

                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerTint)
                        .fixedSize(horizontal: false, vertical: true)

                    if let descriptor, !descriptor.isEmpty {
                        Text(descriptor)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        cardioInfoChip(
                            WorkoutCardioDurationFormatter.text(seconds: targetDurationSeconds),
                            tint: WGJTheme.accentBlue
                        )

                        if let statusText, !statusText.isEmpty {
                            cardioInfoChip(statusText, tint: statusTint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 12)

                completionButton

                headerActions
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(16)
        .background { cardBackground }
        .wgjCardContainer(strong: true)
        .overlay { cardOverlay }
        .modifier(CardioCardIdentifier(identifier: accessibilityIdentifier))
    }

    private var headerTint: Color {
        if isCompleted {
            return WGJTheme.success
        }

        switch phase {
        case .preWorkout:
            return WGJTheme.accentBlue
        case .postWorkout:
            return WGJTheme.accentGold
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isCompleted {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .fill(WGJTheme.success.opacity(0.10))
        }
    }

    @ViewBuilder
    private var cardOverlay: some View {
        if isCompleted {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .stroke(WGJTheme.success.opacity(0.22), lineWidth: 1.2)
        }
    }

    private var completionButton: some View {
        Button(action: onToggleCompletion) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 20, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(completionTint)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(completionTint.opacity(isCompleted ? 0.18 : 0.12))
                        .overlay(
                            Circle()
                                .stroke(completionTint.opacity(isCompleted ? 0.36 : 0.24), lineWidth: 1)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 54)
        .disabled(!canComplete && !isCompleted)
        .accessibilityLabel(isCompleted ? undoAccessibilityLabel : completionAccessibilityLabel)
        .modifier(CardioCompletionIdentifier(identifier: completionAccessibilityIdentifier))
    }

    private var completionTint: Color {
        if isCompleted {
            return WGJTheme.success
        }
        return canComplete ? WGJTheme.accentBlue : WGJTheme.accentGold
    }

    private func cardioInfoChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )
            )
    }
}

struct ActiveWorkoutCardioHeaderActionIcon: View {
    let tint: Color

    var body: some View {
        Image(systemName: "ellipsis.circle")
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )
            )
    }
}

private struct CardioCompletionIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct CardioCardIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
