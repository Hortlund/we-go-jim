import Foundation
import Observation
import SwiftData
import UIKit

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
        resolver: @escaping @Sendable () async throws -> ModelContainerBootstrap,
        failureFallback: (@Sendable (Error) async throws -> ModelContainerBootstrap)? = nil
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
                if let failureFallback {
                    do {
                        let bootstrap = try await failureFallback(error)
                        guard !Task.isCancelled else { return }

                        let resolved = ResolvedAppLaunchBootstrap(
                            bootstrap: bootstrap,
                            backgroundStore: AppBackgroundStore(container: bootstrap.container)
                        )

                        await self.finishResolution(
                            resolved,
                            bootstrap: bootstrap,
                            generation: currentGeneration
                        )
                    } catch {
                        await self.clearResolutionTask(generation: currentGeneration)
                        print("Could not create ModelContainer bootstrap: \(error)")
                    }
                } else {
                    await self.clearResolutionTask(generation: currentGeneration)
                    print("Could not create ModelContainer bootstrap: \(error)")
                }
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
            bootstrap.userDataSyncEnabled
                ? .backedUp(at: nil)
                : .localOnly(reason: bootstrap.cloudSyncErrorDescription)
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
        makeEmergencyInMemoryContainer: (@Sendable () throws -> ModelContainer)? = nil,
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
            return try makeLocalBootstrap(
                makeLocalFallbackContainer: makeLocalFallbackContainer,
                makeEmergencyInMemoryContainer: makeEmergencyInMemoryContainer,
                localOnlyDescription: "CloudKit is unavailable for this build. Using local-only mode for this session.",
                describeError: describeError
            )
        }

        _ = startupDecisionProvider
        _ = makeCloudBackedContainer
        _ = makeCloudFailureLocalFallbackContainer
        _ = describeError

        return try makeLocalBootstrap(
            makeLocalFallbackContainer: makeLocalFallbackContainer,
            makeEmergencyInMemoryContainer: makeEmergencyInMemoryContainer,
            localOnlyDescription: nil,
            describeError: describeError
        )
    }

    private static func makeLocalBootstrap(
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        makeEmergencyInMemoryContainer: (@Sendable () throws -> ModelContainer)?,
        localOnlyDescription: String?,
        describeError: @escaping @Sendable (Error) -> String
    ) throws -> ModelContainerBootstrap {
        do {
            return ModelContainerBootstrap(
                container: try makeLocalFallbackContainer(),
                storageMode: .localAuthoritative,
                cloudRuntimeMode: localOnlyDescription.map(CloudRuntimeMode.unavailable) ?? .checking,
                cloudFeaturesEnabled: localOnlyDescription == nil,
                userDataSyncEnabled: false,
                cloudSyncEnabled: localOnlyDescription == nil,
                cloudSyncErrorDescription: localOnlyDescription
            )
        } catch {
            guard let makeEmergencyInMemoryContainer else {
                throw error
            }

            let description = "Local storage could not be opened. Keeping the app running in temporary local-only mode. \(describeError(error))"
            return ModelContainerBootstrap(
                container: try makeEmergencyInMemoryContainer(),
                storageMode: .localAuthoritative,
                cloudRuntimeMode: .unavailable(description),
                cloudFeaturesEnabled: false,
                userDataSyncEnabled: false,
                cloudSyncEnabled: false,
                cloudSyncErrorDescription: description
            )
        }
    }
}

final class AppLifecycleDiagnostics {
    static let shared = AppLifecycleDiagnostics()

    private enum Key {
        static let launchID = "appLifecycleDiagnostics.launchID"
        static let state = "appLifecycleDiagnostics.state"
        static let launchStartedAt = "appLifecycleDiagnostics.launchStartedAt"
        static let lastMemoryWarningAt = "appLifecycleDiagnostics.lastMemoryWarningAt"
        static let lastUnexpectedRestartAt = "appLifecycleDiagnostics.lastUnexpectedRestartAt"
        static let lastUnexpectedRestartReason = "appLifecycleDiagnostics.lastUnexpectedRestartReason"
    }

    private enum State {
        static let launching = "launching"
        static let active = "active"
        static let inactive = "inactive"
        static let background = "background"
        static let terminated = "terminated"
    }

    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var didStart = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        recordLaunch()
        installObservers()
    }

    private func recordLaunch(date: Date = .now) {
        let previousLaunchID = defaults.string(forKey: Key.launchID)
        let previousState = defaults.string(forKey: Key.state)
        if previousLaunchID != nil, previousState != nil, previousState != State.terminated {
            let reason = unexpectedRestartReason(now: date)
            defaults.set(date, forKey: Key.lastUnexpectedRestartAt)
            defaults.set(reason, forKey: Key.lastUnexpectedRestartReason)
            print("Previous app process ended without clean termination: \(reason)")
        }

        defaults.set(UUID().uuidString, forKey: Key.launchID)
        defaults.set(date, forKey: Key.launchStartedAt)
        defaults.set(State.launching, forKey: Key.state)
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.set(State.active, forKey: Key.state)
        })
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.set(State.inactive, forKey: Key.state)
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.set(State.background, forKey: Key.state)
            self?.purgeVolatileMemoryCaches()
        })
        observers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.set(State.terminated, forKey: Key.state)
        })
        observers.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.defaults.set(Date(), forKey: Key.lastMemoryWarningAt)
            self?.defaults.set("memory-warning", forKey: Key.state)
            self?.purgeVolatileMemoryCaches()
        })
    }

    private func purgeVolatileMemoryCaches() {
        ExerciseImageCacheService.clearMemoryCache()
        AvatarThumbnailCacheService.shared.clear()
        ExerciseSearchService.clearCachedCatalogIndexes()
        HistoryAnalyticsCache.shared.clear()
    }

    private func unexpectedRestartReason(now: Date) -> String {
        guard let lastMemoryWarningAt = defaults.object(forKey: Key.lastMemoryWarningAt) as? Date else {
            return "unclean-exit"
        }

        let secondsSinceMemoryWarning = now.timeIntervalSince(lastMemoryWarningAt)
        if secondsSinceMemoryWarning >= 0, secondsSinceMemoryWarning < 300 {
            return "possible-memory-pressure"
        }
        return "unclean-exit"
    }
}
