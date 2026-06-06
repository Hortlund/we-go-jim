import Testing
import SwiftUI
@testable import WGJ

struct AppBootstrapTests {
    @Test
    func cloudFailureRecoveryPreservesExistingStores() {
        #expect(AppBootstrapRecoveryPolicy.preservesExistingStoresOnCloudFailure)
    }

    @Test
    func storeLayoutUsesNamedStoresForEachConfiguration() {
        #expect(AppStoreLayout.appGroupIdentifier == WeeklyGoalWidgetStore.appGroupIdentifier)
        #expect(AppStoreLayout.configurationNames == [
            "LocalCatalog",
            "UserData",
            "ActiveWorkoutDraft",
            "SocialOutbox",
            "HistoryProjection",
        ])
        #expect(AppStoreLayout.storeFilePrefixes == [
            "LocalCatalog.store",
            "UserData.store",
            "ActiveWorkoutDraft.store",
            "SocialOutbox.store",
            "HistoryProjection.store",
        ])
        #expect(!AppStoreLayout.storeFilePrefixes.contains("default.store"))
    }

    @Test
    func historyProjectionStorePinsAppGroupContainerWhileOtherStoresKeepAutomaticResolution() throws {
        let appSource = try String(contentsOf: appSourceURL(), encoding: .utf8)

        #expect(appSource.contains("prepareHistoryProjectionStoreDirectory()"))
        #expect(appSource.contains("ModelConfiguration.GroupContainer.identifier(appGroupIdentifier)"))
        #expect(appSource.components(separatedBy: "groupContainer: AppStoreLayout.historyProjectionGroupContainer").count - 1 == 1)
        #expect(!appSource.contains("groupContainer: AppStoreLayout.historyProjectionGroupContainer,\n                cloudKitDatabase: userDataCloudKitDatabase"))
    }

    @Test
    func socialMaintenanceOnlyRunsWhenThereIsLocalBrosContext() {
        #expect(!SocialMaintenancePlanner.shouldRun(
            hasKnownMembership: false,
            hasPendingOutboxItems: false
        ))
        #expect(SocialMaintenancePlanner.shouldRun(
            hasKnownMembership: true,
            hasPendingOutboxItems: false
        ))
        #expect(SocialMaintenancePlanner.shouldRun(
            hasKnownMembership: false,
            hasPendingOutboxItems: true
        ))
    }

    @Test
    func brosCleanStartPolicyOnlyAppliesOncePerSchemaVersion() {
        #expect(BrosCleanStartPolicy.needsLocalReset(appliedVersion: 0))
        #expect(!BrosCleanStartPolicy.needsLocalReset(
            appliedVersion: BrosCleanStartPolicy.currentSchemaVersion
        ))
    }

    @Test
    func appMaintenanceOnlyRunsResumeCriticalInMainActiveState() {
        #expect(!AppMaintenancePolicy.shouldRunResumeCritical(appPhase: .splash, scenePhase: .active))
        #expect(!AppMaintenancePolicy.shouldRunResumeCritical(appPhase: .login, scenePhase: .active))
        #expect(!AppMaintenancePolicy.shouldRunResumeCritical(appPhase: .main, scenePhase: .inactive))
        #expect(!AppMaintenancePolicy.shouldRunResumeCritical(appPhase: .main, scenePhase: .background))
        #expect(AppMaintenancePolicy.shouldRunResumeCritical(appPhase: .main, scenePhase: .active))
    }

    @Test
    func deferredMaintenanceOnlySchedulesWhenPendingAndNoActiveWorkoutExists() {
        #expect(
            !AppMaintenancePolicy.shouldScheduleDeferred(
                appPhase: .main,
                scenePhase: .active,
                activeSessionID: UUID(),
                hasPendingDeferredMaintenance: true
            )
        )
        #expect(
            !AppMaintenancePolicy.shouldScheduleDeferred(
                appPhase: .main,
                scenePhase: .active,
                activeSessionID: nil,
                hasPendingDeferredMaintenance: false
            )
        )
        #expect(
            AppMaintenancePolicy.shouldScheduleDeferred(
                appPhase: .main,
                scenePhase: .active,
                activeSessionID: nil,
                hasPendingDeferredMaintenance: true
            )
        )
    }

    @Test
    func resumeCriticalMaintenanceTrackerInvalidatesStaleRunsAcrossStartupResets() throws {
        var tracker = ResumeCriticalMaintenanceTracker()
        let firstRunCandidate = tracker.beginRunIfNeeded()
        let firstRunID = try #require(firstRunCandidate)

        #expect(tracker.hasRunThisForegroundCycle)
        #expect(tracker.isRunning)
        #expect(tracker.isCurrent(firstRunID))

        tracker.resetForegroundCycle()

        #expect(!tracker.hasRunThisForegroundCycle)
        #expect(!tracker.isRunning)
        #expect(!tracker.isCurrent(firstRunID))

        let secondRunCandidate = tracker.beginRunIfNeeded()
        let secondRunID = try #require(secondRunCandidate)
        tracker.finishRun(firstRunID)

        #expect(tracker.isRunning)
        #expect(tracker.isCurrent(secondRunID))

        tracker.finishRun(secondRunID)

        #expect(!tracker.isRunning)
    }

    private func appSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("WGJApp.swift")
    }
}
