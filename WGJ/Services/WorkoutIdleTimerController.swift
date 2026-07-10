import UIKit

nonisolated enum WorkoutIdleTimerPolicy {
    static func shouldDisableIdleTimer(
        isSceneActive: Bool,
        keepsScreenAwake: Bool,
        hasActiveWorkout: Bool
    ) -> Bool {
        isSceneActive && keepsScreenAwake && hasActiveWorkout
    }
}

nonisolated final class WorkoutIdleTimerController {
    private let setDisabled: (Bool) -> Void
    private var currentValue = false

    convenience init() {
        self.init { isDisabled in
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = isDisabled
            }
        }
    }

    init(setDisabled: @escaping (Bool) -> Void) {
        self.setDisabled = setDisabled
    }

    func update(
        isSceneActive: Bool,
        keepsScreenAwake: Bool,
        hasActiveWorkout: Bool
    ) {
        let nextValue = WorkoutIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: isSceneActive,
            keepsScreenAwake: keepsScreenAwake,
            hasActiveWorkout: hasActiveWorkout
        )
        guard nextValue != currentValue else { return }
        currentValue = nextValue
        setDisabled(nextValue)
    }

    func reset() {
        guard currentValue else { return }
        currentValue = false
        setDisabled(false)
    }
}
