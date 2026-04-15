import SwiftData
import SwiftUI

struct AppBackgroundJobKey: Hashable, Sendable {
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
    private var runningJobs: [AppBackgroundJobKey: Task<Void, Never>] = [:]

    init(container: ModelContainer) {
        self.container = container
    }

    func perform<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        return try operation(context)
    }

    func performAsync<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) async throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        return try await operation(context)
    }

    func performWrite<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        let result = try operation(context)
        if context.hasChanges {
            try context.save()
        }
        return result
    }

    func performWriteAsync<T: Sendable>(
        _ operationName: StaticString? = nil,
        _ operation: @Sendable (ModelContext) async throws -> T
    ) async throws -> T {
        _ = operationName

        let context = makeContext()
        let result = try await operation(context)
        if context.hasChanges {
            try context.save()
        }
        return result
    }

    func scheduleCoalesced(
        key: AppBackgroundJobKey,
        operationName: StaticString? = nil,
        priority: TaskPriority = .utility,
        cancelExisting: Bool = false,
        _ operation: @Sendable @escaping (ModelContext) async -> Void
    ) {
        if cancelExisting {
            runningJobs[key]?.cancel()
            runningJobs[key] = nil
        } else if runningJobs[key] != nil {
            return
        }

        let container = self.container
        let task = Task.detached(priority: priority) { [weak self] in
            _ = operationName

            let context = Self.makeContext(container: container)
            await operation(context)
            await self?.finishJob(for: key)
        }

        runningJobs[key] = task
    }

    func cancelJob(_ key: AppBackgroundJobKey) {
        runningJobs[key]?.cancel()
        runningJobs[key] = nil
    }

    private func finishJob(for key: AppBackgroundJobKey) {
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

private struct AppBackgroundStoreKey: EnvironmentKey {
    static let defaultValue: AppBackgroundStore? = nil
}

extension EnvironmentValues {
    var appBackgroundStore: AppBackgroundStore? {
        get { self[AppBackgroundStoreKey.self] }
        set { self[AppBackgroundStoreKey.self] = newValue }
    }
}
