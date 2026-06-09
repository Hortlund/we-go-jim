import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
struct UserDataCloudMirrorCoordinatorTests {
    @Test
    func coordinatorEnablesUserDataSyncOnlyAfterMirrorContainerIsBuilt() async throws {
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: false, errorDescription: "Local launch")
        defer {
            _ = tracker.configureForLaunch(isCloudEnabled: false, errorDescription: nil)
        }

        let mirrorContainer = try makeContainer()
        let buildRecorder = LockedMirrorBuildRecorder()
        let bridge = CountingMirrorBridge()
        let coordinator = UserDataCloudMirrorCoordinator(
            isCloudBackupEnabled: {
                false
            },
            postStartHydrationDelays: []
        )

        await coordinator.startIfNeeded(
            localContainer: mirrorContainer,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                buildRecorder.recordBuild()
                return mirrorContainer
            },
            makeBridge: { _, _ in
                bridge
            }
        )

        #expect(buildRecorder.didBuild)
        #expect(await bridge.syncCount == 1)
        #expect(await coordinator.state == .active)
        let snapshot = try #require(await coordinator.lastUserDataSyncSnapshot)
        #expect(snapshot.cloudSyncEnabled)
        #expect(snapshot.state == .caughtUp)
        #expect(snapshot.latestLocalMutationAt == nil)
    }

    @Test
    func coordinatorKeepsUserDataSyncLocalOnlyWhenCloudKitCannotBeUsed() async throws {
        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: false, errorDescription: nil)
        defer {
            _ = tracker.configureForLaunch(isCloudEnabled: false, errorDescription: nil)
        }

        let coordinator = UserDataCloudMirrorCoordinator(postStartHydrationDelays: [])

        await coordinator.startIfNeeded(
            localContainer: try makeContainer(),
            cloudRuntimeMode: .unavailable("No iCloud account is signed in."),
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                Issue.record("Mirror container should not be built when CloudKit is unavailable.")
                return try makeContainer()
            }
        )

        #expect(await coordinator.state == .unavailable("No iCloud account is signed in."))
        let snapshot = try #require(await coordinator.lastUserDataSyncSnapshot)
        #expect(!snapshot.cloudSyncEnabled)
    }

    @Test
    func coordinatorRunsActiveBridgeAgainWhenExplicitSyncIsRequested() async throws {
        let container = try makeContainer()
        let bridge = CountingMirrorBridge()
        let coordinator = UserDataCloudMirrorCoordinator(postStartHydrationDelays: [])

        await coordinator.startIfNeeded(
            localContainer: container,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                container
            },
            makeBridge: { _, _ in
                bridge
            }
        )

        #expect(await bridge.syncCount == 1)

        await coordinator.syncIfActive()

        #expect(await bridge.syncCount == 2)
    }

    @Test
    func coordinatorCanDisableDirectBackupWithoutDisablingMirrorBridge() async throws {
        let container = try makeContainer()
        let bridge = CountingMirrorBridge()
        let backupFactory = LockedBackupFactory()
        let coordinator = UserDataCloudMirrorCoordinator(
            makeBackupStore: {
                backupFactory.makeStore()
            },
            isCloudBackupEnabled: {
                false
            },
            postStartHydrationDelays: []
        )

        await coordinator.startIfNeeded(
            localContainer: container,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                container
            },
            makeBridge: { _, _ in
                bridge
            }
        )

        await coordinator.syncIfActive()

        #expect(await bridge.syncCount == 2)
        #expect(!backupFactory.didBuild)
    }

    @Test
    func routineActiveSyncDoesNotRunDirectBackupExport() async throws {
        let container = try makeContainer()
        let bridge = CountingMirrorBridge()
        let backupStore = CountingBackupStore()
        let coordinator = UserDataCloudMirrorCoordinator(
            makeBackupStore: {
                backupStore
            },
            isCloudBackupEnabled: {
                true
            },
            postStartHydrationDelays: []
        )

        await coordinator.startIfNeeded(
            localContainer: container,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                container
            },
            makeBridge: { _, _ in
                bridge
            }
        )
        let fetchCountAfterStart = await backupStore.fetchCount
        let saveCountAfterStart = await backupStore.saveCount

        await coordinator.syncIfActive()

        #expect(await bridge.syncCount == 2)
        #expect(await backupStore.fetchCount == fetchCountAfterStart)
        #expect(await backupStore.saveCount == saveCountAfterStart)
    }

    @Test
    func coordinatorRunsActiveBridgeWhenCloudImportCompletes() async throws {
        let container = try makeContainer()
        let bridge = CountingMirrorBridge()
        let coordinator = UserDataCloudMirrorCoordinator(postStartHydrationDelays: [])

        await coordinator.startIfNeeded(
            localContainer: container,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                container
            },
            makeBridge: { _, _ in
                bridge
            }
        )

        #expect(await bridge.syncCount == 1)

        await coordinator.syncAfterCloudImportIfActive(importFinishedAt: Date(timeIntervalSinceReferenceDate: 100))

        #expect(await bridge.syncCount == 2)
    }

    @Test
    func coordinatorDeduplicatesAlreadyHandledCloudImport() async throws {
        let container = try makeContainer()
        let bridge = CountingMirrorBridge()
        let coordinator = UserDataCloudMirrorCoordinator(postStartHydrationDelays: [])
        let importFinishedAt = Date(timeIntervalSinceReferenceDate: 100)

        await coordinator.startIfNeeded(
            localContainer: container,
            cloudRuntimeMode: .available,
            canUseConfiguredCloudKitContainer: true,
            makeMirrorContainer: {
                container
            },
            makeBridge: { _, _ in
                bridge
            }
        )

        await coordinator.syncAfterCloudImportIfActive(importFinishedAt: importFinishedAt)
        await coordinator.syncAfterCloudImportIfActive(importFinishedAt: importFinishedAt)

        #expect(await bridge.syncCount == 2)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
        ])
        let configuration = ModelConfiguration(
            "UserDataCloudMirrorCoordinatorTest-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private final class LockedMirrorBuildRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var hasBuilt = false

    var didBuild: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasBuilt
    }

    func recordBuild() {
        lock.lock()
        defer { lock.unlock() }
        hasBuilt = true
    }
}

private actor CountingMirrorBridge: UserDataCloudMirrorBridging {
    private var count = 0

    var syncCount: Int {
        count
    }

    func syncLocalChangesToMirror() async throws {
        count += 1
    }
}

private final class LockedBackupFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var hasBuilt = false

    var didBuild: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasBuilt
    }

    func makeStore() -> any UserDataCloudBackupStoring {
        lock.lock()
        hasBuilt = true
        lock.unlock()
        return UnusedBackupStore()
    }
}

private struct UnusedBackupStore: UserDataCloudBackupStoring {
    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws {
        Issue.record("Backup store should not save when direct backup is disabled.")
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        Issue.record("Backup store should not fetch when direct backup is disabled.")
        return nil
    }
}

private actor CountingBackupStore: UserDataCloudBackupStoring {
    private var fetched = 0
    private var saved = 0

    var fetchCount: Int {
        fetched
    }

    var saveCount: Int {
        saved
    }

    func saveBackup(_ record: UserDataCloudBackupRemoteRecord) async throws {
        _ = record
        saved += 1
    }

    func fetchBackup() async throws -> UserDataCloudBackupRemoteRecord? {
        fetched += 1
        return nil
    }
}
