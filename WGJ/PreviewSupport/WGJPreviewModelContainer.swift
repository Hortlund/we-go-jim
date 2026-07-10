import SwiftData
import SwiftUI

private struct WGJPreviewModelContainerModifier: ViewModifier {
    private let container: ModelContainer?

    init() {
        container = try? AppSchema.makeInMemoryContainer(name: "WGJPreview")
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The in-memory preview store could not be created.")
            )
        }
    }
}

extension View {
    func wgjPreviewModelContainer() -> some View {
        modifier(WGJPreviewModelContainerModifier())
    }
}
