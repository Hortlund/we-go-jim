import SwiftData
import SwiftUI

nonisolated struct AppBackgroundJobKey: Hashable, Sendable {
    let feature: String
    let identifier: String?

    init(feature: String, identifier: String? = nil) {
        self.feature = feature
        self.identifier = identifier
    }

    static func feature(_ feature: String) -> AppBackgroundJobKey {
        AppBackgroundJobKey(feature: feature)
    }

    static func session(_ feature: String, sessionID: UUID) -> AppBackgroundJobKey {
        AppBackgroundJobKey(feature: feature, identifier: sessionID.uuidString.lowercased())
    }
}

actor AppBackgroundStore {
    private let container: ModelContainer
    private let coachNarrativeService: AppleCoachNarrativeService
    private let coachNarrativeCache: CoachNarrativeStore
    private var profileNameTask: Task<Void, Never>?
    private var lastProfileNameAttempt: (id: UUID, date: Date)?
    private struct RunningJob {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var runningJobs: [AppBackgroundJobKey: RunningJob] = [:]

    init(container: ModelContainer) {
        self.container = container
        let cache = CoachNarrativeStore(modelContainer: container)
        self.coachNarrativeCache = cache
        self.coachNarrativeService = AppleCoachNarrativeService(cache: cache)
    }

    /// Optional enrichment never delays the local profile or dashboard. Coalesce
    /// attempts across warmup/reloads, and retry unavailable names at most every 5 minutes.
    @discardableResult
    func scheduleProfileNameUpgrade(profile: ProfileIdentitySnapshot,
                                    provider: any ProfileDefaultDisplayNameProviding = ICloudProfileDefaultDisplayNameProvider()) -> Task<Void, Never>? {
        guard ProfileRepository.needsCloudDisplayName(profile.displayName) else { return nil }
        if let profileNameTask { return profileNameTask }
        if let last = lastProfileNameAttempt, last.id == profile.id, Date().timeIntervalSince(last.date) < 300 { return nil }
        lastProfileNameAttempt = (profile.id, .now)
        profileNameTask = Task {
            defer { profileNameTask = nil }
            let revision = await AppRuntimeState.shared.cloudBackupSessionRevision
            guard let name = await provider.defaultDisplayName(), !Task.isCancelled else { return }
            guard await AppRuntimeState.shared.cloudBackupSessionRevision == revision else { return }
            do {
                let context = makeContext()
                let repository = ProfileRepository(modelContext: context)
                guard let current = try repository.currentProfileSnapshot(), current.id == profile.id,
                      ProfileRepository.needsCloudDisplayName(current.displayName) else { return }
                let updated = try repository.bootstrapProfileIdentitySnapshot(preferredDisplayName: name)
                if updated.displayName != current.displayName {
                    NotificationCenter.default.post(name: .wgjProfileIdentityDidChange, object: nil)
                }
            } catch { /* Optional identity enrichment can retry at a later boundary. */ }
        }
        return profileNameTask
    }

    func pruneCoachCache() async throws {
        // The narrative cache uses its own model actor, keeping pruning off UI reads.
        try await coachNarrativeCache.prune()
    }

    func narrativeService() -> AppleCoachNarrativeService {
        coachNarrativeService
    }

    /// Cancellable reads only. Persisting operations continue to use perform/performWrite.
    nonisolated func performRead<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        let trace = WGJPerformance.begin("store.read.wait-and-run")
        defer { WGJPerformance.end(trace) }
        try Task.checkCancellation()
        return try await executeRead(operationName, operation)
    }

    private func executeRead<T: Sendable>(
        _ operationName: StaticString?,
        _ operation: @Sendable (ModelContext) throws -> T
    ) throws -> T {
        try Task.checkCancellation()
        let result = try WGJPerformance.measure(operationName ?? "store.read.execute") {
            try operation(makeContext())
        }
        try Task.checkCancellation()
        return result
    }

    func perform<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        return try operation(context)
    }

    func performWrite<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        let result = try operation(context)
        if context.hasChanges {
            try context.saveWithRecoveryProtection()
        }
        return result
    }

    @discardableResult
    func scheduleCoalesced(
        key: AppBackgroundJobKey,
        operationName: StaticString? = nil,
        priority: TaskPriority = .utility,
        cancelExisting: Bool = false,
        _ operation: @Sendable @escaping (ModelContext) -> Void
    ) -> Task<Void, Never> {
        if cancelExisting {
            runningJobs[key]?.task.cancel()
            runningJobs[key] = nil
        } else if let existing = runningJobs[key] {
            return existing.task
        }

        let container = self.container
        let jobID = UUID()
        let task = Task.detached(priority: priority) { [weak self] in
            // Cancellation can skip queued maintenance, but never interrupts a
            // synchronous persistence operation once it has started.
            if !Task.isCancelled {
                WGJPerformance.measure(operationName ?? "store.maintenance.execute") {
                    let context = Self.makeContext(container: container)
                    operation(context)
                }
            }
            await self?.finishJob(for: key, id: jobID)
        }

        runningJobs[key] = RunningJob(id: jobID, task: task)
        return task
    }

    func cancelJob(_ key: AppBackgroundJobKey) {
        runningJobs[key]?.task.cancel()
        runningJobs[key] = nil
    }

    private func finishJob(for key: AppBackgroundJobKey, id: UUID) {
        guard runningJobs[key]?.id == id else { return }
        runningJobs[key] = nil
    }

    private func makeContext() -> ModelContext {
        Self.makeContext(container: container)
    }

    private static func makeContext(container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}

extension EnvironmentValues {
    @Entry var appBackgroundStore: AppBackgroundStore? = nil
}

extension Notification.Name {
    nonisolated static let wgjProfileIdentityDidChange = Notification.Name("wgjProfileIdentityDidChange")
}
