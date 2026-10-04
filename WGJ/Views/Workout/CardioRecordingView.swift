import SwiftUI
import UIKit

struct CardioRecordingRequest: Identifiable {
    let id: UUID
}

struct CardioRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var controller: CardioRecordingController
    @State private var isWorking = false
    @State private var showingFinishConfirmation = false
    @State private var showingCancelConfirmation = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 64
    let onEditResult: (Bool, Double?) -> Void
    let onSaveWorkout: () -> Void
    let isEmbedded: Bool
    let onMinimize: (() -> Void)?
    let onCancelWorkout: (() -> Void)?

    init(activityID: UUID, coordinator: ActiveWorkoutCoordinator, isEmbedded: Bool = false,
         onMinimize: (() -> Void)? = nil,
         onCancelWorkout: (() -> Void)? = nil,
         onSaveWorkout: @escaping () -> Void, onEditResult: @escaping (Bool, Double?) -> Void) {
        _controller = State(initialValue: CardioRecordingController(activityID: activityID, coordinator: coordinator))
        self.onEditResult = onEditResult
        self.onSaveWorkout = onSaveWorkout
        self.isEmbedded = isEmbedded
        self.onMinimize = onMinimize
        self.onCancelWorkout = onCancelWorkout
    }

    var body: some View {
        Group {
            if isEmbedded {
                recordingContent
            } else {
                NavigationStack { recordingContent }
            }
        }
        .wgjSheetSurface()
    }

    private var recordingContent: some View {
        ScrollView {
            if let activity = controller.activity {
                VStack(spacing: 18) {
                    sessionHeading(activity)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        stats(activity, at: context.date)
                    }
                    routeContent(activity)
                    if let error = controller.errorMessage ?? controller.recorder.persistenceError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(WGJTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
        }
        .wgjScreenBackground()
        .safeAreaInset(edge: .bottom) {
            if let activity = controller.activity {
                controls(activity)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(WGJTheme.bgBase)
            }
        }
        .navigationTitle(controller.activity?.isCompleted == true ? "Activity Summary" : "Record Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onMinimize { onMinimize() } else { closePresentation() }
                } label: {
                    if !isEmbedded && controller.activity?.isCompleted == true {
                        Text("Done")
                    } else {
                        Label("Minimize", systemImage: "chevron.down")
                    }
                }
                .accessibilityIdentifier("cardio-recording-minimize-button")
            }
            if isEmbedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Cancel Workout", systemImage: "xmark.circle", role: .destructive) {
                            showingCancelConfirmation = true
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Activity options")
                    .accessibilityIdentifier("cardio-recording-options-button")
                }
            }
        }
        .task { await controller.prepare() }
        .alert("Cancel workout?", isPresented: $showingCancelConfirmation) {
            Button("Keep Recording", role: .cancel) { }
            Button("Cancel Workout", role: .destructive) { onCancelWorkout?() }
        } message: {
            Text("This activity and its recorded route will be discarded.")
        }
    }

    private func closePresentation() {
        if !isEmbedded { dismiss() }
    }

    private func sessionHeading(_ activity: ActiveWorkoutRuntimeCardioBlock) -> some View {
        HStack(spacing: 14) {
            Image(systemName: CardioRecordingPolicy.symbol(for: activity))
                .font(.system(size: 32, weight: .medium)).foregroundStyle(WGJTheme.accentBlue)
            VStack(alignment: .leading, spacing: 5) {
                Text(activity.exerciseNameSnapshot)
                    .font(.title2.weight(.bold))
                Text(activity.isCompleted ? String(localized: "Completed") : activity.timerState == .paused ? String(localized: "Paused") : activity.timerState == .running ? String(localized: "In progress") : String(localized: "Ready when you are"))
                    .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cardio-recording-heading")
    }

    private func stats(_ activity: ActiveWorkoutRuntimeCardioBlock, at date: Date) -> some View {
        let seconds = activity.isCompleted
            ? activity.actualDurationSeconds ?? 0
            : WorkoutCardioTimerCoordinator.elapsedSeconds(for: activity, at: date)
        let distance = activity.isCompleted ? activity.actualDistanceMeters : controller.route?.distanceMeters
        let unit = activity.preferredDistanceUnit == .miles ? WorkoutDistanceUnit.miles : .kilometers
        let profile = WorkoutCardioTrackingProfileResolver.resolved(storedProfile: activity.trackingProfile,
            catalogExerciseUUID: activity.catalogExerciseUUID, exerciseName: activity.exerciseNameSnapshot,
            hasDistance: distance != nil)
        let metrics = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: seconds, distanceMeters: distance, displayUnit: unit, profile: profile)
        let showsSpeed = profile == .machineDistance
        let rateTitle = showsSpeed ? String(localized: "Avg. speed") : String(localized: "Avg. pace")
        let rateValue = showsSpeed
            ? metrics.averageSpeedPerHour?.formatted(.number.precision(.fractionLength(1))) ?? "—"
            : metrics.paceSecondsPerDisplayUnit.map { timeText(Int($0.rounded())) } ?? "—"
        let rateUnit = showsSpeed ? "\(unit.symbol)/h" : "/\(unit.symbol)"
        return VStack(spacing: 22) {
            metric(title: String(localized: "Time"), value: timeText(seconds), unit: nil, large: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    metric(title: String(localized: "Distance"), value: distanceText(distance, unit: unit), unit: unit.symbol)
                    metric(title: rateTitle, value: rateValue, unit: rateUnit)
                }
                VStack(spacing: 20) {
                    metric(title: String(localized: "Distance"), value: distanceText(distance, unit: unit), unit: unit.symbol)
                    metric(title: rateTitle, value: rateValue, unit: rateUnit)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("cardio-recording-stats")
    }

    private func metric(title: String, value: String, unit: String?, large: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            Text(value).font(large ? .system(size: min(timerFontSize, 88), weight: .bold, design: .rounded) : .title.weight(.semibold))
                .monospacedDigit().foregroundStyle(large ? WGJTheme.accentCyan : WGJTheme.textPrimary)
                .minimumScaleFactor(0.65).lineLimit(1)
            if let unit { Text(unit).font(.caption).foregroundStyle(WGJTheme.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: !large, vertical: false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func routeContent(_ activity: ActiveWorkoutRuntimeCardioBlock) -> some View {
        if CardioRecordingPolicy.recordsGPS(activity) {
            VStack(alignment: .leading, spacing: 12) {
                if let route = controller.route, !route.points.isEmpty {
                    CardioRouteMap(route: route, isCompleted: activity.isCompleted).frame(height: 220)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "map").font(.largeTitle).foregroundStyle(WGJTheme.accentBlue)
                        Text(activity.isCompleted ? "No route recorded" : "Your route starts here")
                            .font(.headline)
                        Text(activity.isCompleted ? "You can add the distance manually." : activity.timerState == .running ? "Your route appears here when GPS finds your location." : "Start to record your outdoor activity with GPS.")
                            .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .padding(16).wgjCardContainer()
                }
                if !activity.isCompleted {
                    Label(controller.recorder.gpsState.message, systemImage: "location")
                        .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if controller.recorder.gpsState == .denied {
                        Button("Open Location Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(WGJGhostButtonStyle())
                    } else if controller.recorder.gpsState == .approximate {
                        Button("Use Precise Location") { controller.recorder.requestPreciseLocation() }
                            .buttonStyle(WGJGhostButtonStyle())
                    }
                }
            }
        } else {
            Label("Start the timer. Add the distance from your machine when you finish.", systemImage: "figure.run.treadmill")
                .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16).wgjCardContainer()
        }
    }

    @ViewBuilder
    private func controls(_ activity: ActiveWorkoutRuntimeCardioBlock) -> some View {
        VStack(spacing: 12) {
            if activity.isCompleted {
                if controller.canSaveWorkout {
                    Button {
                        onSaveWorkout()
                        closePresentation()
                    } label: { Label("Save Workout", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .accessibilityIdentifier("cardio-recording-save-workout-button")
                }
                Button {
                    onEditResult(false, controller.recordedDistanceForResultReview)
                    closePresentation()
                } label: { Label("Edit Result", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(WGJGhostButtonStyle())
            } else {
                Button {
                    isWorking = true
                    Task {
                        if activity.timerState == .running { await controller.pause() }
                        else { await controller.startOrResume() }
                        isWorking = false
                    }
                } label: {
                    Label(activity.timerState == .running ? "Pause" : activity.timerState == .paused ? "Resume" : "Start", systemImage: activity.timerState == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("cardio-recording-primary-button")
                if activity.timerState != .idle {
                    Button { showingFinishConfirmation = true } label: {
                        Label("Finish Activity", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("cardio-recording-finish-button")
                    .confirmationDialog("Finish activity?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
                        Button("Finish Activity") { finish() }
                            .accessibilityIdentifier("cardio-recording-confirm-finish-button")
                        Button("Keep Recording", role: .cancel) { }
                    } message: {
                        Text("Save your time and distance for this activity.")
                    }
                }
            }
        }
        .disabled(isWorking || controller.isPreparing)
    }

    private func finish() {
        isWorking = true
        Task {
            if await controller.finish() {
                onEditResult(controller.canSaveWorkout, controller.recordedDistanceForResultReview)
                closePresentation()
            }
            isWorking = false
        }
    }

    private func timeText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func distanceText(_ meters: Double?, unit: WorkoutDistanceUnit) -> String {
        guard let meters else { return "—" }
        return unit.value(fromMeters: meters).formatted(.number.precision(.fractionLength(2)))
    }
}
