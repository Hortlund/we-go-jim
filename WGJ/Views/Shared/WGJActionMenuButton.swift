import SwiftUI

struct WGJActionMenuButton<Label: View, Actions: View>: View {
    let title: String
    let titleVisibility: Visibility
    let message: String?
    let label: () -> Label
    let actions: () -> Actions

    @State private var isPresented = false

    init(
        _ title: String,
        titleVisibility: Visibility = .visible,
        message: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.title = title
        self.titleVisibility = titleVisibility
        self.message = message
        self.actions = actions
        self.label = label
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .confirmationDialog(title, isPresented: $isPresented, titleVisibility: titleVisibility) {
            actions()
        } message: {
            if let message {
                Text(message)
            }
        }
    }
}
