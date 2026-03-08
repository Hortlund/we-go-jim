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
            Section {
                WGJEmptyStateCard(
                    title: "Profile widgets",
                    message: "Choose the cards that appear on your profile, then drag enabled widgets to reorder them.",
                    icon: "square.grid.2x2"
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if enabledConfigs.isEmpty {
                    WGJEmptyStateCard(
                        title: "No widgets enabled",
                        message: "Turn on at least one widget to show progress on your profile.",
                        icon: "rectangle.stack.badge.plus"
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(enabledConfigs) { config in
                    widgetRow(config)
                }
                .onMove(perform: moveEnabledWidgets)
            } header: {
                sectionHeader("Enabled", subtitle: "Visible on your profile")
            }

            Section {
                ForEach(disabledConfigs) { config in
                    widgetRow(config)
                }
            } header: {
                sectionHeader("Available", subtitle: "Add more profile modules")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Manage Widgets")
        .navigationBarTitleDisplayMode(.inline)
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

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        WGJSectionHeader(title, subtitle: subtitle)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func widgetRow(_ config: ProfileWidgetConfig) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: config.kind))
                .font(.headline.weight(.semibold))
                .foregroundStyle(config.isEnabled ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(WGJTheme.cardElevated.opacity(0.88))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(config.kind.title)
                    .font(.headline)
                    .foregroundStyle(WGJTheme.textPrimary)

                Text(description(for: config.kind))
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Spacer()

            if config.isEnabled {
                Button("Remove") {
                    toggleConfig(config)
                }
                .buttonStyle(WGJGhostButtonStyle())
            } else {
                Button("Add") {
                    toggleConfig(config)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(cornerRadius: WGJRadius.control)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func iconName(for kind: ProfileWidgetKind) -> String {
        switch kind {
        case .prs:
            return "trophy.fill"
        case .weeklyGoals:
            return "target"
        }
    }

    private func description(for kind: ProfileWidgetKind) -> String {
        switch kind {
        case .prs:
            return "Show your latest personal records."
        case .weeklyGoals:
            return "Track progress toward your workout goal."
        }
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
