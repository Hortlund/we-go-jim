import Testing
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
            "SocialOutbox",
            "HistoryProjection",
        ])
        #expect(AppStoreLayout.storeFilePrefixes == [
            "LocalCatalog.store",
            "UserData.store",
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
}
