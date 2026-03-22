import SwiftData
import SwiftUI

struct ProfileWidgetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var configs: [ProfileWidgetConfig] = []
    @State private var exerciseOptions: [ExerciseHistoryOption] = []
    @State private var selectingKind: ProfileWidgetKind?
    @State private var enableAfterSelection = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var repository: ProfileWidgetRepository {
        ProfileWidgetRepository(modelContext: modelContext)
    }

    private var metricsService: WorkoutMetricsService {
        WorkoutMetricsService(modelContext: modelContext)
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
                    message: "Choose the cards that appear on your profile, from PRs and goals to streaks, favorites, and consistency heatmaps.",
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
            loadExerciseOptions()
        }
        .sheet(item: $selectingKind) { kind in
            ProfileWidgetExercisePickerView(
                title: kind.title,
                options: exerciseOptions,
                onSelect: { option in
                    saveExerciseSelection(option, for: kind, enableWidget: enableAfterSelection)
                }
            )
        }
        .alert("Widget Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        WGJCompactSectionHeader(title, subtitle: subtitle)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func widgetRow(_ config: ProfileWidgetConfig) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: config.kind))
                .font(.headline.weight(.semibold))
                .foregroundStyle(config.isEnabled ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(WGJTheme.cardElevated.opacity(0.88))
                }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.kind.title)
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(description(for: config.kind))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                if config.kind.requiresExerciseSelection {
                    exerciseSelectionBadge(config)
                }

                HStack(spacing: 8) {
                    if config.kind.requiresExerciseSelection {
                        Button(config.selectedCatalogExerciseUUID == nil ? "Choose Exercise" : "Change") {
                            presentExercisePicker(for: config.kind, enableWidgetAfterSelection: false)
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                    }

                    Spacer(minLength: 0)

                    if config.isEnabled {
                        Button("Remove") {
                            toggleConfig(config)
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                    } else {
                        Button("Add") {
                            enableConfig(config)
                        }
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                    }
                }
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
        case .exerciseOneRMTrend:
            return "chart.line.uptrend.xyaxis"
        case .exerciseVolumeTrend:
            return "chart.bar.xaxis"
        case .streaks:
            return "flame.fill"
        case .topExercises:
            return "list.number"
        case .consistencyCalendar:
            return "calendar"
        }
    }

    private func description(for kind: ProfileWidgetKind) -> String {
        switch kind {
        case .prs:
            return "Show your strongest logged PRs."
        case .weeklyGoals:
            return "Track progress toward your workout goal."
        case .exerciseOneRMTrend:
            return "Chart your best estimated 1RM across recent workouts."
        case .exerciseVolumeTrend:
            return "Track weighted training volume over time for one exercise."
        case .streaks:
            return "See your current streak, longest run, and active days this month."
        case .topExercises:
            return "Show the lifts that keep showing up in your training."
        case .consistencyCalendar:
            return "Visualize the last 6 weeks of workout consistency."
        }
    }

    @ViewBuilder
    private func exerciseSelectionBadge(_ config: ProfileWidgetConfig) -> some View {
        if let selectedName = config.selectedExerciseNameSnapshot, !selectedName.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.semibold))
                Text(selectedName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(WGJTheme.accentCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(WGJTheme.accentCyan.opacity(0.12))
            )
        } else {
            Text("Choose an exercise before enabling this graph.")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
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

    private func enableConfig(_ config: ProfileWidgetConfig) {
        if config.kind.requiresExerciseSelection, config.selectedCatalogExerciseUUID == nil {
            presentExercisePicker(for: config.kind, enableWidgetAfterSelection: true)
            return
        }

        toggleConfig(config)
    }

    private func loadConfigs() {
        do {
            configs = try repository.configurations()
        } catch {
            showError(error)
        }
    }

    private func loadExerciseOptions() {
        do {
            exerciseOptions = try metricsService.exerciseHistoryOptions()
        } catch {
            showError(error)
        }
    }

    private func presentExercisePicker(for kind: ProfileWidgetKind, enableWidgetAfterSelection: Bool) {
        loadExerciseOptions()
        guard !exerciseOptions.isEmpty else {
            errorMessage = "Log a weighted exercise first, then you can add a graph widget for it."
            showingError = true
            return
        }

        enableAfterSelection = enableWidgetAfterSelection
        selectingKind = kind
    }

    private func saveExerciseSelection(
        _ option: ExerciseHistoryOption,
        for kind: ProfileWidgetKind,
        enableWidget: Bool
    ) {
        do {
            try repository.updateExerciseSelection(
                kind: kind,
                catalogExerciseUUID: option.catalogExerciseUUID,
                exerciseName: option.exerciseName
            )
            if enableWidget {
                try repository.setEnabled(kind: kind, isEnabled: true)
            }
            loadConfigs()
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
