import CloudKit
import Foundation
import Synchronization

nonisolated enum AccountUnavailableReason: Equatable, Sendable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
}

nonisolated enum AccountStatus: Equatable, Sendable {
    case checking
    case available
    case unavailable(AccountUnavailableReason)
}

nonisolated protocol AccountStatusProviding: Sendable {
    func fetchAccountStatus() async -> AccountStatus
}

nonisolated protocol CloudAccountStatusClient: Sendable {
    func accountStatus() async throws -> CKAccountStatus
}

nonisolated struct CKContainerAccountStatusClient: CloudAccountStatusClient, Sendable {
    let containerIdentifier: String?

    init(container: CKContainer? = nil) {
        containerIdentifier = container?.containerIdentifier
            ?? (AppRuntimeConfig.canUseConfiguredCloudKitContainer
                ? AppRuntimeConfig.cloudKitContainerIdentifier
                : nil)
    }

    func accountStatus() async throws -> CKAccountStatus {
        guard let containerIdentifier else {
            throw CloudKitContainerAvailabilityError.unavailable
        }
        return try await CKContainer(identifier: containerIdentifier).accountStatus()
    }
}

nonisolated struct AccountStatusService: AccountStatusProviding, Sendable {
    private let client: any CloudAccountStatusClient

    init(client: any CloudAccountStatusClient = CKContainerAccountStatusClient()) {
        self.client = client
    }

    func fetchAccountStatus() async -> AccountStatus {
#if DEBUG
        if AppRuntimeConfig.isExplicitICloudUITestLaunch {
            return .available
        }
#endif

        do {
            let status = try await client.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .unavailable(.noAccount)
            case .restricted:
                return .unavailable(.restricted)
            case .temporarilyUnavailable:
                return .unavailable(.temporarilyUnavailable)
            case .couldNotDetermine:
                return .unavailable(.unknown)
            @unknown default:
                return .unavailable(.unknown)
            }
        } catch {
            return .unavailable(.unknown)
        }
    }
}

/// CloudKit callbacks may outlive cancellation. A task group would wait for
/// that callback when leaving its scope, defeating the startup timeout.
nonisolated func accountStatusWithTimeout(
    provider: any AccountStatusProviding,
    timeout: Duration
) async -> AccountStatus {
    guard timeout > .zero, !Task.isCancelled else { return .unavailable(.unknown) }
    let race = AccountStatusRace()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            race.install(continuation)
            let request = Task {
                guard !Task.isCancelled else { return }
                race.finish(await provider.fetchAccountStatus())
            }
            let deadline = Task {
                do {
                    try await Task.sleep(for: timeout)
                    race.finish(.unavailable(.unknown))
                } catch { }
            }
            race.track([request, deadline])
        }
    } onCancel: {
        race.finish(.unavailable(.unknown))
    }
}

private nonisolated final class AccountStatusRace: Sendable {
    private struct State {
        var result: AccountStatus?
        var continuation: CheckedContinuation<AccountStatus, Never>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<AccountStatus, Never>) {
        let result = state.withLock { state -> AccountStatus? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil as AccountStatus?
        }
        if let result { continuation.resume(returning: result) }
    }

    func track(_ tasks: [Task<Void, Never>]) {
        let isFinished = state.withLock { state in
            guard state.result == nil else { return true }
            state.tasks = tasks
            return false
        }
        if isFinished { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: AccountStatus) {
        let pending = state.withLock { state -> (CheckedContinuation<AccountStatus, Never>?, [Task<Void, Never>]) in
            guard state.result == nil else { return (nil, []) }
            state.result = result
            let pending = (state.continuation, state.tasks)
            state.continuation = nil
            state.tasks = []
            return pending
        }
        // Resume and cancel outside the lock: cancellation handlers can reenter.
        pending.0?.resume(returning: result)
        pending.1.forEach { $0.cancel() }
    }
}
