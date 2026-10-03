import Foundation
import Observation

nonisolated enum AppRoute: Equatable, Sendable {
    case profile(ProfileRoute)
    case activeWorkout(UUID)
}

nonisolated enum ProfileRoute: Equatable, Sendable {
    case weeklyGoal
}

nonisolated struct AppRouteRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let route: AppRoute
}

nonisolated enum AppRouteParser {
    static func parse(
        _ url: URL,
        expectedScheme: String = AppRuntimeConfig.urlScheme
    ) -> AppRoute? {
        guard url.scheme?.lowercased() == expectedScheme.lowercased() else { return nil }
        if url.host?.lowercased() == "workout", let id = UUID(uuidString: String(url.path.dropFirst())) {
            return .activeWorkout(id)
        }
        guard
              url.host?.lowercased() == "profile",
              url.path.lowercased() == "/weekly-goal"
        else { return nil }
        return .profile(.weeklyGoal)
    }
}

@Observable
nonisolated final class AppRouteState {
    private(set) var pendingRequest: AppRouteRequest?

    @discardableResult
    func enqueue(_ route: AppRoute) -> AppRouteRequest {
        let request = AppRouteRequest(id: UUID(), route: route)
        pendingRequest = request
        return request
    }

    func consume(id: UUID) {
        guard pendingRequest?.id == id else { return }
        pendingRequest = nil
    }
}
