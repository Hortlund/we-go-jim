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
    let isEnabled: Bool
    @State private var viewMaxY = UIScreen.main.bounds.maxY

    @ViewBuilder
    func body(content: Content) -> some View {
        let measuredContent = content
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
                guard abs(updatedMaxY - viewMaxY) > 0.5 else { return }
                viewMaxY = updatedMaxY
            }

        if isEnabled {
            measuredContent
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateVisibility(
                        WGJKeyboard.isVisible(from: notification, viewMaxY: viewMaxY)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    updateVisibility(false)
                }
        } else {
            measuredContent
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

private struct WGJMinimalKeyboardToolbarModifier: ViewModifier {
    let onDismiss: () -> Void
    private let externalIsKeyboardVisible: Binding<Bool>?
    @State private var localIsKeyboardVisible = false

    init(
        isKeyboardVisible: Binding<Bool>? = nil,
        onDismiss: @escaping () -> Void
    ) {
        externalIsKeyboardVisible = isKeyboardVisible
        self.onDismiss = onDismiss
    }

    func body(content: Content) -> some View {
        trackedContent(content)
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
                        .accessibilityIdentifier("keyboard-hide-button")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
    }

    @ViewBuilder
    private func trackedContent(_ content: Content) -> some View {
        if externalIsKeyboardVisible == nil {
            content.wgjTrackKeyboardVisibility($localIsKeyboardVisible)
        } else {
            content
        }
    }

    private var isKeyboardVisible: Bool {
        externalIsKeyboardVisible?.wrappedValue ?? localIsKeyboardVisible
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

    @MainActor
    func wgjMinimalKeyboardToolbar() -> some View {
        modifier(WGJMinimalKeyboardToolbarModifier(onDismiss: {
            WGJKeyboard.dismiss()
        }))
    }

    func wgjMinimalKeyboardToolbar(isKeyboardVisible: Binding<Bool>) -> some View {
        modifier(WGJMinimalKeyboardToolbarModifier(
            isKeyboardVisible: isKeyboardVisible,
            onDismiss: {
                WGJKeyboard.dismiss()
            }
        ))
    }

    func wgjMinimalKeyboardToolbar(onDismiss: @escaping () -> Void) -> some View {
        modifier(WGJMinimalKeyboardToolbarModifier(onDismiss: onDismiss))
    }
}
