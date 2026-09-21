import SwiftData
import SwiftUI

struct ProfileWidgetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    @State private var isReordering = false
    @State private var reorderSaveTask: Task<Void, Never>?
    @State private var reorderSaveToken: UUID?
    @State private var isSavingConfiguration = false

    @State private var configs: [ProfileWidgetConfigSnapshot] = []
    @State private var widgetListSnapshot = ProfileWidgetManagerListSnapshot.empty
    @State private var exerciseOptions: [ExerciseHistoryOption] = []
    @State private var selectingExerciseTarget: ExerciseSelectionTarget?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isLoading = false
    @State private var exercisePickerLoadTask: Task<Void, Never>?
    @State private var exercisePickerLoadToken: UUID?

    private enum ExerciseSelectionTarget: Identifiable, Sendable {
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

    }

    private var widgetBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        let visibleEnabledConfigs = widgetListSnapshot.visibleEnabledConfigs
        let visibleAvailableConfigs = widgetListSnapshot.visibleAvailableConfigs

        List {
            Section {
                WGJEmptyStateCard(
                    title: "Profile widgets",
                    message: isReordering
                        ? "Use the up and down arrows to change the order. Changes save automatically."
                        : "Choose your profile widgets. Tap Reorder to change their order.",
                    icon: "square.grid.2x2"
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if visibleEnabledConfigs.isEmpty {
                    WGJEmptyStateCard(
                        title: "No widgets enabled",
                        message: "Turn on at least one widget to show progress on your profile.",
                        icon: "rectangle.stack.badge.plus"
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(visibleEnabledConfigs) { config in
                    if isReordering {
                        reorderRow(config)
                    } else {
                        widgetRow(config)
                    }
                }
            } header: {
                sectionHeader("Enabled", subtitle: "Visible on your profile")
            }

            if !isReordering {
                Section {
                    addExerciseTrendRow

                    ForEach(visibleAvailableConfigs) { config in
                        widgetRow(config)
                    }
                } header: {
                    sectionHeader("Available", subtitle: "Add more profile modules")
                }
            }
        }
        .disabled(isSavingConfiguration)
        .interactiveDismissDisabled(isSavingConfiguration || reorderSaveToken != nil)
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
                .disabled(isSavingConfiguration || reorderSaveToken != nil)
                .accessibilityIdentifier("profile-widgets-done-button")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(isReordering ? "Finish" : "Reorder") {
                    withAnimation { isReordering.toggle() }
                }
                .disabled(isSavingConfiguration || reorderSaveToken != nil || visibleEnabledConfigs.count < 2)
                .accessibilityIdentifier("profile-widgets-reorder-button")
            }
        }
        .task {
            await reloadInitialData()
        }
        .onDisappear {
            cancelExercisePickerLoad()
        }
        .sheet(item: $selectingExerciseTarget) { target in
            ProfileWidgetExercisePickerView(
                initialMetric: target.metric ?? .oneRepMax,
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

    private func widgetRow(_ config: ProfileWidgetConfigSnapshot) -> some View {
        let isLocked = false

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
                        Button(config.selectedCatalogExerciseUUID == nil ? "Choose Exercise" : "Edit Trend") {
                            presentExercisePicker(for: selectionTarget(for: config, enableAfterSelection: false))
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                        .accessibilityIdentifier("profile-widget-edit-\(accessibilityIDToken(for: config))")
                    }

                    Spacer(minLength: 0)

                    if config.isEnabled {
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
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

            Button {
                presentExercisePicker(for: .newTrend(metric: .oneRepMax))
            } label: {
                Label("Add Exercise Trend", systemImage: "plus")
            }
            .buttonStyle(WGJCompactPrimaryButtonStyle())
            .accessibilityIdentifier("profile-widget-add-exerciseTrend")
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

    private func title(for config: ProfileWidgetConfigSnapshot) -> String {
        guard config.kind.isExerciseTrend else {
            return config.kind.title
        }

        return config.trendTitle
    }

    private func description(for config: ProfileWidgetConfigSnapshot) -> String {
        config.kind.isExerciseTrend ? config.exerciseTrendMetric.trendDescription : description(for: config.kind)
    }

    @ViewBuilder
    private func exerciseSelectionBadge(_ config: ProfileWidgetConfigSnapshot) -> some View {
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

    private func reorderRow(_ config: ProfileWidgetConfigSnapshot) -> some View {
        let enabled = widgetListSnapshot.visibleEnabledConfigs
        let index = enabled.firstIndex { $0.id == config.id } ?? 0
        return HStack(spacing: 12) {
            Text(title(for: config))
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                moveEnabledWidgets(from: IndexSet(integer: index), to: index - 1)
            } label: {
                Image(systemName: "arrow.up").frame(width: 32, height: 44)
            }
            .disabled(index == 0)
            .accessibilityLabel("Move \(title(for: config)) up")
            .accessibilityIdentifier("profile-widget-move-up-\(accessibilityIDToken(for: config))")
            Button {
                moveEnabledWidgets(from: IndexSet(integer: index), to: index + 2)
            } label: {
                Image(systemName: "arrow.down").frame(width: 32, height: 44)
            }
            .disabled(index == enabled.count - 1)
            .accessibilityLabel("Move \(title(for: config)) down")
            .accessibilityIdentifier("profile-widget-move-down-\(accessibilityIDToken(for: config))")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }

    private func moveEnabledWidgets(from source: IndexSet, to destination: Int) {
        var ids = widgetListSnapshot.visibleEnabledConfigs.map(\.id)
        guard !source.isEmpty, source.allSatisfy({ ids.indices.contains($0) }),
              (0...ids.count).contains(destination) else { return }
        let original = ids
        ids.move(fromOffsets: source, toOffset: destination)
        guard ids != original else { return }
        let order = ids
        let byID = Dictionary(configs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let movedIDs = Set(order)
        let ordered = order.compactMap { byID[$0] } + configs.filter { !movedIDs.contains($0.id) }
        applyConfigs(ordered.enumerated().map { $0.element.updating(sortOrder: $0.offset) })

        let backgroundStore = widgetBackgroundStore
        let previousSave = reorderSaveTask
        let token = UUID()
        reorderSaveToken = token
        reorderSaveTask = Task { @MainActor in
            // Preserve move order and prevent older results from reverting a newer move.
            await previousSave?.value
            do {
                let snapshots = try await backgroundStore.performWrite("profile-widgets.move") { backgroundContext in
                    let repository = ProfileWidgetRepository(modelContext: backgroundContext)
                    try repository.reorderEnabledWidgets(ids: order)
                    return try repository.configurationSnapshots()
                }
                if reorderSaveToken == token { applyConfigs(snapshots) }
            } catch {
                if reorderSaveToken == token {
                    let snapshots = try? await backgroundStore.perform("profile-widgets.reload-order", { context in
                        try ProfileWidgetRepository(modelContext: context).configurationSnapshots()
                    })
                    // A newer move may take ownership while the recovery read is suspended.
                    guard reorderSaveToken == token else { return }
                    if let snapshots { applyConfigs(snapshots) }
                    showError(error)
                }
            }
            if reorderSaveToken == token {
                reorderSaveToken = nil
                reorderSaveTask = nil
            }
        }
    }

    private func toggleConfig(_ config: ProfileWidgetConfigSnapshot) {
        guard !isSavingConfiguration else { return }
        isSavingConfiguration = true
        let backgroundStore = widgetBackgroundStore
        applyConfigs(configs.map { snapshot in
            guard snapshot.id == config.id else { return snapshot }
            return snapshot.updating(isEnabled: !config.isEnabled)
        })
        Task { @MainActor in
            defer { isSavingConfiguration = false }
            do {
                let snapshots = try await backgroundStore.performWrite("profile-widgets.toggle") { backgroundContext in
                    let repository = ProfileWidgetRepository(modelContext: backgroundContext)
                    if config.kind.isExerciseTrend {
                        try repository.setEnabled(id: config.id, isEnabled: !config.isEnabled)
                    } else {
                        try repository.setEnabled(kind: config.kind, isEnabled: !config.isEnabled)
                    }
                    return try repository.configurationSnapshots()
                }
                applyConfigs(snapshots)
            } catch {
                showError(error)
            }
        }
    }

    private func removeOrToggleConfig(_ config: ProfileWidgetConfigSnapshot) {
        guard !isSavingConfiguration else { return }
        isSavingConfiguration = true
        let backgroundStore = widgetBackgroundStore
        if config.kind.isExerciseTrend {
            applyConfigs(configs.filter { $0.id != config.id })
        } else {
            applyConfigs(configs.map { snapshot in
                guard snapshot.id == config.id else { return snapshot }
                return snapshot.updating(isEnabled: false)
            })
        }
        Task { @MainActor in
            defer { isSavingConfiguration = false }
            do {
                let snapshots = try await backgroundStore.performWrite("profile-widgets.remove") { backgroundContext in
                    let repository = ProfileWidgetRepository(modelContext: backgroundContext)
                    if config.kind.isExerciseTrend {
                        try repository.removeConfig(id: config.id)
                    } else {
                        try repository.setEnabled(kind: config.kind, isEnabled: false)
                    }
                    return try repository.configurationSnapshots()
                }
                applyConfigs(snapshots)
            } catch {
                showError(error)
            }
        }
    }

    private func enableConfig(_ config: ProfileWidgetConfigSnapshot) {
        if config.kind.requiresExerciseSelection, config.selectedCatalogExerciseUUID == nil {
            presentExercisePicker(for: selectionTarget(for: config, enableAfterSelection: true))
            return
        }

        toggleConfig(config)
    }

    @MainActor
    private func reloadInitialData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let backgroundStore = widgetBackgroundStore
        do {
            let snapshot = try await backgroundStore.perform("profile-widgets.initial-load") { backgroundContext in
                ProfileWidgetManagerSnapshot(
                    configs: try ProfileWidgetRepository(modelContext: backgroundContext).configurationSnapshots(),
                    exerciseOptions: try WorkoutMetricsService(modelContext: backgroundContext).exerciseHistoryOptions()
                )
            }
            applyConfigs(snapshot.configs)
            exerciseOptions = snapshot.exerciseOptions
        } catch {
            showError(error)
        }
    }

    private func presentExercisePicker(for target: ExerciseSelectionTarget) {
        exercisePickerLoadTask?.cancel()
        let token = UUID()
        exercisePickerLoadToken = token
        let backgroundStore = widgetBackgroundStore
        let metric = target.metric
        let emptyMessage = "Complete sets for an exercise first, then add a trend with or without weight."
        exercisePickerLoadTask = Task.detached(priority: .userInitiated) {
            do {
                let options = try await backgroundStore.perform("profile-widgets.exercise-options") { backgroundContext in
                    try WorkoutMetricsService(modelContext: backgroundContext).exerciseHistoryOptions(metric: metric)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard exercisePickerLoadToken == token else { return }
                    exerciseOptions = options
                    exercisePickerLoadTask = nil
                    exercisePickerLoadToken = nil
                    guard !options.isEmpty else {
                        errorMessage = emptyMessage
                        showingError = true
                        return
                    }
                    selectingExerciseTarget = target
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard exercisePickerLoadToken == token else { return }
                    exercisePickerLoadTask = nil
                    exercisePickerLoadToken = nil
                    showError(error)
                }
            }
        }
    }

    private func cancelExercisePickerLoad() {
        exercisePickerLoadTask?.cancel()
        exercisePickerLoadTask = nil
        exercisePickerLoadToken = nil
    }

    private func saveExerciseSelection(
        _ option: ExerciseHistoryOption,
        for target: ExerciseSelectionTarget
    ) {
        guard !isSavingConfiguration else { return }
        isSavingConfiguration = true
        let backgroundStore = widgetBackgroundStore
        applyConfigs(Self.applyingExerciseSelection(option, target: target, to: configs))
        Task { @MainActor in
            defer { isSavingConfiguration = false }
            do {
                let snapshots = try await backgroundStore.performWrite("profile-widgets.exercise-selection") { backgroundContext in
                    let repository = ProfileWidgetRepository(modelContext: backgroundContext)
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
                    case .existingTrend(let id, _):
                        try repository.updateExerciseTrendConfig(
                            id: id,
                            metric: option.trendMetric,
                            catalogExerciseUUID: option.catalogExerciseUUID,
                            exerciseName: option.exerciseName
                        )
                    case .newTrend:
                        try repository.createExerciseTrendConfig(
                            metric: option.trendMetric,
                            catalogExerciseUUID: option.catalogExerciseUUID,
                            exerciseName: option.exerciseName,
                            isEnabled: true
                        )
                    }
                    return try repository.configurationSnapshots()
                }
                applyConfigs(snapshots)
            } catch {
                showError(error)
            }
        }
    }

    private func selectionTarget(for config: ProfileWidgetConfigSnapshot, enableAfterSelection: Bool) -> ExerciseSelectionTarget {
        if config.kind.isExerciseTrend {
            return .existingTrend(id: config.id, metric: config.exerciseTrendMetric)
        }
        return .singleton(kind: config.kind, enableAfterSelection: enableAfterSelection)
    }

    private func shouldShowConfig(_ config: ProfileWidgetConfigSnapshot) -> Bool {
        guard config.kind.isExerciseTrend else { return true }
        return config.selectedCatalogExerciseUUID != nil
    }

    private func accessibilityIDToken(for config: ProfileWidgetConfigSnapshot) -> String {
        if config.kind.isExerciseTrend {
            return "exerciseTrend-\(config.id.uuidString)"
        }
        return config.kind.rawValue
    }

    @MainActor
    private func applyConfigs(_ snapshots: [ProfileWidgetConfigSnapshot]) {
        configs = snapshots
        rebuildWidgetListSnapshot()
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    @MainActor
    private func rebuildWidgetListSnapshot() {
        widgetListSnapshot = ProfileWidgetManagerListSnapshot.make(
            configs: configs,
            canUseWidget: { _ in true }
        )
    }

    nonisolated private static func applyingExerciseSelection(
        _ option: ExerciseHistoryOption,
        target: ExerciseSelectionTarget,
        to configs: [ProfileWidgetConfigSnapshot]
    ) -> [ProfileWidgetConfigSnapshot] {
        switch target {
        case .singleton(let kind, let enableWidget):
            return configs.map { config in
                guard config.kind == kind else { return config }
                return config.updating(
                    isEnabled: enableWidget ? true : config.isEnabled,
                    selectedCatalogExerciseUUID: option.catalogExerciseUUID,
                    selectedExerciseNameSnapshot: option.exerciseName
                )
            }
        case .existingTrend(let id, _):
            return configs.map { config in
                guard config.id == id else { return config }
                return config.updating(
                    kind: .exerciseOneRMTrend,
                    selectedCatalogExerciseUUID: option.catalogExerciseUUID,
                    selectedExerciseNameSnapshot: option.exerciseName,
                    exerciseTrendMetric: option.trendMetric
                )
            }
        case .newTrend:
            let nextSortOrder = (configs.map(\.sortOrder).max() ?? -1) + 1
            return configs + [
                ProfileWidgetConfigSnapshot(
                    id: UUID(),
                    kind: .exerciseOneRMTrend,
                    isEnabled: true,
                    sortOrder: nextSortOrder,
                    selectedCatalogExerciseUUID: option.catalogExerciseUUID,
                    selectedExerciseNameSnapshot: option.exerciseName,
                    exerciseTrendMetric: option.trendMetric,
                    updatedAt: .now
                ),
            ]
        }
    }
}

private struct ProfileWidgetManagerSnapshot: Sendable {
    let configs: [ProfileWidgetConfigSnapshot]
    let exerciseOptions: [ExerciseHistoryOption]
}

nonisolated struct ProfileWidgetManagerListSnapshot: Sendable {
    let visibleEnabledConfigs: [ProfileWidgetConfigSnapshot]
    let visibleAvailableConfigs: [ProfileWidgetConfigSnapshot]

    static let empty = ProfileWidgetManagerListSnapshot(
        visibleEnabledConfigs: [],
        visibleAvailableConfigs: []
    )

    static func make(
        configs: [ProfileWidgetConfigSnapshot],
        canUseWidget: (ProfileWidgetKind) -> Bool
    ) -> ProfileWidgetManagerListSnapshot {
        var visibleEnabledConfigs: [ProfileWidgetConfigSnapshot] = []
        var visibleAvailableConfigs: [ProfileWidgetConfigSnapshot] = []

        for config in configs.sorted(by: { $0.sortOrder < $1.sortOrder }) where shouldShowConfig(config) {
            if config.isEnabled && canUseWidget(config.kind) {
                visibleEnabledConfigs.append(config)
            } else {
                visibleAvailableConfigs.append(config)
            }
        }

        return ProfileWidgetManagerListSnapshot(
            visibleEnabledConfigs: visibleEnabledConfigs,
            visibleAvailableConfigs: visibleAvailableConfigs
        )
    }

    private static func shouldShowConfig(_ config: ProfileWidgetConfigSnapshot) -> Bool {
        guard config.kind.isExerciseTrend else { return true }
        return config.selectedCatalogExerciseUUID != nil
    }
}

#Preview {
    NavigationStack {
        ProfileWidgetManagerView()
    }
    .wgjPreviewModelContainer()
}
