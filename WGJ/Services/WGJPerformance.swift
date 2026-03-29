import Foundation
import OSLog

enum WGJPerformance {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "Performance"
    )
#endif

    struct TraceToken {
        fileprivate let name: String
        fileprivate let startedAt: ContinuousClock.Instant
    }

    @discardableResult
    static func measure<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try operation()
    }

    @discardableResult
    static func measureAsync<T>(_ name: String, _ operation: () async throws -> T) async rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try await operation()
    }

    static func begin(_ name: String) -> TraceToken {
        TraceToken(name: name, startedAt: ContinuousClock.now)
    }

    static func end(_ token: TraceToken) {
#if DEBUG
        let elapsed = token.startedAt.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds)
            + (Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000)
        logger.debug("\(token.name, privacy: .public) took \(seconds, format: .fixed(precision: 3))s")
#endif
    }
}
