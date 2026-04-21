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
}

private struct MockAsyncCloudStartupAccountStatusProvider: AsyncCloudStartupAccountStatusProviding {
    let status: CloudStartupAccountStatus

    func currentStatus() async -> CloudStartupAccountStatus {
        status
    }
}

private struct MockProcessInfo: ProcessInfoProviding {
    let arguments: [String]
}
