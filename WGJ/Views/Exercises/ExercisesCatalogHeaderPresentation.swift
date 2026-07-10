import Observation
import SwiftUI

nonisolated enum ExercisesCatalogHeaderCollapsePolicy {
    static let collapseDistance: CGFloat = 36
    static let minimumProgressDelta: CGFloat = 1.0 / 120.0

    static func progress(forContentOffsetY offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / collapseDistance))
    }

    static func nextProgress(current: CGFloat, candidate: CGFloat) -> CGFloat? {
        let normalized = min(1, max(0, candidate))
        guard abs(normalized - current) >= minimumProgressDelta else { return nil }
        return normalized
    }

    static func expandedControlsHeight(usesCompactFilterLayout: Bool) -> CGFloat {
        usesCompactFilterLayout ? 158 : 112
    }
}

@Observable
nonisolated final class ExercisesCatalogHeaderPresentationModel {
    private(set) var progress: CGFloat = 0
    @ObservationIgnored private var fallbackBaseline: CGFloat?

    @discardableResult
    func consume(contentOffsetY: CGFloat) -> Bool {
        let candidate = ExercisesCatalogHeaderCollapsePolicy.progress(
            forContentOffsetY: contentOffsetY
        )
        guard let next = ExercisesCatalogHeaderCollapsePolicy.nextProgress(
            current: progress,
            candidate: candidate
        ) else {
            return false
        }
        progress = next
        return true
    }

    @discardableResult
    func consumeFallback(markerY: CGFloat) -> Bool {
        if fallbackBaseline == nil {
            fallbackBaseline = markerY
        }
        return consume(
            contentOffsetY: max(0, (fallbackBaseline ?? markerY) - markerY)
        )
    }

    func reset() {
        fallbackBaseline = nil
        if progress != 0 {
            progress = 0
        }
    }
}

struct ExercisesCatalogCollapsingHeader<Content: View>: View {
    let model: ExercisesCatalogHeaderPresentationModel
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        content(model.progress)
    }
}
