import SwiftUI

nonisolated enum ActiveWorkoutSceneTransitionPolicy {
    static func shouldFlushLocalDraft(scenePhase: ScenePhase) -> Bool {
        scenePhase == .background
    }
}
