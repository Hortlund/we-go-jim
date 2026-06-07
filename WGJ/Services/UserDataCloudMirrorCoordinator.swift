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

    @ObservationIgnored private var localContainer: ModelContainer?
    @ObservationIgnored private var mirrorContainer: ModelContainer?
    @ObservationIgnored private var mirrorBridge: (any UserDataCloudMirrorBridging)?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

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
                try await bridge.syncLocalChangesToMirror()
                self?.finishStart(
                    localContainer: localContainer,
                    mirrorContainer: container,
                    bridge: bridge
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
        bridge: any UserDataCloudMirrorBridging
    ) {
        self.localContainer = localContainer
        self.mirrorContainer = mirrorContainer
        mirrorBridge = bridge
        state = .active
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: true,
            errorDescription: nil
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        UserDataSyncTrackerBridge.markLocalMutation()
        startTask = nil
    }

    private func failStart(errorDescription: String) {
        state = .degraded(errorDescription)
        mirrorBridge = nil
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: false,
            errorDescription: errorDescription
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        startTask = nil
    }

    private func markUnavailable(_ reason: String) {
        state = .unavailable(reason)
        let snapshot = UserDataSyncTrackerBridge.configureForLaunch(
            isCloudEnabled: false,
            errorDescription: reason
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
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
