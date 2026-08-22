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

    private var visibility: CGFloat {
        1 - min(max(progress, 0), 1)
    }

    var body: some View {
        ExercisesCatalogCollapsibleHeaderLayout(
            progress: progress,
            reduceMotion: reduceMotion
        ) {
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
            .opacity(visibility)
            .clipped()
            .allowsHitTesting(visibility > 0.01)
            .accessibilityHidden(visibility <= 0.01)
    }
}

private struct ExercisesCatalogCollapsibleHeaderLayout: Layout {
    let progress: CGFloat
    let reduceMotion: Bool

    private var normalizedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let contentSize = subview.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        return CGSize(
            width: proposal.width ?? contentSize.width,
            height: contentSize.height * (1 - normalizedProgress)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: CGPoint(
                x: bounds.minX,
                y: bounds.minY - (reduceMotion ? 0 : 8 * normalizedProgress)
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
