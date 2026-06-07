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
            isEnabled: bootstrap.cloudSyncEnabled,
            errorDescription: bootstrap.cloudSyncErrorDescription
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(
            UserDataSyncTrackerBridge.configureForLaunch(
                isCloudEnabled: bootstrap.cloudSyncEnabled,
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
        cloudContainerBuildTimeout: Duration = .seconds(6),
        makeUITestContainer: @escaping @Sendable () throws -> ModelContainer,
        makeCloudBackedContainer: @escaping @Sendable () throws -> ModelContainer,
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        makeCloudFailureLocalFallbackContainer: (@Sendable () throws -> ModelContainer)? = nil,
        describeError: @escaping @Sendable (Error) -> String
    ) async throws -> ModelContainerBootstrap {
        if processInfo.arguments.contains(uiTestInMemoryStoreArgument) {
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

        let explicitICloudUITest = AppRuntimeConfig.isExplicitICloudUITestLaunch(
            isRunningXCTest: processInfo.environment["XCTestConfigurationFilePath"] != nil,
            launchArguments: processInfo.arguments
        )
        var cloudSyncErrorDescription: String?
        if !explicitICloudUITest {
            try Task.checkCancellation()
            let startupDecision = await startupDecisionProvider()
            try Task.checkCancellation()
            cloudSyncErrorDescription = startupDecision.cloudSyncErrorDescription
            if startupDecision.shouldForceLocalFallbackStore {
                return ModelContainerBootstrap(
                    container: try makeLocalFallbackContainer(),
                    cloudSyncEnabled: false,
                    cloudSyncErrorDescription: startupDecision.cloudSyncErrorDescription
                )
            }
        }

        do {
            try Task.checkCancellation()
            return ModelContainerBootstrap(
                container: try await makeCloudBackedContainerWithTimeout(
                    timeout: cloudContainerBuildTimeout,
                    makeCloudBackedContainer: makeCloudBackedContainer
                ),
                cloudSyncEnabled: true,
                cloudSyncErrorDescription: cloudSyncErrorDescription
            )
        } catch {
            let fallbackContainer = try (makeCloudFailureLocalFallbackContainer ?? makeLocalFallbackContainer)()
            return ModelContainerBootstrap(
                container: fallbackContainer,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: describeError(error)
            )
        }
    }

    private static func makeCloudBackedContainerWithTimeout(
        timeout: Duration,
        makeCloudBackedContainer: @escaping @Sendable () throws -> ModelContainer
    ) async throws -> ModelContainer {
        let resultBox = CloudContainerBuildResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                resultBox.finish(.success(try makeCloudBackedContainer()))
            } catch {
                resultBox.finish(.failure(error))
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let result = resultBox.result() {
                return try result.get()
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }

        if let result = resultBox.result() {
            return try result.get()
        }
        throw CloudContainerBuildTimeoutError(timeout: timeout)
    }
}

private struct CloudContainerBuildTimeoutError: Error, CustomStringConvertible {
    let timeout: Duration

    var description: String {
        "Cloud-backed store creation timed out after \(timeout)."
    }
}

private final class CloudContainerBuildResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<ModelContainer, Error>?

    func finish(_ result: Result<ModelContainer, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard storedResult == nil else { return }
        storedResult = result
    }

    func result() -> Result<ModelContainer, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}
