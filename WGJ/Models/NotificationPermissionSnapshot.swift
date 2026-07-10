import UserNotifications

nonisolated struct NotificationPermissionSnapshot: Equatable, Sendable {
    let authorizationStatus: UNAuthorizationStatus
    let timeSensitiveSetting: UNNotificationSetting

    var allowsAlerts: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var allowsTimeSensitive: Bool {
        allowsAlerts && timeSensitiveSetting == .enabled
    }

    static let authorizedTimeSensitive = Self(
        authorizationStatus: .authorized,
        timeSensitiveSetting: .enabled
    )
    static let authorizedStandard = Self(
        authorizationStatus: .authorized,
        timeSensitiveSetting: .disabled
    )
    static let denied = Self(
        authorizationStatus: .denied,
        timeSensitiveSetting: .notSupported
    )
}

nonisolated struct UserNotificationRequestDescriptor: Equatable, Sendable {
    let identifier: String
    let title: String
    let subtitle: String
    let body: String
    let usesDefaultSound: Bool
    let interruptionLevel: UNNotificationInterruptionLevel
    let timeInterval: TimeInterval
}

nonisolated enum RestTimerInterruptionPolicy {
    static func effectiveLevel(
        style: WorkoutNotificationStyle,
        permissions: NotificationPermissionSnapshot
    ) -> UNNotificationInterruptionLevel {
        switch style {
        case .standard:
            return .active
        case .timeSensitive:
            return permissions.allowsTimeSensitive ? .timeSensitive : .active
        }
    }
}

nonisolated struct RestTimerNotificationAuthorization: Sendable {
    let client: any UserNotificationCenterClient

    func ensureAuthorization() async -> NotificationPermissionSnapshot {
        let initial = await client.settings()
        guard initial.authorizationStatus == .notDetermined else { return initial }
        _ = await client.requestAlertAuthorization()
        return await client.settings()
    }
}
