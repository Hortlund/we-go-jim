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
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .wgjTrackKeyboardVisibility($isKeyboardVisible)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isKeyboardVisible {
                    HStack {
                        Spacer()

                        Button(action: onDismiss) {
                            HStack(spacing: 8) {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.footnote.weight(.bold))

                                Text("Hide")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(WGJTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(WGJTheme.card.opacity(0.98))
                                    .overlay(
                                        Capsule()
                                            .stroke(WGJTheme.rowDivider.opacity(0.9), lineWidth: 1)
                                    )
                                    .wgjCapsuleGlass(
                                        tint: WGJTheme.accentBlue.opacity(0.08),
                                        interactive: true
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide keyboard")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
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
