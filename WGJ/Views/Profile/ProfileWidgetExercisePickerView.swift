import SwiftUI

struct ProfileWidgetExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [ExerciseHistoryOption]
    let onSelect: (ExerciseHistoryOption) -> Void

    @State private var searchText = ""
    @State private var filteredOptions: [ExerciseHistoryOption]

    init(
        title: String,
        options: [ExerciseHistoryOption],
        onSelect: @escaping (ExerciseHistoryOption) -> Void
    ) {
        self.title = title
        self.options = options
        self.onSelect = onSelect
        _filteredOptions = State(initialValue: options)
    }

    var body: some View {
        NavigationStack {
            List {
                if options.isEmpty {
                    WGJEmptyStateCard(
                        title: "No exercise history yet",
                        message: "Complete weighted sets for an exercise before adding a graph widget for it.",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if filteredOptions.isEmpty {
                    WGJEmptyStateCard(
                        title: "No matches",
                        message: "Try a different exercise name.",
                        icon: "magnifyingglass"
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredOptions) { option in
                        Button {
                            onSelect(option)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.exerciseName)
                                        .font(.headline)
                                        .foregroundStyle(WGJTheme.textPrimary)

                                    Text("Last logged \(option.lastPerformedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(WGJTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WGJTheme.textSecondary)
                            }
                            .padding(12)
                            .wgjCardContainer(cornerRadius: WGJRadius.control)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercise history")
            .task(id: searchText) {
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    refreshFilteredOptions()
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                refreshFilteredOptions()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func refreshFilteredOptions() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            filteredOptions = options
            return
        }

        filteredOptions = options.filter { option in
            option.exerciseName.localizedCaseInsensitiveContains(query)
        }
    }
}
