import Foundation
import SwiftData
import SwiftUI

nonisolated enum UserDataCloudMirrorCoordinatorState: Equatable, Sendable {
    case idle
    case unavailable(String)
    case preparing
    case active
    case degraded(String)
}

nonisolated enum UserDataCloudMirrorStartupPolicy {
    static let postStartHydrationDelays: [Duration] = [
        .seconds(30),
        .seconds(120),
        .seconds(300),
    ]
}

actor UserDataCloudMirrorCoordinator {
    private(set) var state: UserDataCloudMirrorCoordinatorState = .idle
    private(set) var lastUserDataSyncSnapshot: UserDataSyncStatusSnapshot?

    private let makeBackupStore: @Sendable () -> any UserDataCloudBackupStoring
    private let isCloudBackupEnabled: @Sendable () -> Bool
    private let postStartHydrationDelays: [Duration]
    private var localContainer: ModelContainer?
    private var mirrorContainer: ModelContainer?
    private var mirrorBridge: (any UserDataCloudMirrorBridging)?
    private var makeMirrorContainer: (@Sendable () throws -> ModelContainer)?
    private var makeBridge: (@Sendable (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging)?
    private var startTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var postStartHydrationTask: Task<Void, Never>?
    private var lastHandledCloudImportAt: Date?

    init(
        makeBackupStore: @escaping @Sendable () -> any UserDataCloudBackupStoring = {
            CloudKitUserDataCloudBackupStore()
        },
        isCloudBackupEnabled: @escaping @Sendable () -> Bool = {
            UserDataCloudMirrorCoordinator.defaultCloudBackupEnabled
        },
        postStartHydrationDelays: [Duration] = UserDataCloudMirrorStartupPolicy.postStartHydrationDelays
    ) {
        self.makeBackupStore = makeBackupStore
        self.isCloudBackupEnabled = isCloudBackupEnabled
        self.postStartHydrationDelays = postStartHydrationDelays
    }

    deinit {
        startTask?.cancel()
        syncTask?.cancel()
        postStartHydrationTask?.cancel()
    }

    func startIfNeeded(
        localContainer: ModelContainer,
        cloudRuntimeMode: CloudRuntimeMode,
        canUseConfiguredCloudKitContainer: Bool,
        makeMirrorContainer: @escaping @Sendable () throws -> ModelContainer,
        makeBridge: @escaping @Sendable (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging = {
            UserDataCloudMirrorBridge(localContainer: $0, mirrorContainer: $1)
        }
    ) async {
        guard mirrorContainer == nil else { return }
        guard startTask == nil else {
            await startTask?.value
            return
        }

        guard canUseConfiguredCloudKitContainer else {
            markUnavailable("CloudKit is unavailable for this build. User data is saved locally.")
            return
        }

        guard cloudRuntimeMode == .available else {
            if cloudRuntimeMode == .checking {
                return
            }
            markUnavailable(cloudRuntimeMode.errorDescription ?? "CloudKit is unavailable right now. User data is saved locally.")
            return
        }

        state = .preparing
        let task = Task { [weak self] in
            do {
                let container = try await Task.detached(priority: .utility) {
                    try makeMirrorContainer()
                }.value
                let bridge = makeBridge(localContainer, container)
                let isCloudBackupEnabled = await self?.isDirectBackupEnabled() ?? true
                if isCloudBackupEnabled {
                    _ = try? await UserDataCloudBackupService(
                        localContainer: localContainer,
                        mirrorContainer: container,
                        backupStore: await self?.makeDirectBackupStore() ?? CloudKitUserDataCloudBackupStore()
                    ).restoreLatestBackup()
                }
                try await bridge.syncLocalChangesToMirror()
                if isCloudBackupEnabled {
                    _ = try? await UserDataCloudBackupService(
                        localContainer: localContainer,
                        mirrorContainer: container,
                        backupStore: await self?.makeDirectBackupStore() ?? CloudKitUserDataCloudBackupStore()
                    ).exportCurrentBackup()
                }
                await self?.finishStart(
                    localContainer: localContainer,
                    mirrorContainer: container,
                    bridge: bridge,
                    makeMirrorContainer: makeMirrorContainer,
                    makeBridge: makeBridge
                )
            } catch {
                await self?.failStart(errorDescription: String(describing: error))
            }
        }
        startTask = task
        await task.value
    }

    func syncIfActive() async {
        guard state == .active, let mirrorBridge else { return }
        guard syncTask == nil else {
            await syncTask?.value
            return
        }

        let task = Task { [weak self, mirrorBridge] in
            do {
                try await mirrorBridge.syncLocalChangesToMirror()
            } catch {
                await self?.failStart(errorDescription: String(describing: error))
            }
            await self?.clearSyncTask()
        }
        syncTask = task
        await task.value
    }

    func syncAfterCloudImportIfActive(importFinishedAt: Date?) async {
        guard let importFinishedAt else { return }
        guard state == .active else { return }
        if let lastHandledCloudImportAt,
           importFinishedAt <= lastHandledCloudImportAt {
            return
        }

        await syncFromFreshMirrorIfActive()
        if state == .active {
            lastHandledCloudImportAt = importFinishedAt
        }
    }

    func syncFromFreshMirrorIfActive() async {
        guard state == .active,
              localContainer != nil,
              makeMirrorContainer != nil,
              makeBridge != nil
        else {
            return
        }
        guard syncTask == nil else {
            await syncTask?.value
            return
        }

        let task = Task { [weak self] in
            do {
                try await self?.rebuildMirrorBridgeAndSync()
            } catch {
                await self?.failStart(errorDescription: String(describing: error))
            }
            await self?.clearSyncTask()
        }
        syncTask = task
        await task.value
    }

    private func finishStart(
        localContainer: ModelContainer,
        mirrorContainer: ModelContainer,
        bridge: any UserDataCloudMirrorBridging,
        makeMirrorContainer: @escaping @Sendable () throws -> ModelContainer,
        makeBridge: @escaping @Sendable (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging
    ) {
        self.localContainer = localContainer
        self.mirrorContainer = mirrorContainer
        mirrorBridge = bridge
        self.makeMirrorContainer = makeMirrorContainer
        self.makeBridge = makeBridge
        state = .active
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: true,
            errorDescription: nil
        )
        lastUserDataSyncSnapshot = snapshot
        Task { @MainActor in
            AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        }
        schedulePostStartHydrationPasses()
        startTask = nil
    }

    private func rebuildMirrorBridgeAndSync() async throws {
        guard let localContainer,
              let makeMirrorContainer,
              let makeBridge
        else {
            return
        }

        let refreshedMirrorContainer = try await Task.detached(priority: .utility) {
            try makeMirrorContainer()
        }.value
        let refreshedBridge = makeBridge(localContainer, refreshedMirrorContainer)
        mirrorContainer = refreshedMirrorContainer
        mirrorBridge = refreshedBridge
        if isDirectBackupEnabled() {
            _ = try? await UserDataCloudBackupService(
                localContainer: localContainer,
                mirrorContainer: refreshedMirrorContainer,
                backupStore: makeDirectBackupStore()
            ).restoreLatestBackup()
        }
        try await refreshedBridge.syncLocalChangesToMirror()
        if isDirectBackupEnabled() {
            _ = try? await UserDataCloudBackupService(
                localContainer: localContainer,
                mirrorContainer: refreshedMirrorContainer,
                backupStore: makeDirectBackupStore()
            ).exportCurrentBackup()
        }
    }

    private func schedulePostStartHydrationPasses() {
        guard !postStartHydrationDelays.isEmpty else { return }
        postStartHydrationTask?.cancel()
        let delays = postStartHydrationDelays
        postStartHydrationTask = Task.detached(priority: .utility) { [weak self, delays] in
            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.syncFromFreshMirrorIfActive()
            }
            await self?.clearPostStartHydrationTask()
        }
    }

    private func clearPostStartHydrationTask() {
        postStartHydrationTask = nil
    }

    private func clearSyncTask() {
        syncTask = nil
    }

    private func isDirectBackupEnabled() -> Bool {
        isCloudBackupEnabled()
    }

    private func makeDirectBackupStore() -> any UserDataCloudBackupStoring {
        makeBackupStore()
    }

    private func failStart(errorDescription: String) {
        state = .degraded(errorDescription)
        mirrorBridge = nil
        makeMirrorContainer = nil
        makeBridge = nil
        postStartHydrationTask?.cancel()
        postStartHydrationTask = nil
        lastHandledCloudImportAt = nil
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: false,
            errorDescription: errorDescription
        )
        lastUserDataSyncSnapshot = snapshot
        Task { @MainActor in
            AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        }
        startTask = nil
    }

    private func markUnavailable(_ reason: String) {
        state = .unavailable(reason)
        postStartHydrationTask?.cancel()
        postStartHydrationTask = nil
        lastHandledCloudImportAt = nil
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: false,
            errorDescription: reason
        )
        lastUserDataSyncSnapshot = snapshot
        Task { @MainActor in
            AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        }
    }

    private nonisolated static var defaultCloudBackupEnabled: Bool {
#if DEBUG
        !ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_USER_DATA_CLOUD_BACKUP")
#else
        true
#endif
    }
}

enum UserDataCloudMirrorContainerFactoryError: Error, CustomStringConvertible {
    case unconfigured

    var description: String {
        "User data CloudKit mirror container factory is not configured."
    }
}

private struct UserDataCloudMirrorContainerFactoryKey: EnvironmentKey {
    static let defaultValue: @Sendable () throws -> ModelContainer = {
        throw UserDataCloudMirrorContainerFactoryError.unconfigured
    }
}

extension EnvironmentValues {
    var makeUserDataCloudMirrorContainer: @Sendable () throws -> ModelContainer {
        get { self[UserDataCloudMirrorContainerFactoryKey.self] }
        set { self[UserDataCloudMirrorContainerFactoryKey.self] = newValue }
    }
}
