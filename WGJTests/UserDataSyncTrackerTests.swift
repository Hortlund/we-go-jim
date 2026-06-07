import CloudKit
import Dispatch
import Foundation
import Testing
@testable import WGJ

@Suite(.serialized)
struct UserDataSyncTrackerTests {
    @Test
    func cloudStartupPreflightForcesLocalFallbackOnlyWhenCloudCannotBeUsed() {
        let localFallbackStatuses: [CloudStartupAccountStatus] = [
            .noAccount,
            .restricted,
            .containerUnavailable,
        ]

        for status in localFallbackStatuses {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(decision.shouldForceLocalFallbackStore)
        }

        let transientCloudBackedStatuses: [CloudStartupAccountStatus] = [
            .temporarilyUnavailable,
            .couldNotDetermine,
            .timedOut,
            .error,
        ]

        for status in transientCloudBackedStatuses {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(!decision.shouldForceLocalFallbackStore)
            #expect(decision.storeMode == .cloudBacked)
            #expect(decision.cloudSyncErrorDescription != nil)
        }

        let availableDecision = CloudStartupPreflight.makeDecision(
            statusProvider: MockCloudStartupAccountStatusProvider(status: .available)
        )
        #expect(!availableDecision.shouldForceLocalFallbackStore)
        #expect(availableDecision.storeMode == .cloudBacked)
        #expect(availableDecision.cloudSyncErrorDescription == nil)
    }

    @Test
    func userDataSyncTrackerMovesThroughPendingExportCaughtUpAndDegradedStates() {
        let tracker = UserDataSyncTracker.shared

        let configured = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        #expect(configured.state == .caughtUp)
        #expect(configured.allowsDirectCloudOperations)

        let pending = tracker.markLocalUserDataMutation(
            at: Date(timeIntervalSinceReferenceDate: 10)
        )
        #expect(pending.state == .pendingExport)
        #expect(pending.hasPendingExport)
        #expect(pending.allowsDirectCloudOperations)

        let exported = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .export,
                status: .succeeded,
                startedAt: Date(timeIntervalSinceReferenceDate: 20),
                endedAt: Date(timeIntervalSinceReferenceDate: 21)
            )
        )
        #expect(exported.state == .caughtUp)
        #expect(!exported.hasPendingExport)

        let degraded = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .export,
                status: .failed,
                startedAt: Date(timeIntervalSinceReferenceDate: 30),
                endedAt: Date(timeIntervalSinceReferenceDate: 31),
                error: CloudSyncErrorSnapshot(
                    domain: CKError.errorDomain,
                    code: CKError.Code.permissionFailure.rawValue,
                    underlyingDomain: nil,
                    underlyingCode: nil,
                    description: "CloudKit permission failure."
                )
            )
        )
        #expect(degraded.state == .degraded)
        #expect(degraded.latestErrorDescription?.contains("permission") == true)
        #expect(!degraded.allowsDirectCloudOperations)

        let recovered = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .import,
                status: .succeeded,
                startedAt: Date(timeIntervalSinceReferenceDate: 40),
                endedAt: Date(timeIntervalSinceReferenceDate: 41)
            )
        )
        #expect(recovered.state == .caughtUp)
        #expect(recovered.latestSuccessfulImportAt == Date(timeIntervalSinceReferenceDate: 41))
        #expect(recovered.allowsDirectCloudOperations)
    }

    @Test
    func runtimeCloudRecoveryClearsLaunchDegradationWithoutDroppingPendingExport() {
        let tracker = UserDataSyncTracker.shared

        let degraded = tracker.configureForLaunch(
            isCloudEnabled: true,
            errorDescription: "iCloud availability check timed out."
        )
        #expect(degraded.state == .degraded)
        #expect(!degraded.allowsDirectCloudOperations)

        let pending = tracker.markLocalUserDataMutation(at: Date(timeIntervalSinceReferenceDate: 10))
        #expect(pending.state == .degraded)
        #expect(pending.hasPendingExport)
        #expect(!pending.allowsDirectCloudOperations)

        let recovered = tracker.recordRuntimeCloudAvailabilityRecovered()
        #expect(recovered.state == .pendingExport)
        #expect(recovered.hasPendingExport)
        #expect(recovered.latestErrorDescription == nil)
        #expect(recovered.allowsDirectCloudOperations)
    }

    @Test
    func runtimeCloudRecoveryDoesNotClearCloudEventFailures() {
        let tracker = UserDataSyncTracker.shared

        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        let failedExport = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .export,
                status: .failed,
                startedAt: Date(timeIntervalSinceReferenceDate: 30),
                endedAt: Date(timeIntervalSinceReferenceDate: 31),
                error: CloudSyncErrorSnapshot(
                    domain: CKError.errorDomain,
                    code: CKError.Code.permissionFailure.rawValue,
                    underlyingDomain: nil,
                    underlyingCode: nil,
                    description: "CloudKit permission failure."
                )
            )
        )
        #expect(failedExport.state == .degraded)
        #expect(!failedExport.allowsDirectCloudOperations)

        let accountRecovered = tracker.recordRuntimeCloudAvailabilityRecovered()
        #expect(accountRecovered.state == .degraded)
        #expect(accountRecovered.latestErrorDescription?.contains("permission") == true)
        #expect(!accountRecovered.allowsDirectCloudOperations)
    }

    @Test
    func userDataSyncTrackerDoesNotDegradeForAccountAuthFrameworkEvents() {
        let tracker = UserDataSyncTracker.shared

        let configured = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        #expect(configured.state == .caughtUp)

        let noAccount = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .setup,
                status: .failed,
                error: CloudSyncErrorSnapshot(
                    domain: NSCocoaErrorDomain,
                    code: 134400,
                    underlyingDomain: nil,
                    underlyingCode: nil,
                    description: "Unable to initialize without an iCloud account."
                )
            )
        )
        #expect(noAccount.state == .caughtUp)
        #expect(noAccount.latestErrorDescription == nil)

        let notAuthenticated = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .import,
                status: .failed,
                error: CloudSyncErrorSnapshot(
                    domain: CKError.errorDomain,
                    code: CKError.Code.notAuthenticated.rawValue,
                    underlyingDomain: nil,
                    underlyingCode: nil,
                    description: "Not authenticated."
                )
            )
        )
        #expect(notAuthenticated.state == .caughtUp)
        #expect(notAuthenticated.latestErrorDescription == nil)
    }

    @Test
    func userDataSyncTrackerStopsShowingSyncingForStaleRunningFrameworkEvents() {
        let tracker = UserDataSyncTracker.shared

        let configured = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        #expect(configured.state == .caughtUp)

        let running = tracker.recordCloudEvent(
            makeCloudSyncSummary(
                type: .export,
                status: .running,
                startedAt: Date(timeIntervalSinceReferenceDate: 10)
            )
        )
        #expect(running.state == .syncing)

        let stale = tracker.currentSnapshot(
            now: Date(timeIntervalSinceReferenceDate: 10)
                .addingTimeInterval(UserDataSyncTrackerPolicy.runningCloudEventVisibleDuration + 1)
        )
        #expect(stale.state == .caughtUp)
        #expect(stale.runningCloudEventType == nil)
    }

    private func makeCloudSyncSummary(
        type: CloudSyncEventType,
        status: CloudSyncEventStatus,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        error: CloudSyncErrorSnapshot? = nil
    ) -> CloudSyncEventSummary {
        CloudSyncEventSummary(
            type: type,
            status: status,
            storeIdentifier: "UserData",
            startedAt: startedAt,
            endedAt: endedAt,
            error: error
        )
    }
}

private struct MockCloudStartupAccountStatusProvider: CloudStartupAccountStatusProviding {
    let status: CloudStartupAccountStatus

    func currentStatus(timeout: TimeInterval) -> CloudStartupAccountStatus {
        status
    }
}
