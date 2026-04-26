import CloudKit
import CoreData
import Foundation

nonisolated enum CloudSyncEventHealthResolution: Equatable {
    case noChange
    case clearRuntimeError
    case setRuntimeError(String)
}

nonisolated enum CloudSyncEventHealthClassifier {
    private static let backgroundTaskSchedulerErrorDomain = "BGSystemTaskSchedulerErrorDomain"
    private static let ignoredBackgroundTaskSchedulerCodes: Set<Int> = [3, 8]

    static func resolution(for summary: CloudSyncEventSummary) -> CloudSyncEventHealthResolution {
        switch summary.status {
        case .running:
            return .noChange
        case .succeeded:
            switch summary.type {
            case .setup, .import, .export:
                return .clearRuntimeError
            case .unknown:
                return .noChange
            }
        case .failed:
            guard let description = runtimeErrorDescription(for: summary) else {
                return .noChange
            }

            return .setRuntimeError(description)
        }
    }

    static func suppressesUserVisibleFailure(_ summary: CloudSyncEventSummary) -> Bool {
        guard summary.status == .failed, let error = summary.error else {
            return false
        }

        return matches(error, domain: backgroundTaskSchedulerErrorDomain, codes: ignoredBackgroundTaskSchedulerCodes)
            || matchesAccountAuthNoise(error)
    }

    static func runtimeErrorDescription(for summary: CloudSyncEventSummary) -> String? {
        if suppressesUserVisibleFailure(summary) {
            return nil
        }

        if let error = summary.error {
            if matches(error, domain: CKError.errorDomain, codes: [CKError.Code.permissionFailure.rawValue]) {
                return "CloudKit permission failed for this account. Cloud features are currently unavailable."
            }
        }

        switch summary.type {
        case .setup:
            return "CloudKit setup failed. Cloud features are currently unavailable."
        case .import, .export:
            return "CloudKit sync encountered an error. Cloud features are temporarily unavailable."
        case .unknown:
            return nil
        }
    }

    private static func matches(
        _ error: CloudSyncErrorSnapshot,
        domain: String,
        codes: Set<Int>
    ) -> Bool {
        if error.domain == domain && codes.contains(error.code) {
            return true
        }

        guard let underlyingDomain = error.underlyingDomain,
              let underlyingCode = error.underlyingCode
        else {
            return false
        }

        return underlyingDomain == domain && codes.contains(underlyingCode)
    }

    private static func matchesAccountAuthNoise(_ error: CloudSyncErrorSnapshot) -> Bool {
        matchesNoAccountSetupNoise(error)
            || matches(error, domain: CKError.errorDomain, codes: [CKError.Code.notAuthenticated.rawValue])
    }

    private static func matchesNoAccountSetupNoise(_ error: CloudSyncErrorSnapshot) -> Bool {
        guard matches(error, domain: NSCocoaErrorDomain, codes: [134400]) else {
            return false
        }

        let description = error.description.lowercased()
        return description.contains("ckaccountstatusnoaccount")
            || description.contains("without an icloud account")
    }
}

@MainActor
final class CloudSyncEventMonitor {
    static let shared = CloudSyncEventMonitor()

    private var observer: NSObjectProtocol?

    private init() { }

    func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            let summary = Self.summary(from: event)
            let resolution = CloudSyncEventHealthClassifier.resolution(for: summary)
            Task { @MainActor in
                AppRuntimeState.shared.updateLatestCloudSyncEvent(summary)
                UserDataSyncTrackerBridge.recordCloudEvent(summary)
                switch resolution {
                case .noChange:
                    break
                case .clearRuntimeError:
                    AppRuntimeState.shared.updateCloudRuntimeError(nil)
                case .setRuntimeError(let description):
                    AppRuntimeState.shared.updateCloudRuntimeError(description)
                }
            }
        }
    }

    nonisolated private static func summary(from event: NSPersistentCloudKitContainer.Event) -> CloudSyncEventSummary {
        CloudSyncEventSummary(
            type: type(for: event),
            status: status(for: event),
            storeIdentifier: event.storeIdentifier,
            startedAt: event.startDate,
            endedAt: event.endDate,
            error: event.error.map(Self.snapshot)
        )
    }

    nonisolated private static func type(for event: NSPersistentCloudKitContainer.Event) -> CloudSyncEventType {
        switch event.type {
        case .setup:
            return .setup
        case .import:
            return .import
        case .export:
            return .export
        @unknown default:
            return .unknown
        }
    }

    nonisolated private static func status(for event: NSPersistentCloudKitContainer.Event) -> CloudSyncEventStatus {
        if event.endDate == nil {
            return .running
        }

        return event.succeeded ? .succeeded : .failed
    }

    nonisolated private static func snapshot(_ error: Error) -> CloudSyncErrorSnapshot {
        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        return CloudSyncErrorSnapshot(
            domain: nsError.domain,
            code: nsError.code,
            underlyingDomain: underlyingError?.domain,
            underlyingCode: underlyingError?.code,
            description: describe(error)
        )
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfo = nsError.userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        if userInfo.isEmpty {
            return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        }

        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription) [\(userInfo)]"
    }
}
