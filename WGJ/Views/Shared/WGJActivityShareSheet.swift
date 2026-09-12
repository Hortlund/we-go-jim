import SwiftUI
import UIKit

struct WGJActivityShareSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let activityItems: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            // UIKit can finish an activity after an external-app handoff. End
            // SwiftUI's presentation too, for success, cancellation, or failure.
            // Becoming active alone does not mean the activity has finished.
            Task { @MainActor in
                dismiss()
                onComplete?()
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
    }
}
