import AudioToolbox
import CloudKit
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

nonisolated struct AppReviewPolicy {
    let brosEnabled: Bool
    let syncBrosAvatars: Bool
}

nonisolated enum CloudSyncEventType: Equatable, Sendable {
    case setup
    case `import`
    case export
    case unknown

    var label: String {
        switch self {
        case .setup:
            return "Setup"
        case .import:
            return "Import"
        case .export:
            return "Export"
        case .unknown:
            return "Unknown"
        }
    }
}

nonisolated enum CloudSyncEventStatus: Equatable, Sendable {
    case running
    case succeeded
    case failed

    var label: String {
        switch self {
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }
}

nonisolated struct CloudSyncErrorSnapshot: Equatable, Sendable {
    let domain: String
    let code: Int
    let underlyingDomain: String?
    let underlyingCode: Int?
    let description: String
}

nonisolated struct CloudSyncEventSummary: Equatable, Sendable {
    let type: CloudSyncEventType
    let status: CloudSyncEventStatus
    let storeIdentifier: String
    let startedAt: Date
    let endedAt: Date?
    let error: CloudSyncErrorSnapshot?

    var typeLabel: String { type.label }
    var statusLabel: String { status.label }
    var errorDescription: String? { error?.description }
}

nonisolated enum CloudKitContainerAvailabilityError: Error, Sendable {
    case unavailable
}

nonisolated enum AppEnvironment: String {
    case development
    case production

    var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }

    var cloudKitConsoleEnvironmentName: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }
}

nonisolated enum AppRuntimeConfig {
    private enum InfoKey {
        static let appEnvironment = "WGJAppEnvironment"
        static let cloudKitContainerIdentifier = "WGJCloudKitContainerIdentifier"
    }

    static let supportEmail = "support@wegojim.app"
    static let privacyPolicyURL: URL? = nil
    static let supportURL: URL? = nil
    static let reviewPolicy = AppReviewPolicy(
        brosEnabled: true,
        syncBrosAvatars: true
    )

    static var appEnvironment: AppEnvironment {
        guard let rawValue = infoString(for: InfoKey.appEnvironment)?.lowercased(),
              let environment = AppEnvironment(rawValue: rawValue)
        else {
            return .production
        }

        return environment
    }

    static var cloudKitConsoleEnvironmentName: String {
        appEnvironment.cloudKitConsoleEnvironmentName
    }

    static var cloudKitContainerIdentifier: String {
        normalizedInfoString(for: InfoKey.cloudKitContainerIdentifier) ?? "iCloud.se.highball.WeGoJim"
    }

    static var isRunningTests: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.environment["XCTestConfigurationFilePath"] != nil
            || processInfo.arguments.contains("UITEST_IN_MEMORY_STORE")
    }

    static var canUseConfiguredCloudKitContainer: Bool {
        guard !isRunningTests else {
            return false
        }

        // `url(forUbiquityContainerIdentifier:)` checks iCloud Drive containers, not CloudKit-only setup.
        return !cloudKitContainerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func makeCloudKitContainer() -> CKContainer? {
        guard canUseConfiguredCloudKitContainer else {
            return nil
        }

        return CKContainer(identifier: cloudKitContainerIdentifier)
    }

    private static func infoString(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func normalizedInfoString(for key: String) -> String? {
        guard let value = infoString(for: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }
}

@MainActor
@Observable
final class AppRuntimeState {
    static let shared = AppRuntimeState()

    var cloudSyncEnabled = false
    var cloudSyncErrorDescription: String?
    var latestCloudSyncEvent: CloudSyncEventSummary?
    var userDataSyncStatus = UserDataSyncStatusSnapshot.localOnly(reason: nil)
    var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive

    @ObservationIgnored private var hasResolvedRuntimeCloudAvailability = false
    @ObservationIgnored private var isRefreshingRuntimeCloudAvailability = false

    private init() { }

    func updateCloudState(isEnabled: Bool, errorDescription: String?) {
        cloudSyncEnabled = isEnabled
        cloudSyncErrorDescription = errorDescription
        hasResolvedRuntimeCloudAvailability = false
    }

    func updateCloudRuntimeError(_ errorDescription: String?) {
        cloudSyncErrorDescription = errorDescription
    }

    func updateLatestCloudSyncEvent(_ summary: CloudSyncEventSummary?) {
        latestCloudSyncEvent = summary
    }

    func updateUserDataSyncStatus(_ snapshot: UserDataSyncStatusSnapshot) {
        userDataSyncStatus = snapshot
    }

    func updateWorkoutNotificationStyle(_ style: WorkoutNotificationStyle) {
        workoutNotificationStyle = style
    }

    func refreshCloudAvailabilityIfNeeded(
        force: Bool = false,
        accountService: (any AccountStatusProviding)? = nil
    ) {
        guard cloudSyncEnabled else { return }
        guard force || !hasResolvedRuntimeCloudAvailability else { return }
        guard !isRefreshingRuntimeCloudAvailability else { return }

        isRefreshingRuntimeCloudAvailability = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRefreshingRuntimeCloudAvailability = false
                self.hasResolvedRuntimeCloudAvailability = true
            }

            let status = await (accountService ?? AccountStatusService()).fetchAccountStatus()
            switch status {
            case .checking:
                break
            case .available:
                self.updateCloudRuntimeError(nil)
            case .unavailable(let reason):
                self.updateCloudRuntimeError(Self.runtimeErrorDescription(for: reason))
            }
        }
    }

    func isBrosCloudAvailable(cloudContainerAvailable: Bool) -> Bool {
        AppRuntimeConfig.reviewPolicy.brosEnabled
            && cloudSyncEnabled
            && cloudSyncErrorDescription == nil
            && cloudContainerAvailable
    }

    var isBrosCloudAvailable: Bool {
        isBrosCloudAvailable(cloudContainerAvailable: AppRuntimeConfig.canUseConfiguredCloudKitContainer)
    }

    private static func runtimeErrorDescription(for reason: AccountUnavailableReason) -> String {
        switch reason {
        case .noAccount:
            return "No iCloud account is signed in on this device. Cloud features are unavailable for this session."
        case .restricted:
            return "iCloud is restricted on this device. Cloud features are unavailable for this session."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable on this device. Cloud features are temporarily unavailable."
        case .unknown:
            return "WGJ could not verify iCloud availability right now. Cloud features are temporarily unavailable."
        }
    }
}

extension WorkoutNotificationStyle {
    var notificationInterruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .standard:
            return .active
        case .timeSensitive:
            return .timeSensitive
        }
    }

    // Foreground rest timer feedback stays haptic-only so external audio keeps playing.
    var foregroundRestTimerAlertPolicy: RestTimerForegroundAlertPolicy {
        switch self {
        case .standard:
            return RestTimerForegroundAlertPolicy(
                playsSound: false,
                usesEnhancedHaptics: false
            )
        case .timeSensitive:
            return RestTimerForegroundAlertPolicy(
                playsSound: false,
                usesEnhancedHaptics: true
            )
        }
    }
}

struct RestTimerForegroundAlertPolicy: Equatable {
    let playsSound: Bool
    let usesEnhancedHaptics: Bool
}

struct RestTimerNotificationDescriptor: Equatable {
    let title: String
    let subtitle: String
    let body: String
    let usesDefaultSound: Bool
    let interruptionLevel: UNNotificationInterruptionLevel
}

extension Notification.Name {
    static let wgjDidDeleteAllUserData = Notification.Name("wgj.didDeleteAllUserData")
}

nonisolated enum AppPhase {
    case splash
    case login
    case main
}

nonisolated enum AppMainTab: Hashable {
    case profile
    case history
    case startWorkout
    case exercises
    case bros
}

nonisolated struct PendingTemplateFileOpen: Equatable, Identifiable {
    let requestID: UUID
    let fileURL: URL

    init(fileURL: URL, requestID: UUID = UUID()) {
        self.requestID = requestID
        self.fileURL = fileURL
    }

    var id: UUID { requestID }
}

@MainActor
@Observable
final class AppTabState {
    var selectedTab: AppMainTab = .startWorkout
}

@MainActor
@Observable
final class TemplateFileOpenState {
    var pendingRequest: PendingTemplateFileOpen?

    @discardableResult
    func enqueueIfSupported(url: URL) -> Bool {
        guard Self.supports(url: url) else {
            return false
        }

        pendingRequest = PendingTemplateFileOpen(fileURL: url)
        return true
    }

    func routePendingRequestIfNeeded(appPhase: AppPhase, tabState: AppTabState) {
        guard appPhase == .main, pendingRequest != nil else {
            return
        }

        tabState.selectedTab = .startWorkout
    }

    func clear(requestID: UUID) {
        guard pendingRequest?.requestID == requestID else {
            return
        }

        pendingRequest = nil
    }

    static func supports(url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return url.pathExtension.localizedCaseInsensitiveCompare(
            TemplateTransferFileFormat.filenameExtension
        ) == .orderedSame
    }
}

@MainActor
@Observable
final class AppNotificationRouter {
    static let shared = AppNotificationRouter()

    var requestedTab: AppMainTab?
    var routeRequestID: UUID?
    var brosRefreshRequestID: UUID?

    private init() { }

    func openBros() {
        requestedTab = .bros
        routeRequestID = UUID()
        brosRefreshRequestID = UUID()
    }

    func consumeRequestedTab() {
        requestedTab = nil
    }
}

struct WorkoutCompletionPresentation: Identifiable, Equatable {
    let sessionID: UUID

    var id: UUID { sessionID }
}

enum ActiveWorkoutScrollTarget: Hashable {
    case header
    case preWorkoutCardio
    case exercise(UUID)
    case postWorkoutCardio
    case cancelSection
}

@MainActor
@Observable
final class WorkoutCompletionPresentationState {
    var presentedWorkout: WorkoutCompletionPresentation?
    @ObservationIgnored private var queuedWorkout: WorkoutCompletionPresentation?

    func present(sessionID: UUID) {
        queuedWorkout = nil
        presentedWorkout = WorkoutCompletionPresentation(sessionID: sessionID)
    }

    func queueAfterActiveWorkoutDismiss(sessionID: UUID) {
        queuedWorkout = WorkoutCompletionPresentation(sessionID: sessionID)
    }

    func presentQueuedIfNeeded() {
        guard presentedWorkout == nil, let queuedWorkout else { return }
        presentedWorkout = queuedWorkout
        self.queuedWorkout = nil
    }

    func dismiss() {
        presentedWorkout = nil
    }
}

@MainActor
@Observable
final class ActiveWorkoutPresentationState {
    var activeSessionID: UUID?
    var isActiveWorkoutPresented = false
    var isActiveWorkoutStripCollapsed = false
    var scrollTarget: ActiveWorkoutScrollTarget?

    func present(sessionID: UUID) {
        if activeSessionID != sessionID {
            scrollTarget = nil
        }
        guard
            activeSessionID != sessionID
                || !isActiveWorkoutPresented
                || isActiveWorkoutStripCollapsed
        else {
            return
        }

        activeSessionID = sessionID
        isActiveWorkoutPresented = true
        isActiveWorkoutStripCollapsed = false
    }

    func collapseActiveWorkout() {
        guard activeSessionID != nil else {
            clearPresentation()
            return
        }
        guard isActiveWorkoutPresented || !isActiveWorkoutStripCollapsed else {
            return
        }
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = true
    }

    func clearPresentation() {
        guard activeSessionID != nil || isActiveWorkoutPresented || isActiveWorkoutStripCollapsed else {
            return
        }
        activeSessionID = nil
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = false
        scrollTarget = nil
    }

    func clearActiveWorkout(restTimerState: RestTimerState? = nil) {
        clearPresentation()
        restTimerState?.clearRestTimer()
        restTimerState?.dismissRestTimerPopup()
    }

    func restoreActiveSessionIfMissing(modelContext: ModelContext) {
        guard activeSessionID == nil else { return }
        restoreActiveSessionIfNeeded(modelContext: modelContext)
    }

    func restoreActiveSessionIfNeeded(modelContext: ModelContext) {
        let repository = ActiveWorkoutDraftRepository(modelContext: modelContext)
        do {
            if let active = try repository.activeSession() {
                activeSessionID = active.id
                isActiveWorkoutStripCollapsed = !isActiveWorkoutPresented
            } else {
                clearPresentation()
            }
        } catch {
            clearPresentation()
        }
    }
}

@MainActor
@Observable
final class RestTimerState {
    var restTimerEndsAt: Date?
    var restTimerExerciseName: String?
    var restTimerSetLabel: String?
    var restTimerSourceSetID: UUID?
    var restTimerPopup: RestTimerPopup?

    @ObservationIgnored private var restTimerPopupDismissTask: Task<Void, Never>?

    func startRestTimer(seconds: Int, exerciseName: String, setLabel: String?, sourceSetID: UUID) {
        let normalized = max(0, min(3600, seconds))
        guard normalized > 0 else {
            clearRestTimer()
            return
        }

        dismissRestTimerPopup()
        restTimerEndsAt = Date().addingTimeInterval(TimeInterval(normalized))
        restTimerExerciseName = exerciseName
        restTimerSetLabel = setLabel
        restTimerSourceSetID = sourceSetID
        RestTimerNotificationManager.shared.scheduleRestTimer(
            seconds: normalized,
            style: AppRuntimeState.shared.workoutNotificationStyle
        )
    }

    func clearRestTimer(sourceSetID: UUID? = nil, cancelNotification: Bool = true) {
        if let sourceSetID, restTimerSourceSetID != sourceSetID {
            return
        }

        restTimerEndsAt = nil
        restTimerExerciseName = nil
        restTimerSetLabel = nil
        restTimerSourceSetID = nil
        if cancelNotification {
            RestTimerNotificationManager.shared.cancelRestTimerNotification()
        }
    }

    func restTimerRemaining(at date: Date = .now) -> Int? {
        guard let restTimerEndsAt else { return nil }
        let remaining = Int(ceil(restTimerEndsAt.timeIntervalSince(date)))
        return remaining > 0 ? remaining : nil
    }

    func restTimerContextLabel() -> String? {
        switch (restTimerExerciseName, restTimerSetLabel) {
        case let (exerciseName?, setLabel?):
            return "\(exerciseName) · \(setLabel)"
        case let (exerciseName?, nil):
            return exerciseName
        case let (nil, setLabel?):
            return setLabel
        case (nil, nil):
            return nil
        }
    }

    func handleRestTimerExpirationIfNeeded(at date: Date = .now) {
        guard let restTimerEndsAt, restTimerEndsAt <= date else { return }

        let exerciseName = restTimerExerciseName
        let setLabel = restTimerSetLabel
        clearRestTimer(cancelNotification: false)
        WorkoutFeedbackCenter.shared.restTimerCompleted(style: AppRuntimeState.shared.workoutNotificationStyle)
        showRestTimerPopup(exerciseName: exerciseName, setLabel: setLabel)
    }

    func clearExpiredRestTimerIfNeeded(at date: Date = .now) {
        guard let restTimerEndsAt, restTimerEndsAt <= date else { return }
        clearRestTimer(cancelNotification: false)
    }

    func dismissRestTimerPopup() {
        restTimerPopupDismissTask?.cancel()
        restTimerPopupDismissTask = nil
        restTimerPopup = nil
    }

    private func showRestTimerPopup(exerciseName: String?, setLabel: String?) {
        restTimerPopupDismissTask?.cancel()

        let message: String?
        switch (exerciseName, setLabel) {
        case let (exerciseName?, setLabel?):
            message = "\(exerciseName) · \(setLabel)"
        case let (exerciseName?, nil):
            message = exerciseName
        case let (nil, setLabel?):
            message = setLabel
        case (nil, nil):
            message = nil
        }

        let popup = RestTimerPopup(title: "Rest complete", message: message)
        restTimerPopup = popup

        restTimerPopupDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled, restTimerPopup?.id == popup.id else { return }
            restTimerPopup = nil
            restTimerPopupDismissTask = nil
        }
    }
}

struct RestTimerPopup: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String?
}

@MainActor
final class WorkoutFeedbackCenter {
    static let shared = WorkoutFeedbackCenter()

    private var hapticPatternTask: Task<Void, Never>?
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)

    private init() {
        prepareGenerators()
    }

    func setCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .impact(style: .heavy, intensity: 1.0)),
            HapticStep(delay: .milliseconds(70), command: .impact(style: .rigid, intensity: 0.88)),
        ])
    }

    func exerciseCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .notification(.success)),
            HapticStep(delay: .milliseconds(70), command: .impact(style: .heavy, intensity: 0.96)),
        ])
    }

    func workoutCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .notification(.success)),
            HapticStep(delay: .milliseconds(75), command: .impact(style: .heavy, intensity: 1.0)),
            HapticStep(delay: .milliseconds(95), command: .impact(style: .rigid, intensity: 0.9)),
        ])
    }

    func restTimerCompleted(style: WorkoutNotificationStyle) {
        guard !AppRuntimeConfig.isRunningTests else { return }
        let policy = style.foregroundRestTimerAlertPolicy
        if policy.usesEnhancedHaptics {
            runHapticPattern([
                HapticStep(delay: .zero, command: .vibrate),
                HapticStep(delay: .zero, command: .notification(.warning)),
                HapticStep(delay: .milliseconds(140), command: .impact(style: .heavy, intensity: 1.0)),
                HapticStep(delay: .milliseconds(90), command: .impact(style: .rigid, intensity: 0.9)),
                HapticStep(delay: .milliseconds(100), command: .vibrate),
            ])
        } else {
            runHapticPattern([
                HapticStep(delay: .zero, command: .notification(.warning)),
                HapticStep(delay: .milliseconds(90), command: .impact(style: .heavy, intensity: 0.92)),
            ])
        }
    }

    private func runHapticPattern(_ steps: [HapticStep]) {
        hapticPatternTask?.cancel()
        hapticPatternTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for step in steps {
                if step.delay > .zero {
                    try? await Task.sleep(for: step.delay)
                }
                guard !Task.isCancelled else { return }
                self.perform(step.command)
            }

            self.hapticPatternTask = nil
            self.prepareGenerators()
        }
    }

    private func perform(_ command: HapticCommand) {
        switch command {
        case let .notification(type):
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
        case let .impact(style, intensity):
            let generator = impactGenerator(for: style)
            generator.prepare()
            generator.impactOccurred(intensity: intensity)
        case .vibrate:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .medium:
            return mediumImpactGenerator
        case .heavy:
            return heavyImpactGenerator
        case .rigid:
            return rigidImpactGenerator
        case .light, .soft:
            return UIImpactFeedbackGenerator(style: style)
        @unknown default:
            return UIImpactFeedbackGenerator(style: style)
        }
    }

    private func prepareGenerators() {
        notificationGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
    }

    private struct HapticStep {
        let delay: Duration
        let command: HapticCommand
    }

    private enum HapticCommand {
        case notification(UINotificationFeedbackGenerator.FeedbackType)
        case impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)
        case vibrate
    }
}

private struct WGJTabActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct WGJActiveWorkoutOverlayBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var isTabActive: Bool {
        get { self[WGJTabActiveKey.self] }
        set { self[WGJTabActiveKey.self] = newValue }
    }

    var activeWorkoutOverlayBottomInset: CGFloat {
        get { self[WGJActiveWorkoutOverlayBottomInsetKey.self] }
        set { self[WGJActiveWorkoutOverlayBottomInsetKey.self] = newValue }
    }
}

@MainActor
final class RestTimerNotificationManager {
    static let shared = RestTimerNotificationManager()

    private let notificationIdentifierPrefix = AppNotificationManager.restTimerIdentifierPrefix
    private var schedulingTask: Task<Void, Never>?
    private var schedulingGeneration = 0
    private var currentNotificationIdentifier: String?

    private init() { }

    func configureNotifications() {
        AppNotificationManager.shared.configureNotifications()
    }

    func scheduleRestTimer(
        seconds: Int,
        style: WorkoutNotificationStyle
    ) {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        clearCurrentRestTimerNotifications()
        let notificationIdentifier = "\(notificationIdentifierPrefix).\(generation)"
        currentNotificationIdentifier = notificationIdentifier
        schedulingTask?.cancel()

        schedulingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            let isAuthorized = await AppNotificationManager.shared.requestAlertAuthorizationIfNeeded()

            guard isAuthorized else {
                if self.currentNotificationIdentifier == notificationIdentifier {
                    self.currentNotificationIdentifier = nil
                }
                self.schedulingTask = nil
                return
            }
            guard !Task.isCancelled, generation == self.schedulingGeneration else { return }

            let descriptor = Self.notificationDescriptor(style: style)
            let content = Self.makeNotificationContent(from: descriptor)

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(1, seconds)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
            if generation != self.schedulingGeneration || self.currentNotificationIdentifier != notificationIdentifier {
                self.clearRestTimerNotifications(
                    using: center,
                    identifier: notificationIdentifier
                )
            }
            if self.currentNotificationIdentifier == notificationIdentifier {
                self.schedulingTask = nil
            }
        }
    }

    func cancelRestTimerNotification() {
        schedulingGeneration += 1
        schedulingTask?.cancel()
        schedulingTask = nil
        clearCurrentRestTimerNotifications()
    }

    static func notificationDescriptor(
        style: WorkoutNotificationStyle
    ) -> RestTimerNotificationDescriptor {
        RestTimerNotificationDescriptor(
            title: "Rest complete",
            subtitle: "",
            body: "Time for your next set.",
            usesDefaultSound: true,
            interruptionLevel: style.notificationInterruptionLevel
        )
    }

    private static func makeNotificationContent(from descriptor: RestTimerNotificationDescriptor) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.subtitle = descriptor.subtitle
        content.body = descriptor.body
        content.sound = descriptor.usesDefaultSound ? .default : nil
        content.interruptionLevel = descriptor.interruptionLevel
        return content
    }

    private func clearCurrentRestTimerNotifications() {
        guard let currentNotificationIdentifier else { return }
        let center = UNUserNotificationCenter.current()
        clearRestTimerNotifications(
            using: center,
            identifier: currentNotificationIdentifier
        )
        self.currentNotificationIdentifier = nil
    }

    private func clearRestTimerNotifications(
        using center: UNUserNotificationCenter,
        identifier: String
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

final class AppNotificationManager {
    static let shared = AppNotificationManager()

    nonisolated static let brosReactionCategoryIdentifier = "wgj.bros.reaction"
    static let restTimerIdentifierPrefix = "wgj.activeWorkout.restTimer"

    private init() { }

    @MainActor
    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WGJNotificationCenterDelegate.shared
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.brosReactionCategoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    @MainActor
    func requestAlertAuthorizationIfNeeded() async -> Bool {
        guard !AppRuntimeConfig.isRunningTests else {
            return false
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    @MainActor
    func enableRemoteReactionNotifications() async -> Bool {
        let isAuthorized = await requestAlertAuthorizationIfNeeded()
        guard isAuthorized else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    func isRestTimerNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix(Self.restTimerIdentifierPrefix)
    }

    func isBrosReactionNotification(_ notification: UNNotification) -> Bool {
        notification.request.content.categoryIdentifier == Self.brosReactionCategoryIdentifier
    }
}

final class WGJNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WGJNotificationCenterDelegate()

    static func presentationOptions(
        isRestTimerNotification: Bool,
        isBrosReactionNotification: Bool
    ) -> UNNotificationPresentationOptions {
        if isRestTimerNotification {
            return []
        }

        if isBrosReactionNotification {
            return [.banner, .list, .sound, .badge]
        }

        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            Self.presentationOptions(
                isRestTimerNotification: AppNotificationManager.shared.isRestTimerNotification(notification),
                isBrosReactionNotification: AppNotificationManager.shared.isBrosReactionNotification(notification)
            )
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              AppNotificationManager.shared.isBrosReactionNotification(response.notification)
        else {
            completionHandler()
            return
        }

        Task { @MainActor in
            AppNotificationRouter.shared.openBros()
            completionHandler()
        }
    }
}

private struct CloudSyncEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct CloudSyncErrorDescriptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct UserDataSyncStatusKey: EnvironmentKey {
    static let defaultValue = UserDataSyncStatusSnapshot.localOnly(reason: nil)
}

extension EnvironmentValues {
    var cloudSyncEnabled: Bool {
        get { self[CloudSyncEnabledKey.self] }
        set { self[CloudSyncEnabledKey.self] = newValue }
    }

    var cloudSyncErrorDescription: String? {
        get { self[CloudSyncErrorDescriptionKey.self] }
        set { self[CloudSyncErrorDescriptionKey.self] = newValue }
    }

    var userDataSyncStatus: UserDataSyncStatusSnapshot {
        get { self[UserDataSyncStatusKey.self] }
        set { self[UserDataSyncStatusKey.self] = newValue }
    }
}
