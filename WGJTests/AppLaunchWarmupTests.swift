import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import WGJ

@MainActor
struct AppLaunchWarmupTests {
    @Test
    func appWarmupPolicyOnlyRunsInMainActiveWithoutActiveWorkout() {
        #expect(!AppWarmupPolicy.shouldWarm(
            appPhase: .splash,
            scenePhase: .active,
            activeSessionID: nil
        ))
        #expect(!AppWarmupPolicy.shouldWarm(
            appPhase: .main,
            scenePhase: .background,
            activeSessionID: nil
        ))
        #expect(!AppWarmupPolicy.shouldWarm(
            appPhase: .main,
            scenePhase: .active,
            activeSessionID: UUID()
        ))
        #expect(AppWarmupPolicy.shouldWarm(
            appPhase: .main,
            scenePhase: .active,
            activeSessionID: nil
        ))
    }

    @Test
    func appWarmupStateReusesFreshProfileSnapshotAndInvalidatesStaleEntries() {
        let state = AppWarmupState()
        let snapshot = ProfileWarmSnapshot(
            profile: makeProfileSnapshot(updatedAt: .distantPast),
            dashboard: .empty,
            warmedAt: Date(timeIntervalSince1970: 600)
        )

        state.storeProfile(snapshot)

        #expect(state.latestProfile?.profile.displayName == snapshot.profile.displayName)
        #expect(state.latestProfile?.warmedAt == snapshot.warmedAt)
        #expect(state.freshProfile(now: Date(timeIntervalSince1970: 620), maxAge: 30)?.warmedAt == snapshot.warmedAt)
        #expect(state.freshProfile(now: Date(timeIntervalSince1970: 700), maxAge: 30) == nil)
        #expect(!state.shouldWarmProfile(now: Date(timeIntervalSince1970: 620), maxAge: 30))
        #expect(state.shouldWarmProfile(now: Date(timeIntervalSince1970: 700), maxAge: 30))

        state.invalidateProfile()
        #expect(state.latestProfile == nil)
        #expect(state.shouldWarmProfile(now: Date(timeIntervalSince1970: 620), maxAge: 30))
    }

    @Test
    func appWarmupStateReusesFreshBrosSnapshotAndInvalidatesStaleEntries() {
        let state = AppWarmupState()
        let snapshot = BrosWarmSnapshot(
            state: .active(makeBrosSnapshot()),
            blockedUserRecordNames: ["blocked-user"],
            warmedAt: Date(timeIntervalSince1970: 700)
        )

        state.storeBros(snapshot)

        #expect(state.latestBros?.blockedUserRecordNames == ["blocked-user"])
        #expect(state.freshBros(now: Date(timeIntervalSince1970: 720), maxAge: 30)?.warmedAt == snapshot.warmedAt)
        #expect(state.freshBros(now: Date(timeIntervalSince1970: 750), maxAge: 30) == nil)
        #expect(!state.shouldWarmBros(now: Date(timeIntervalSince1970: 720), maxAge: 30))
        #expect(state.shouldWarmBros(now: Date(timeIntervalSince1970: 750), maxAge: 30))

        state.invalidateBros()
        #expect(state.latestBros == nil)
        #expect(state.shouldWarmBros(now: Date(timeIntervalSince1970: 720), maxAge: 30))
    }

    @Test
    func appWarmupDefaultsKeepStartupSnapshotsReusableForFirstVisits() {
        #expect(AppWarmupState.defaultProfileFreshnessInterval == 300)
        #expect(AppWarmupState.defaultBrosFreshnessInterval == 300)
    }

    @Test
    func brosWarmSnapshotsCanCompareRenderableContentWithoutTimestampNoise() {
        let base = BrosWarmSnapshot(
            state: .active(makeBrosSnapshot()),
            blockedUserRecordNames: ["blocked-user"],
            warmedAt: Date(timeIntervalSince1970: 100)
        )
        let refreshedAtOnly = BrosWarmSnapshot(
            state: base.state,
            blockedUserRecordNames: base.blockedUserRecordNames,
            warmedAt: Date(timeIntervalSince1970: 200)
        )
        let changedBlockedList = BrosWarmSnapshot(
            state: base.state,
            blockedUserRecordNames: ["other-user"],
            warmedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(base.hasSameRenderableContent(as: refreshedAtOnly))
        #expect(!base.hasSameRenderableContent(as: changedBlockedList))
    }

    @Test
    func appWarmupStateIgnoresLateWarmupResultsAfterInvalidationOrNewerRun() throws {
        let state = AppWarmupState()
        let firstRunID = try #require(state.beginProfileWarmup())
        #expect(state.isProfileWarmupActive)
        let newerRunID = try #require(state.beginProfileWarmup(force: true))
        let staleSnapshot = ProfileWarmSnapshot(
            profile: makeProfileSnapshot(updatedAt: Date(timeIntervalSince1970: 100)),
            dashboard: .empty,
            warmedAt: Date(timeIntervalSince1970: 100)
        )
        let currentSnapshot = ProfileWarmSnapshot(
            profile: makeProfileSnapshot(updatedAt: Date(timeIntervalSince1970: 200)),
            dashboard: .empty,
            warmedAt: Date(timeIntervalSince1970: 200)
        )

        state.finishProfileWarmup(runID: firstRunID, snapshot: staleSnapshot)
        #expect(state.latestProfile == nil)

        state.finishProfileWarmup(runID: newerRunID, snapshot: currentSnapshot)
        #expect(state.latestProfile?.warmedAt == currentSnapshot.warmedAt)
        #expect(!state.isProfileWarmupActive)

        let brosRunID = try #require(state.beginBrosWarmup())
        #expect(state.isBrosWarmupActive)
        state.invalidateBros()
        state.finishBrosWarmup(
            runID: brosRunID,
            snapshot: BrosWarmSnapshot(
                state: .active(makeBrosSnapshot()),
                blockedUserRecordNames: [],
                warmedAt: Date(timeIntervalSince1970: 300)
            )
        )
        #expect(state.latestBros == nil)
        #expect(!state.isBrosWarmupActive)
    }

    @Test
    func appWarmupStateIncrementsCompletionVersionsOnFinishAndInvalidate() throws {
        let state = AppWarmupState()
        #expect(state.profileCompletionVersion == 0)
        #expect(state.brosCompletionVersion == 0)

        let profileRunID = try #require(state.beginProfileWarmup())
        state.finishProfileWarmup(
            runID: profileRunID,
            snapshot: ProfileWarmSnapshot(
                profile: makeProfileSnapshot(updatedAt: Date(timeIntervalSince1970: 100)),
                dashboard: .empty,
                warmedAt: Date(timeIntervalSince1970: 100)
            )
        )
        #expect(state.profileCompletionVersion == 1)

        state.invalidateProfile()
        #expect(state.profileCompletionVersion == 2)

        let brosRunID = try #require(state.beginBrosWarmup())
        state.finishBrosWarmup(
            runID: brosRunID,
            snapshot: BrosWarmSnapshot(
                state: .active(makeBrosSnapshot()),
                blockedUserRecordNames: [],
                warmedAt: Date(timeIntervalSince1970: 200)
            )
        )
        #expect(state.brosCompletionVersion == 1)

        state.invalidateBros()
        #expect(state.brosCompletionVersion == 2)
    }

    @Test
    func startupWarmupStarterMarksProfileAndBrosActiveSynchronously() throws {
        let state = AppWarmupState()

        let runIDs = state.beginStartupWarmups(
            shouldWarmProfile: true,
            shouldWarmBros: true
        )

        let profileRunID = try #require(runIDs.profileRunID)
        let brosRunID = try #require(runIDs.brosRunID)
        #expect(runIDs.hasAnyWarmup)
        #expect(state.isProfileWarmupActive)
        #expect(state.isBrosWarmupActive)
        #expect(state.profileCompletionVersion == 0)
        #expect(state.brosCompletionVersion == 0)

        state.finishProfileWarmup(runID: profileRunID, snapshot: nil)
        state.finishBrosWarmup(runID: brosRunID, snapshot: nil)

        #expect(!state.isProfileWarmupActive)
        #expect(!state.isBrosWarmupActive)
        #expect(state.profileCompletionVersion == 1)
        #expect(state.brosCompletionVersion == 1)
    }

    @Test
    func firstFrameTabPolicyUsesWarmProfileSnapshotForImmediateInitialContent() {
        #expect(!FirstFrameTabContentPolicy.shouldDeferInitialContentMount(
            tab: .profile,
            hasFreshWarmSnapshot: true
        ))
        #expect(FirstFrameTabContentPolicy.shouldDeferInitialContentMount(tab: .bros))
        #expect(!FirstFrameTabContentPolicy.shouldDeferInitialContentMount(tab: .history))

        #expect(FirstFrameTabContentPolicy.presentation(
            tab: .profile,
            selectedTab: .profile,
            hasLoaded: false,
            deferInitialContentMount: false,
            isInitialContentMountReady: false
        ) == .content)
        #expect(FirstFrameTabContentPolicy.presentation(
            tab: .bros,
            selectedTab: .bros,
            hasLoaded: false,
            deferInitialContentMount: true,
            isInitialContentMountReady: false
        ) == .shell)
        #expect(FirstFrameTabContentPolicy.presentation(
            tab: .profile,
            selectedTab: .profile,
            hasLoaded: false,
            deferInitialContentMount: true,
            isInitialContentMountReady: true
        ) == .content)
        #expect(FirstFrameTabContentPolicy.presentation(
            tab: .history,
            selectedTab: .history,
            hasLoaded: false,
            deferInitialContentMount: false,
            isInitialContentMountReady: false
        ) == .content)
        #expect(FirstFrameTabContentPolicy.presentation(
            tab: .profile,
            selectedTab: .startWorkout,
            hasLoaded: false,
            deferInitialContentMount: true,
            isInitialContentMountReady: false
        ) == .empty)
    }

    @Test
    func firstFrameTabPolicyDefersInitialProfileAndBrosMounts() {
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(
            tab: .profile,
            hasFreshWarmSnapshot: false
        ) == 0)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(
            tab: .bros,
            hasFreshWarmSnapshot: false
        ) >= 350)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(tab: .history) == 0)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(tab: .startWorkout) == 0)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(tab: .exercises) == 0)
    }

    @Test
    func firstFrameTabPolicyPreloadsProfileWhenWarmSnapshotIsReady() {
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(
            tab: .profile,
            hasFreshWarmSnapshot: true
        ) == 0)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(
            tab: .bros,
            hasFreshWarmSnapshot: true
        ) >= 350)
        #expect(FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(
            tab: .history,
            hasFreshWarmSnapshot: true
        ) == 0)
        #expect(FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .profile,
            hasFreshWarmSnapshot: true
        ))
    }

    @Test
    func firstFrameTabPolicyDoesNotScheduleDeferredContentFromTabAppear() {
        #expect(!FirstFrameTabContentPolicy.shouldScheduleInitialContentMount(
            isSelectionChange: false,
            deferInitialContentMount: true
        ))
        #expect(FirstFrameTabContentPolicy.shouldScheduleInitialContentMount(
            isSelectionChange: true,
            deferInitialContentMount: true
        ))
        #expect(FirstFrameTabContentPolicy.shouldScheduleInitialContentMount(
            isSelectionChange: false,
            deferInitialContentMount: false
        ))
    }

    @Test
    func firstFrameTabPolicyPreloadsWarmFirstVisitTabsThroughTabView() {
        #expect(FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .profile,
            hasFreshWarmSnapshot: true
        ))
        #expect(FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .profile,
            hasFreshWarmSnapshot: false,
            isWarmupActive: true
        ))
        #expect(FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .bros,
            hasFreshWarmSnapshot: true,
            isWarmupActive: false
        ))
        #expect(FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .bros,
            hasFreshWarmSnapshot: false,
            isWarmupActive: true
        ))
        #expect(!FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .profile,
            hasFreshWarmSnapshot: false,
            isWarmupActive: false
        ))
        #expect(!FirstFrameTabContentPolicy.shouldPreloadDeferredContent(
            tab: .history,
            hasFreshWarmSnapshot: true,
            isWarmupActive: true
        ))
    }

    @Test
    func startupWarmupGateWaitsForFastWarmups() async {
        let probe = WarmupGateProbe()
        let profileTask = Task {
            await probe.finishProfile()
        }
        let brosTask = Task {
            await probe.finishBros()
        }

        await StartupWarmupGate.waitForWarmups(
            profileTask: profileTask,
            brosTask: brosTask,
            timeout: .seconds(1)
        )

        #expect(await probe.didFinishProfile)
        #expect(await probe.didFinishBros)
    }

    @Test
    func startupWarmupGateReturnsAfterTimeoutWithoutCancellingWarmups() async {
        let probe = WarmupGateProbe()
        let profileTask = Task {
            await probe.waitForProfileRelease()
            await probe.finishProfile()
        }
        while await probe.isWaitingForProfileRelease == false {
            await Task.yield()
        }

        await StartupWarmupGate.waitForWarmups(
            profileTask: profileTask,
            brosTask: nil,
            timeout: .milliseconds(20)
        )

        #expect(await probe.didFinishProfile == false)

        await probe.releaseProfile()
        await profileTask.value
        #expect(await probe.didFinishProfile)
    }

    @MainActor
    @Test
    func profileActivationWaitsForActiveStartupWarmupToFinish() async throws {
        let state = AppWarmupState()
        let probe = WarmupGateProbe()
        let runID = try #require(state.beginProfileWarmup())

        let waiterTask = Task { @MainActor in
            await state.waitForActiveProfileWarmup()
            await probe.finishProfile()
        }

        await Task.yield()
        #expect(await probe.didFinishProfile == false)

        state.finishProfileWarmup(runID: runID, snapshot: nil)
        await waiterTask.value
        #expect(await probe.didFinishProfile)
    }

    @Test
    func startupWarmupLaunchPolicyStartsWarmupsAndOnlyWaitsOnFirstRun() {
        #expect(StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: false,
            hasBackgroundStore: true,
            shouldWarmProfile: true,
            shouldWarmBros: false
        ))
        #expect(StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: false,
            hasBackgroundStore: true,
            shouldWarmProfile: false,
            shouldWarmBros: true
        ))
        #expect(!StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: true,
            hasBackgroundStore: true,
            shouldWarmProfile: true,
            shouldWarmBros: true
        ))
        #expect(!StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: false,
            hasBackgroundStore: false,
            shouldWarmProfile: true,
            shouldWarmBros: true
        ))

        #expect(StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: false,
            hasAnyWarmup: true,
            isFirstRunLaunch: true
        ))
        #expect(!StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: true,
            hasAnyWarmup: true,
            isFirstRunLaunch: true
        ))
        #expect(!StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: false,
            hasAnyWarmup: true,
            isFirstRunLaunch: false
        ))
        #expect(!StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: false,
            hasAnyWarmup: false,
            isFirstRunLaunch: true
        ))
    }

    @Test
    func firstRunLocalBootstrapPolicyBlocksOnlyRealFirstLaunches() {
        #expect(FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: false,
            hasBackgroundStore: true,
            hasCompletedBootstrap: false
        ))
        #expect(!FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: true,
            hasBackgroundStore: true,
            hasCompletedBootstrap: false
        ))
        #expect(!FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: false,
            hasBackgroundStore: false,
            hasCompletedBootstrap: false
        ))
        #expect(!FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: false,
            hasBackgroundStore: true,
            hasCompletedBootstrap: true
        ))
    }

    @Test
    func firstRunLocalBootstrapProgressIsVersioned() {
        #expect(FirstRunLocalBootstrapProgress.isCompleted(appliedVersion: 0) == false)
        #expect(FirstRunLocalBootstrapProgress.isCompleted(
            appliedVersion: FirstRunLocalBootstrapProgress.currentVersion
        ))
    }

    @Test
    func firstRunLocalBootstrapWarmsProfileAndBrosSnapshotsBeforeMainEntry() throws {
        let source = try String(contentsOf: contentViewSourceURL(), encoding: .utf8)

        #expect(source.contains("let profileWarmSnapshot = try? await Self.buildProfileWarmSnapshot"))
        #expect(source.contains("let brosWarmSnapshot = try? await Self.buildBrosWarmSnapshot"))
        #expect(source.contains("FirstRunLocalBootstrapResult("))
        #expect(source.contains("profileWarmSnapshot: profileWarmSnapshot"))
        #expect(source.contains("brosWarmSnapshot: brosWarmSnapshot"))
        #expect(source.contains("appWarmupState.storeProfile(profileWarmSnapshot)"))
        #expect(source.contains("appWarmupState.storeBros(brosWarmSnapshot)"))
    }

    @Test
    func profileInitialLoadPolicyDefersReloadWhileStartupWarmupIsActive() {
        #expect(FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: false,
            hasCurrentProfile: false,
            isProfileWarmupActive: true,
            hasFreshWarmSnapshot: false
        ))
        #expect(!FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: false,
            hasCurrentProfile: false,
            isProfileWarmupActive: true,
            hasFreshWarmSnapshot: true
        ))
        #expect(!FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: false,
            hasCurrentProfile: false,
            isProfileWarmupActive: false,
            hasFreshWarmSnapshot: false
        ))
    }

    @Test
    func brosInitialActivationPolicyDefersRefreshWhileStartupWarmupIsActive() {
        #expect(BrosInitialActivationPolicy.shouldDeferActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            isBrosWarmupActive: true,
            hasFreshWarmSnapshot: false,
            hasNotificationRefreshRequest: false
        ))
        #expect(!BrosInitialActivationPolicy.shouldDeferActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            isBrosWarmupActive: true,
            hasFreshWarmSnapshot: true,
            hasNotificationRefreshRequest: false
        ))
        #expect(!BrosInitialActivationPolicy.shouldDeferActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            isBrosWarmupActive: true,
            hasFreshWarmSnapshot: false,
            hasNotificationRefreshRequest: true
        ))
        #expect(!BrosInitialActivationPolicy.shouldDeferActivationRefresh(
            hasCompletedInitialActivationRefresh: true,
            isBrosWarmupActive: true,
            hasFreshWarmSnapshot: false,
            hasNotificationRefreshRequest: false
        ))
    }

    @Test
    func brosInitialActivationPolicySkipsFirstRefreshWhenWarmSnapshotExists() {
        #expect(!BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            hasFreshWarmSnapshot: BrosWarmStateSnapshot.active(makeBrosSnapshot()).canSkipInitialActivationRefresh,
            hasNotificationRefreshRequest: false
        ))
        #expect(BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            hasFreshWarmSnapshot: BrosWarmStateSnapshot.unavailable("iCloud is temporarily unavailable.").canSkipInitialActivationRefresh,
            hasNotificationRefreshRequest: false
        ))
        #expect(BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            hasFreshWarmSnapshot: BrosWarmStateSnapshot.loading.canSkipInitialActivationRefresh,
            hasNotificationRefreshRequest: false
        ))
        #expect(BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            hasFreshWarmSnapshot: BrosWarmStateSnapshot.onboarding.canSkipInitialActivationRefresh,
            hasNotificationRefreshRequest: true
        ))
        #expect(BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: false,
            hasFreshWarmSnapshot: false,
            hasNotificationRefreshRequest: false
        ))
        #expect(BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: true,
            hasFreshWarmSnapshot: true,
            hasNotificationRefreshRequest: false
        ))
    }

    @Test
    func startupBrosWarmSnapshotPolicyAvoidsRemoteFetchWhenCloudIsAvailable() {
        #expect(BrosWarmSnapshotPolicy.stateBeforeRemoteFetch(
            cloudSyncEnabled: true,
            cloudSyncErrorDescription: nil,
            allowsRemoteFetch: false,
            unavailableMessage: "Unavailable"
        ) == .loading)
        #expect(BrosWarmSnapshotPolicy.stateBeforeRemoteFetch(
            cloudSyncEnabled: true,
            cloudSyncErrorDescription: nil,
            allowsRemoteFetch: true,
            unavailableMessage: "Unavailable"
        ) == nil)
        #expect(BrosWarmSnapshotPolicy.stateBeforeRemoteFetch(
            cloudSyncEnabled: true,
            cloudSyncErrorDescription: "iCloud is warming up.",
            allowsRemoteFetch: false,
            unavailableMessage: "Unavailable"
        ) == .unavailable("iCloud is warming up."))
        #expect(BrosWarmSnapshotPolicy.stateBeforeRemoteFetch(
            cloudSyncEnabled: false,
            cloudSyncErrorDescription: nil,
            allowsRemoteFetch: false,
            unavailableMessage: "Unavailable"
        ) == .unavailable("Unavailable"))
    }

    @Test
    func profileDashboardRenderPolicyDefersFirstDashboardMountEvenWhenProfileSnapshotIsWarm() {
        #expect(ProfileDashboardRenderPolicy.renderDelay(hasRenderedDashboardContent: false) == .milliseconds(450))
        #expect(ProfileDashboardRenderPolicy.renderDelay(hasRenderedDashboardContent: true) == .zero)
        #expect(ProfileDashboardRenderPolicy.renderDelay(
            hasRenderedDashboardContent: false,
            hasFreshWarmSnapshot: true
        ) == .milliseconds(450))
    }

    @Test
    func profileDashboardRenderPolicyPreservesRenderedContentWhenCancellingForTabExit() {
        #expect(ProfileDashboardRenderPolicy.visibilityAfterCancellingRender(
            hasRenderedDashboardContent: true,
            isTabExit: true
        ))
        #expect(!ProfileDashboardRenderPolicy.visibilityAfterCancellingRender(
            hasRenderedDashboardContent: false,
            isTabExit: true
        ))
        #expect(!ProfileDashboardRenderPolicy.visibilityAfterCancellingRender(
            hasRenderedDashboardContent: true,
            isTabExit: false
        ))
    }

    @Test
    func userDataSyncTrackerReportsRunningCloudImportAsSyncing() {
        let tracker = UserDataSyncTracker.shared
        var snapshot = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        #expect(snapshot.state == .caughtUp)

        snapshot = tracker.recordCloudEvent(CloudSyncEventSummary(
            type: .import,
            status: .running,
            storeIdentifier: "UserData",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            error: nil
        ))

        #expect(snapshot.state == .syncing)
        #expect(snapshot.runningCloudEventType == .import)
        #expect(snapshot.title == "Cloud sync in progress")

        snapshot = tracker.recordCloudEvent(CloudSyncEventSummary(
            type: .import,
            status: .succeeded,
            storeIdentifier: "UserData",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 120),
            error: nil
        ))

        #expect(snapshot.state == .caughtUp)
        #expect(snapshot.runningCloudEventType == nil)
    }

    @Test
    func profileReloadPolicySkipsFreshReloadWhenNothingChanged() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let refreshedAt = Date(timeIntervalSince1970: 1_040)

        #expect(!ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: true,
            needsExplicitRefresh: false,
            currentProfileUpdatedAt: updatedAt,
            lastLoadedProfileUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
    }

    @Test
    func timestampedReloadPolicyReloadsOnlyForDirtyChangedOrStaleContent() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let refreshedAt = Date(timeIntervalSince1970: 1_040)

        #expect(!TimestampedReloadPolicy.shouldReload(
            hasLoaded: true,
            needsExplicitRefresh: false,
            currentContentUpdatedAt: updatedAt,
            lastLoadedContentUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(TimestampedReloadPolicy.shouldReload(
            hasLoaded: false,
            needsExplicitRefresh: false,
            currentContentUpdatedAt: updatedAt,
            lastLoadedContentUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(TimestampedReloadPolicy.shouldReload(
            hasLoaded: true,
            needsExplicitRefresh: true,
            currentContentUpdatedAt: updatedAt,
            lastLoadedContentUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(TimestampedReloadPolicy.shouldReload(
            hasLoaded: true,
            needsExplicitRefresh: false,
            currentContentUpdatedAt: Date(timeIntervalSince1970: 1_120),
            lastLoadedContentUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(TimestampedReloadPolicy.shouldReload(
            hasLoaded: true,
            needsExplicitRefresh: false,
            currentContentUpdatedAt: updatedAt,
            lastLoadedContentUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_120),
            freshnessInterval: 60
        ))
    }

    @Test
    func runtimeCloudAvailabilityRefreshPolicyThrottlesUnresolvedAndResolvedRefreshes() {
        #expect(RuntimeCloudAvailabilityRefreshPolicy.shouldRefresh(
            cloudSyncEnabled: true,
            force: false,
            hasResolvedRuntimeCloudAvailability: false,
            isRefreshingRuntimeCloudAvailability: false,
            lastRefreshAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 110),
            unresolvedRetryInterval: 15,
            resolvedRefreshInterval: 300
        ) == false)

        #expect(RuntimeCloudAvailabilityRefreshPolicy.shouldRefresh(
            cloudSyncEnabled: true,
            force: false,
            hasResolvedRuntimeCloudAvailability: false,
            isRefreshingRuntimeCloudAvailability: false,
            lastRefreshAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 116),
            unresolvedRetryInterval: 15,
            resolvedRefreshInterval: 300
        ))

        #expect(RuntimeCloudAvailabilityRefreshPolicy.shouldRefresh(
            cloudSyncEnabled: true,
            force: false,
            hasResolvedRuntimeCloudAvailability: true,
            isRefreshingRuntimeCloudAvailability: false,
            lastRefreshAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 350),
            unresolvedRetryInterval: 15,
            resolvedRefreshInterval: 300
        ) == false)

        #expect(RuntimeCloudAvailabilityRefreshPolicy.shouldRefresh(
            cloudSyncEnabled: true,
            force: false,
            hasResolvedRuntimeCloudAvailability: true,
            isRefreshingRuntimeCloudAvailability: false,
            lastRefreshAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 401),
            unresolvedRetryInterval: 15,
            resolvedRefreshInterval: 300
        ))
    }


    @Test
    func profileReloadPolicyReloadsForExplicitRefreshProfileMutationOrStaleData() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let refreshedAt = Date(timeIntervalSince1970: 1_040)

        #expect(ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: false,
            needsExplicitRefresh: false,
            currentProfileUpdatedAt: updatedAt,
            lastLoadedProfileUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: true,
            needsExplicitRefresh: true,
            currentProfileUpdatedAt: updatedAt,
            lastLoadedProfileUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: true,
            needsExplicitRefresh: false,
            currentProfileUpdatedAt: Date(timeIntervalSince1970: 1_120),
            lastLoadedProfileUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_060),
            freshnessInterval: 60
        ))
        #expect(ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: true,
            needsExplicitRefresh: false,
            currentProfileUpdatedAt: updatedAt,
            lastLoadedProfileUpdatedAt: updatedAt,
            lastRefreshAt: refreshedAt,
            now: Date(timeIntervalSince1970: 1_120),
            freshnessInterval: 60
        ))
    }

    @Test
    func profileReloadPolicyKeepsFreshWarmSnapshotOffFirstActivationReloadPath() {
        #expect(!ProfileReloadPolicy.shouldReloadAfterApplyingWarmSnapshot(
            force: false,
            didApplyWarmSnapshot: true
        ))
        #expect(ProfileReloadPolicy.shouldReloadAfterApplyingWarmSnapshot(
            force: true,
            didApplyWarmSnapshot: true
        ))
        #expect(ProfileReloadPolicy.shouldReloadAfterApplyingWarmSnapshot(
            force: false,
            didApplyWarmSnapshot: false
        ))
    }

    @Test
    func asyncCloudStartupPreflightUsesLocalFallbackForNoAccount() async {
        let decision = await CloudStartupPreflight.makeDecisionAsync(
            statusProvider: MockAsyncCloudStartupAccountStatusProvider(status: .noAccount)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(decision.cloudSyncEnabled == false)
        #expect(decision.cloudSyncErrorDescription?.contains("No iCloud account") == true)
    }

    @Test
    func asyncCloudStartupPreflightUsesLocalFallbackForTransientStartupStatus() async {
        let decision = await CloudStartupPreflight.makeDecisionAsync(
            statusProvider: MockAsyncCloudStartupAccountStatusProvider(status: .timedOut)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(!decision.cloudSyncEnabled)
        #expect(decision.cloudSyncErrorDescription?.contains("timed out") == true)
    }

    @Test
    func asyncCloudStartupPreflightReturnsWhenAccountStatusNeverCompletes() async {
        let start = ContinuousClock.now

        let decision = await CloudStartupPreflight.makeDecisionAsync(
            statusProvider: HangingAsyncCloudStartupAccountStatusProvider(),
            timeout: .milliseconds(25)
        )

        let elapsed = start.duration(to: .now)
        #expect(decision.accountStatus == .timedOut)
        #expect(decision.storeMode == .localFallback)
        #expect(elapsed < .seconds(2))
    }

    @Test
    func appLaunchBootstrapResolverBuildsLocalFallbackWhenStartupDecisionRejectsCloud() async throws {
        let container = try makeContainer()
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(arguments: []),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                CloudStartupDecision(
                    accountStatus: .noAccount,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "No iCloud account is signed in on this device. Using local-only mode for this session."
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return container
            },
            makeCloudBackedContainer: {
                didRequestCloudContainer = true
                return container
            },
            makeLocalFallbackContainer: {
                didRequestLocalFallback = true
                return container
            },
            describeError: { _ in "unreachable" }
        )

        #expect(bootstrap.cloudSyncEnabled == false)
        #expect(bootstrap.cloudSyncErrorDescription?.contains("No iCloud account") == true)
        #expect(didRequestLocalFallback)
        #expect(!didRequestCloudContainer)
    }

    @Test
    func appLaunchBootstrapResolverUsesLocalFallbackForTimedOutStartupStatus() async throws {
        let container = try makeContainer()
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(arguments: []),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                await CloudStartupPreflight.makeDecisionAsync(
                    statusProvider: MockAsyncCloudStartupAccountStatusProvider(status: .timedOut)
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return container
            },
            makeCloudBackedContainer: {
                didRequestCloudContainer = true
                return container
            },
            makeLocalFallbackContainer: {
                didRequestLocalFallback = true
                return container
            },
            describeError: { _ in "unreachable" }
        )

        #expect(bootstrap.cloudSyncEnabled == false)
        #expect(bootstrap.cloudSyncErrorDescription?.contains("timed out") == true)
        #expect(!didRequestCloudContainer)
        #expect(didRequestLocalFallback)
    }

    @Test
    func cloudKitContainerAvailabilityOnlyAllowsExplicitICloudUITestLaunches() {
        #expect(AppRuntimeConfig.canUseConfiguredCloudKitContainer(
            isRunningXCTest: false,
            launchArguments: [],
            cloudKitContainerIdentifier: "iCloud.se.highball.WeGoJim"
        ))

        #expect(!AppRuntimeConfig.canUseConfiguredCloudKitContainer(
            isRunningXCTest: true,
            launchArguments: [],
            cloudKitContainerIdentifier: "iCloud.se.highball.WeGoJim"
        ))

        #expect(AppRuntimeConfig.canUseConfiguredCloudKitContainer(
            isRunningXCTest: true,
            launchArguments: ["UITEST_ENABLE_ICLOUD"],
            cloudKitContainerIdentifier: "iCloud.se.highball.WeGoJim"
        ))

        #expect(AppRuntimeConfig.isExplicitICloudUITestLaunch(
            isRunningXCTest: true,
            launchArguments: ["UITEST_ENABLE_ICLOUD"]
        ))

        #expect(!AppRuntimeConfig.isExplicitICloudUITestLaunch(
            isRunningXCTest: false,
            launchArguments: ["UITEST_ENABLE_ICLOUD"]
        ))

        #expect(!AppRuntimeConfig.isExplicitICloudUITestLaunch(
            isRunningXCTest: true,
            launchArguments: ["UITEST_ENABLE_ICLOUD", "UITEST_IN_MEMORY_STORE"]
        ))

        #expect(!AppRuntimeConfig.canUseConfiguredCloudKitContainer(
            isRunningXCTest: true,
            launchArguments: ["UITEST_ENABLE_ICLOUD", "UITEST_IN_MEMORY_STORE"],
            cloudKitContainerIdentifier: "iCloud.se.highball.WeGoJim"
        ))

        #expect(!AppRuntimeConfig.canUseConfiguredCloudKitContainer(
            isRunningXCTest: true,
            launchArguments: ["UITEST_ENABLE_ICLOUD"],
            cloudKitContainerIdentifier: "   "
        ))
    }

    @Test
    func appLaunchBootstrapResolverTrustsExplicitICloudUITestOptIn() async throws {
        let container = try makeContainer()
        var didRunStartupPreflight = false
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(
                arguments: ["UITEST_ENABLE_ICLOUD"],
                environment: ["XCTestConfigurationFilePath": "UITest.xctestconfiguration"]
            ),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                didRunStartupPreflight = true
                return CloudStartupDecision(
                    accountStatus: .timedOut,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "unreachable"
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return container
            },
            makeCloudBackedContainer: {
                didRequestCloudContainer = true
                return container
            },
            makeLocalFallbackContainer: {
                didRequestLocalFallback = true
                return container
            },
            describeError: { _ in "unreachable" }
        )

        #expect(bootstrap.cloudSyncEnabled)
        #expect(bootstrap.cloudSyncErrorDescription == nil)
        #expect(!didRunStartupPreflight)
        #expect(didRequestCloudContainer)
        #expect(!didRequestLocalFallback)
    }

    @Test
    func appLaunchBootstrapResolverRecognizesUITestLaunchArgumentsWithoutXCTestEnvironment() async throws {
        let container = try makeContainer()
        var didRunStartupPreflight = false
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(
                arguments: ["UITEST_SKIP_SPLASH", "UITEST_ENABLE_ICLOUD"],
                environment: [:]
            ),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                didRunStartupPreflight = true
                return CloudStartupDecision(
                    accountStatus: .temporarilyUnavailable,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "unreachable"
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return container
            },
            makeCloudBackedContainer: {
                didRequestCloudContainer = true
                return container
            },
            makeLocalFallbackContainer: {
                didRequestLocalFallback = true
                return container
            },
            describeError: { _ in "unreachable" }
        )

        #expect(bootstrap.cloudSyncEnabled)
        #expect(bootstrap.cloudSyncErrorDescription == nil)
        #expect(!didRunStartupPreflight)
        #expect(didRequestCloudContainer)
        #expect(!didRequestLocalFallback)
    }

    @Test
    func appLaunchBootstrapResolverDoesNotTrustICloudUITestOptInOutsideXCTest() async throws {
        let container = try makeContainer()
        var didRunStartupPreflight = false
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(
                arguments: ["UITEST_ENABLE_ICLOUD"],
                environment: [:]
            ),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                didRunStartupPreflight = true
                return CloudStartupDecision(
                    accountStatus: .noAccount,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "No iCloud account is signed in on this device. Using local-only mode for this session."
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return container
            },
            makeCloudBackedContainer: {
                didRequestCloudContainer = true
                return container
            },
            makeLocalFallbackContainer: {
                didRequestLocalFallback = true
                return container
            },
            describeError: { _ in "unreachable" }
        )

        #expect(bootstrap.cloudSyncEnabled == false)
        #expect(bootstrap.cloudSyncErrorDescription?.contains("No iCloud account") == true)
        #expect(didRunStartupPreflight)
        #expect(!didRequestCloudContainer)
        #expect(didRequestLocalFallback)
    }

    @Test
    func appLaunchBootstrapResolverFallsBackToLocalWhenCloudContainerCreationFails() async throws {
        let localFallbackContainer = try makeContainer()
        enum TestError: Error { case boom }

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(arguments: []),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                CloudStartupDecision(
                    accountStatus: .available,
                    storeMode: .cloudBacked,
                    cloudSyncErrorDescription: nil
                )
            },
            makeUITestContainer: {
                Issue.record("UI test container should not be requested.")
                return localFallbackContainer
            },
            makeCloudBackedContainer: {
                throw TestError.boom
            },
            makeLocalFallbackContainer: {
                localFallbackContainer
            },
            describeError: { error in
                String(describing: error)
            }
        )

        #expect(bootstrap.cloudSyncEnabled == false)
        #expect(bootstrap.cloudSyncErrorDescription?.contains("boom") == true)
    }

    @Test
    func runtimeCloudAvailabilityForceRefreshSupersedesStaleInFlightResults() async {
        let runtimeState = AppRuntimeState.makeTestingInstance()
        runtimeState.updateCloudState(isEnabled: true, errorDescription: nil)

        let accountService = ControlledRuntimeAccountStatusProvider()
        defer {
            Task {
                await accountService.resumeAll(with: .available)
            }
        }

        runtimeState.refreshCloudAvailabilityIfNeeded(accountService: accountService)
        await waitUntil("first runtime refresh starts") {
            await accountService.currentFetchCount() == 1
        }

        runtimeState.refreshCloudAvailabilityIfNeeded(force: true, accountService: accountService)
        await waitUntil("forced runtime refresh starts a second fetch") {
            await accountService.currentFetchCount() == 2
        }

        let fetchCount = await accountService.currentFetchCount()
        #expect(fetchCount == 2)

        await accountService.resumeNext(with: .unavailable(.temporarilyUnavailable))
        await Task.yield()
        #expect(runtimeState.cloudSyncErrorDescription == nil)

        await accountService.resumeNext(with: .available)
        await waitUntil("replacement runtime refresh clears the cloud error") {
            await MainActor.run {
                runtimeState.cloudSyncErrorDescription == nil
            }
        }

        #expect(runtimeState.cloudSyncErrorDescription == nil)
    }

    @Test
    func appLaunchBootstrapResolverHonorsTaskCancellationBeforeBuildingStores() async throws {
        let recorder = LockedBootstrapBuildRecorder()
        let container = try makeContainer()

        let task = Task {
            try await AppLaunchBootstrapResolver.resolve(
                processInfo: MockProcessInfo(arguments: []),
                canUseConfiguredCloudKitContainer: true,
                startupDecisionProvider: {
                    try? await Task.sleep(for: .milliseconds(200))
                    return CloudStartupDecision(
                        accountStatus: .available,
                        storeMode: .cloudBacked,
                        cloudSyncErrorDescription: nil
                    )
                },
                makeUITestContainer: {
                    recorder.recordUITestRequest()
                    return container
                },
                makeCloudBackedContainer: {
                    recorder.recordCloudRequest()
                    return container
                },
                makeLocalFallbackContainer: {
                    recorder.recordLocalFallbackRequest()
                    return container
                },
                describeError: { error in
                    String(describing: error)
                }
            )
        }

        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected bootstrap resolution to stop when the task is cancelled.")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected cancellation, got \(error).")
        }

        let counts = recorder.snapshot()
        #expect(counts.cloud == 0)
        #expect(counts.local == 0)
        #expect(counts.uiTest == 0)
    }

    @Test
    func deferredMaintenanceRunTrackerKeepsLaterRequestsPendingUntilNewestRunCompletes() throws {
        var tracker = DeferredMaintenanceRunTracker()
        let firstRunID = try #require(tracker.pendingRunID)

        tracker.requestRun()

        #expect(tracker.isPending)
        let completedStaleRun = tracker.markCompleted(runID: firstRunID)
        #expect(!completedStaleRun)

        let secondRunID = try #require(tracker.pendingRunID)
        #expect(secondRunID != firstRunID)
        let completedLatestRun = tracker.markCompleted(runID: secondRunID)
        #expect(completedLatestRun)
        #expect(!tracker.isPending)
    }

    private func makeProfileSnapshot(updatedAt: Date) -> ProfileIdentitySnapshot {
        let profile = UserProfile(displayName: "Atlas")
        profile.updatedAt = updatedAt
        return ProfileIdentitySnapshot(profile: profile)
    }

    private func makeBrosSnapshot() -> BrosFeedSnapshot {
        BrosFeedSnapshot(
            circle: BroCircleSummary(
                circleID: "circle-1",
                ownerUserRecordName: "user-1",
                inviteCode: "ABC123",
                memberLimit: 4,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            currentMember: BroMemberSummary(
                id: "membership-1",
                circleID: "circle-1",
                userRecordName: "user-1",
                displayName: "Atlas",
                athleteType: nil,
                avatarCacheKey: "membership-1",
                joinedAt: Date(timeIntervalSince1970: 30),
                role: .owner
            ),
            members: [
                BroMemberSummary(
                    id: "membership-1",
                    circleID: "circle-1",
                    userRecordName: "user-1",
                    displayName: "Atlas",
                    athleteType: nil,
                    avatarCacheKey: "membership-1",
                    joinedAt: Date(timeIntervalSince1970: 30),
                    role: .owner
                ),
            ],
            feedEvents: []
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([UserProfile.self]),
            configurations: [
                ModelConfiguration("Test", schema: Schema([UserProfile.self]), isStoredInMemoryOnly: true, cloudKitDatabase: .none),
            ]
        )
    }

    private func waitUntil(
        _ description: String,
        timeoutIterations: Int = 200,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if await condition() {
                return
            }
            await Task.yield()
        }

        Issue.record("Timed out waiting for \(description).")
    }
}

private struct MockAsyncCloudStartupAccountStatusProvider: AsyncCloudStartupAccountStatusProviding {
    let status: CloudStartupAccountStatus

    func currentStatus() async -> CloudStartupAccountStatus {
        status
    }
}

private struct HangingAsyncCloudStartupAccountStatusProvider: AsyncCloudStartupAccountStatusProviding {
    func currentStatus() async -> CloudStartupAccountStatus {
        await withCheckedContinuation { (_: CheckedContinuation<CloudStartupAccountStatus, Never>) in }
    }
}

private struct MockProcessInfo: ProcessInfoProviding {
    let arguments: [String]
    var environment: [String: String] = [:]
}

private actor WarmupGateProbe {
    private(set) var didFinishProfile = false
    private(set) var didFinishBros = false
    private(set) var isWaitingForProfileRelease = false
    private var profileReleaseContinuation: CheckedContinuation<Void, Never>?

    func waitForProfileRelease() async {
        isWaitingForProfileRelease = true
        await withCheckedContinuation { continuation in
            profileReleaseContinuation = continuation
        }
    }

    func releaseProfile() {
        profileReleaseContinuation?.resume()
        profileReleaseContinuation = nil
        isWaitingForProfileRelease = false
    }

    func finishProfile() {
        didFinishProfile = true
    }

    func finishBros() {
        didFinishBros = true
    }
}

private actor ControlledRuntimeAccountStatusProvider: AccountStatusProviding {
    private var fetchCount = 0
    private var continuations: [CheckedContinuation<AccountStatus, Never>] = []

    func fetchAccountStatus() async -> AccountStatus {
        fetchCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func currentFetchCount() -> Int {
        fetchCount
    }

    func resumeNext(with status: AccountStatus) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: status)
    }

    func resumeAll(with status: AccountStatus) {
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume(returning: status)
        }
    }
}

private func contentViewSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("WGJ")
        .appendingPathComponent("ContentView.swift")
}

private final class LockedBootstrapBuildRecorder: @unchecked Sendable {
    private let lock = NSLock()

    private(set) var cloudRequests = 0
    private(set) var localFallbackRequests = 0
    private(set) var uiTestRequests = 0

    func recordCloudRequest() {
        lock.lock()
        cloudRequests += 1
        lock.unlock()
    }

    func recordLocalFallbackRequest() {
        lock.lock()
        localFallbackRequests += 1
        lock.unlock()
    }

    func recordUITestRequest() {
        lock.lock()
        uiTestRequests += 1
        lock.unlock()
    }

    func snapshot() -> (cloud: Int, local: Int, uiTest: Int) {
        lock.lock()
        let snapshot = (cloud: cloudRequests, local: localFallbackRequests, uiTest: uiTestRequests)
        lock.unlock()
        return snapshot
    }
}
