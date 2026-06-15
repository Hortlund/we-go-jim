import SwiftUI

nonisolated enum ActiveWorkoutSceneTransitionPolicy {
    static func shouldFlushLocalDraft(scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
    }
}

nonisolated enum RestTimerExpiryPolicy {
    static func expirationDelay(seconds: Int) -> Duration? {
        let normalized = max(0, min(3600, seconds))
        guard normalized > 0 else { return nil }
        return .seconds(normalized)
    }
}

nonisolated enum ActiveWorkoutLifecycleCheckpoint {
    case finish
    case cancel
    case minimize
    case sceneTransition
    case userEdit
}

nonisolated enum ActiveWorkoutSnapshotPersistencePolicy {
    static func shouldWriteDurableSnapshot(for checkpoint: ActiveWorkoutLifecycleCheckpoint) -> Bool {
        checkpoint == .userEdit || checkpoint == .sceneTransition || checkpoint == .minimize
    }

    static func shouldWriteDurableSnapshot(for summary: ActiveWorkoutSetDraftChangeSummary) -> Bool {
        summary.hasStructuralChange || summary.hasCompletionChange || summary.hasValueChange
    }
}

nonisolated enum ActiveWorkoutKeyboardChromePolicy {
    static func shouldResetKeyboardState(scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
    }

    static func shouldShowTimerDock(
        hasSession: Bool,
        isEndingSession: Bool,
        isKeyboardVisible: Bool,
        isMetricInputFocused: Bool,
        scenePhase: ScenePhase = .active
    ) -> Bool {
        scenePhase == .active && hasSession && !isEndingSession && !isKeyboardVisible && !isMetricInputFocused
    }

    static func shouldAnimateTimerDockVisibilityChange(
        previousIsVisible: Bool,
        currentIsVisible: Bool
    ) -> Bool {
        previousIsVisible != currentIsVisible
    }
}

nonisolated enum ActiveWorkoutBottomDockPlacementPolicy {
    static func shouldReserveBottomSafeAreaInset(
        hasSession: Bool,
        isEndingSession: Bool,
        isCancelArmed: Bool = false
    ) -> Bool {
        hasSession && !isEndingSession && !isCancelArmed
    }

    static func shouldReserveScrollClearance(
        hasSession: Bool,
        isEndingSession: Bool,
        isCancelArmed: Bool = false
    ) -> Bool {
        hasSession && !isEndingSession && !isCancelArmed
    }
}

nonisolated enum ActiveWorkoutInteractionWorkPolicy {
    static let defaultPreviousPerformanceHydrationDelay: Duration = .milliseconds(0)
    static let defaultGuidanceRefreshDelay: Duration = .milliseconds(900)
    static let foregroundResumeGraceDelay: Duration = .milliseconds(2_500)

    static func shouldCancelNonCriticalInteractionWork(scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
    }

    static func shouldRunNonCriticalInteractionWork(scenePhase: ScenePhase) -> Bool {
        scenePhase == .active
    }

    static func shouldRunNonCriticalInteractionWork(
        scenePhase: ScenePhase,
        isMetricInputFocused: Bool
    ) -> Bool {
        shouldRunNonCriticalInteractionWork(scenePhase: scenePhase) && !isMetricInputFocused
    }

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
