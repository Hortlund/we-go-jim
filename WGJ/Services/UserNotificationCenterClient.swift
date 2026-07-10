import UserNotifications

nonisolated protocol UserNotificationCenterClient: Sendable {
    func settings() async -> NotificationPermissionSnapshot
    func requestAlertAuthorization() async -> Bool
    func add(_ descriptor: UserNotificationRequestDescriptor) async throws
    func pendingRequestIdentifiers() async -> [String]
    func deliveredRequestIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async
}

actor SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func settings() async -> NotificationPermissionSnapshot {
        let settings = await center.notificationSettings()
        return NotificationPermissionSnapshot(
            authorizationStatus: settings.authorizationStatus,
            timeSensitiveSetting: settings.timeSensitiveSetting
        )
    }

    func requestAlertAuthorization() async -> Bool {
        guard !AppRuntimeConfig.isRunningTests else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ descriptor: UserNotificationRequestDescriptor) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.subtitle = descriptor.subtitle
        content.body = descriptor.body
        content.sound = descriptor.usesDefaultSound ? .default : nil
        content.interruptionLevel = descriptor.interruptionLevel
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, descriptor.timeInterval),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: descriptor.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func pendingRequestIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func deliveredRequestIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
