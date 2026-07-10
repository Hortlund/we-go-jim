import Foundation

nonisolated final class WorkoutGridDebounceCoordinator {
    enum CommitKind: Equatable, Sendable {
        case currentState
        case bufferedInput
    }

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let sleep: Sleeper
    @MainActor private var commitTask: Task<Void, Never>?
    @MainActor private var displayRefreshTask: Task<Void, Never>?
    @MainActor private(set) var pendingCommitKind: CommitKind?

    @MainActor
    var hasPendingCommit: Bool {
        commitTask != nil
    }

    @MainActor
    var hasPendingDisplayRefresh: Bool {
        displayRefreshTask != nil
    }

    init(
        sleep: @escaping Sleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.sleep = sleep
    }

    @MainActor
    func scheduleCommit(
        _ kind: CommitKind,
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        commitTask?.cancel()
        pendingCommitKind = kind
        let sleep = self.sleep
        commitTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingCommitKind = nil
            self.commitTask = nil
            action()
        }
    }

    @MainActor
    func scheduleDisplayRefresh(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        displayRefreshTask?.cancel()
        let sleep = self.sleep
        displayRefreshTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.displayRefreshTask = nil
            action()
        }
    }

    @MainActor
    @discardableResult
    func cancelCommit() -> Bool {
        let hadTask = commitTask != nil
        commitTask?.cancel()
        commitTask = nil
        pendingCommitKind = nil
        return hadTask
    }

    @MainActor
    @discardableResult
    func cancelDisplayRefresh() -> Bool {
        let hadTask = displayRefreshTask != nil
        displayRefreshTask?.cancel()
        displayRefreshTask = nil
        return hadTask
    }

    @MainActor
    func cancelAll() {
        cancelCommit()
        cancelDisplayRefresh()
    }
}
