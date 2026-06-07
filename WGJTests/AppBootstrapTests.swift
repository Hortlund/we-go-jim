import Testing
import SwiftUI
@testable import WGJ

struct AppBootstrapTests {
    @Test
    func cloudFailureRecoveryPreservesExistingStores() {
        #expect(AppBootstrapRecoveryPolicy.preservesExistingStoresOnCloudFailure)
    }

    @Test
    func cloudFailureRecoveryUsesDedicatedFallbackUserDataStore() throws {
        let appSource = try String(contentsOf: appSourceURL(), encoding: .utf8)

        #expect(appSource.contains("makeCloudFailureLocalFallbackContainer"))
        #expect(appSource.contains("cloudFailureFallbackUserDataConfigurationName"))
        #expect(appSource.contains("userDataConfigurationName: AppStoreLayout.cloudFailureFallbackUserDataConfigurationName"))
    }

    @Test
    func storeLayoutUsesNamedStoresForEachConfiguration() {
        #expect(AppStoreLayout.appGroupIdentifier == WeeklyGoalWidgetStore.appGroupIdentifier)
        #expect(AppStoreLayout.configurationNames == [
            "LocalCatalog",
            "UserData",
            "UserDataCloudMirror",
            "ActiveWorkoutDraft",
            "SocialOutbox",
            "HistoryProjection",
        ])
        #expect(AppStoreLayout.storeFilePrefixes == [
            "LocalCatalog.store",
            "UserData.store",
            "UserDataCloudMirror.store",
            "ActiveWorkoutDraft.store",
            "SocialOutbox.store",
            "HistoryProjection.store",
        ])
        #expect(!AppStoreLayout.storeFilePrefixes.contains("default.store"))
    }

    @Test
    func namedStorePreparationCreatesSharedAppGroupSupportDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJ-AppStoreLayout-\(UUID().uuidString)", isDirectory: true)
        let appGroupURL = temporaryRoot
            .appendingPathComponent("AppGroup", isDirectory: true)
        try FileManager.default.createDirectory(at: appGroupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let fileManager = AppStoreLayoutTestingFileManager(appGroupURL: appGroupURL)
        try AppStoreLayout.prepareAppGroupStoreDirectory(fileManager: fileManager)

        let supportDirectory = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: supportDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test
    func historyProjectionStorePinsAppGroupContainerWhileOtherStoresKeepAutomaticResolution() throws {
        let appSource = try String(contentsOf: appSourceURL(), encoding: .utf8)

        #expect(appSource.contains("prepareAppGroupStoreDirectory()"))
        #expect(appSource.contains("ModelConfiguration.GroupContainer.identifier(appGroupIdentifier)"))
        #expect(appSource.components(separatedBy: "groupContainer: AppStoreLayout.historyProjectionGroupContainer").count - 1 == 1)
        #expect(!appSource.contains("groupContainer: AppStoreLayout.historyProjectionGroupContainer,\n                cloudKitDatabase: userDataCloudKitDatabase"))
    }

    @Test
    func cloudMirrorStoreUsesDedicatedAutomaticCloudKitConfigurationOutsideRootBootstrap() throws {
        let appSource = try String(contentsOf: appSourceURL(), encoding: .utf8)

        #expect(appSource.contains("userDataCloudMirrorConfigurationName = \"UserDataCloudMirror\""))
        #expect(appSource.contains("makeUserDataCloudMirrorContainer()"))
        #expect(appSource.contains("AppStoreLayout.userDataCloudMirrorConfigurationName"))
        #expect(appSource.contains("cloudKitDatabase: .automatic"))
    }

    @Test
    func cloudMirrorSchemaIncludesDurableUserCatalogAndSafetyData() throws {
        let appSource = try String(contentsOf: appSourceURL(), encoding: .utf8)
        let schemaStart = try #require(appSource.range(of: "nonisolated private static func userDataCloudMirrorSchema()"))
        let schemaRemainder = appSource[schemaStart.lowerBound...]
        let schemaEnd = try #require(schemaRemainder.range(of: "private static func storeConfigurations("))
        let schemaSource = String(schemaRemainder[..<schemaEnd.lowerBound])

        #expect(schemaSource.contains("CustomExerciseCloudRecord.self"))
        #expect(schemaSource.contains("BlockedBroCloudRecord.self"))
        #expect(!schemaSource.contains("ExerciseCatalogItem.self"))
        #expect(!schemaSource.contains("MuscleGroup.self"))
        #expect(!schemaSource.contains("ExerciseAlias.self"))
        #expect(!schemaSource.contains("BlockedBro.self"))
    }

    @Test
    func appLaunchBootstrapResolutionRunsOffMainActorUntilStatePublication() throws {
        let source = try String(contentsOf: appLaunchBootstrapSourceURL(), encoding: .utf8)

        #expect(source.contains("Task.detached(priority: .userInitiated)"))
        #expect(source.contains("await self.finishResolution("))
        #expect(source.contains("await self.clearResolutionTask("))
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

    private func appLaunchBootstrapSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("AppLaunchBootstrap.swift")
    }
}

private final class AppStoreLayoutTestingFileManager: FileManager, @unchecked Sendable {
    private let appGroupURL: URL

    init(appGroupURL: URL) {
        self.appGroupURL = appGroupURL
        super.init()
    }

    override func containerURL(
        forSecurityApplicationGroupIdentifier groupIdentifier: String
    ) -> URL? {
        groupIdentifier == AppStoreLayout.appGroupIdentifier ? appGroupURL : nil
    }
}
