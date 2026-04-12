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

                headerActions
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            completionRow
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

    @ViewBuilder
    private var completionRow: some View {
        if isCompleted {
            HStack(spacing: 10) {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.success)
                    .wgjSingleLineText(scale: 0.9)

                Spacer(minLength: 8)

                Button("Undo", action: onToggleCompletion)
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityLabel(undoAccessibilityLabel)
                    .modifier(CardioCompletionIdentifier(identifier: completionAccessibilityIdentifier))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WGJTheme.success.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WGJTheme.success.opacity(0.22), lineWidth: 1)
                    )
            )
        } else {
            Button(action: onToggleCompletion) {
                Label(completionTitle, systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .wgjSingleLineText(scale: 0.82)
            }
            .buttonStyle(WGJCompactPrimaryButtonStyle())
            .disabled(!canComplete)
            .accessibilityLabel(completionAccessibilityLabel)
            .modifier(CardioCompletionIdentifier(identifier: completionAccessibilityIdentifier))
        }
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
