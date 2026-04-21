import Foundation
import Observation
import SwiftData

protocol ProcessInfoProviding {
    var arguments: [String] { get }
}

extension ProcessInfo: ProcessInfoProviding { }

struct ModelContainerBootstrap {
    let container: ModelContainer
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

    func resolveIfNeeded(
        resolver: @escaping @Sendable () async throws -> ModelContainerBootstrap
    ) {
        guard resolvedBootstrap == nil, resolutionTask == nil else { return }

        resolutionTask = Task { @MainActor [weak self] in
            defer { self?.resolutionTask = nil }

            do {
                let bootstrap = try await resolver()
                let resolved = ResolvedAppLaunchBootstrap(
                    bootstrap: bootstrap,
                    backgroundStore: AppBackgroundStore(container: bootstrap.container)
                )
                AppRuntimeState.shared.updateCloudState(
                    isEnabled: bootstrap.cloudSyncEnabled,
                    errorDescription: bootstrap.cloudSyncErrorDescription
                )
                AppRuntimeState.shared.updateUserDataSyncStatus(
                    UserDataSyncTrackerBridge.configureForLaunch(
                        isCloudEnabled: bootstrap.cloudSyncEnabled,
                        errorDescription: bootstrap.cloudSyncErrorDescription
                    )
                )
                self?.resolvedBootstrap = resolved
            } catch {
                preconditionFailure("Could not create ModelContainer bootstrap: \(error)")
            }
        }
    }

    func reset() {
        resolutionTask?.cancel()
        resolutionTask = nil
        resolvedBootstrap = nil
    }
}

enum AppLaunchBootstrapResolver {
    static func resolve(
        processInfo: any ProcessInfoProviding = ProcessInfo.processInfo,
        canUseConfiguredCloudKitContainer: Bool = AppRuntimeConfig.canUseConfiguredCloudKitContainer,
        startupDecisionProvider: @escaping @Sendable () async -> CloudStartupDecision = {
            await CloudStartupPreflight.makeDecisionAsync()
        },
        makeUITestContainer: @escaping @Sendable () throws -> ModelContainer,
        makeCloudBackedContainer: @escaping @Sendable () throws -> ModelContainer,
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        describeError: @escaping @Sendable (Error) -> String
    ) async throws -> ModelContainerBootstrap {
        if processInfo.arguments.contains("UITEST_IN_MEMORY_STORE") {
            return ModelContainerBootstrap(
                container: try makeUITestContainer(),
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: "UI test run using an in-memory local container."
            )
        }

        guard canUseConfiguredCloudKitContainer else {
            return ModelContainerBootstrap(
                container: try makeLocalFallbackContainer(),
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: "CloudKit is unavailable for this build. Using local-only mode for this session."
            )
        }

        let startupDecision = await startupDecisionProvider()
        if startupDecision.shouldForceLocalFallbackStore {
            return ModelContainerBootstrap(
                container: try makeLocalFallbackContainer(),
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: startupDecision.cloudSyncErrorDescription
            )
        }

        do {
            return ModelContainerBootstrap(
                container: try makeCloudBackedContainer(),
                cloudSyncEnabled: true,
                cloudSyncErrorDescription: nil
            )
        } catch {
            let fallbackContainer = try makeLocalFallbackContainer()
            return ModelContainerBootstrap(
                container: fallbackContainer,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: describeError(error)
            )
        }
    }
}
