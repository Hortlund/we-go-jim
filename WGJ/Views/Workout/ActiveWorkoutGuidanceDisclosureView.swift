import SwiftUI

struct ActiveWorkoutGuidanceDisclosureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let guidance: ActiveWorkoutExerciseGuidancePresentation
    let accessibilityIdentifier: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: guidance.badge.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tintColor)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(tintColor.opacity(0.14))
                                .overlay {
                                    Circle()
                                        .stroke(tintColor.opacity(0.24), lineWidth: 1)
                                }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(guidance.badge.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tintColor)
                            .textCase(.uppercase)

                        if let subtitle = guidance.badge.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tintColor.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tintColor.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(tintColor.opacity(0.22), lineWidth: 1)
                        }
                        .wgjRoundedGlass(cornerRadius: 14, tint: tintColor.opacity(0.12), interactive: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(buttonAccessibilityIdentifier)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides the coach tip details." : "Shows the coach tip details.")

            if isExpanded {
                TrainingGuidanceBannerView(
                    title: guidance.title,
                    message: guidance.summary,
                    tone: guidance.tone,
                    compact: true
                )
                .accessibilityIdentifier(detailAccessibilityIdentifier)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: guidance) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue.tone != .accent {
                setExpanded(true)
            }
        }
    }

    private var tintColor: Color {
        switch guidance.tone {
        case .accent:
            return WGJTheme.accentCyan
        case .success:
            return WGJTheme.success
        case .caution:
            return WGJTheme.accentGold
        }
    }

    private var buttonAccessibilityIdentifier: String {
        if let accessibilityIdentifier {
            return "\(accessibilityIdentifier)-guidance-badge-button"
        }

        return "workout-exercise-guidance-badge-button"
    }

    private var detailAccessibilityIdentifier: String {
        if let accessibilityIdentifier {
            return "\(accessibilityIdentifier)-guidance-detail"
        }

        return "workout-exercise-guidance-detail"
    }

    private var accessibilityLabel: String {
        let parts = [
            guidance.badge.title,
            guidance.badge.subtitle,
            guidance.title,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        return parts.joined(separator: ". ")
    }

    private func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            isExpanded = expanded
        }
    }
}
