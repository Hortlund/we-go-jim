import Foundation

actor SocialMaintenanceScheduler {
    private let debounceDuration: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var scheduledTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    private var latestOperation: (@Sendable () async -> Void)?
    private var shouldRunAgain = false

    init(
        debounceDuration: Duration = .milliseconds(280),
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.debounceDuration = debounceDuration
        self.sleep = sleep
    }

    func schedule(
        after delay: Duration? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        latestOperation = operation

        if activeTask != nil {
            shouldRunAgain = true
            return
        }

        scheduledTask?.cancel()
        let sleep = sleep
        let resolvedDelay = delay ?? debounceDuration
        scheduledTask = Task.detached(priority: .utility) { [weak self, sleep, resolvedDelay] in
            guard let self else { return }
            await sleep(resolvedDelay)
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

#if DEBUG
    func waitForIdleForTesting() async {
        while true {
            let scheduledTask = scheduledTask
            let activeTask = activeTask

            await scheduledTask?.value
            await activeTask?.value

            if self.scheduledTask == nil, self.activeTask == nil {
                return
            }
        }
    }
#endif

    private func runPendingOperation() {
        guard activeTask == nil else {
            shouldRunAgain = true
            return
        }

        scheduledTask = nil
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let operation = await self.nextOperationIteration() else {
                    break
                }
                await operation()

                guard await self.shouldContinueAfterOperation(), !Task.isCancelled else {
                    break
                }
            }

            await self.clearActiveTask()
        }

        activeTask = task
    }

    private func nextOperationIteration() -> (@Sendable () async -> Void)? {
        shouldRunAgain = false
        return latestOperation
    }

    private func shouldContinueAfterOperation() -> Bool {
        shouldRunAgain
    }

    private func clearActiveTask() {
        activeTask = nil
    }
}
