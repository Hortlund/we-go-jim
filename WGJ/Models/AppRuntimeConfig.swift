import CloudKit
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct AppReviewPolicy {
    let brosEnabled: Bool
    let syncBrosAvatars: Bool
}

struct CloudSyncEventSummary: Equatable {
    let typeLabel: String
    let statusLabel: String
    let storeIdentifier: String
    let startedAt: Date
    let endedAt: Date?
    let errorDescription: String?
}

enum CloudKitContainerAvailabilityError: Error {
    case unavailable
}

enum AppRuntimeConfig {
    static let supportEmail = "support@wegojim.app"
    static let privacyPolicyURL: URL? = nil
    static let supportURL: URL? = nil
    static let cloudKitContainerIdentifier = "iCloud.se.highball.WeGoJim"
    static let reviewPolicy = AppReviewPolicy(
        brosEnabled: true,
        syncBrosAvatars: true
    )

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
}

@MainActor
@Observable
final class AppRuntimeState {
    static let shared = AppRuntimeState()

    var cloudSyncEnabled = false
    var cloudSyncErrorDescription: String?
    var latestCloudSyncEvent: CloudSyncEventSummary?

    private init() { }

    func updateCloudState(isEnabled: Bool, errorDescription: String?) {
        cloudSyncEnabled = isEnabled
        cloudSyncErrorDescription = errorDescription
    }

    func updateLatestCloudSyncEvent(_ summary: CloudSyncEventSummary?) {
        latestCloudSyncEvent = summary
    }

    var isBrosCloudAvailable: Bool {
        AppRuntimeConfig.reviewPolicy.brosEnabled
            && cloudSyncEnabled
            && cloudSyncErrorDescription == nil
            && AppRuntimeConfig.canUseConfiguredCloudKitContainer
    }
}

extension Notification.Name {
    static let wgjDidDeleteAllUserData = Notification.Name("wgj.didDeleteAllUserData")
}

enum AppPhase {
    case splash
    case login
    case main
}

enum AppMainTab: Hashable {
    case profile
    case history
    case startWorkout
    case exercises
    case bros
}

struct PendingTemplateFileOpen: Equatable, Identifiable {
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

@MainActor
@Observable
final class WorkoutCompletionPresentationState {
    var presentedWorkout: WorkoutCompletionPresentation?

    func present(sessionID: UUID) {
        presentedWorkout = WorkoutCompletionPresentation(sessionID: sessionID)
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

    func present(sessionID: UUID) {
        activeSessionID = sessionID
        isActiveWorkoutPresented = true
        isActiveWorkoutStripCollapsed = false
    }

    func collapseActiveWorkout() {
        guard activeSessionID != nil else {
            clearPresentation()
            return
        }
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = true
    }

    func clearPresentation() {
        activeSessionID = nil
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = false
    }

    func clearActiveWorkout(restTimerState: RestTimerState? = nil) {
        clearPresentation()
        restTimerState?.clearRestTimer()
        restTimerState?.dismissRestTimerPopup()
    }

    func restoreActiveSessionIfNeeded(modelContext: ModelContext) {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
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

    func startRestTimer(seconds: Int, exerciseName: String, setLabel: String, sourceSetID: UUID) {
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
            exerciseName: exerciseName,
            setLabel: setLabel
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

        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.notificationOccurred(.success)

        restTimerPopupDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
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

private struct WGJTabActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isTabActive: Bool {
        get { self[WGJTabActiveKey.self] }
        set { self[WGJTabActiveKey.self] = newValue }
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

    func scheduleRestTimer(seconds: Int, exerciseName: String, setLabel: String) {
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

            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "\(exerciseName) · \(setLabel)"
            content.sound = .default

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

    static let brosReactionCategoryIdentifier = "wgj.bros.reaction"
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if AppNotificationManager.shared.isRestTimerNotification(notification) {
            completionHandler([])
            return
        }

        if AppNotificationManager.shared.isBrosReactionNotification(notification) {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        completionHandler([.banner, .list, .sound, .badge])
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

extension EnvironmentValues {
    var cloudSyncEnabled: Bool {
        get { self[CloudSyncEnabledKey.self] }
        set { self[CloudSyncEnabledKey.self] = newValue }
    }

    var cloudSyncErrorDescription: String? {
        get { self[CloudSyncErrorDescriptionKey.self] }
        set { self[CloudSyncErrorDescriptionKey.self] = newValue }
    }
}
