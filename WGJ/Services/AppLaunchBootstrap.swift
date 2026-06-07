import Foundation
import Observation
import SwiftData

protocol ProcessInfoProviding {
    var arguments: [String] { get }
    var environment: [String: String] { get }
}

extension ProcessInfo: ProcessInfoProviding { }

struct ModelContainerBootstrap {
    let container: ModelContainer
    let storageMode: AppStorageMode
    let cloudRuntimeMode: CloudRuntimeMode
    let cloudFeaturesEnabled: Bool
    let userDataSyncEnabled: Bool
    let cloudSyncEnabled: Bool
    let cloudSyncErrorDescription: String?
}

struct ResolvedAppLaunchBootstrap {
    let bootstrap: ModelContainerBootstrap
    let backgroundStore: AppBackgroundStore
}

@MainActor
@Observable
final class AppLaunchBootstrapState {
    private(set) var resolvedBootstrap: ResolvedAppLaunchBootstrap?

    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var resolutionGeneration = 0

    func resolveIfNeeded(
        resolver: @escaping @Sendable () async throws -> ModelContainerBootstrap
    ) {
        guard resolvedBootstrap == nil, resolutionTask == nil else { return }

        resolutionGeneration += 1
        let currentGeneration = resolutionGeneration

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let bootstrap = try await resolver()
                guard !Task.isCancelled else { return }

                let resolved = ResolvedAppLaunchBootstrap(
                    bootstrap: bootstrap,
                    backgroundStore: AppBackgroundStore(container: bootstrap.container)
                )

                guard let self else { return }
                await self.finishResolution(
                    resolved,
                    bootstrap: bootstrap,
                    generation: currentGeneration
                )
            } catch is CancellationError {
                guard let self else { return }
                await self.clearResolutionTask(generation: currentGeneration)
            } catch {
                guard let self else { return }
                await self.clearResolutionTask(generation: currentGeneration)
                preconditionFailure("Could not create ModelContainer bootstrap: \(error)")
            }
        }

        resolutionTask = task
    }

    func reset() {
        resolutionGeneration += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        resolvedBootstrap = nil
    }

    private func finishResolution(
        _ resolved: ResolvedAppLaunchBootstrap,
        bootstrap: ModelContainerBootstrap,
        generation: Int
    ) {
        guard resolutionGeneration == generation else { return }
        guard resolutionTask != nil else { return }

        AppRuntimeState.shared.updateCloudState(
            storageMode: bootstrap.storageMode,
            runtimeMode: bootstrap.cloudRuntimeMode,
            isEnabled: bootstrap.cloudFeaturesEnabled,
            errorDescription: bootstrap.cloudSyncErrorDescription
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(
            UserDataSyncTrackerBridge.configureForLaunch(
                isCloudEnabled: bootstrap.userDataSyncEnabled,
                errorDescription: bootstrap.cloudSyncErrorDescription
            )
        )
        resolvedBootstrap = resolved
        resolutionTask = nil
    }

    private func clearResolutionTask(generation: Int) {
        guard resolutionGeneration == generation else { return }
        resolutionTask = nil
    }
}

enum AppLaunchBootstrapResolver {
    private static let uiTestInMemoryStoreArgument = "UITEST_IN_MEMORY_STORE"

    static func resolve(
        processInfo: any ProcessInfoProviding = ProcessInfo.processInfo,
        canUseConfiguredCloudKitContainer: Bool = AppRuntimeConfig.canUseConfiguredCloudKitContainer,
        startupDecisionProvider: @escaping @Sendable () async -> CloudStartupDecision = {
            await CloudStartupPreflight.makeDecisionAsync()
        },
        makeUITestContainer: @escaping @Sendable () throws -> ModelContainer,
        makeCloudBackedContainer: @escaping @Sendable () throws -> ModelContainer,
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        makeCloudFailureLocalFallbackContainer: (@Sendable () throws -> ModelContainer)? = nil,
        describeError: @escaping @Sendable (Error) -> String
    ) async throws -> ModelContainerBootstrap {
        if processInfo.arguments.contains(uiTestInMemoryStoreArgument) {
            return ModelContainerBootstrap(
                container: try makeUITestContainer(),
                storageMode: .localAuthoritative,
                cloudRuntimeMode: .unavailable("UI test run using an in-memory local container."),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: "UI test run using an in-memory local container."
            )
        }

        guard canUseConfiguredCloudKitContainer else {
            return ModelContainerBootstrap(
                container: try makeLocalFallbackContainer(),
                storageMode: .localAuthoritative,
                cloudRuntimeMode: .unavailable("CloudKit is unavailable for this build. Using local-only mode for this session."),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: "CloudKit is unavailable for this build. Using local-only mode for this session."
            )
        }

        _ = startupDecisionProvider
        _ = makeCloudBackedContainer
        _ = makeCloudFailureLocalFallbackContainer
        _ = describeError

        return ModelContainerBootstrap(
            container: try makeLocalFallbackContainer(),
            storageMode: .localAuthoritative,
            cloudRuntimeMode: .checking,
            cloudFeaturesEnabled: true,
            userDataSyncEnabled: false,
            cloudSyncEnabled: true,
            cloudSyncErrorDescription: nil
        )
    }
}
