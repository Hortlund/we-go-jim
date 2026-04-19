import Dispatch
import Foundation
import Testing
@testable import WGJ

struct UserDataSyncTrackerTests {
    @Test
    func cloudStartupPreflightForcesLocalFallbackWheneverLaunchDecisionUsesLocalStore() {
        let definitiveStatuses: [CloudStartupAccountStatus] = [
            .noAccount,
            .restricted,
            .containerUnavailable,
        ]

        for status in definitiveStatuses {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(decision.shouldForceLocalFallbackStore)
        }

        let degradedStatuses: [CloudStartupAccountStatus] = [
            .temporarilyUnavailable,
            .couldNotDetermine,
            .timedOut,
            .error,
        ]

        for status in degradedStatuses {
            let decision = CloudStartupPreflight.makeDecision(
                statusProvider: MockCloudStartupAccountStatusProvider(status: status)
            )

            #expect(decision.shouldForceLocalFallbackStore)
            #expect(decision.storeMode == .localFallback)
        }
    }

    @Test
    func userDataSyncTrackerMovesThroughPendingExportCaughtUpAndDegradedStates() {
        let tracker = UserDataSyncTracker.shared

        let configured = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        #expect(configured.state == .caughtUp)

        let pending = tracker.markLocalUserDataMutation(
            at: Date(timeIntervalSinceReferenceDate: 10)
        )
        #expect(pending.state == .pendingExport)
        #expect(pending.hasPendingExport)

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
                    domain: NSCocoaErrorDomain,
                    code: 134400,
                    underlyingDomain: nil,
                    underlyingCode: nil,
                    description: "Unable to initialize without an iCloud account."
                )
            )
        )
        #expect(degraded.state == .degraded)
        #expect(degraded.latestErrorDescription?.contains("iCloud account") == true)

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
