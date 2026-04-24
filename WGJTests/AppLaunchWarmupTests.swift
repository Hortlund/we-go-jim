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
    func appWarmupStateIgnoresLateWarmupResultsAfterInvalidationOrNewerRun() throws {
        let state = AppWarmupState()
        let firstRunID = try #require(state.beginProfileWarmup())
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

        let brosRunID = try #require(state.beginBrosWarmup())
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
    func asyncCloudStartupPreflightUsesLocalFallbackForNoAccount() async {
        let decision = await CloudStartupPreflight.makeDecisionAsync(
            statusProvider: MockAsyncCloudStartupAccountStatusProvider(status: .noAccount)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(decision.cloudSyncEnabled == false)
        #expect(decision.cloudSyncErrorDescription?.contains("No iCloud account") == true)
    }

    @Test
    func asyncCloudStartupPreflightUsesLocalFallbackForTimedOutStatus() async {
        let decision = await CloudStartupPreflight.makeDecisionAsync(
            statusProvider: MockAsyncCloudStartupAccountStatusProvider(status: .timedOut)
        )

        #expect(decision.storeMode == .localFallback)
        #expect(decision.cloudSyncEnabled == false)
        #expect(decision.cloudSyncErrorDescription?.contains("timed out") == true)
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
    func appLaunchBootstrapResolverBuildsLocalFallbackForTimedOutStartupStatus() async throws {
        let container = try makeContainer()
        var didRequestCloudContainer = false
        var didRequestLocalFallback = false

        let bootstrap = try await AppLaunchBootstrapResolver.resolve(
            processInfo: MockProcessInfo(arguments: []),
            canUseConfiguredCloudKitContainer: true,
            startupDecisionProvider: {
                CloudStartupDecision(
                    accountStatus: .timedOut,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "The iCloud account check timed out during launch. Using local-only mode for this session."
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
                    accountStatus: .timedOut,
                    storeMode: .localFallback,
                    cloudSyncErrorDescription: "The iCloud account check timed out during launch. Using local-only mode for this session."
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

private struct MockProcessInfo: ProcessInfoProviding {
    let arguments: [String]
    var environment: [String: String] = [:]
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
