import Foundation
import Observation
import OSLog
import SwiftData
import UIKit

nonisolated struct ModelContainerBootstrap {
    let container: ModelContainer
    let cloudRuntimeMode: CloudRuntimeMode
    let cloudFeaturesEnabled: Bool
    let userDataSyncEnabled: Bool
    let cloudSyncEnabled: Bool
    let cloudSyncErrorDescription: String?
    let persistenceMode: AppPersistenceMode

    init(
        container: ModelContainer,
        cloudRuntimeMode: CloudRuntimeMode,
        cloudFeaturesEnabled: Bool,
        userDataSyncEnabled: Bool,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?,
        persistenceMode: AppPersistenceMode = .durable
    ) {
        self.container = container
        self.cloudRuntimeMode = cloudRuntimeMode
        self.cloudFeaturesEnabled = cloudFeaturesEnabled
        self.userDataSyncEnabled = userDataSyncEnabled
        self.cloudSyncEnabled = cloudSyncEnabled
        self.cloudSyncErrorDescription = cloudSyncErrorDescription
        self.persistenceMode = persistenceMode
    }
}

struct ResolvedAppLaunchBootstrap {
    let bootstrap: ModelContainerBootstrap
    let backgroundStore: AppBackgroundStore
    let activeWorkoutCoordinator: ActiveWorkoutCoordinator
}

@MainActor
@Observable
final class AppLaunchBootstrapState {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "AppLaunchBootstrap"
    )

    private(set) var resolvedBootstrap: ResolvedAppLaunchBootstrap?
    private(set) var recoveryState: AppStorageRecoveryState?

    @ObservationIgnored private let runtimeStateUpdater: @MainActor (ModelContainerBootstrap) -> Void
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var resolutionGeneration = 0

    init(
        runtimeStateUpdater: @escaping @MainActor (ModelContainerBootstrap) -> Void = AppLaunchBootstrapState.updateRuntimeState
    ) {
        self.runtimeStateUpdater = runtimeStateUpdater
    }

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

                guard let self else { return }
                await self.finishResolution(
                    bootstrap: bootstrap,
                    generation: currentGeneration
                )
            } catch is CancellationError {
                guard let self else { return }
                await self.clearResolutionTask(generation: currentGeneration)
            } catch {
                guard let self else { return }
                await self.finishFailure(error, generation: currentGeneration)
                Self.logger.error("Could not create ModelContainer bootstrap: \(error.localizedDescription, privacy: .public)")
            }
        }

        resolutionTask = task
    }

    func reset() {
        resolutionGeneration += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        resolvedBootstrap = nil
        recoveryState = nil
    }

    func retry(
        resolver: @escaping @Sendable () async throws -> ModelContainerBootstrap
    ) {
        resolutionGeneration += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        resolvedBootstrap = nil
        recoveryState = nil
        resolveIfNeeded(resolver: resolver)
    }

    func enterDiagnosticMode(
        using makeBootstrap: @escaping @Sendable (String) async throws -> ModelContainerBootstrap
    ) {
        guard let recoveryState else { return }
        let reason = [recoveryState.message, recoveryState.diagnosticReport]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        retry {
            try await makeBootstrap(reason)
        }
    }

    private func finishResolution(
        bootstrap: ModelContainerBootstrap,
        generation: Int
    ) {
        guard resolutionGeneration == generation else { return }
        guard resolutionTask != nil else { return }

        runtimeStateUpdater(bootstrap)
        let backgroundStore = AppBackgroundStore(container: bootstrap.container)
        resolvedBootstrap = ResolvedAppLaunchBootstrap(
            bootstrap: bootstrap,
            backgroundStore: backgroundStore,
            activeWorkoutCoordinator: ActiveWorkoutCoordinator(
                persistence: ModelContainerActiveWorkoutPersistence(
                    backgroundStore: backgroundStore
                )
            )
        )
        recoveryState = nil
        resolutionTask = nil
    }

    private func finishFailure(_ error: Error, generation: Int) {
        guard resolutionGeneration == generation else { return }
        resolvedBootstrap = nil
        recoveryState = AppStorageRecoveryState(
            message: "WGJ could not open durable app storage.",
            diagnosticReport: String(describing: error)
        )
        resolutionTask = nil
    }

    private func clearResolutionTask(generation: Int) {
        guard resolutionGeneration == generation else { return }
        resolutionTask = nil
    }

    private static func updateRuntimeState(_ bootstrap: ModelContainerBootstrap) {
        AppRuntimeState.shared.updateCloudState(
            runtimeMode: bootstrap.cloudRuntimeMode,
            isEnabled: bootstrap.cloudFeaturesEnabled,
            errorDescription: bootstrap.cloudSyncErrorDescription
        )
        AppRuntimeState.shared.updateUserDataSyncStatus(
            bootstrap.userDataSyncEnabled
                ? .backedUp(at: nil)
                : .localOnly(reason: bootstrap.cloudSyncErrorDescription)
        )
    }
}

enum AppLaunchBootstrapResolver {
    private static let uiTestInMemoryStoreArgument = "UITEST_IN_MEMORY_STORE"

    static func resolve(
        processArguments: [String] = ProcessInfo.processInfo.arguments,
        canUseConfiguredCloudKitContainer: Bool = AppRuntimeConfig.canUseConfiguredCloudKitContainer,
        makeUITestContainer: @escaping @Sendable () throws -> ModelContainer,
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        describeError: @escaping @Sendable (Error) -> String
    ) async throws -> ModelContainerBootstrap {
        if processArguments.contains(uiTestInMemoryStoreArgument) {
            return ModelContainerBootstrap(
                container: try makeUITestContainer(),
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
                localOnlyDescription: "CloudKit is unavailable for this build. Using local-only mode for this session."
            )
        }

        return try makeLocalBootstrap(
            makeLocalFallbackContainer: makeLocalFallbackContainer,
            localOnlyDescription: nil
        )
    }

    private static func makeLocalBootstrap(
        makeLocalFallbackContainer: @escaping @Sendable () throws -> ModelContainer,
        localOnlyDescription: String?
    ) throws -> ModelContainerBootstrap {
        ModelContainerBootstrap(
            container: try makeLocalFallbackContainer(),
            cloudRuntimeMode: localOnlyDescription.map(CloudRuntimeMode.unavailable) ?? .checking,
            cloudFeaturesEnabled: localOnlyDescription == nil,
            userDataSyncEnabled: false,
            cloudSyncEnabled: localOnlyDescription == nil,
            cloudSyncErrorDescription: localOnlyDescription
        )
    }
}

final class AppLifecycleDiagnostics {
    static let shared = AppLifecycleDiagnostics()
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "AppLifecycleDiagnostics"
    )

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
            Self.logger.info("Previous app process ended without clean termination: \(reason, privacy: .public)")
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
