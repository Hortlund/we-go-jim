import SwiftUI

enum WorkoutCardioDurationFormatter {
    nonisolated static func text(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60

        if remainingSeconds == 0 {
            return String(localized: "\(minutes) min")
        }

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    nonisolated static func minutesText(seconds: Int) -> String {
        String(max(0, seconds) / 60)
    }

    nonisolated static func seconds(fromMinutesText text: String) -> Int {
        let cleaned = text.filter(\.isNumber)
        guard let minutes = Int(cleaned) else {
            return 0
        }

        return min(24 * 60 * 60, max(0, minutes * 60))
    }
}

extension WorkoutCardioRole {
    nonisolated var title: String {
        CardioLocalizedCopy.roleTitle(self)
    }

    nonisolated var compactTitle: String {
        CardioLocalizedCopy.compactRoleTitle(self)
    }

    nonisolated var systemImage: String {
        switch self {
        case .warmUp:
            return "figure.walk"
        case .main:
            return "figure.run"
        case .finisher:
            return "flag.checkered"
        }
    }
}

extension WorkoutCardioGoalKind {
    nonisolated var title: String {
        CardioLocalizedCopy.goalTitle(self)
    }
}

struct WorkoutCardioActivityPlanCard<Actions: View>: View {
    let activityName: String
    let role: WorkoutCardioRole
    let descriptor: String?
    let goalKind: WorkoutCardioGoalKind
    let targetDurationSeconds: Int
    let targetDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit
    let accessibilityIdentifier: String?
    let actions: Actions

    init(
        activityName: String,
        role: WorkoutCardioRole,
        descriptor: String? = nil,
        goalKind: WorkoutCardioGoalKind,
        targetDurationSeconds: Int,
        targetDistanceMeters: Double?,
        preferredDistanceUnit: WorkoutDistanceUnit,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.activityName = activityName
        self.role = role
        self.descriptor = descriptor
        self.goalKind = goalKind
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
        self.preferredDistanceUnit = preferredDistanceUnit
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                    Text(activityName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let descriptor, !descriptor.isEmpty {
                        Text(descriptor)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)
            }

            WGJMetricPill(
                systemImage: goalSystemImage,
                value: goalSummary,
                tint: WGJTheme.accentCyan
            )
            .accessibilityLabel(
                goalAccessibilitySummary
            )

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(strong: true)
        .modifier(WorkoutCardioAccessibilityIdentifier(identifier: accessibilityIdentifier))
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

    private var goalSystemImage: String {
        switch goalKind {
        case .time:
            return "clock.fill"
        case .distance:
            return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .open:
            return "scope"
        }
    }

    private var goalSummary: String {
        switch goalKind {
        case .time:
            return WorkoutCardioDurationFormatter.text(seconds: targetDurationSeconds)
        case .distance:
            guard let targetDistanceMeters, targetDistanceMeters > 0 else {
                return String(localized: "Distance")
            }
            let value = preferredDistanceUnit.value(fromMeters: targetDistanceMeters)
            return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(preferredDistanceUnit.symbol)"
        case .open:
            return String(localized: "No target")
        }
    }

    private var goalAccessibilitySummary: String {
        switch goalKind {
        case .time:
            let minutes = max(0, targetDurationSeconds) / 60
            return String(localized: "\(minutes) minutes")
        case .distance:
            guard let targetDistanceMeters, targetDistanceMeters > 0 else {
                return String(localized: "Distance")
            }
            let number = preferredDistanceUnit.value(fromMeters: targetDistanceMeters)
                .formatted(.number.precision(.fractionLength(0...2)))
            return WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                number,
                semantic: .distance(preferredDistanceUnit)
            )
        case .open:
            return String(localized: "No target")
        }
    }
}

extension WorkoutCardioActivityPlanCard where Actions == EmptyView {
    init(
        activityName: String,
        role: WorkoutCardioRole,
        descriptor: String? = nil,
        goalKind: WorkoutCardioGoalKind,
        targetDurationSeconds: Int,
        targetDistanceMeters: Double?,
        preferredDistanceUnit: WorkoutDistanceUnit,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            activityName: activityName,
            role: role,
            descriptor: descriptor,
            goalKind: goalKind,
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            preferredDistanceUnit: preferredDistanceUnit,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            EmptyView()
        }
    }
}

private struct WorkoutCardioAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
