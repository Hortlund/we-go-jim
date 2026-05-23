import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let actionTitle: String
    let onSelect: (ExerciseCatalogItem) -> Void

    init(
        repository: ExerciseCatalogRepository,
        title: String = "Add Exercise",
        actionTitle: String? = nil,
        onSelect: @escaping (ExerciseCatalogItem) -> Void
    ) {
        _ = repository
        self.title = title
        self.actionTitle = actionTitle ?? title
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ExercisesCatalogView(mode: .pick(actionTitle: actionTitle, onSelect: { selected in
                WGJKeyboard.dismiss()
                onSelect(selected)
                dismiss()
            }))
            .wgjNavigationChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WGJKeyboard.dismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}
