import Foundation
import Observation
import SwiftData
import SwiftUI

enum UserDataCloudMirrorCoordinatorState: Equatable, Sendable {
    case idle
    case unavailable(String)
    case preparing
    case active
    case degraded(String)
}

@MainActor
@Observable
final class UserDataCloudMirrorCoordinator {
    private(set) var state: UserDataCloudMirrorCoordinatorState = .idle

    @ObservationIgnored private let makeBackupStore: @MainActor () -> any UserDataCloudBackupStoring
    @ObservationIgnored private let isCloudBackupEnabled: @MainActor () -> Bool
    @ObservationIgnored private var localContainer: ModelContainer?
    @ObservationIgnored private var mirrorContainer: ModelContainer?
    @ObservationIgnored private var mirrorBridge: (any UserDataCloudMirrorBridging)?
    @ObservationIgnored private var makeMirrorContainer: (@Sendable () throws -> ModelContainer)?
    @ObservationIgnored private var makeBridge: (@MainActor (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging)?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var postStartHydrationTask: Task<Void, Never>?
    @ObservationIgnored private var lastHandledCloudImportAt: Date?

    init(
        makeBackupStore: @escaping @MainActor () -> any UserDataCloudBackupStoring = {
            CloudKitUserDataCloudBackupStore()
        },
        isCloudBackupEnabled: @escaping @MainActor () -> Bool = {
            UserDataCloudMirrorCoordinator.defaultCloudBackupEnabled
        }
    ) {
        self.makeBackupStore = makeBackupStore
        self.isCloudBackupEnabled = isCloudBackupEnabled
    }

    func startIfNeeded(
        localContainer: ModelContainer,
        cloudRuntimeMode: CloudRuntimeMode,
        canUseConfiguredCloudKitContainer: Bool,
        makeMirrorContainer: @escaping @Sendable () throws -> ModelContainer,
        makeBridge: @escaping @MainActor (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging = {
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
                if self?.isCloudBackupEnabled() ?? true {
                    _ = try? await UserDataCloudBackupService(
                        localContainer: localContainer,
                        mirrorContainer: container,
                        backupStore: self?.makeBackupStore() ?? CloudKitUserDataCloudBackupStore()
                    ).restoreLatestBackup()
                }
                try await bridge.syncLocalChangesToMirror()
                if self?.isCloudBackupEnabled() ?? true {
                    _ = try? await UserDataCloudBackupService(
                        localContainer: localContainer,
                        mirrorContainer: container,
                        backupStore: self?.makeBackupStore() ?? CloudKitUserDataCloudBackupStore()
                    ).exportCurrentBackup()
                }
                self?.finishStart(
                    localContainer: localContainer,
                    mirrorContainer: container,
                    bridge: bridge,
                    makeMirrorContainer: makeMirrorContainer,
                    makeBridge: makeBridge
                )
            } catch {
                self?.failStart(errorDescription: String(describing: error))
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
                if let self,
                   let localContainer = self.localContainer,
                   let mirrorContainer = self.mirrorContainer,
                   self.isCloudBackupEnabled() {
                    try? await UserDataCloudBackupService(
                        localContainer: localContainer,
                        mirrorContainer: mirrorContainer,
                        backupStore: self.makeBackupStore()
                    ).exportCurrentBackup()
                }
            } catch {
                self?.failStart(errorDescription: String(describing: error))
            }
            self?.syncTask = nil
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
                self?.failStart(errorDescription: String(describing: error))
            }
            self?.syncTask = nil
        }
        syncTask = task
        await task.value
    }

    private func finishStart(
        localContainer: ModelContainer,
        mirrorContainer: ModelContainer,
        bridge: any UserDataCloudMirrorBridging,
        makeMirrorContainer: @escaping @Sendable () throws -> ModelContainer,
        makeBridge: @escaping @MainActor (ModelContainer, ModelContainer) -> any UserDataCloudMirrorBridging
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
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        UserDataSyncTrackerBridge.markLocalMutation()
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
        if isCloudBackupEnabled() {
            _ = try? await UserDataCloudBackupService(
                localContainer: localContainer,
                mirrorContainer: refreshedMirrorContainer,
                backupStore: makeBackupStore()
            ).restoreLatestBackup()
        }
        try await refreshedBridge.syncLocalChangesToMirror()
        if isCloudBackupEnabled() {
            _ = try? await UserDataCloudBackupService(
                localContainer: localContainer,
                mirrorContainer: refreshedMirrorContainer,
                backupStore: makeBackupStore()
            ).exportCurrentBackup()
        }
    }

    private func schedulePostStartHydrationPasses() {
        postStartHydrationTask?.cancel()
        postStartHydrationTask = Task { @MainActor [weak self] in
            for delay in [2, 6, 15] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.syncFromFreshMirrorIfActive()
            }
            self?.postStartHydrationTask = nil
        }
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
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
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
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
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
