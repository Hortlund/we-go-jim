import ActivityKit
import Foundation

nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var symbol: String
        var isCardio: Bool
        var status: String
        /// Shifted by accumulated time so the system timer survives pause/resume.
        var timerStart: Date?
        var elapsedSeconds: Int
        var distance: String?
        var pace: String?
        var progress: String?
        var restEndsAt: Date?
    }

    var sessionID: UUID

    var workoutURL: URL {
        Self.workoutURL(sessionID: sessionID)
    }

    static func workoutURL(sessionID: UUID, scheme: String = urlScheme) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "workout"
        components.path = "/\(sessionID.uuidString)"
        return components.url!
    }

    private static let urlScheme = Bundle.main.object(forInfoDictionaryKey: "WGJURLScheme") as? String
        ?? (Bundle.main.bundleIdentifier?.contains(".dev") == true ? "wgj-dev" : "wgj")
}
