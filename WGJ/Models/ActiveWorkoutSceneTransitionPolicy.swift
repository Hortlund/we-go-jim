import SwiftUI

nonisolated enum ActiveWorkoutSceneTransitionPolicy {
    static func shouldFlushLocalDraft(scenePhase: ScenePhase) -> Bool {
        false
    }
}

nonisolated enum ActiveWorkoutLifecycleCheckpoint {
    case finish
    case cancel
    case minimize
    case sceneTransition
}

nonisolated enum ActiveWorkoutSnapshotPersistencePolicy {
    static func shouldWriteDurableSnapshot(for checkpoint: ActiveWorkoutLifecycleCheckpoint) -> Bool {
        false
    }
}

nonisolated enum ActiveWorkoutKeyboardChromePolicy {
    static func shouldResetKeyboardState(scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
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
