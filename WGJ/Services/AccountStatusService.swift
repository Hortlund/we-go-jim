import CloudKit
import Foundation

enum AccountUnavailableReason: Equatable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
}

enum AccountStatus: Equatable {
    case checking
    case available
    case unavailable(AccountUnavailableReason)
}

protocol AccountStatusProviding {
    func fetchAccountStatus() async -> AccountStatus
}

protocol CloudAccountStatusClient {
    func accountStatus() async throws -> CKAccountStatus
}

struct CKContainerAccountStatusClient: CloudAccountStatusClient {
    let container: CKContainer?

    init(container: CKContainer? = nil) {
        self.container = container ?? AppRuntimeConfig.makeCloudKitContainer()
    }

    func accountStatus() async throws -> CKAccountStatus {
        guard let container else {
            throw CloudKitContainerAvailabilityError.unavailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, any Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

struct AccountStatusService: AccountStatusProviding {
    private let client: CloudAccountStatusClient

    init(client: CloudAccountStatusClient = CKContainerAccountStatusClient()) {
        self.client = client
    }

    func fetchAccountStatus() async -> AccountStatus {
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
