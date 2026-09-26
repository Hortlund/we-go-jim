import Foundation
import Observation

/// Delays activity as one continuous session across cloud checks and transfers.
/// A fast success stays quiet; failures still surface immediately.
@MainActor
@Observable
final class CloudBackupBannerPresentation {
    struct Input: Equatable {
        let status: UserDataSyncStatusSnapshot
        let operationID: UUID?
        let isSheetPresented: Bool
    }

    private(set) var showsActivity = false
    private(set) var status: UserDataSyncStatusSnapshot?
    private var isActive = false
    private var latestInput: Input?
    private var revealTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .seconds(1)) { self.delay = delay }

    func update(_ input: Input) {
        latestInput = input
        guard !input.isSheetPresented else { reset(); return }
        let active = input.operationID != nil || input.status.state == .checking || input.status.state == .pending
        if active {
            dismissTask?.cancel()
            if !isActive {
                isActive = true
                status = nil
                showsActivity = false
                revealTask = Task { [weak self, delay] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled, let self, self.isActive else { return }
                    self.showsActivity = true
                    self.status = self.latestInput?.status
                }
            } else if showsActivity {
                status = input.status
            }
            return
        }

        let wasVisible = showsActivity
        isActive = false
        showsActivity = false
        revealTask?.cancel()
        revealTask = nil
        switch input.status.state {
        case .localOnly:
            reset()
        case .checked, .backedUp:
            // Do not flash a success for work that never needed a banner.
            guard wasVisible else { return }
            showResult(input.status, for: .seconds(3))
        case .checkFailed, .degraded:
            showResult(input.status, for: .seconds(5))
        case .checking, .pending:
            break
        }
    }

    func reset() {
        revealTask?.cancel()
        dismissTask?.cancel()
        revealTask = nil
        dismissTask = nil
        isActive = false
        showsActivity = false
        status = nil
    }

    private func showResult(_ result: UserDataSyncStatusSnapshot, for duration: Duration) {
        status = result
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.status = nil
        }
    }

    nonisolated deinit { }
}
