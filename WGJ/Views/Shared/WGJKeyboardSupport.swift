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

    fileprivate static func endFrame(from notification: Notification) -> CGRect? {
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

    func body(content: Content) -> some View {
        // Keep the tab hierarchy stable when the workout is expanded/minimized.
        content.background {
            WGJKeyboardWindowObserver(isEnabled: isEnabled) { visible in
                guard isVisible != visible else { return }
                isVisible = visible
            }
            .allowsHitTesting(false)
        }
    }
}

private struct WGJKeyboardWindowObserver: UIViewRepresentable {
    let isEnabled: Bool
    let onVisibilityChange: (Bool) -> Void

    func makeUIView(context: Context) -> WGJKeyboardWindowView {
        WGJKeyboardWindowView()
    }

    func updateUIView(_ view: WGJKeyboardWindowView, context: Context) {
        view.isTrackingEnabled = isEnabled
        view.onVisibilityChange = onVisibilityChange
        view.refreshVisibility()
    }
}

private final class WGJKeyboardWindowView: UIView {
    var isTrackingEnabled = true
    var onVisibilityChange: ((Bool) -> Void)?
    private var keyboardEndFrame: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardHidden),
            name: UIResponder.keyboardDidHideNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshVisibility()
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frame = WGJKeyboard.endFrame(from: notification) else { return }
        keyboardEndFrame = frame
        refreshVisibility()
    }

    @objc private func keyboardHidden() {
        keyboardEndFrame = nil
        refreshVisibility()
    }

    func refreshVisibility() {
        // UIKit layout/updateUIView can run during a SwiftUI update. Publish afterward,
        // using the latest state rather than capturing an obsolete keyboard frame.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard isTrackingEnabled, let window, let keyboardEndFrame else {
                onVisibilityChange?(false)
                return
            }
            // Window bounds do not shrink with SwiftUI keyboard avoidance. Convert
            // from screen coordinates so split windows also use the correct geometry.
            let frame = window.convert(keyboardEndFrame, from: window.screen.coordinateSpace)
            onVisibilityChange?(WGJKeyboardGeometry.isVisible(
                keyboardEndFrame: frame, containerFrame: window.bounds
            ))
        }
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
