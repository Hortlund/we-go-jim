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

struct WGJAccessoryTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    let onDismiss: () -> Void

    init(
        _ placeholder: String,
        text: Binding<String>,
        isFocused: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        _isFocused = isFocused
        self.onDismiss = onDismiss
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = UIColor(WGJTheme.textPrimary)
        textField.tintColor = UIColor(WGJTheme.accentBlue)
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.accessibilityIdentifier = "exercises-search-field"
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        textField.inputAccessoryView = context.coordinator.makeAccessoryView()
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let onDismiss: () -> Void
        weak var textField: UITextField?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onDismiss: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.onDismiss = onDismiss
        }

        func makeAccessoryView() -> UIView {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.barStyle = .default
            toolbar.isTranslucent = true

            var configuration = UIButton.Configuration.bordered()
            configuration.image = UIImage(systemName: "keyboard.chevron.compact.down")
            configuration.imagePadding = 6
            configuration.title = "Hide"

            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = "Hide keyboard"
            button.accessibilityIdentifier = "keyboard-hide-button"
            button.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)

            toolbar.items = [
                UIBarButtonItem.flexibleSpace(),
                UIBarButtonItem(customView: button),
            ]
            return toolbar
        }

        @objc func textDidChange(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        @objc private func dismissKeyboard() {
            isFocused = false
            textField?.resignFirstResponder()
            onDismiss()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            dismissKeyboard()
            return false
        }
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

    init(
        isKeyboardVisible: Binding<Bool>? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    keyboardToolbarButton
                }
            }
    }

    @ViewBuilder
    private var keyboardToolbarButton: some View {
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
            .padding(.vertical, 8)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide keyboard")
        .accessibilityIdentifier("keyboard-hide-button")
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
