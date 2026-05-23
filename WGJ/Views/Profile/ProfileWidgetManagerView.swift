import SwiftData
import SwiftUI

struct ProfileWidgetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionState.self) private var subscriptionState

    @State private var configs: [ProfileWidgetConfig] = []
    @State private var exerciseOptions: [ExerciseHistoryOption] = []
    @State private var selectingExerciseTarget: ExerciseSelectionTarget?
    @State private var newTrendMetric: ProfileExerciseTrendMetric = .oneRepMax
    @State private var errorMessage = ""
    @State private var showingError = false

    private enum ExerciseSelectionTarget: Identifiable {
        case singleton(kind: ProfileWidgetKind, enableAfterSelection: Bool)
        case existingTrend(id: UUID, metric: ProfileExerciseTrendMetric)
        case newTrend(metric: ProfileExerciseTrendMetric)

        var id: String {
            switch self {
            case .singleton(let kind, let enableAfterSelection):
                return "singleton-\(kind.rawValue)-\(enableAfterSelection)"
            case .existingTrend(let id, let metric):
                return "trend-\(id.uuidString)-\(metric.rawValue)"
            case .newTrend(let metric):
                return "new-trend-\(metric.rawValue)"
            }
        }

        var metric: ProfileExerciseTrendMetric? {
            switch self {
            case .singleton(let kind, _):
                return kind.defaultExerciseTrendMetric
            case .existingTrend(_, let metric), .newTrend(let metric):
                return metric
            }
        }

        var pickerTitle: String {
            switch self {
            case .singleton(let kind, _):
                return kind.title
            case .existingTrend(_, let metric), .newTrend(let metric):
                return "\(metric.title) Trend"
            }
        }
    }

    private var repository: ProfileWidgetRepository {
        ProfileWidgetRepository(modelContext: modelContext)
    }

    private var metricsService: WorkoutMetricsService {
        WorkoutMetricsService(modelContext: modelContext)
    }

    private var enabledConfigs: [ProfileWidgetConfig] {
        configs
            .filter { $0.isEnabled && canUseWidget($0.kind) && shouldShowConfig($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledConfigs: [ProfileWidgetConfig] {
        configs
            .filter { (!$0.isEnabled || !canUseWidget($0.kind)) && shouldShowConfig($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
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
                addExerciseTrendRow

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
        .sheet(item: $selectingExerciseTarget) { target in
            ProfileWidgetExercisePickerView(
                title: target.pickerTitle,
                options: exerciseOptions,
                onSelect: { option in
                    saveExerciseSelection(option, for: target)
                }
            )
            .wgjSheetSurface()
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
        let isLocked = isProLocked(config.kind)

        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconName(for: config.kind))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(config.isEnabled && !isLocked ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(WGJTheme.cardElevated.opacity(0.88))
                    }

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WGJTheme.textInverse)
                        .frame(width: 18, height: 18)
                        .background {
                            Circle()
                                .fill(WGJTheme.accentGold)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: config))
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(description(for: config))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                if isLocked {
                    Text("Pro widget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentGold)
                } else if config.kind.requiresExerciseSelection {
                    exerciseSelectionBadge(config)
                }

                HStack(spacing: 8) {
                    if config.kind.requiresExerciseSelection && !isLocked {
                        Button(config.selectedCatalogExerciseUUID == nil ? "Choose Exercise" : "Change") {
                            presentExercisePicker(for: selectionTarget(for: config, enableAfterSelection: false))
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                    }

                    Spacer(minLength: 0)

                    if isLocked && config.isEnabled {
                        Button("Remove") {
                            removeOrToggleConfig(config)
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                        .accessibilityIdentifier("profile-widget-remove-\(accessibilityIDToken(for: config))")

                        Button {
                            subscriptionState.presentPaywall()
                        } label: {
                            Label("Unlock Pro", systemImage: "sparkles")
                        }
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                        .accessibilityIdentifier("profile-widget-unlock-pro-\(config.kind.rawValue)")
                    } else if isLocked {
                        Button {
                            subscriptionState.presentPaywall()
                        } label: {
                            Label("Unlock Pro", systemImage: "sparkles")
                        }
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                        .accessibilityIdentifier("profile-widget-unlock-pro-\(config.kind.rawValue)")
                    } else if config.isEnabled {
                        Button("Remove") {
                            removeOrToggleConfig(config)
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                        .accessibilityIdentifier("profile-widget-remove-\(accessibilityIDToken(for: config))")
                    } else {
                        Button("Add") {
                            enableConfig(config)
                        }
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                        .accessibilityIdentifier("profile-widget-add-\(accessibilityIDToken(for: config))")
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

    private var addExerciseTrendRow: some View {
        let isLocked = isProLocked(.exerciseOneRMTrend)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isLocked ? WGJTheme.textSecondary : WGJTheme.accentCyan)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(WGJTheme.cardElevated.opacity(0.88))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercise Trend")
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("Add another exercise metric card to your profile.")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            if isLocked {
                HStack {
                    Text("Pro widget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentGold)
                    Spacer(minLength: 0)
                    Button {
                        subscriptionState.presentPaywall()
                    } label: {
                        Label("Unlock Pro", systemImage: "sparkles")
                    }
                    .buttonStyle(WGJCompactPrimaryButtonStyle())
                    .accessibilityIdentifier("profile-widget-unlock-pro-exerciseTrend")
                }
            } else {
                Picker("Metric", selection: $newTrendMetric) {
                    ForEach(ProfileExerciseTrendMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("profile-widget-new-trend-metric-picker")

                Button {
                    presentExercisePicker(for: .newTrend(metric: newTrendMetric))
                } label: {
                    Label("Add Exercise Trend", systemImage: "plus")
                }
                .buttonStyle(WGJCompactPrimaryButtonStyle())
                .accessibilityIdentifier("profile-widget-add-exerciseTrend")
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
        case .weeklyMuscleHeatmap:
            return "figure.strengthtraining.traditional"
        case .coachBrief:
            return "quote.bubble"
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
        case .weeklyMuscleHeatmap:
            return "Show the muscle groups trained this week."
        case .coachBrief:
            return "Read a short coach summary of what changed."
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

    private func title(for config: ProfileWidgetConfig) -> String {
        guard config.kind.isExerciseTrend else {
            return config.kind.title
        }

        if let selectedName = config.selectedExerciseNameSnapshot, !selectedName.isEmpty {
            return "\(selectedName) - \(config.exerciseTrendMetric.title)"
        }
        return "\(config.exerciseTrendMetric.title) Trend"
    }

    private func description(for config: ProfileWidgetConfig) -> String {
        guard config.kind.isExerciseTrend else {
            return description(for: config.kind)
        }

        switch config.exerciseTrendMetric {
        case .oneRepMax:
            return "Chart estimated max strength across recent workouts."
        case .maxWeight:
            return "Track the best load you logged across recent workouts."
        case .volume:
            return "Track weighted training volume over time for one exercise."
        case .maxReps:
            return "Track the best completed reps across recent workouts."
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
        guard canUseWidget(config.kind) || config.isEnabled else {
            subscriptionState.presentPaywall()
            return
        }

        do {
            if config.kind.isExerciseTrend {
                try repository.setEnabled(id: config.id, isEnabled: !config.isEnabled)
            } else {
                try repository.setEnabled(kind: config.kind, isEnabled: !config.isEnabled)
            }
            loadConfigs()
        } catch {
            showError(error)
        }
    }

    private func removeOrToggleConfig(_ config: ProfileWidgetConfig) {
        do {
            if config.kind.isExerciseTrend {
                try repository.removeConfig(id: config.id)
            } else {
                try repository.setEnabled(kind: config.kind, isEnabled: false)
            }
            loadConfigs()
        } catch {
            showError(error)
        }
    }

    private func enableConfig(_ config: ProfileWidgetConfig) {
        guard canUseWidget(config.kind) else {
            subscriptionState.presentPaywall()
            return
        }

        if config.kind.requiresExerciseSelection, config.selectedCatalogExerciseUUID == nil {
            presentExercisePicker(for: selectionTarget(for: config, enableAfterSelection: true))
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

    private func loadExerciseOptions(metric: ProfileExerciseTrendMetric? = nil) {
        do {
            exerciseOptions = try metricsService.exerciseHistoryOptions(metric: metric)
        } catch {
            showError(error)
        }
    }

    private func presentExercisePicker(for target: ExerciseSelectionTarget) {
        loadExerciseOptions(metric: target.metric)
        guard !exerciseOptions.isEmpty else {
            errorMessage = emptyExerciseMessage(for: target.metric)
            showingError = true
            return
        }

        selectingExerciseTarget = target
    }

    private func saveExerciseSelection(
        _ option: ExerciseHistoryOption,
        for target: ExerciseSelectionTarget
    ) {
        do {
            switch target {
            case .singleton(let kind, let enableWidget):
                try repository.updateExerciseSelection(
                    kind: kind,
                    catalogExerciseUUID: option.catalogExerciseUUID,
                    exerciseName: option.exerciseName
                )
                if enableWidget {
                    try repository.setEnabled(kind: kind, isEnabled: true)
                }
            case .existingTrend(let id, let metric):
                try repository.updateExerciseTrendConfig(
                    id: id,
                    metric: metric,
                    catalogExerciseUUID: option.catalogExerciseUUID,
                    exerciseName: option.exerciseName
                )
            case .newTrend(let metric):
                try repository.createExerciseTrendConfig(
                    metric: metric,
                    catalogExerciseUUID: option.catalogExerciseUUID,
                    exerciseName: option.exerciseName,
                    isEnabled: true
                )
            }
            loadConfigs()
        } catch {
            showError(error)
        }
    }

    private func selectionTarget(for config: ProfileWidgetConfig, enableAfterSelection: Bool) -> ExerciseSelectionTarget {
        if config.kind.isExerciseTrend {
            return .existingTrend(id: config.id, metric: config.exerciseTrendMetric)
        }
        return .singleton(kind: config.kind, enableAfterSelection: enableAfterSelection)
    }

    private func shouldShowConfig(_ config: ProfileWidgetConfig) -> Bool {
        guard config.kind.isExerciseTrend else { return true }
        return config.selectedCatalogExerciseUUID != nil
    }

    private func accessibilityIDToken(for config: ProfileWidgetConfig) -> String {
        if config.kind.isExerciseTrend {
            return "exerciseTrend-\(config.id.uuidString)"
        }
        return config.kind.rawValue
    }

    private func emptyExerciseMessage(for metric: ProfileExerciseTrendMetric?) -> String {
        guard let metric else {
            return "Log a weighted exercise first, then you can add a graph widget for it."
        }

        switch metric {
        case .oneRepMax:
            return "Log weighted sets first, then you can add a 1RM trend."
        case .maxWeight:
            return "Log weighted sets first, then you can add a max weight trend."
        case .volume:
            return "Log weighted sets first, then you can add a volume trend."
        case .maxReps:
            return "Log completed sets first, then you can add a max reps trend."
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func canUseWidget(_ kind: ProfileWidgetKind) -> Bool {
        !ProAccessPolicy.requiresPro(kind) || subscriptionState.isPro
    }

    private func isProLocked(_ kind: ProfileWidgetKind) -> Bool {
        ProAccessPolicy.requiresPro(kind) && !subscriptionState.isPro
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
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
