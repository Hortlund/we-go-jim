import Foundation
import OSLog

enum WGJPerformance {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "Performance"
    )
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "Performance"
    )
#endif

    struct TraceToken {
        fileprivate let name: StaticString
        fileprivate let startedAt: ContinuousClock.Instant
#if DEBUG
        fileprivate let intervalState: OSSignpostIntervalState
#endif
    }

    @discardableResult
    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try operation()
    }

    @discardableResult
    static func measureAsync<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try await operation()
    }

    static func begin(_ name: StaticString) -> TraceToken {
#if DEBUG
        TraceToken(
            name: name,
            startedAt: ContinuousClock.now,
            intervalState: signposter.beginInterval(name)
        )
#else
        TraceToken(name: name, startedAt: ContinuousClock.now)
#endif
    }

    static func end(_ token: TraceToken) {
#if DEBUG
        signposter.endInterval(token.name, token.intervalState)
        let elapsed = token.startedAt.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds)
            + (Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000)
        logger.debug("\(String(describing: token.name), privacy: .public) took \(seconds, format: .fixed(precision: 3))s")
#endif
    }
}
