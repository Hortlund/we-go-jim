import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ExerciseCatalogItem) -> Void

    init(repository: ExerciseCatalogRepository, onSelect: @escaping (ExerciseCatalogItem) -> Void) {
        _ = repository
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ExercisesCatalogView(mode: .pick(onSelect: { selected in
                onSelect(selected)
                dismiss()
            }))
            .wgjNavigationChrome()
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
