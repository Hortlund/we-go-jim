import Observation
import SwiftUI

nonisolated enum ExercisesCatalogHeaderCollapsePolicy {
    static let collapseOffset: CGFloat = 48
    static let expandOffset: CGFloat = 12

    static func nextCollapsed(
        current: Bool,
        contentOffsetY: CGFloat,
        isForcedExpanded: Bool
    ) -> Bool {
        guard !isForcedExpanded else { return false }
        return current
            ? contentOffsetY > expandOffset
            : contentOffsetY >= collapseOffset
    }
}

@Observable
nonisolated final class ExercisesCatalogHeaderPresentationModel {
    private(set) var isCollapsed = false
    @ObservationIgnored private var fallbackBaseline: CGFloat?
    @ObservationIgnored private var isForcedExpanded = false

    @discardableResult
    func consume(contentOffsetY: CGFloat) -> Bool {
        let next = ExercisesCatalogHeaderCollapsePolicy.nextCollapsed(
            current: isCollapsed,
            contentOffsetY: max(0, contentOffsetY),
            isForcedExpanded: isForcedExpanded
        )
        guard next != isCollapsed else { return false }
        isCollapsed = next
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
        isForcedExpanded = false
        if isCollapsed {
            isCollapsed = false
        }
    }

    func forceExpanded(_ isForced: Bool) {
        isForcedExpanded = isForced
        if isForced, isCollapsed {
            isCollapsed = false
        }
    }
}

struct ExercisesCatalogCollapsingHeader<Content: View>: View {
    let model: ExercisesCatalogHeaderPresentationModel
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(model.isCollapsed)
    }
}
