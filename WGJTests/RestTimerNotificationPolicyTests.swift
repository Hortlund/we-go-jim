import UserNotifications
import XCTest
@testable import WGJ

final class RestTimerNotificationPolicyTests: XCTestCase {
    @MainActor
    func testSystemNotificationDeliveryKeepsTheRestDeadline() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            throw XCTSkip("Enable notifications with the background delivery UI test before running this integration test.")
        }
        let identifier = "test.rest.delivery.\(UUID().uuidString)"
        let observer = NotificationDeliveryObserver(identifier: identifier)
        let previousDelegate = center.delegate
        center.delegate = observer
        defer {
            center.delegate = previousDelegate
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        let deadline = Date.now.addingTimeInterval(5)
        let client = SystemUserNotificationCenterClient()
        try await client.add(.init(identifier: identifier, title: "Rest complete", subtitle: "",
            body: "Timer delivery test", usesDefaultSound: false, interruptionLevel: .timeSensitive,
            fireDate: deadline))
        await fulfillment(of: [observer.delivered], timeout: 10)
        let arrival = try XCTUnwrap(observer.arrival)
        let delay = arrival.timeIntervalSince(deadline)
        let measurement = XCTAttachment(string: "System notification delivery relative to deadline: \(delay) seconds")
        measurement.lifetime = .keepAlways
        add(measurement)
        XCTAssertGreaterThanOrEqual(delay, -0.25)
        XCTAssertLessThan(delay, 3, "The system notification was delivered late.")
    }

    func testNotificationUsesOnlyTimeRemainingAfterSchedulingDelay() {
        let start = Date(timeIntervalSince1970: 10_000)
        let deadline = start.addingTimeInterval(30)
        let trigger = UserNotificationTiming.trigger(fireDate: deadline, at: start.addingTimeInterval(4.25))
        XCTAssertEqual(trigger?.timeInterval, 25.75)
        XCTAssertEqual(trigger?.repeats, false)
        // Sub-second time must not be rounded up and cause another delay.
        XCTAssertEqual(UserNotificationTiming.trigger(fireDate: deadline, at: deadline.addingTimeInterval(-0.25))?.timeInterval, 0.25)
        XCTAssertNil(UserNotificationTiming.trigger(fireDate: deadline, at: deadline))
        XCTAssertNil(UserNotificationTiming.trigger(fireDate: deadline, at: deadline.addingTimeInterval(5)))
    }

    func testSchedulingWorkerPreservesTheOriginalRestDeadline() async throws {
        let client = RecordingNotificationCenterClient(settings: .authorizedTimeSensitive)
        let worker = RestTimerNotificationWorker(notificationIdentifierPrefix: "test.rest", client: client)
        let deadline = Date.now.addingTimeInterval(30)
        await worker.scheduleRestTimer(endsAt: deadline, style: .timeSensitive)
        await worker.waitForPendingScheduling()
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.fireDate, deadline)
        XCTAssertEqual(requests.first?.interruptionLevel, .timeSensitive)
    }
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

private nonisolated final class NotificationDeliveryObserver: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let delivered = XCTestExpectation(description: "System delivered the scheduled rest notification")
    private let identifier: String
    private let lock = NSLock()
    private var arrivalDate: Date?

    init(identifier: String) { self.identifier = identifier }

    var arrival: Date? {
        lock.lock()
        defer { lock.unlock() }
        return arrivalDate
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
        guard notification.request.identifier == identifier else { return }
        lock.lock()
        arrivalDate = Date.now
        lock.unlock()
        delivered.fulfill()
    }
}

private actor RecordingNotificationCenterClient: UserNotificationCenterClient {
    private var current: NotificationPermissionSnapshot
    private let settingsAfterRequest: NotificationPermissionSnapshot?
    private(set) var requestCount = 0
    private(set) var settingsCount = 0
    private(set) var requests: [UserNotificationRequestDescriptor] = []

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

    func add(_ descriptor: UserNotificationRequestDescriptor) throws { requests.append(descriptor) }
    func pendingRequestIdentifiers() -> [String] { [] }
    func deliveredRequestIdentifiers() -> [String] { [] }
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {}
}
