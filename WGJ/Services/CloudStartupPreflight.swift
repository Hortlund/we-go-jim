import CloudKit
import Dispatch
import Foundation

enum CloudStartupStoreMode: Equatable {
    case cloudBacked
    case localFallback
}

struct CloudStartupDecision: Equatable {
    let storeMode: CloudStartupStoreMode
    let cloudSyncErrorDescription: String?

    var cloudSyncEnabled: Bool {
        storeMode == .cloudBacked
    }
}

enum CloudStartupAccountStatus: Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case timedOut
    case containerUnavailable
    case error
}

protocol CloudStartupAccountStatusProviding {
    func currentStatus(timeout: TimeInterval) -> CloudStartupAccountStatus
}

struct CloudKitStartupAccountStatusProvider: CloudStartupAccountStatusProviding {
    private let container: CKContainer?

    init(container: CKContainer? = AppRuntimeConfig.makeCloudKitContainer()) {
        self.container = container
    }

    func currentStatus(timeout: TimeInterval) -> CloudStartupAccountStatus {
        guard let container else {
            return .containerUnavailable
        }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var resolvedStatus: CloudStartupAccountStatus?

        container.accountStatus { status, error in
            let nextStatus: CloudStartupAccountStatus
            if error != nil {
                nextStatus = .error
            } else {
                switch status {
                case .available:
                    nextStatus = .available
                case .noAccount:
                    nextStatus = .noAccount
                case .restricted:
                    nextStatus = .restricted
                case .temporarilyUnavailable:
                    nextStatus = .temporarilyUnavailable
                case .couldNotDetermine:
                    nextStatus = .couldNotDetermine
                @unknown default:
                    nextStatus = .couldNotDetermine
                }
            }

            lock.lock()
            resolvedStatus = nextStatus
            lock.unlock()
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .timedOut
        }

        lock.lock()
        let finalStatus = resolvedStatus ?? .couldNotDetermine
        lock.unlock()
        return finalStatus
    }
}

enum CloudStartupPreflight {
    static let defaultTimeout: TimeInterval = 1.0

    static func makeDecision(
        statusProvider: any CloudStartupAccountStatusProviding = CloudKitStartupAccountStatusProvider(),
        timeout: TimeInterval = defaultTimeout
    ) -> CloudStartupDecision {
        switch statusProvider.currentStatus(timeout: timeout) {
        case .available:
            return CloudStartupDecision(
                storeMode: .cloudBacked,
                cloudSyncErrorDescription: nil
            )
        case .noAccount:
            return CloudStartupDecision(
                storeMode: .localFallback,
                cloudSyncErrorDescription: "No iCloud account is signed in on this device. Using local-only mode for this session."
            )
        case .restricted:
            return CloudStartupDecision(
                storeMode: .localFallback,
                cloudSyncErrorDescription: "iCloud is restricted on this device. Using local-only mode for this session."
            )
        case .containerUnavailable:
            return CloudStartupDecision(
                storeMode: .localFallback,
                cloudSyncErrorDescription: "CloudKit is unavailable for this build. Using local-only mode for this session."
            )
        case .temporarilyUnavailable, .couldNotDetermine, .timedOut, .error:
            return CloudStartupDecision(
                storeMode: .cloudBacked,
                cloudSyncErrorDescription: nil
            )
        }
    }
}
