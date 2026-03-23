import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct AppReviewPolicy {
    let brosEnabled: Bool
    let syncBrosAvatars: Bool
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
}

@MainActor
@Observable
final class AppRuntimeState {
    static let shared = AppRuntimeState()

    var cloudSyncEnabled = false
    var cloudSyncErrorDescription: String?

    private init() { }

    func updateCloudState(isEnabled: Bool, errorDescription: String?) {
        cloudSyncEnabled = isEnabled
        cloudSyncErrorDescription = errorDescription
    }

    var isBrosCloudAvailable: Bool {
        AppRuntimeConfig.reviewPolicy.brosEnabled
    }
}

extension Notification.Name {
    static let wgjDidDeleteAllUserData = Notification.Name("wgj.didDeleteAllUserData")
}

enum AppMainTab: Hashable {
    case profile
    case history
    case startWorkout
    case exercises
    case bros
}

@MainActor
@Observable
final class ActiveWorkoutCoordinator {
    var selectedTab: AppMainTab = .startWorkout
    var activeSessionID: UUID?
    var isActiveWorkoutPresented = false
    var isActiveWorkoutStripCollapsed = false
    var restTimerEndsAt: Date?
    var restTimerExerciseName: String?
    var restTimerSetLabel: String?
    var restTimerSourceSetID: UUID?
    var restTimerPopup: RestTimerPopup?

    @ObservationIgnored private var restTimerPopupDismissTask: Task<Void, Never>?

    func present(sessionID: UUID) {
        activeSessionID = sessionID
        isActiveWorkoutPresented = true
        isActiveWorkoutStripCollapsed = false
    }

    func collapseActiveWorkout() {
        guard activeSessionID != nil else {
            clearActiveWorkout()
            return
        }
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = true
    }

    func clearActiveWorkout() {
        activeSessionID = nil
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = false
        clearRestTimer()
        dismissRestTimerPopup()
    }

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

    func restoreActiveSessionIfNeeded(modelContext: ModelContext) {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        do {
            if let active = try repository.activeSession() {
                activeSessionID = active.id
                isActiveWorkoutStripCollapsed = !isActiveWorkoutPresented
            } else {
                clearActiveWorkout()
            }
        } catch {
            clearActiveWorkout()
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

@MainActor
final class RestTimerNotificationManager {
    static let shared = RestTimerNotificationManager()

    private let notificationIdentifierPrefix = "wgj.activeWorkout.restTimer"
    private var schedulingTask: Task<Void, Never>?
    private var schedulingGeneration = 0
    private var currentNotificationIdentifier: String?

    private init() { }

    func configureNotifications() {
        UNUserNotificationCenter.current().delegate = RestTimerNotificationDelegate.shared
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
            let settings = await center.notificationSettings()
            let isAuthorized: Bool

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }

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

final class RestTimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestTimerNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
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
