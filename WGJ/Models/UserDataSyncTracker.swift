import Foundation

enum UserDataSyncStateKind: String, Equatable, Sendable {
    case localOnly
    case caughtUp
    case pendingExport
    case degraded
}

struct UserDataSyncStatusSnapshot: Equatable, Sendable {
    let state: UserDataSyncStateKind
    let cloudSyncEnabled: Bool
    let latestLocalMutationAt: Date?
    let latestSuccessfulSetupAt: Date?
    let latestSuccessfulImportAt: Date?
    let latestSuccessfulExportAt: Date?
    let hasPendingExport: Bool
    let latestErrorDescription: String?
    let localOnlyReason: String?

    static func localOnly(reason: String?) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .localOnly,
            cloudSyncEnabled: false,
            latestLocalMutationAt: nil,
            latestSuccessfulSetupAt: nil,
            latestSuccessfulImportAt: nil,
            latestSuccessfulExportAt: nil,
            hasPendingExport: false,
            latestErrorDescription: nil,
            localOnlyReason: reason
        )
    }

    var title: String {
        switch state {
        case .localOnly:
            return "Local-only mode"
        case .caughtUp:
            return "Cloud sync caught up"
        case .pendingExport:
            return "Cloud sync pending"
        case .degraded:
            return "Cloud sync degraded"
        }
    }

    var detail: String {
        switch state {
        case .localOnly:
            return localOnlyReason
                ?? "This session is running locally, so durable data will stay on this device until iCloud is available."
        case .caughtUp:
            if let latestSuccessfulExportAt {
                return "Latest export finished at \(latestSuccessfulExportAt.formatted(date: .abbreviated, time: .shortened))."
            }
            if let latestSuccessfulImportAt {
                return "Latest import finished at \(latestSuccessfulImportAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Cloud-backed user data is enabled and there are no known pending exports."
        case .pendingExport:
            if let latestLocalMutationAt {
                return "A local change was saved at \(latestLocalMutationAt.formatted(date: .abbreviated, time: .shortened)) and is still waiting to export."
            }
            return "Local changes are waiting to export to iCloud."
        case .degraded:
            return latestErrorDescription
                ?? "Cloud-backed storage is enabled, but the latest sync state is degraded."
        }
    }
}

final class UserDataSyncTracker {
    static let shared = UserDataSyncTracker()

    private let lock = NSLock()

    private var cloudSyncEnabled = false
    private var localOnlyReason: String?
    private var latestLocalMutationAt: Date?
    private var latestSuccessfulSetupAt: Date?
    private var latestSuccessfulImportAt: Date?
    private var latestSuccessfulExportAt: Date?
    private var latestErrorDescription: String?

    private init() { }

    func configureForLaunch(isCloudEnabled: Bool, errorDescription: String?) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }

        cloudSyncEnabled = isCloudEnabled
        localOnlyReason = isCloudEnabled ? nil : errorDescription
        latestLocalMutationAt = nil
        latestSuccessfulSetupAt = nil
        latestSuccessfulImportAt = nil
        latestSuccessfulExportAt = nil
        latestErrorDescription = isCloudEnabled ? errorDescription : nil
        return makeSnapshotLocked()
    }

    func markLocalUserDataMutation(at date: Date = .now) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }

        latestLocalMutationAt = date
        return makeSnapshotLocked()
    }

    func recordCloudEvent(_ summary: CloudSyncEventSummary) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let completedAt = summary.endedAt ?? summary.startedAt

        switch summary.status {
        case .running:
            break
        case .succeeded:
            switch summary.type {
            case .setup:
                latestSuccessfulSetupAt = completedAt
            case .import:
                latestSuccessfulImportAt = completedAt
            case .export:
                latestSuccessfulExportAt = completedAt
            case .unknown:
                break
            }

            if summary.type != .unknown {
                latestErrorDescription = nil
            }
        case .failed:
            latestErrorDescription = CloudSyncEventHealthClassifier.runtimeErrorDescription(for: summary)
                ?? summary.errorDescription
        }

        return makeSnapshotLocked()
    }

    func currentSnapshot() -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshotLocked()
    }

    private func makeSnapshotLocked() -> UserDataSyncStatusSnapshot {
        guard cloudSyncEnabled else {
            return .localOnly(reason: localOnlyReason)
        }

        let hasPendingExport: Bool
        if let latestLocalMutationAt {
            if let latestSuccessfulExportAt {
                hasPendingExport = latestLocalMutationAt > latestSuccessfulExportAt
            } else {
                hasPendingExport = true
            }
        } else {
            hasPendingExport = false
        }

        let state: UserDataSyncStateKind
        if let latestErrorDescription, !latestErrorDescription.isEmpty {
            state = .degraded
        } else if hasPendingExport {
            state = .pendingExport
        } else {
            state = .caughtUp
        }

        return UserDataSyncStatusSnapshot(
            state: state,
            cloudSyncEnabled: cloudSyncEnabled,
            latestLocalMutationAt: latestLocalMutationAt,
            latestSuccessfulSetupAt: latestSuccessfulSetupAt,
            latestSuccessfulImportAt: latestSuccessfulImportAt,
            latestSuccessfulExportAt: latestSuccessfulExportAt,
            hasPendingExport: hasPendingExport,
            latestErrorDescription: latestErrorDescription,
            localOnlyReason: localOnlyReason
        )
    }
}

enum UserDataSyncTrackerBridge {
    static func configureForLaunch(
        isCloudEnabled: Bool,
        errorDescription: String?
    ) -> UserDataSyncStatusSnapshot {
        UserDataSyncTracker.shared.configureForLaunch(
            isCloudEnabled: isCloudEnabled,
            errorDescription: errorDescription
        )
    }

    static func markLocalMutation(at date: Date = .now) {
        let snapshot = UserDataSyncTracker.shared.markLocalUserDataMutation(at: date)
        Task { @MainActor in
            AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        }
    }

    static func recordCloudEvent(_ summary: CloudSyncEventSummary) {
        let snapshot = UserDataSyncTracker.shared.recordCloudEvent(summary)
        Task { @MainActor in
            AppRuntimeState.shared.updateUserDataSyncStatus(snapshot)
        }
    }
}
