import Foundation

@MainActor
final class SocialMaintenanceScheduler {
    private let debounceDuration: Duration
    private var scheduledTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    private var latestOperation: (@MainActor () async -> Void)?
    private var shouldRunAgain = false

    init(debounceDuration: Duration = .milliseconds(280)) {
        self.debounceDuration = debounceDuration
    }

    func schedule(
        after delay: Duration? = nil,
        operation: @escaping @MainActor () async -> Void
    ) {
        latestOperation = operation

        if activeTask != nil {
            shouldRunAgain = true
            return
        }

        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay ?? self.debounceDuration)
            guard !Task.isCancelled else { return }
            await self.runPendingOperation()
        }
    }

    func cancel() {
        scheduledTask?.cancel()
        scheduledTask = nil
        activeTask?.cancel()
        activeTask = nil
        latestOperation = nil
        shouldRunAgain = false
    }

    private func runPendingOperation() async {
        guard activeTask == nil else {
            shouldRunAgain = true
            return
        }

        scheduledTask = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            repeat {
                self.shouldRunAgain = false
                if let latestOperation = self.latestOperation {
                    await latestOperation()
                }
            } while self.shouldRunAgain && !Task.isCancelled

            self.activeTask = nil
        }

        activeTask = task
        await task.value
    }
}
