import SwiftUI
import SwiftData

struct ActiveWorkoutKeyboardAwareBottomDock: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutRuntimeSession?
    let isEndingSession: Bool
    let reduceMotion: Bool
    let isKeyboardVisible: Bool
    let isMetricInputFocused: Bool
    let onDismissRestTimer: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowDock, let session {
                ActiveWorkoutBottomDock(
                    session: session,
                    reduceMotion: reduceMotion,
                    onDismissRestTimer: onDismissRestTimer
                )
                .transition(WGJMotion.cardTransition(reduceMotion: reduceMotion))
            } else if shouldReserveMetricInputClearance {
                Color.clear
                    .frame(height: ActiveWorkoutKeyboardChromePolicy.metricInputClearanceHeight)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: restTimerState.restTimerPopup?.id)
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: shouldShowDock)
    }

    private var shouldShowDock: Bool {
        ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: session != nil,
            isEndingSession: isEndingSession,
            isKeyboardVisible: isKeyboardVisible,
            isMetricInputFocused: isMetricInputFocused,
            scenePhase: scenePhase
        )
    }

    private var shouldReserveMetricInputClearance: Bool {
        ActiveWorkoutKeyboardChromePolicy.shouldReserveMetricInputClearance(
            isMetricInputFocused: isMetricInputFocused
        )
    }
}
