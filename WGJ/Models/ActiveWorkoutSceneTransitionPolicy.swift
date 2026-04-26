import SwiftUI

nonisolated enum ActiveWorkoutSceneTransitionPolicy {
    static func shouldFlushLocalDraft(scenePhase: ScenePhase) -> Bool {
        scenePhase == .background
    }
}

nonisolated enum ActiveWorkoutInteractionWorkPolicy {
    static let defaultPreviousPerformanceHydrationDelay: Duration = .milliseconds(650)
    static let defaultGuidanceRefreshDelay: Duration = .milliseconds(900)

    static func previousPerformanceHydrationDelay(
        isRunningTests: Bool = AppRuntimeConfig.isRunningTests,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Duration {
        guard isRunningTests,
              let rawValue = environment["UITEST_ACTIVE_WORKOUT_PREVIOUS_PERFORMANCE_DELAY_MS"],
              let milliseconds = Int(rawValue)
        else {
            return defaultPreviousPerformanceHydrationDelay
        }

        return .milliseconds(max(0, milliseconds))
    }
}
