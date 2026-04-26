import Foundation

nonisolated enum UserDataSyncStateKind: String, Equatable, Sendable {
    case localOnly
    case syncing
    case caughtUp
    case pendingExport
    case degraded
}

nonisolated enum UserDataSyncTrackerPolicy {
    static let runningCloudEventVisibleDuration: TimeInterval = 20
    static let runningCloudEventExpiryWakeupLeeway: TimeInterval = 0.25
}

nonisolated struct UserDataSyncStatusSnapshot: Equatable, Sendable {
    let state: UserDataSyncStateKind
    let cloudSyncEnabled: Bool
    let latestLocalMutationAt: Date?
    let latestSuccessfulSetupAt: Date?
    let latestSuccessfulImportAt: Date?
    let latestSuccessfulExportAt: Date?
    let hasPendingExport: Bool
    let runningCloudEventType: CloudSyncEventType?
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
            runningCloudEventType: nil,
            latestErrorDescription: nil,
            localOnlyReason: reason
        )
    }

    var title: String {
        switch state {
        case .localOnly:
            return "Local-only mode"
        case .syncing:
            return "Cloud sync in progress"
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
        case .syncing:
            if let runningCloudEventType {
                return "\(runningCloudEventType.label) is syncing templates, profile, and workout data."
            }
            return "Templates, profile, and workout data are catching up from iCloud."
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

nonisolated final class UserDataSyncTracker {
    nonisolated static let shared = UserDataSyncTracker()

    private let lock = NSLock()

    private var cloudSyncEnabled = false
    private var localOnlyReason: String?
    private var latestLocalMutationAt: Date?
    private var latestSuccessfulSetupAt: Date?
    private var latestSuccessfulImportAt: Date?
    private var latestSuccessfulExportAt: Date?
    private var runningCloudEventType: CloudSyncEventType?
    private var runningCloudEventStartedAt: Date?
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
        runningCloudEventType = nil
        runningCloudEventStartedAt = nil
        latestErrorDescription = isCloudEnabled ? errorDescription : nil
        return makeSnapshotLocked(now: .now)
    }

    func markLocalUserDataMutation(at date: Date = .now, now: Date = .now) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }

        latestLocalMutationAt = date
        return makeSnapshotLocked(now: now)
    }

    func recordCloudEvent(_ summary: CloudSyncEventSummary) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let completedAt = summary.endedAt ?? summary.startedAt

        switch summary.status {
        case .running:
            if summary.type != .unknown {
                runningCloudEventType = summary.type
                runningCloudEventStartedAt = summary.startedAt
            }
        case .succeeded:
            if summary.type == runningCloudEventType {
                runningCloudEventType = nil
                runningCloudEventStartedAt = nil
            }
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
            if summary.type == runningCloudEventType {
                runningCloudEventType = nil
                runningCloudEventStartedAt = nil
            }
            if !CloudSyncEventHealthClassifier.suppressesUserVisibleFailure(summary) {
                latestErrorDescription = CloudSyncEventHealthClassifier.runtimeErrorDescription(for: summary)
                    ?? summary.errorDescription
            }
        }

        return makeSnapshotLocked(now: completedAt)
    }

    func currentSnapshot(now: Date = .now) -> UserDataSyncStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return makeSnapshotLocked(now: now)
    }

    private func makeSnapshotLocked(now: Date) -> UserDataSyncStatusSnapshot {
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

        let visibleRunningCloudEventType = visibleRunningCloudEventType(now: now)
        let state: UserDataSyncStateKind
        if let latestErrorDescription, !latestErrorDescription.isEmpty {
            state = .degraded
        } else if visibleRunningCloudEventType != nil {
            state = .syncing
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
            runningCloudEventType: visibleRunningCloudEventType,
            latestErrorDescription: latestErrorDescription,
            localOnlyReason: localOnlyReason
        )
    }

    private func visibleRunningCloudEventType(now: Date) -> CloudSyncEventType? {
        guard let runningCloudEventType, let runningCloudEventStartedAt else {
            return nil
        }

        guard now.timeIntervalSince(runningCloudEventStartedAt)
            <= UserDataSyncTrackerPolicy.runningCloudEventVisibleDuration
        else {
            return nil
        }

        return runningCloudEventType
    }
}

nonisolated enum UserDataSyncTrackerBridge {
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
        scheduleRunningEventExpiryIfNeeded(for: snapshot)
    }

    private static func scheduleRunningEventExpiryIfNeeded(for snapshot: UserDataSyncStatusSnapshot) {
        guard snapshot.state == .syncing else { return }

        Task {
            let delay = UserDataSyncTrackerPolicy.runningCloudEventVisibleDuration
                + UserDataSyncTrackerPolicy.runningCloudEventExpiryWakeupLeeway
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let refreshedSnapshot = UserDataSyncTracker.shared.currentSnapshot()
            await MainActor.run {
                AppRuntimeState.shared.updateUserDataSyncStatus(refreshedSnapshot)
            }
        }
    }
}
