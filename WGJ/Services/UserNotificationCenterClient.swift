import UserNotifications

nonisolated enum UserNotificationTiming {
    static func trigger(fireDate: Date, at date: Date = .now) -> UNTimeIntervalNotificationTrigger? {
        let remaining = fireDate.timeIntervalSince(date)
        guard remaining > 0 else { return nil }
        return UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
    }
}

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
#if DEBUG
        guard !AppRuntimeConfig.isRunningTests
            || ProcessInfo.processInfo.arguments.contains("UITEST_ALLOW_NOTIFICATIONS") else { return false }
#else
        guard !AppRuntimeConfig.isRunningTests else { return false }
#endif
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ descriptor: UserNotificationRequestDescriptor) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.subtitle = descriptor.subtitle
        content.body = descriptor.body
        content.sound = descriptor.usesDefaultSound ? .default : nil
        content.interruptionLevel = descriptor.interruptionLevel
        // Account for permission/cleanup/queue time instead of starting the
        // original rest duration again when the request reaches the system.
        let trigger = UserNotificationTiming.trigger(fireDate: descriptor.fireDate)
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
