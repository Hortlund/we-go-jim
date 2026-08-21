import Foundation
import OSLog
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
        case logResult
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
    let metricAccessibilityText: String
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
                actionLayout = [.start, .logResult]
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
            metricAccessibilityText: metricAccessibilityText(for: activity),
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
        if category.caseInsensitiveCompare("Cardio") == .orderedSame {
            return String(localized: "Cardio")
        }
        return category.isEmpty ? nil : category
    }

    private static func goalText(for activity: ActiveWorkoutRuntimeCardioBlock) -> String {
        switch activity.goalKind {
        case .time:
            return CardioLocalizedCopy.activeGoalSummary(
                .time,
                formattedValue: durationText(seconds: activity.targetDurationSeconds, alwaysShowsHours: false)
            )
        case .distance:
            guard let meters = activity.targetDistanceMeters, meters > 0 else {
                return CardioLocalizedCopy.activeGoalSummary(.distance, formattedValue: nil)
            }
            let unit = activity.preferredDistanceUnit ?? .kilometers
            return CardioLocalizedCopy.activeGoalSummary(
                .distance,
                formattedValue: distanceText(meters: meters, unit: unit)
            )
        case .open:
            return CardioLocalizedCopy.activeGoalSummary(.open, formattedValue: nil)
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

        guard let first = parts.first else { return String(localized: "Completed") }
        guard parts.count > 1 else { return first }
        return String(localized: "\(first) · \(parts[1])")
    }

    private static func metricAccessibilityText(
        for activity: ActiveWorkoutRuntimeCardioBlock
    ) -> String {
        if activity.isCompleted {
            var parts: [String] = []
            if let duration = activity.actualDurationSeconds, duration > 0 {
                parts.append(spokenDuration(seconds: duration))
            }
            if let distance = activity.actualDistanceMeters, distance > 0 {
                let unit = activity.preferredDistanceUnit ?? .kilometers
                parts.append(
                    WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                        distanceValueText(meters: distance, unit: unit),
                        semantic: .distance(unit)
                    )
                )
            }
            guard let first = parts.first else { return String(localized: "Completed") }
            guard parts.count > 1 else { return first }
            return String(localized: "\(first), \(parts[1])")
        }

        switch activity.goalKind {
        case .time:
            return CardioLocalizedCopy.activeGoalAccessibilitySummary(
                .time,
                formattedValue: spokenDuration(seconds: activity.targetDurationSeconds)
            )
        case .distance:
            guard let meters = activity.targetDistanceMeters, meters > 0 else {
                return CardioLocalizedCopy.activeGoalAccessibilitySummary(.distance, formattedValue: nil)
            }
            let unit = activity.preferredDistanceUnit ?? .kilometers
            let distance = WorkoutMetricAccessibilityPolicy.cardioMetricValue(
                distanceValueText(meters: meters, unit: unit),
                semantic: .distance(unit)
            )
            return CardioLocalizedCopy.activeGoalAccessibilitySummary(
                .distance,
                formattedValue: distance
            )
        case .open:
            return CardioLocalizedCopy.activeGoalAccessibilitySummary(.open, formattedValue: nil)
        }
    }

    private static func spokenDuration(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60
        if hours > 0 {
            return String(localized: "\(hours) hours, \(minutes) minutes, \(seconds) seconds")
        }
        return String(localized: "\(minutes) minutes, \(seconds) seconds")
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

    private static func distanceValueText(
        meters: Double,
        unit: WorkoutDistanceUnit
    ) -> String {
        unit.value(fromMeters: meters)
            .formatted(.number.precision(.fractionLength(0...2)))
    }
}

private extension ActiveWorkoutCardioPresentation.Action {
    nonisolated var localizedCopyAction: CardioLocalizedCopy.Action {
        switch self {
        case .start: return .start
        case .pause: return .pause
        case .resume: return .resume
        case .finish: return .finish
        case .logResult: return .logResult
        case .editResult: return .editResult
        }
    }
}

nonisolated enum ActiveWorkoutCardioQuickAddPolicy {
    static func defaultRole(hasStrengthExercises: Bool) -> WorkoutCardioRole {
        hasStrengthExercises ? .finisher : .main
    }
}

nonisolated enum ActiveWorkoutCardioInteractionPolicy {
    static func usesQuickCompletion(for role: WorkoutCardioRole) -> Bool {
        role != .main
    }
}

nonisolated enum ActiveWorkoutCardioRecordedDataPolicy {
    static func hasRecordedData(activity: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        activity.actualDurationSeconds != nil
            || activity.actualDistanceMeters != nil
            || activity.inclinePercent != nil
            || activity.resistanceLevel != nil
            || !activity.cardioNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activity.timerAccumulatedSeconds > 0
            || activity.timerSegmentStartedAt != nil
    }
}

nonisolated enum ActiveWorkoutCardioRemovalPolicy {
    static func requiresConfirmation(activity: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(activity: activity)
            || activity.isCompleted
            || activity.timerState != .idle
    }
}

nonisolated enum ActiveWorkoutCardioReplacementPolicy {
    enum Decision: Equatable, Sendable {
        case replaceDirectly
        case confirmClearingRecordedData
    }

    static var confirmationMessage: String {
        CardioLocalizedCopy.replacementWarning
    }

    static func decision(activity: ActiveWorkoutRuntimeCardioBlock) -> Decision {
        guard activity.timerState == .idle,
              !activity.isCompleted,
              !ActiveWorkoutCardioRecordedDataPolicy.hasRecordedData(activity: activity) else {
            return .confirmClearingRecordedData
        }
        return .replaceDirectly
    }
}

nonisolated enum ActiveWorkoutCardioConfirmationCopy {
    static var timerConflictTitle: String {
        CardioLocalizedCopy.confirmationTitle(.timerConflict, activityName: "")
    }

    static func replacementTitle(activityName: String) -> String {
        CardioLocalizedCopy.confirmationTitle(.replacement, activityName: activityName)
    }

    static func removalTitle(activityName: String) -> String {
        CardioLocalizedCopy.confirmationTitle(.removal, activityName: activityName)
    }

    static var timerConflictMessage: String {
        CardioLocalizedCopy.confirmationMessage(.timerConflict)
    }

    static var replacementMessage: String {
        CardioLocalizedCopy.confirmationMessage(.replacement)
    }

    static var removalMessage: String {
        CardioLocalizedCopy.confirmationMessage(.removal)
    }
}

nonisolated enum ActiveWorkoutCardioControlLayout {
    enum Direction: Equatable, Sendable {
        case adaptive
        case vertical
    }

    static func direction(isAccessibilitySize: Bool) -> Direction {
        isAccessibilitySize ? .vertical : .adaptive
    }
}

#if DEBUG
@MainActor
enum ActiveWorkoutCardioRuntimeDiagnostics {
    enum PersistenceKind: String, Equatable, Sendable {
        case timerTransition
        case activeWorkoutSnapshot
    }

    enum Event: Equatable, Sendable {
        case displayTick(activityID: UUID, elapsedText: String)
        case persistenceBoundary(activityID: UUID?, kind: PersistenceKind)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "CardioTimerDiagnostics"
    )
    private static var testObserver: ((Event) -> Void)?

    static func installTestObserver(_ observer: ((Event) -> Void)?) {
        testObserver = observer
    }

    static func recordDisplayTick(activityID: UUID, elapsedText: String) {
        let event = Event.displayTick(activityID: activityID, elapsedText: elapsedText)
        testObserver?(event)
        logger.debug(
            "cardio.timer.display.tick activity=\(activityID.uuidString, privacy: .public) elapsed=\(elapsedText, privacy: .public)"
        )
    }

    static func recordPersistenceBoundary(
        activityID: UUID?,
        kind: PersistenceKind
    ) {
        let event = Event.persistenceBoundary(activityID: activityID, kind: kind)
        testObserver?(event)
        logger.debug(
            "cardio.timer.persistence.boundary kind=\(kind.rawValue, privacy: .public) activity=\(activityID?.uuidString ?? "none", privacy: .public)"
        )
    }
}
#endif

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        .accessibilityLabel(
                            presentation.metricAccessibilityText
                        )

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
                let elapsedText = presentation.elapsedText(at: context.date)
#if DEBUG
                let _ = ActiveWorkoutCardioRuntimeDiagnostics.recordDisplayTick(
                    activityID: presentation.id,
                    elapsedText: elapsedText
                )
#endif
                timerText(elapsedText)
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
        Group {
            if ActiveWorkoutCardioControlLayout.direction(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ) == .vertical {
                VStack(spacing: 10) {
                    actionButtons
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        actionButtons
                    }

                    VStack(spacing: 10) {
                        actionButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(presentation.actionLayout, id: \.self) { action in
            actionButton(action)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: ActiveWorkoutCardioPresentation.Action) -> some View {
        let button = Button(action: callback(for: action)) {
            Label(actionTitle(for: action), systemImage: actionSystemImage(for: action))
                .frame(maxWidth: .infinity)
        }
            .accessibilityLabel(
                WorkoutMetricAccessibilityPolicy.cardioAction(
                    accessibilityAction(for: action),
                    activityName: presentation.activityName
                )
            )
            .accessibilityIdentifier("active-workout-cardio-\(presentation.id)-\(action.rawValue)-button")

        if action == .pause || action == .logResult {
            button.buttonStyle(WGJCompactGhostButtonStyle())
        } else {
            button.buttonStyle(WGJCompactPrimaryButtonStyle())
        }
    }

    private func actionSystemImage(for action: ActiveWorkoutCardioPresentation.Action) -> String {
        switch action {
        case .start, .resume:
            return "play.fill"
        case .pause:
            return "pause.fill"
        case .finish:
            return "checkmark"
        case .logResult:
            return "square.and.pencil"
        case .editResult:
            return "pencil"
        }
    }

    private func accessibilityAction(
        for action: ActiveWorkoutCardioPresentation.Action
    ) -> WorkoutMetricAccessibilityPolicy.CardioAction {
        switch action {
        case .start:
            return .start
        case .pause:
            return .pause
        case .resume:
            return .resume
        case .finish:
            return .finish
        case .logResult:
            return .logResult
        case .editResult:
            return .editResult
        }
    }

    private func actionTitle(for action: ActiveWorkoutCardioPresentation.Action) -> String {
        CardioLocalizedCopy.actionTitle(action.localizedCopyAction)
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
        case .logResult:
            return onEditResult
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
            return CardioLocalizedCopy.stateTitle(.ready)
        case .running:
            return CardioLocalizedCopy.stateTitle(.running)
        case .paused:
            return CardioLocalizedCopy.stateTitle(.paused)
        case .completed:
            return CardioLocalizedCopy.stateTitle(.complete)
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
