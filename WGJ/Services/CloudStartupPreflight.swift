import CloudKit
import Dispatch
import Foundation

nonisolated enum CloudStartupStoreMode: Equatable {
    case cloudBacked
    case localFallback
}

nonisolated struct CloudStartupDecision: Equatable {
    let accountStatus: CloudStartupAccountStatus
    let storeMode: CloudStartupStoreMode
    let cloudSyncErrorDescription: String?

    var cloudSyncEnabled: Bool {
        storeMode == .cloudBacked
    }

    var shouldForceLocalFallbackStore: Bool {
        storeMode == .localFallback
    }
}

nonisolated enum CloudStartupAccountStatus: Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case timedOut
    case containerUnavailable
    case error
}

nonisolated protocol CloudStartupAccountStatusProviding {
    func currentStatus(timeout: TimeInterval) -> CloudStartupAccountStatus
}

nonisolated protocol AsyncCloudStartupAccountStatusProviding {
    func currentStatus() async -> CloudStartupAccountStatus
}

nonisolated struct CloudKitStartupAccountStatusProvider: CloudStartupAccountStatusProviding {
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

nonisolated struct AsyncCloudKitStartupAccountStatusProvider: AsyncCloudStartupAccountStatusProviding {
    private let container: CKContainer?

    init(container: CKContainer? = AppRuntimeConfig.makeCloudKitContainer()) {
        self.container = container
    }

    func currentStatus() async -> CloudStartupAccountStatus {
        guard let container else {
            return .containerUnavailable
        }

        return await withCheckedContinuation { continuation in
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

                continuation.resume(returning: nextStatus)
            }
        }
    }
}

nonisolated enum CloudStartupPreflight {
    static let defaultTimeout: TimeInterval = 1.0

    static func makeDecision(
        statusProvider: any CloudStartupAccountStatusProviding = CloudKitStartupAccountStatusProvider(),
        timeout: TimeInterval = defaultTimeout
    ) -> CloudStartupDecision {
        decision(for: statusProvider.currentStatus(timeout: timeout))
    }

    static func makeDecisionAsync(
        statusProvider: any AsyncCloudStartupAccountStatusProviding = AsyncCloudKitStartupAccountStatusProvider(),
        timeout: Duration = .milliseconds(Int(defaultTimeout * 1_000))
    ) async -> CloudStartupDecision {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<CloudStartupAccountStatus, Never>) in
            let lock = NSLock()
            var didResume = false
            var statusTask: Task<Void, Never>?
            var timeoutTask: Task<Void, Never>?

            func resumeOnce(_ status: CloudStartupAccountStatus) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()
                statusTask?.cancel()
                timeoutTask?.cancel()
                continuation.resume(returning: status)
            }

            statusTask = Task {
                let status = await statusProvider.currentStatus()
                resumeOnce(status)
            }
            timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                resumeOnce(.timedOut)
            }
        }

        return decision(for: status)
    }

    private static func decision(for status: CloudStartupAccountStatus) -> CloudStartupDecision {
        switch status {
        case .available:
            return CloudStartupDecision(
                accountStatus: .available,
                storeMode: .cloudBacked,
                cloudSyncErrorDescription: nil
            )
        case .noAccount:
            return localFallbackDecision(
                .noAccount,
                "No iCloud account is signed in on this device. Using local-only mode for this session."
            )
        case .restricted:
            return localFallbackDecision(
                .restricted,
                "iCloud is restricted on this device. Using local-only mode for this session."
            )
        case .containerUnavailable:
            return localFallbackDecision(
                .containerUnavailable,
                "CloudKit is unavailable for this build. Using local-only mode for this session."
            )
        case .temporarilyUnavailable:
            return cloudBackedDecision(
                .temporarilyUnavailable,
                "iCloud is temporarily unavailable. Local changes will sync when iCloud is available again."
            )
        case .couldNotDetermine:
            return cloudBackedDecision(
                .couldNotDetermine,
                "WGJ could not verify iCloud availability. Local changes will sync when iCloud is available."
            )
        case .timedOut:
            return cloudBackedDecision(
                .timedOut,
                "iCloud availability check timed out. Local changes will sync when iCloud is available."
            )
        case .error:
            return cloudBackedDecision(
                .error,
                "CloudKit startup error. Local changes will sync when iCloud recovers."
            )
        }
    }

    private static func cloudBackedDecision(
        _ accountStatus: CloudStartupAccountStatus,
        _ description: String?
    ) -> CloudStartupDecision {
        CloudStartupDecision(
            accountStatus: accountStatus,
            storeMode: .cloudBacked,
            cloudSyncErrorDescription: description
        )
    }

    private static func localFallbackDecision(
        _ accountStatus: CloudStartupAccountStatus,
        _ description: String
    ) -> CloudStartupDecision {
        CloudStartupDecision(
            accountStatus: accountStatus,
            storeMode: .localFallback,
            cloudSyncErrorDescription: description
        )
    }

}
