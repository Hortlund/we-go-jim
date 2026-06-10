import SwiftUI
import UIKit

enum WGJKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func isVisible(from notification: Notification, screenMaxY: CGFloat = UIScreen.main.bounds.maxY) -> Bool {
        guard
            screenMaxY.isFinite,
            screenMaxY > 0,
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            endFrame.minY.isFinite
        else {
            return false
        }

        return endFrame.minY < screenMaxY
    }

    static func bottomOverlap(from notification: Notification, screenMaxY: CGFloat = UIScreen.main.bounds.maxY) -> CGFloat {
        guard
            isVisible(from: notification, screenMaxY: screenMaxY),
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            endFrame.minY.isFinite
        else {
            return 0
        }

        return max(0, screenMaxY - endFrame.minY)
    }
}

struct WGJAccessoryTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var accessibilityIdentifier: String = "exercises-search-field"
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .search
    var textAlignment: NSTextAlignment = .natural
    var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    var textColor: UIColor = UIColor(WGJTheme.textPrimary)
    var tintColor: UIColor = UIColor(WGJTheme.accentBlue)
    var isEnabled: Bool = true
    var showsAccessoryDismissButton: Bool = false
    let onDismiss: () -> Void

    init(
        _ placeholder: String,
        text: Binding<String>,
        isFocused: Binding<Bool>,
        accessibilityIdentifier: String = "exercises-search-field",
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .search,
        textAlignment: NSTextAlignment = .natural,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body),
        textColor: UIColor = UIColor(WGJTheme.textPrimary),
        tintColor: UIColor = UIColor(WGJTheme.accentBlue),
        isEnabled: Bool = true,
        showsAccessoryDismissButton: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        _isFocused = isFocused
        self.accessibilityIdentifier = accessibilityIdentifier
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.textAlignment = textAlignment
        self.font = font
        self.textColor = textColor
        self.tintColor = tintColor
        self.isEnabled = isEnabled
        self.showsAccessoryDismissButton = showsAccessoryDismissButton
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
        textField.keyboardType = keyboardType
        textField.returnKeyType = returnKeyType
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.font = font
        textField.textAlignment = textAlignment
        textField.adjustsFontForContentSizeCategory = true
        textField.isEnabled = isEnabled
        textField.accessibilityIdentifier = accessibilityIdentifier
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        textField.inputAccessoryView = nil
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.returnKeyType = returnKeyType
        textField.textAlignment = textAlignment
        textField.font = font
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.isEnabled = isEnabled
        textField.accessibilityIdentifier = accessibilityIdentifier
        if textField.inputAccessoryView != nil {
            textField.inputAccessoryView = nil
            textField.reloadInputViews()
        }

        if isFocused, isEnabled, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
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

private struct WGJKeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    guard WGJKeyboard.isVisible(from: notification) else { return }
                    updateVisibility(true)
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
        self
    }

    func wgjMinimalKeyboardToolbar(isKeyboardVisible: Binding<Bool>) -> some View {
        self
    }

    func wgjMinimalKeyboardToolbar(
        isEnabled: Bool = true,
        onDismiss: @escaping () -> Void
    ) -> some View {
        self
    }
}
