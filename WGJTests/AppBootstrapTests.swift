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
}
