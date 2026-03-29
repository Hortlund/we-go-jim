import SwiftUI

enum SwipeDeleteGestureStrategy {
    case highPriority
    case simultaneous
}

private enum SwipeDeleteDragIntent {
    case undecided
    case horizontal
    case vertical
}

struct SwipeDeleteRow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var offset: CGFloat
    @Binding var isRemoving: Bool

    var threshold: CGFloat = 84
    var isEnabled: Bool = true
    var activeRegionMaxY: CGFloat? = nil
    var gestureStrategy: SwipeDeleteGestureStrategy = .simultaneous
    var gestureMask: GestureMask = .subviews
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var rowWidth: CGFloat = 0
    @State private var dragIntent: SwipeDeleteDragIntent = .undecided

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.destructiveField.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.danger.opacity(0.78))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WGJTheme.danger.opacity(0.28), lineWidth: 1)
                }
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .opacity(revealProgress)
                        .scaleEffect(0.86 + (0.14 * revealProgress))
                        .padding(.trailing, 16)
                }
                .opacity(backgroundOpacity)

            swipeHost
        }
    }

    private var swipeHost: some View {
        let dragGesture = DragGesture(minimumDistance: 12)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }

        return Group {
            if gestureStrategy == .simultaneous {
                baseSwipeContent.simultaneousGesture(dragGesture, including: gestureMask)
            } else {
                baseSwipeContent.highPriorityGesture(dragGesture, including: gestureMask)
            }
        }
    }

    private var baseSwipeContent: some View {
        content()
            .offset(x: offset)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            rowWidth = geometry.size.width
                        }
                        .onChange(of: geometry.size.width) { _, newValue in
                            rowWidth = newValue
                        }
                }
            )
    }

    private var deleteThreshold: CGFloat {
        max(threshold, rowWidth * 0.35)
    }

    private var revealTrigger: CGFloat {
        deleteThreshold * 0.72
    }

    private var backgroundOpacity: CGFloat {
        let distance = -offset
        guard distance > 0 else { return 0 }
        return min(1, distance / max(1, deleteThreshold))
    }

    private var revealProgress: CGFloat {
        let distance = -offset
        guard distance > revealTrigger else { return 0 }
        return min(1, (distance - revealTrigger) / max(1, deleteThreshold - revealTrigger))
    }

    private var intentLockThreshold: CGFloat {
        10
    }

    private func shouldHandleDrag(_ value: DragGesture.Value) -> Bool {
        guard isEnabled else { return false }
        guard !isRemoving else { return false }
        if let activeRegionMaxY {
            return value.startLocation.y <= activeRegionMaxY
        }
        return true
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard shouldHandleDrag(value) else {
            dragIntent = .vertical
            offset = 0
            return
        }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if verticalDistance > horizontalDistance + intentLockThreshold {
            dragIntent = .vertical
            offset = 0
            return
        }

        if horizontalDistance > verticalDistance + intentLockThreshold {
            dragIntent = .horizontal
        }

        guard dragIntent == .horizontal else { return }
        offset = min(0, value.translation.width)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer { dragIntent = .undecided }

        guard dragIntent == .horizontal, shouldHandleDrag(value) else {
            resetOffset()
            return
        }

        if -value.translation.width >= deleteThreshold {
            dismissRow()
        } else {
            resetOffset()
        }
    }

    private func resetOffset() {
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            offset = 0
        }
    }

    private func dismissRow() {
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            isRemoving = true
            offset = -max(420, rowWidth)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 20 : 170))
            onDelete()
            isRemoving = false
            offset = 0
        }
    }
}
