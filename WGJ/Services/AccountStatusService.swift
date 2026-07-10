import CloudKit
import Foundation

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

nonisolated func accountStatusWithTimeout(
    provider: any AccountStatusProviding,
    timeout: Duration
) async -> AccountStatus {
    await withTaskGroup(of: AccountStatus.self) { group in
        group.addTask {
            await provider.fetchAccountStatus()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return .unavailable(.unknown)
        }
        let result = await group.next() ?? .unavailable(.unknown)
        group.cancelAll()
        return result
    }
}
