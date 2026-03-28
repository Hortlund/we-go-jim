import CoreData
import Foundation

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
            Task { @MainActor in
                AppRuntimeState.shared.updateLatestCloudSyncEvent(summary)
            }
        }
    }

    nonisolated private static func summary(from event: NSPersistentCloudKitContainer.Event) -> CloudSyncEventSummary {
        CloudSyncEventSummary(
            typeLabel: typeLabel(for: event),
            statusLabel: statusLabel(for: event),
            storeIdentifier: event.storeIdentifier,
            startedAt: event.startDate,
            endedAt: event.endDate,
            errorDescription: event.error.map(Self.describe)
        )
    }

    nonisolated private static func typeLabel(for event: NSPersistentCloudKitContainer.Event) -> String {
        switch event.type {
        case .setup:
            return "Setup"
        case .import:
            return "Import"
        case .export:
            return "Export"
        @unknown default:
            return "Unknown"
        }
    }

    nonisolated private static func statusLabel(for event: NSPersistentCloudKitContainer.Event) -> String {
        if event.endDate == nil {
            return "Running"
        }

        return event.succeeded ? "Succeeded" : "Failed"
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
