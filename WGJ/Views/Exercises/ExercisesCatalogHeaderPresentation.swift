import Observation
import SwiftUI

nonisolated enum ExercisesCatalogContentPresentationPolicy {
    static func showsLoadingPlaceholder(
        hasProjectedSections: Bool,
        isProjecting: Bool,
        isCatalogLoading: Bool,
        isBootstrapping: Bool
    ) -> Bool {
        isCatalogLoading
            || isBootstrapping
            || (!hasProjectedSections && isProjecting)
    }
}

nonisolated enum ExercisesCatalogHeaderCollapsePolicy {
    static let fullyCollapsedOffset: CGFloat = 48

    static func collapseProgress(
        contentOffsetY: CGFloat,
        isForcedExpanded: Bool
    ) -> CGFloat {
        guard !isForcedExpanded else { return 0 }
        return min(max(contentOffsetY, 0) / fullyCollapsedOffset, 1)
    }
}

@Observable
nonisolated final class ExercisesCatalogHeaderPresentationModel {
    private(set) var collapseProgress: CGFloat = 0
    @ObservationIgnored private var fallbackBaseline: CGFloat?
    @ObservationIgnored private var isForcedExpanded = false

    var isCollapsed: Bool {
        collapseProgress >= 1
    }

    @discardableResult
    func consume(contentOffsetY: CGFloat) -> Bool {
        let next = ExercisesCatalogHeaderCollapsePolicy.collapseProgress(
            contentOffsetY: max(0, contentOffsetY),
            isForcedExpanded: isForcedExpanded
        )
        guard abs(next - collapseProgress) > 0.001 else { return false }
        collapseProgress = next
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
        if collapseProgress != 0 {
            collapseProgress = 0
        }
    }

    func forceExpanded(_ isForced: Bool) {
        isForcedExpanded = isForced
        if isForced, collapseProgress != 0 {
            collapseProgress = 0
        }
    }
}

struct ExercisesCatalogCollapsingHeader<Content: View>: View {
    let model: ExercisesCatalogHeaderPresentationModel
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        content(model.collapseProgress)
    }
}

struct ExercisesCatalogCollapsibleHeaderSection<Content: View>: View {
    let progress: CGFloat
    let reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    @State private var expandedHeight: CGFloat?

    private var visibility: CGFloat {
        1 - min(max(progress, 0), 1)
    }

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                guard height > 0,
                      expandedHeight == nil || abs((expandedHeight ?? 0) - height) > 0.5
                else { return }
                expandedHeight = height
            }
            .opacity(visibility)
            .offset(y: reduceMotion ? 0 : -8 * progress)
            .frame(
                height: expandedHeight.map { $0 * visibility },
                alignment: .top
            )
            .clipped()
            .allowsHitTesting(visibility > 0.01)
            .accessibilityHidden(visibility <= 0.01)
    }
}
