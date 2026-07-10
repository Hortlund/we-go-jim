import UserNotifications
import XCTest
@testable import WGJ

final class RestTimerNotificationPolicyTests: XCTestCase {
    func testTimeSensitiveFallsBackUnlessSystemSettingIsEnabled() {
        XCTAssertEqual(
            RestTimerInterruptionPolicy.effectiveLevel(
                style: .timeSensitive,
                permissions: .authorizedTimeSensitive
            ),
            .timeSensitive
        )
        XCTAssertEqual(
            RestTimerInterruptionPolicy.effectiveLevel(
                style: .timeSensitive,
                permissions: .authorizedStandard
            ),
            .active
        )
        XCTAssertEqual(
            RestTimerInterruptionPolicy.effectiveLevel(
                style: .standard,
                permissions: .authorizedTimeSensitive
            ),
            .active
        )
    }

    func testDeniedAuthorizationDoesNotRequestAgain() async {
        let client = RecordingNotificationCenterClient(settings: .denied)
        _ = await RestTimerNotificationAuthorization(client: client).ensureAuthorization()
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testNotDeterminedRequestsExactlyOnceAndRefetches() async {
        let client = RecordingNotificationCenterClient(
            settings: NotificationPermissionSnapshot(
                authorizationStatus: .notDetermined,
                timeSensitiveSetting: .notSupported
            ),
            settingsAfterRequest: .authorizedStandard
        )

        let result = await RestTimerNotificationAuthorization(client: client).ensureAuthorization()

        XCTAssertEqual(result, .authorizedStandard)
        let requestCount = await client.requestCount
        let settingsCount = await client.settingsCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(settingsCount, 2)
    }
}

private actor RecordingNotificationCenterClient: UserNotificationCenterClient {
    private var current: NotificationPermissionSnapshot
    private let settingsAfterRequest: NotificationPermissionSnapshot?
    private(set) var requestCount = 0
    private(set) var settingsCount = 0

    init(
        settings: NotificationPermissionSnapshot,
        settingsAfterRequest: NotificationPermissionSnapshot? = nil
    ) {
        current = settings
        self.settingsAfterRequest = settingsAfterRequest
    }

    func settings() -> NotificationPermissionSnapshot {
        settingsCount += 1
        return current
    }

    func requestAlertAuthorization() -> Bool {
        requestCount += 1
        if let settingsAfterRequest {
            current = settingsAfterRequest
        }
        return current.allowsAlerts
    }

    func add(_ descriptor: UserNotificationRequestDescriptor) throws {}
    func pendingRequestIdentifiers() -> [String] { [] }
    func deliveredRequestIdentifiers() -> [String] { [] }
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {}
}
