import Foundation
import Observation

nonisolated enum CloudBackupStage: String, Sendable {
    case waiting = "Waiting for another backup operation…"
    case checking = "Checking iCloud…"
    case preparing = "Preparing backup…"
    case uploading = "Uploading backup…"
    case downloading = "Downloading backup…"
    case validating = "Checking backup…"
    case restoring = "Restoring your data…"
    case rebuilding = "Rebuilding workout history…"
    case saving = "Saving restored data…"
    case finishing = "Finishing up…"
}

nonisolated struct CloudBackupProgressUpdate: Equatable, Sendable {
    let stage: CloudBackupStage
    var completed: Int? = nil
    var total: Int? = nil

    var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var countDescription: String? {
        guard let completed, let total, total > 0 else { return nil }
        return "\(min(total, max(0, completed))) of \(total) backup parts"
    }
}

/// Synchronous reporting also works inside the protected restore transaction.
/// Callbacks must only publish UI state; they must never write to the data store.
nonisolated struct CloudBackupProgressReporter: Sendable {
    var report: @Sendable (CloudBackupProgressUpdate) -> Void = { _ in }

    func callAsFunction(_ stage: CloudBackupStage, completed: Int? = nil, total: Int? = nil) {
        report(.init(stage: stage, completed: completed, total: total))
    }
}

@MainActor
@Observable
final class CloudBackupOperation: Identifiable {
    enum Kind { case backup, restore }
    enum Outcome: Equatable {
        case success(String)
        case failure(String)
    }

    let id = UUID()
    let kind: Kind
    private(set) var foreground: Bool
    let restoreRequestID: UUID?
    private(set) var progress = CloudBackupProgressUpdate(stage: .waiting)
    private(set) var outcome: Outcome?
    var needsPresentation = false
    private var attemptID = UUID()

    init(kind: Kind, foreground: Bool, restoreRequestID: UUID? = nil) {
        self.kind = kind
        self.foreground = foreground
        self.restoreRequestID = restoreRequestID
    }

    var isRunning: Bool { outcome == nil }
    var title: String {
        switch outcome {
        case .success: kind == .backup ? "Backup complete" : "Restore complete"
        case .failure: kind == .backup ? "Backup stopped" : "Restore stopped"
        case nil: kind == .backup ? "Backing up to iCloud" : "Restoring from iCloud"
        }
    }

    var reporter: CloudBackupProgressReporter {
        .init { [weak self, attemptID] update in
            // FIFO dispatch preserves stage order, including synchronous restore
            // checkpoints. Late callbacks cannot overwrite a terminal result.
            DispatchQueue.main.async {
                guard let self, self.attemptID == attemptID else { return }
                self.update(update)
            }
        }
    }

    fileprivate func restart(foreground: Bool) {
        attemptID = UUID()
        self.foreground = foreground
        progress = .init(stage: .waiting)
        outcome = nil
    }

    func update(_ update: CloudBackupProgressUpdate) {
        guard isRunning else { return }
        progress = update
    }

    func finish(_ outcome: Outcome) {
        guard isRunning else { return }
        self.outcome = outcome
    }

    nonisolated deinit { }
}

@MainActor
@Observable
final class CloudBackupProgressCenter {
    static let shared = CloudBackupProgressCenter()

    private(set) var operations: [CloudBackupOperation] = []
    var presentedOperation: CloudBackupOperation?
    private var presentedID: UUID?

    var activeOperation: CloudBackupOperation? {
        operations.first { $0.isRunning && $0.progress.stage != .waiting }
            ?? operations.first { $0.isRunning }
    }

    var hasForegroundOperation: Bool { operations.contains { $0.foreground && $0.isRunning } }

    func beginRestore(requestID: UUID, foreground: Bool) -> CloudBackupOperation? {
        guard !operations.contains(where: { $0.restoreRequestID == requestID && $0.isRunning }) else { return nil }
        if let previous = operations.first(where: { $0.restoreRequestID == requestID }),
           case .failure = previous.outcome {
            // Keep the sheet's identity and observed object so a resumed restore
            // immediately replaces its old error and disables dismissal again.
            previous.restart(foreground: foreground)
            if foreground { requestPresentation(previous) }
            return previous
        }
        return begin(kind: .restore, foreground: foreground, restoreRequestID: requestID)
    }

    func begin(kind: CloudBackupOperation.Kind, foreground: Bool, restoreRequestID: UUID? = nil) -> CloudBackupOperation {
        let operation = CloudBackupOperation(kind: kind, foreground: foreground, restoreRequestID: restoreRequestID)
        operations.append(operation)
        if foreground {
            if kind == .restore {
                requestPresentation(operation)
            } else {
                Task { [weak self, weak operation] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, let operation, operation.isRunning else { return }
                    self.requestPresentation(operation)
                }
            }
        }
        return operation
    }

    func finish(_ operation: CloudBackupOperation, outcome: CloudBackupOperation.Outcome) {
        guard operation.isRunning else { return }
        operation.finish(outcome)
        if operation.foreground, case .failure = outcome { requestPresentation(operation) }
        if !operation.needsPresentation {
            operations.removeAll { $0.id == operation.id }
        }
    }

    func didDismiss() {
        // A retry can start after Done was tapped but before dismissal finishes.
        // Preserve and re-present that running operation instead of losing it.
        operations.removeAll { $0.id == presentedID && !$0.isRunning }
        presentedID = nil
        presentedOperation = nil
        presentNext()
    }

    private func requestPresentation(_ operation: CloudBackupOperation) {
        operation.needsPresentation = true
        presentNext()
    }

    private func presentNext() {
        guard presentedID == nil,
              let operation = operations.first(where: \.needsPresentation) else { return }
        presentedID = operation.id
        presentedOperation = operation
    }

    nonisolated deinit { }
}
