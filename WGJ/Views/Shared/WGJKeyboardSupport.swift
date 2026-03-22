import SwiftUI
import UIKit

enum WGJKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func isVisible(from notification: Notification, viewMaxY: CGFloat) -> Bool {
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return false
        }

        return endFrame.minY < viewMaxY
    }
}

private struct WGJKeyboardMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = UIScreen.main.bounds.maxY

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WGJKeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @State private var viewMaxY = UIScreen.main.bounds.maxY

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: WGJKeyboardMaxYPreferenceKey.self,
                            value: proxy.frame(in: .global).maxY
                        )
                }
            }
            .onPreferenceChange(WGJKeyboardMaxYPreferenceKey.self) { updatedMaxY in
                guard updatedMaxY > 0 else { return }
                viewMaxY = updatedMaxY
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                isVisible = WGJKeyboard.isVisible(from: notification, viewMaxY: viewMaxY)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isVisible = false
            }
    }
}

private struct WGJMinimalKeyboardToolbarModifier: ViewModifier {
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentBlue)
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
    }
}

extension View {
    @MainActor
    func wgjTrackKeyboardVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(WGJKeyboardVisibilityModifier(isVisible: isVisible))
    }

    @MainActor
    func wgjMinimalKeyboardToolbar() -> some View {
        modifier(WGJMinimalKeyboardToolbarModifier(onDismiss: {
            WGJKeyboard.dismiss()
        }))
    }

    func wgjMinimalKeyboardToolbar(onDismiss: @escaping () -> Void) -> some View {
        modifier(WGJMinimalKeyboardToolbarModifier(onDismiss: onDismiss))
    }
}
