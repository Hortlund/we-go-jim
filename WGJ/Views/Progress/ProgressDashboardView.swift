import SwiftData
import SwiftUI

struct ProgressDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.isTabActive) private var isTabActive

    @State private var snapshot = WorkoutProgressDashboardSnapshot.empty
    @State private var selectedPreviousSessionID: UUID?
    @State private var selectedCurrentSessionID: UUID?
    @State private var hasLoadedSnapshot = false
    @State private var lastLoadedContentUpdatedAt: Date?
    @State private var lastRefreshAt: Date?
    @State private var isLoadingSnapshot = false
    @State private var snapshotLoadGeneration = AsyncLoadGenerationTracker()
    @State private var isWorkoutPickerExpanded = false
    @State private var pickerTarget: ProgressWorkoutPickerTarget?
    @State private var errorMessage = ""
    @State private var showingError = false

    private var progressBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader(
                    "Progress",
                    subtitle: "Compare two completed workouts and see what moved."
                )

                content
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadSnapshotIfNeeded()
        }
        .sheet(item: $pickerTarget) { target in
            ProgressWorkoutPickerSheet(
                title: target.title,
                options: snapshot.compatibleWorkoutOptions(for: target.selectionSlot),
                selectedSessionID: target == .previous ? selectedPreviousSessionID : selectedCurrentSessionID,
                disabledSessionID: target == .previous ? selectedCurrentSessionID : selectedPreviousSessionID,
                onSelect: { option in
                    selectWorkout(option, target: target)
                }
            )
        }
        .alert("Progress Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.state {
        case .insufficientHistory(let availableWorkoutCount):
            WGJEmptyStateCard(
                title: "Log two workouts to compare progress",
                message: availableWorkoutCount == 0
                    ? "Completed workouts will show up here once you finish them."
                    : "One completed workout is saved. Finish one more and this turns into a comparison.",
                icon: "chart.line.uptrend.xyaxis"
            )
        case .selectionUnavailable:
            WGJEmptyStateCard(
                title: "Pick two different workouts",
                message: "The selected comparison could not be loaded. Choose two completed workouts from history.",
                icon: "exclamationmark.triangle"
            )
            workoutPickerSection(previous: nil, current: nil)
        case .ready(let comparison):
            workoutPickerSection(
                previous: comparison.previousWorkout,
                current: comparison.currentWorkout
            )
            exerciseComparisonSection(comparison.exerciseComparisons)
            metricGrid(comparison.metricDeltas)
            highlightSection(comparison.highlightCards)
        }
    }

    private func workoutPickerSection(
        previous: WorkoutProgressWorkoutSummary?,
        current: WorkoutProgressWorkoutSummary?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isWorkoutPickerExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        WGJSectionHeader(
                            "Workout Matchup",
                            subtitle: pickerSubtitle(previous: previous, current: current)
                        )
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isWorkoutPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(WGJTheme.fieldStrong.opacity(0.82))
                        }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress-workout-picker-toggle")

            if isWorkoutPickerExpanded {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        workoutSelectionButton(
                            title: "Earlier",
                            workout: previous,
                            target: .previous
                        )
                        workoutSelectionButton(
                            title: "Later",
                            workout: current,
                            target: .current
                        )
                    }

                    VStack(spacing: 12) {
                        workoutSelectionButton(
                            title: "Earlier",
                            workout: previous,
                            target: .previous
                        )
                        workoutSelectionButton(
                            title: "Later",
                            workout: current,
                            target: .current
                        )
                    }
                }
            }

            if isLoadingSnapshot {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("progress-loading-indicator")
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("progress-workout-picker-section")
    }

    private func pickerSubtitle(
        previous: WorkoutProgressWorkoutSummary?,
        current: WorkoutProgressWorkoutSummary?
    ) -> String {
        guard let previous, let current else {
            return "Defaults to your latest repeat. Tap to choose any completed workouts."
        }

        return "\(previous.name) -> \(current.name)"
    }

    private func workoutSelectionButton(
        title: String,
        workout: WorkoutProgressWorkoutSummary?,
        target: ProgressWorkoutPickerTarget
    ) -> some View {
        Button {
            pickerTarget = target
        } label: {
            HStack(spacing: 12) {
                Image(systemName: target == .previous ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(workout?.name ?? "Choose workout")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)

                    if let workout {
                        Text(workout.dateText)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.fieldStrong.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.42), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func metricGrid(_ metricDeltas: [WorkoutProgressMetricDelta]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            ForEach(metricDeltas) { metric in
                ProgressMetricDeltaCard(metric: metric)
            }
        }
    }

    private func highlightSection(_ highlights: [WorkoutProgressHighlightCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Highlights", subtitle: "Useful signals from this matchup.")

            ForEach(highlights) { highlight in
                ProgressHighlightCard(highlight: highlight)
            }
        }
    }

    private func exerciseComparisonSection(_ comparisons: [WorkoutProgressExerciseComparison]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Template Exercise Progress",
                subtitle: "Weight, reps, and volume movement on repeated exercises."
            )

            if comparisons.isEmpty {
                WGJEmptyStateCard(
                    title: "No shared exercises",
                    message: "Pick two runs from the same template to compare exercise movement cleanly.",
                    icon: "arrow.triangle.branch"
                )
            } else {
                ForEach(comparisons) { comparison in
                    ProgressExerciseComparisonRow(comparison: comparison)
                }
            }
        }
    }

    @MainActor
    private func reloadSnapshotIfNeeded() async {
        let currentContentUpdatedAt = await currentProgressContentUpdatedAt()
        guard TimestampedReloadPolicy.shouldReload(
            hasLoaded: hasLoadedSnapshot,
            needsExplicitRefresh: false,
            currentContentUpdatedAt: currentContentUpdatedAt,
            lastLoadedContentUpdatedAt: lastLoadedContentUpdatedAt,
            lastRefreshAt: lastRefreshAt
        ) else {
            return
        }

        await reloadSnapshot(contentUpdatedAt: currentContentUpdatedAt)
    }

    @MainActor
    private func reloadSnapshot(contentUpdatedAt: Date? = nil) async {
        let loadGeneration = snapshotLoadGeneration.next()
        isLoadingSnapshot = true
        defer {
            if snapshotLoadGeneration.isCurrent(loadGeneration) {
                isLoadingSnapshot = false
            }
        }

        do {
            let previousSelection = selectedPreviousSessionID
            let currentSelection = selectedCurrentSessionID
            let backgroundStore = progressBackgroundStore
            let loadedSnapshot = try await backgroundStore.perform("progress-dashboard.snapshot") { backgroundContext in
                try WorkoutProgressSnapshotLoader.load(
                    modelContext: backgroundContext,
                    selectedPreviousSessionID: previousSelection,
                    selectedCurrentSessionID: currentSelection
                )
            }

            guard snapshotLoadGeneration.isCurrent(loadGeneration) else { return }
            snapshot = loadedSnapshot
            selectedPreviousSessionID = loadedSnapshot.selectedPreviousSessionID
            selectedCurrentSessionID = loadedSnapshot.selectedCurrentSessionID
            hasLoadedSnapshot = true
            lastLoadedContentUpdatedAt = contentUpdatedAt
            lastRefreshAt = .now
        } catch {
            guard snapshotLoadGeneration.isCurrent(loadGeneration) else { return }
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func selectWorkout(
        _ option: WorkoutProgressWorkoutOption,
        target: ProgressWorkoutPickerTarget
    ) {
        switch target {
        case .previous:
            if option.sessionID == selectedCurrentSessionID {
                selectedCurrentSessionID = selectedPreviousSessionID
            }
            selectedPreviousSessionID = option.sessionID
        case .current:
            if option.sessionID == selectedPreviousSessionID {
                selectedPreviousSessionID = selectedCurrentSessionID
            }
            selectedCurrentSessionID = option.sessionID
        }

        pickerTarget = nil
        isWorkoutPickerExpanded = false
        Task {
            await reloadSnapshot()
        }
    }

    @MainActor
    private func currentProgressContentUpdatedAt() async -> Date? {
        let backgroundStore = progressBackgroundStore
        return try? await backgroundStore.perform("progress-dashboard.latest-updated-at") { backgroundContext in
            try WorkoutSessionRepository(modelContext: backgroundContext).latestCompletedSessionUpdatedAt()
        }
    }
}

private enum ProgressWorkoutPickerTarget: Identifiable {
    case previous
    case current

    var id: String {
        switch self {
        case .previous:
            return "previous"
        case .current:
            return "current"
        }
    }

    var title: String {
        switch self {
        case .previous:
            return "Earlier Workout"
        case .current:
            return "Later Workout"
        }
    }

    var selectionSlot: WorkoutProgressSelectionSlot {
        switch self {
        case .previous:
            return .previous
        case .current:
            return .current
        }
    }
}

private struct ProgressMetricDeltaCard: View {
    let metric: WorkoutProgressMetricDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: metric.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(directionTint(metric.direction))
                Text(metric.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }

            Text(metric.currentText)
                .font(.title3.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(spacing: 6) {
                Text(metric.deltaText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(directionTint(metric.direction))

                Text("from \(metric.previousText)")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .wgjCardContainer(strong: true)
    }
}

private struct ProgressHighlightCard: View {
    let highlight: WorkoutProgressHighlightCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: highlight.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(directionTint(highlight.direction))
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(directionTint(highlight.direction).opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)
                    .textCase(.uppercase)

                Text(highlight.value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .lineLimit(2)

                Text(highlight.detail)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .wgjCardContainer()
    }
}

private struct ProgressExerciseComparisonRow: View {
    let comparison: WorkoutProgressExerciseComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(comparison.exerciseName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)

                    Text(comparison.deltaText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(directionTint(comparison.direction))
                }

                Spacer(minLength: 0)

                Image(systemName: directionSystemImage(comparison.direction))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(directionTint(comparison.direction))
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(directionTint(comparison.direction).opacity(0.14))
                    }
            }

            HStack(alignment: .top, spacing: 10) {
                comparisonColumn(
                    title: "Earlier",
                    bestSet: comparison.previousBestSetText,
                    volume: comparison.previousVolumeText
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(.top, 24)

                comparisonColumn(
                    title: "Later",
                    bestSet: comparison.currentBestSetText,
                    volume: comparison.currentVolumeText
                )
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("progress-exercise-comparison-row")
    }

    private func comparisonColumn(title: String, bestSet: String, volume: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.textSecondary)
                .textCase(.uppercase)

            Text(bestSet)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(volume)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                .fill(WGJTheme.fieldStrong.opacity(0.72))
        }
    }
}

private struct ProgressWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [WorkoutProgressWorkoutOption]
    let selectedSessionID: UUID?
    let disabledSessionID: UUID?
    let onSelect: (WorkoutProgressWorkoutOption) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if options.isEmpty {
                        WGJEmptyStateCard(
                            title: "No completed workouts",
                            message: "Finish workouts and they will appear here.",
                            icon: "clock.fill"
                        )
                    } else {
                        ForEach(options) { option in
                            optionButton(option)
                        }
                    }
                }
                .padding(16)
            }
            .wgjScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func optionButton(_ option: WorkoutProgressWorkoutOption) -> some View {
        let isSelected = option.sessionID == selectedSessionID
        let isDisabled = option.sessionID == disabledSessionID

        return Button {
            guard !isDisabled else { return }
            onSelect(option)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? WGJTheme.success : WGJTheme.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isDisabled ? WGJTheme.textSecondary : WGJTheme.textPrimary)
                        .lineLimit(2)

                    Text(option.detailText)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                Spacer(minLength: 0)

                if isDisabled {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .padding(14)
            .wgjCardContainer(strong: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private func directionTint(_ direction: WorkoutProgressDirection) -> Color {
    switch direction {
    case .up:
        return WGJTheme.success
    case .down:
        return WGJTheme.warning
    case .flat:
        return WGJTheme.textSecondary
    }
}

private func directionSystemImage(_ direction: WorkoutProgressDirection) -> String {
    switch direction {
    case .up:
        return "arrow.up.right"
    case .down:
        return "arrow.down.right"
    case .flat:
        return "minus"
    }
}

#Preview {
    ProgressDashboardView()
        .modelContainer(for: [
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
        ], inMemory: true)
}
