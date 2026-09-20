import Foundation
import SwiftData

/// All explicit store commits participate, including background maintenance. Restore
/// excludes writers from its first SQLite snapshot through its commit point.
/// The condition protects only admission state, never disk work. No async work
/// may run inside an admitted operation.
nonisolated enum LocalStoreWriteBarrier {
    struct RestoreInProgress: LocalizedError, CustomStringConvertible {
        var description: String { "WGJ is restoring local data. Your edits have not been saved. Please try saving again when the restore finishes." }
        var errorDescription: String? {
            description
        }
    }

    private final class State: @unchecked Sendable {
        let condition = NSCondition()
        var restoring = false
        var writers = 0
    }
    private static let state = State()

    static func exclusively<T>(_ operation: () throws -> T) rethrows -> T {
        state.condition.lock()
        while state.restoring { state.condition.wait() }
        state.restoring = true
        while state.writers > 0 { state.condition.wait() }
        state.condition.unlock()
        defer {
            state.condition.lock()
            state.restoring = false
            state.condition.broadcast()
            state.condition.unlock()
        }
        return try operation()
    }

    static func writing<T>(_ operation: () throws -> T) throws -> T {
        state.condition.lock()
        while state.restoring {
            if Thread.isMainThread {
                state.condition.unlock()
                throw RestoreInProgress()
            }
            state.condition.wait()
        }
        state.writers += 1
        state.condition.unlock()
        defer {
            state.condition.lock()
            state.writers -= 1
            state.condition.broadcast()
            state.condition.unlock()
        }
        return try operation()
    }
}

extension ModelContext {
    nonisolated func saveWithRecoveryProtection() throws {
        try LocalStoreWriteBarrier.writing {
            try PersistentRestoreRecovery.requireHealthyStore(container)
            try save()
        }
    }
}
