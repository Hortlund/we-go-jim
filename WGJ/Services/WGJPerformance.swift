import Foundation
import OSLog

enum WGJPerformance {
    nonisolated private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "Performance"
    )
#if DEBUG
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "Performance"
    )
#endif

    struct TraceToken {
        fileprivate let name: StaticString
        fileprivate let startedAt: ContinuousClock.Instant
        fileprivate let intervalState: OSSignpostIntervalState
    }

    @discardableResult
    nonisolated static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try operation()
    }

    @discardableResult
    nonisolated static func measureAsync<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try await operation()
    }

    nonisolated static func begin(_ name: StaticString) -> TraceToken {
        TraceToken(
            name: name,
            startedAt: ContinuousClock.now,
            intervalState: signposter.beginInterval(name)
        )
    }

    nonisolated static func end(_ token: TraceToken) {
        signposter.endInterval(token.name, token.intervalState)
#if DEBUG
        let elapsed = token.startedAt.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds)
            + (Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000)
        logger.debug("\(String(describing: token.name), privacy: .public) took \(seconds, format: .fixed(precision: 3))s")
#endif
    }
}
