import Foundation
import Observation

nonisolated enum AppRoute: Equatable, Sendable {
    case profile(ProfileRoute)
}

nonisolated enum ProfileRoute: Equatable, Sendable {
    case weeklyGoal
}

nonisolated struct AppRouteRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let route: AppRoute
}

nonisolated enum AppRouteParser {
    static func parse(_ url: URL) -> AppRoute? {
        guard url.scheme?.lowercased() == "wgj",
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
