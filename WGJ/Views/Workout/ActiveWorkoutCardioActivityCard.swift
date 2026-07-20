import Foundation
import SwiftUI

nonisolated struct ActiveWorkoutCardioPresentation: Identifiable, Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case idle
        case running
        case paused
        case completed
    }

    enum Action: String, Equatable, Hashable, Sendable {
        case start
        case pause
        case resume
        case finish
        case editResult
    }

    struct LayoutIdentity: Equatable, Sendable {
        let id: UUID
        let role: WorkoutCardioRole
        let state: State
        let actionLayout: [Action]
        let reservedTimerWidth: Double
    }

    static let timerWidth: Double = 88

    let id: UUID
    let role: WorkoutCardioRole
    let activityName: String
    let descriptor: String?
    let goalText: String
    let resultText: String?
    let state: State
    let actionLayout: [Action]
    let reservedTimerWidth: Double
    let elapsedText: String

    private let timerActivity: ActiveWorkoutRuntimeCardioBlock

    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }

    var layoutIdentity: LayoutIdentity {
        LayoutIdentity(
            id: id,
            role: role,
            state: state,
            actionLayout: actionLayout,
            reservedTimerWidth: reservedTimerWidth
        )
    }

    static func make(
        activity: ActiveWorkoutRuntimeCardioBlock,
        at date: Date = .now
    ) -> Self {
        let state: State
        let actionLayout: [Action]

        if activity.isCompleted {
            state = .completed
            actionLayout = [.editResult]
        } else {
            switch activity.timerState {
            case .idle:
                state = .idle
                actionLayout = [.start]
            case .running:
                state = .running
                actionLayout = [.pause, .finish]
            case .paused:
                state = .paused
                actionLayout = [.resume, .finish]
            }
        }

        return Self(
            id: activity.id,
            role: activity.role,
            activityName: activity.exerciseNameSnapshot,
            descriptor: descriptor(for: activity),
            goalText: goalText(for: activity),
            resultText: resultText(for: activity),
            state: state,
            actionLayout: actionLayout,
            reservedTimerWidth: timerWidth,
            elapsedText: elapsedText(for: activity, at: date),
            timerActivity: activity
        )
    }

    func elapsedText(at date: Date) -> String {
        Self.elapsedText(for: timerActivity, at: date)
    }

    private static func elapsedText(
        for activity: ActiveWorkoutRuntimeCardioBlock,
        at date: Date
    ) -> String {
        durationText(
            seconds: WorkoutCardioTimerCoordinator.elapsedSeconds(for: activity, at: date),
            alwaysShowsHours: true
        )
    }

    private static func descriptor(for activity: ActiveWorkoutRuntimeCardioBlock) -> String? {
        let muscleSummary = activity.muscleSummarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        let category = activity.categorySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? nil : category
    }

    private static func goalText(for activity: ActiveWorkoutRuntimeCardioBlock) -> String {
        switch activity.goalKind {
        case .time:
            return "Goal · \(durationText(seconds: activity.targetDurationSeconds, alwaysShowsHours: false))"
        case .distance:
            guard let meters = activity.targetDistanceMeters, meters > 0 else {
                return "Distance goal"
            }
            let unit = activity.preferredDistanceUnit ?? .kilometers
            return "Goal · \(distanceText(meters: meters, unit: unit))"
        case .open:
            return "No target"
        }
    }

    private static func resultText(for activity: ActiveWorkoutRuntimeCardioBlock) -> String? {
        guard activity.isCompleted else { return nil }
        var parts: [String] = []

        if let duration = activity.actualDurationSeconds, duration > 0 {
            parts.append(durationText(seconds: duration, alwaysShowsHours: false))
        }
        if let distance = activity.actualDistanceMeters, distance > 0 {
            parts.append(
                distanceText(
                    meters: distance,
                    unit: activity.preferredDistanceUnit ?? .kilometers
                )
            )
        }

        return parts.isEmpty ? "Completed" : parts.joined(separator: " · ")
    }

    private static func durationText(seconds: Int, alwaysShowsHours: Bool) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60

        if alwaysShowsHours || hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func distanceText(
        meters: Double,
        unit: WorkoutDistanceUnit
    ) -> String {
        let value = unit.value(fromMeters: meters)
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit.symbol)"
    }
}

nonisolated enum ActiveWorkoutCardioQuickAddPolicy {
    static func defaultRole(hasStrengthExercises: Bool) -> WorkoutCardioRole {
        hasStrengthExercises ? .finisher : .main
    }
}

nonisolated enum ActiveWorkoutCardioRemovalPolicy {
    static func requiresConfirmation(activity: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        activity.actualDurationSeconds != nil
            || activity.actualDistanceMeters != nil
            || activity.isCompleted
            || activity.timerAccumulatedSeconds > 0
            || activity.timerState != .idle
    }
}

nonisolated struct ActiveWorkoutPendingCardioResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityName: String
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit?
    let inclinePercent: Double?
    let resistanceLevel: Double?
    let notes: String
    let trackingProfile: WorkoutCardioTrackingProfile?
    let isCompleted: Bool

    static func make(activity: ActiveWorkoutRuntimeCardioBlock) -> Self {
        Self(
            id: activity.id,
            activityName: activity.exerciseNameSnapshot,
            actualDurationSeconds: activity.actualDurationSeconds,
            actualDistanceMeters: activity.actualDistanceMeters,
            preferredDistanceUnit: activity.preferredDistanceUnit,
            inclinePercent: activity.inclinePercent,
            resistanceLevel: activity.resistanceLevel,
            notes: activity.cardioNotes,
            trackingProfile: activity.trackingProfile,
            isCompleted: activity.isCompleted
        )
    }
}

struct ActiveWorkoutCardioActivityCard: View {
    let presentation: ActiveWorkoutCardioPresentation
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void
    let onEditResult: () -> Void
    let onEditPlan: () -> Void
    let onChangeExercise: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.role.title.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(roleTint)

                    Text(presentation.activityName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(presentation.state == .completed ? WGJTheme.success : WGJTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let descriptor = presentation.descriptor {
                        Text(descriptor)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Menu {
                    Button("Edit Plan", action: onEditPlan)
                    Button("Change Exercise", action: onChangeExercise)
                        .disabled(presentation.state != .idle)
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(roleTint)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Cardio Actions")
                .accessibilityIdentifier("active-workout-cardio-\(presentation.id)-actions-button")
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.resultText ?? presentation.goalText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(presentation.state == .completed ? WGJTheme.success : WGJTheme.textSecondary)

                    if presentation.isRunning || presentation.isPaused {
                        timerDisplay
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                stateBadge
            }

            actionControls
                .frame(minHeight: 44)
        }
        .padding(16)
        .background { cardBackground }
        .wgjCardContainer(strong: true)
        .overlay { cardOverlay }
        .accessibilityIdentifier("active-workout-cardio-\(presentation.id)-card")
    }

    @ViewBuilder
    private var timerDisplay: some View {
        if presentation.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                timerText(presentation.elapsedText(at: context.date))
            }
        } else {
            timerText(presentation.elapsedText)
        }
    }

    private func timerText(_ text: String) -> some View {
        Text(text)
            .font(.title3.monospacedDigit().weight(.bold))
            .foregroundStyle(roleTint)
            .frame(minWidth: CGFloat(presentation.reservedTimerWidth), alignment: .leading)
            .accessibilityLabel("Elapsed time \(text)")
    }

    private var actionControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
            }

            VStack(spacing: 10) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(presentation.actionLayout, id: \.self) { action in
            actionButton(action)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: ActiveWorkoutCardioPresentation.Action) -> some View {
        let button = Button(actionTitle(for: action), action: callback(for: action))
            .accessibilityLabel("\(actionTitle(for: action)) \(presentation.activityName)")
            .accessibilityIdentifier("active-workout-cardio-\(presentation.id)-\(action.rawValue)-button")

        if action == .pause {
            button.buttonStyle(WGJGhostButtonStyle())
        } else {
            button.buttonStyle(WGJPrimaryButtonStyle())
        }
    }

    private func actionTitle(for action: ActiveWorkoutCardioPresentation.Action) -> String {
        switch action {
        case .start:
            return "Start"
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .finish:
            return "Finish"
        case .editResult:
            return "Edit Result"
        }
    }

    private func callback(for action: ActiveWorkoutCardioPresentation.Action) -> () -> Void {
        switch action {
        case .start:
            return onStart
        case .pause:
            return onPause
        case .resume:
            return onResume
        case .finish:
            return onFinish
        case .editResult:
            return onEditResult
        }
    }

    private var stateBadge: some View {
        Text(stateTitle.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(roleTint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(roleTint.opacity(0.12))
            )
    }

    private var stateTitle: String {
        switch presentation.state {
        case .idle:
            return "Ready"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .completed:
            return "Complete"
        }
    }

    private var roleTint: Color {
        if presentation.state == .completed {
            return WGJTheme.success
        }

        switch presentation.role {
        case .warmUp:
            return WGJTheme.accentBlue
        case .main:
            return WGJTheme.accentCyan
        case .finisher:
            return WGJTheme.accentGold
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if presentation.state == .completed {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .fill(WGJTheme.success.opacity(0.10))
        }
    }

    @ViewBuilder
    private var cardOverlay: some View {
        if presentation.state == .completed {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .stroke(WGJTheme.success.opacity(0.22), lineWidth: 1.2)
        }
    }
}

struct ActiveWorkoutPendingCardioResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let result: ActiveWorkoutPendingCardioResult

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                WGJSectionHeader(
                    result.activityName,
                    subtitle: "Your cardio result is saved."
                )

                VStack(alignment: .leading, spacing: 12) {
                    if let duration = result.actualDurationSeconds {
                        resultRow("Duration", value: WorkoutCardioDurationFormatter.text(seconds: duration))
                    }

                    if let distance = result.actualDistanceMeters {
                        let unit = result.preferredDistanceUnit ?? .kilometers
                        let value = unit.value(fromMeters: distance)
                            .formatted(.number.precision(.fractionLength(0...2)))
                        resultRow("Distance", value: "\(value) \(unit.symbol)")
                    }

                    if result.actualDurationSeconds == nil && result.actualDistanceMeters == nil {
                        Text("No measured result yet.")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .padding(16)
                .wgjCardContainer(strong: true)

                Spacer()
            }
            .padding(16)
            .wgjScreenBackground()
            .navigationTitle("Cardio Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .wgjSheetSurface()
    }

    private func resultRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(WGJTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(WGJTheme.textPrimary)
        }
    }
}
