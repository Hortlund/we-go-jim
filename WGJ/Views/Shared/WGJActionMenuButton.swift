import SwiftUI

struct WGJActionMenuButton<Label: View, Actions: View>: View {
    let title: String
    let titleVisibility: Visibility
    let message: String?
    let usesPlainButtonStyle: Bool
    let label: () -> Label
    let actions: () -> Actions

    @State private var isPresented = false

    init(
        _ title: String,
        titleVisibility: Visibility = .visible,
        message: String? = nil,
        usesPlainButtonStyle: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.title = title
        self.titleVisibility = titleVisibility
        self.message = message
        self.usesPlainButtonStyle = usesPlainButtonStyle
        self.actions = actions
        self.label = label
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .modifier(WGJOptionalPlainButtonStyle(isEnabled: usesPlainButtonStyle))
        .confirmationDialog(title, isPresented: $isPresented, titleVisibility: titleVisibility) {
            actions()
        } message: {
            if let message {
                Text(message)
            }
        }
    }
}

private struct WGJOptionalPlainButtonStyle: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.buttonStyle(.plain)
        } else {
            content
        }
    }
}
