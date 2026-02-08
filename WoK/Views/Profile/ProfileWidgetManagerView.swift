import SwiftData
import SwiftUI

struct ProfileWidgetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var configs: [ProfileWidgetConfig] = []
    @State private var errorMessage = ""
    @State private var showingError = false

    private var repository: ProfileWidgetRepository {
        ProfileWidgetRepository(modelContext: modelContext)
    }

    private var enabledConfigs: [ProfileWidgetConfig] {
        configs.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledConfigs: [ProfileWidgetConfig] {
        configs.filter { !$0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section("Enabled") {
                if enabledConfigs.isEmpty {
                    Text("No widgets enabled.")
                        .foregroundStyle(WoKTheme.textSecondary)
                }

                ForEach(enabledConfigs) { config in
                    widgetRow(config)
                }
                .onMove(perform: moveEnabledWidgets)
            }

            Section("Available") {
                ForEach(disabledConfigs) { config in
                    widgetRow(config)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WoKTheme.screenBackgroundGradient.ignoresSafeArea())
        .wokNavigationChrome()
        .navigationTitle("Manage Widgets")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .task {
            loadConfigs()
        }
        .alert("Widget Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func widgetRow(_ config: ProfileWidgetConfig) -> some View {
        HStack {
            Text(config.kind.title)
                .foregroundStyle(WoKTheme.textPrimary)

            Spacer()

            Button(config.isEnabled ? "Remove" : "Add") {
                toggleConfig(config)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(config.isEnabled ? WoKTheme.danger : WoKTheme.accentBlue)
        }
        .listRowBackground(WoKTheme.card)
    }

    private func moveEnabledWidgets(from source: IndexSet, to destination: Int) {
        do {
            try repository.moveEnabledWidget(fromOffsets: source, toOffset: destination)
            loadConfigs()
        } catch {
            showError(error)
        }
    }

    private func toggleConfig(_ config: ProfileWidgetConfig) {
        do {
            try repository.setEnabled(kind: config.kind, isEnabled: !config.isEnabled)
            loadConfigs()
        } catch {
            showError(error)
        }
    }

    private func loadConfigs() {
        do {
            configs = try repository.configurations()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

#Preview {
    NavigationStack {
        ProfileWidgetManagerView()
    }
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
