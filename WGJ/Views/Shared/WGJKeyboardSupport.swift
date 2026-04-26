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
}

enum WGJKeyboardHideControl {
    static let title = "Hide"
    static let systemImage = "keyboard.chevron.compact.down"
    static let accessibilityLabel = "Hide keyboard"
    static let accessibilityIdentifier = "keyboard-hide-button"
    static let imagePadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6

    static var foregroundStyle: Color {
        WGJTheme.textPrimary
    }

    static var foregroundUIColor: UIColor {
        UIColor(WGJTheme.textPrimary)
    }

    static func buttonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = imagePadding
        configuration.title = title
        configuration.baseForegroundColor = foregroundUIColor
        return configuration
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

            let button = UIButton(configuration: WGJKeyboardHideControl.buttonConfiguration())
            button.accessibilityLabel = WGJKeyboardHideControl.accessibilityLabel
            button.accessibilityIdentifier = WGJKeyboardHideControl.accessibilityIdentifier
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

private struct WGJKeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateVisibility(
                        WGJKeyboard.isVisible(from: notification)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
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
            HStack(spacing: WGJKeyboardHideControl.imagePadding) {
                Image(systemName: WGJKeyboardHideControl.systemImage)
                    .font(.footnote.weight(.bold))

                Text(WGJKeyboardHideControl.title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(WGJKeyboardHideControl.foregroundStyle)
            .padding(.horizontal, WGJKeyboardHideControl.horizontalPadding)
            .padding(.vertical, WGJKeyboardHideControl.verticalPadding)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WGJKeyboardHideControl.accessibilityLabel)
        .accessibilityIdentifier(WGJKeyboardHideControl.accessibilityIdentifier)
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
