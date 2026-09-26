#if DEBUG
import Foundation

/// Exercises the real presentation path without requiring an iCloud account or
/// replacing any user data. Only available with an explicitly in-memory launch.
@MainActor
enum CloudBackupProgressUITestScenario {
    private static var installed = false

    static func installIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard !installed, arguments.contains("UITEST_IN_MEMORY_STORE"),
              let scenario = arguments.first(where: { $0.hasPrefix("UITEST_BACKUP_PROGRESS_") }) else { return }
        installed = true
        let center = CloudBackupProgressCenter.shared
        let isAutomatic = scenario == "UITEST_BACKUP_PROGRESS_AUTOMATIC"
        let isRetry = scenario == "UITEST_BACKUP_PROGRESS_RETRY"
        let requestID = UUID()
        let operation: CloudBackupOperation
        if isRetry {
            guard let started = center.beginRestore(requestID: requestID, foreground: true) else { return }
            operation = started
        } else {
            operation = center.begin(kind: isAutomatic ? .backup : .restore, foreground: !isAutomatic)
        }
        operation.update(.init(stage: isAutomatic ? .uploading : .downloading, completed: 50, total: 200))
        try? await Task.sleep(for: .seconds(12))
        if isRetry {
            center.finish(operation, outcome: .failure("The connection was interrupted."))
            try? await Task.sleep(for: .seconds(5))
            guard let retry = center.beginRestore(requestID: requestID, foreground: true) else { return }
            retry.update(.init(stage: .restoring))
            try? await Task.sleep(for: .seconds(12))
            center.finish(retry, outcome: .success("Your backup has been restored on this device."))
        } else if scenario == "UITEST_BACKUP_PROGRESS_FAILURE" {
            center.finish(operation, outcome: .failure("The connection was interrupted. Check your connection and try again."))
        } else {
            center.finish(operation, outcome: .success("Your backup has been restored on this device."))
        }
    }
}
#endif
