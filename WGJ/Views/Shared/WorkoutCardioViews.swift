import SwiftUI

enum WorkoutCardioDurationFormatter {
    static func text(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60

        if remainingSeconds == 0 {
            return "\(minutes) min"
        }

        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    static func minutesText(seconds: Int) -> String {
        String(max(0, seconds) / 60)
    }

    static func seconds(fromMinutesText text: String) -> Int {
        let cleaned = text.filter(\.isNumber)
        guard let minutes = Int(cleaned) else {
            return 0
        }

        return min(24 * 60 * 60, max(0, minutes * 60))
    }
}

extension WorkoutCardioRole {
    nonisolated var title: String {
        switch self {
        case .warmUp:
            return "Warm-up"
        case .main:
            return "Main Cardio"
        case .finisher:
            return "Finisher"
        }
    }

    nonisolated var compactTitle: String {
        switch self {
        case .warmUp:
            return "Warm-up"
        case .main:
            return "Main"
        case .finisher:
            return "Finisher"
        }
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
        switch self {
        case .time:
            return "Time"
        case .distance:
            return "Distance"
        case .open:
            return "No Target"
        }
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
                return "Distance"
            }
            let value = preferredDistanceUnit.value(fromMeters: targetDistanceMeters)
            return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(preferredDistanceUnit.symbol)"
        case .open:
            return "No target"
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

struct WorkoutCardioSettingsDraft: Identifiable, Equatable {
    let id: UUID
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let descriptor: String?
    let targetDurationSeconds: Int

    init(
        id: UUID = UUID(),
        phase: WorkoutCardioPhase,
        exerciseName: String,
        descriptor: String?,
        targetDurationSeconds: Int
    ) {
        self.id = id
        self.phase = phase
        self.exerciseName = exerciseName
        self.descriptor = descriptor
        self.targetDurationSeconds = targetDurationSeconds
    }
}

struct WorkoutCardioPhaseCard<Actions: View>: View {
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let descriptor: String?
    let targetDurationSeconds: Int
    let statusText: String?
    let statusTint: Color
    let footnote: String?
    let accessibilityIdentifier: String?
    let actions: Actions

    init(
        phase: WorkoutCardioPhase,
        exerciseName: String,
        descriptor: String?,
        targetDurationSeconds: Int,
        statusText: String? = nil,
        statusTint: Color = WGJTheme.textSecondary,
        footnote: String? = nil,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.phase = phase
        self.exerciseName = exerciseName
        self.descriptor = descriptor
        self.targetDurationSeconds = targetDurationSeconds
        self.statusText = statusText
        self.statusTint = statusTint
        self.footnote = footnote
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phase.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(phaseTint)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(phaseTint.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(phaseTint)
                        .textCase(.uppercase)

                    Text(exerciseName)
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

            HStack(spacing: 8) {
                WGJMetricPill(
                    systemImage: "clock.fill",
                    value: WorkoutCardioDurationFormatter.text(seconds: targetDurationSeconds),
                    tint: WGJTheme.accentCyan
                )

                if let statusText {
                    WGJMetricPill(
                        systemImage: phaseStatusIcon,
                        value: statusText,
                        tint: statusTint
                    )
                }
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
        .modifier(WorkoutCardioAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }

    private var phaseTint: Color {
        switch phase {
        case .preWorkout:
            return WGJTheme.accentBlue
        case .postWorkout:
            return WGJTheme.accentGold
        }
    }

    private var phaseStatusIcon: String {
        statusTint == WGJTheme.success ? "checkmark.circle.fill" : "clock.fill"
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

extension WorkoutCardioPhaseCard where Actions == EmptyView {
    init(
        phase: WorkoutCardioPhase,
        exerciseName: String,
        descriptor: String?,
        targetDurationSeconds: Int,
        statusText: String? = nil,
        statusTint: Color = WGJTheme.textSecondary,
        footnote: String? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            phase: phase,
            exerciseName: exerciseName,
            descriptor: descriptor,
            targetDurationSeconds: targetDurationSeconds,
            statusText: statusText,
            statusTint: statusTint,
            footnote: footnote,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            EmptyView()
        }
    }
}

struct WorkoutCardioSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: WorkoutCardioSettingsDraft
    let onSave: (Int) -> Void

    @State private var durationMinutesText: String

    init(
        draft: WorkoutCardioSettingsDraft,
        onSave: @escaping (Int) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self._durationMinutesText = State(
            initialValue: WorkoutCardioDurationFormatter.minutesText(seconds: draft.targetDurationSeconds)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader(draft.phase.title, subtitle: draft.exerciseName)

                    if let descriptor = draft.descriptor, !descriptor.isEmpty {
                        Text(descriptor)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    TextField("Minutes", text: $durationMinutesText)
                        .keyboardType(.numberPad)
                        .wgjPillField()
                        .accessibilityIdentifier("cardio-settings-duration-field")

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            presetButtons
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            presetButtons
                        }
                    }
                }
                .padding(16)
                .wgjCardContainer(strong: true)

                Spacer(minLength: 0)
            }
            .padding(16)
            .wgjSheetSurface()
            .navigationTitle("Cardio Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(resolvedDurationSeconds)
                        dismiss()
                    }
                    .disabled(resolvedDurationSeconds <= 0)
                }
            }
        }
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(presetMinutes, id: \.self) { minutes in
            Button("\(minutes) min") {
                durationMinutesText = String(minutes)
            }
            .buttonStyle(WGJGhostButtonStyle())
        }
    }

    private var presetMinutes: [Int] {
        switch draft.phase {
        case .preWorkout:
            return [5, 10, 15]
        case .postWorkout:
            return [10, 20, 30, 45]
        }
    }

    private var resolvedDurationSeconds: Int {
        let seconds = WorkoutCardioDurationFormatter.seconds(fromMinutesText: durationMinutesText)
        return seconds > 0 ? seconds : draft.phase.defaultDurationSeconds
    }
}
