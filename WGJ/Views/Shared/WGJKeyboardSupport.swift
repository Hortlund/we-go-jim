import SwiftUI
import UIKit

enum WGJKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func isVisible(from notification: Notification, containerFrame: CGRect) -> Bool {
        guard let endFrame = endFrame(from: notification) else { return false }
        return WGJKeyboardGeometry.isVisible(
            keyboardEndFrame: endFrame,
            containerFrame: containerFrame
        )
    }

    static func bottomOverlap(from notification: Notification, containerFrame: CGRect) -> CGFloat {
        guard let endFrame = endFrame(from: notification) else { return 0 }
        return WGJKeyboardGeometry.bottomOverlap(
            keyboardEndFrame: endFrame,
            containerFrame: containerFrame
        )
    }

    private static func endFrame(from notification: Notification) -> CGRect? {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width.isFinite,
              frame.height.isFinite
        else { return nil }
        return frame
    }
}

nonisolated enum WGJKeyboardGeometry {
    static func isVisible(keyboardEndFrame: CGRect, containerFrame: CGRect) -> Bool {
        bottomOverlap(keyboardEndFrame: keyboardEndFrame, containerFrame: containerFrame) > 0
    }

    static func bottomOverlap(keyboardEndFrame: CGRect, containerFrame: CGRect) -> CGFloat {
        guard !containerFrame.isEmpty,
              keyboardEndFrame.maxY >= containerFrame.maxY,
              keyboardEndFrame.intersects(containerFrame)
        else { return 0 }
        return max(0, containerFrame.intersection(keyboardEndFrame).height)
    }
}

private struct WGJContainerFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct WGJKeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    let isEnabled: Bool
    @State private var containerFrame = CGRect.zero

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: WGJContainerFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                    }
                }
                .onPreferenceChange(WGJContainerFramePreferenceKey.self) { containerFrame = $0 }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateVisibility(WGJKeyboard.isVisible(
                        from: notification,
                        containerFrame: containerFrame
                    ))
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    updateVisibility(false)
                }
        } else {
            content
                .onChange(of: isEnabled) { _, newValue in
                    if !newValue {
                        updateVisibility(false)
                    }
                }
        }
    }

    private func updateVisibility(_ newValue: Bool) {
        guard isVisible != newValue else { return }
        isVisible = newValue
    }
}

private struct WGJContainerFrameModifier: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WGJContainerFramePreferenceKey.self,
                        value: geometry.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(WGJContainerFramePreferenceKey.self) { frame = $0 }
    }
}

extension View {
    @MainActor
    func wgjTrackKeyboardVisibility(
        _ isVisible: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(WGJKeyboardVisibilityModifier(isVisible: isVisible, isEnabled: isEnabled))
    }

    func wgjTrackContainerFrame(_ frame: Binding<CGRect>) -> some View {
        modifier(WGJContainerFrameModifier(frame: frame))
    }
}
