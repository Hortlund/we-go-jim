import XCTest
@testable import WGJ

final class AccountStatusTimeoutTests: XCTestCase {
    func testAccountStatusReturnsBeforeTimeout() async {
        let status = await accountStatusWithTimeout(
            provider: DelayedAccountStatusProvider(status: .available, delay: .zero),
            timeout: .seconds(1)
        )

        XCTAssertEqual(status, .available)
    }

    func testAccountStatusTimesOutAsUnknown() async {
        let status = await accountStatusWithTimeout(
            provider: DelayedAccountStatusProvider(
                status: .available,
                delay: .seconds(1)
            ),
            timeout: .milliseconds(10)
        )

        XCTAssertEqual(status, .unavailable(.unknown))
    }

    @MainActor
    func testForcedRefreshRejectsOlderCompletion() async {
        let state = AppRuntimeState.makeTestingInstance()
        state.updateCloudState(runtimeMode: .checking, isEnabled: true, errorDescription: nil)
        state.refreshCloudAvailabilityIfNeeded(
            accountService: DelayedAccountStatusProvider(
                status: .available,
                delay: .milliseconds(100),
                ignoresCancellation: true
            ),
            runtimeTimeout: .seconds(1)
        )
        state.refreshCloudAvailabilityIfNeeded(
            force: true,
            accountService: DelayedAccountStatusProvider(
                status: .unavailable(.restricted),
                delay: .zero
            ),
            runtimeTimeout: .seconds(1)
        )

        try? await Task.sleep(for: .milliseconds(150))

        guard case .degraded(let message) = state.cloudRuntimeMode else {
            return XCTFail("Expected the later restricted result to win")
        }
        XCTAssertTrue(message.contains("restricted"))
    }

    @MainActor
    func testCancelledRefreshDoesNotPublish() async {
        let state = AppRuntimeState.makeTestingInstance()
        state.updateCloudState(runtimeMode: .checking, isEnabled: true, errorDescription: nil)
        state.refreshCloudAvailabilityIfNeeded(
            accountService: DelayedAccountStatusProvider(
                status: .available,
                delay: .milliseconds(50),
                ignoresCancellation: true
            ),
            runtimeTimeout: .seconds(1)
        )

        state.updateCloudState(
            runtimeMode: .unavailable("Disabled while refreshing"),
            isEnabled: false,
            errorDescription: "Disabled while refreshing"
        )
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(state.cloudRuntimeMode, .unavailable("Disabled while refreshing"))
    }
}

private actor DelayedAccountStatusProvider: AccountStatusProviding {
    let status: AccountStatus
    let delay: Duration
    let ignoresCancellation: Bool

    init(
        status: AccountStatus,
        delay: Duration,
        ignoresCancellation: Bool = false
    ) {
        self.status = status
        self.delay = delay
        self.ignoresCancellation = ignoresCancellation
    }

    func fetchAccountStatus() async -> AccountStatus {
        do {
            try await Task.sleep(for: delay)
        } catch where !ignoresCancellation {
            return .unavailable(.unknown)
        } catch {
            try? await Task.sleep(for: delay)
        }
        return status
    }
}
