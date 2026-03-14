import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutSession.updatedAt, order: .reverse)])
    private var trackedSessions: [WorkoutSession]
    @Query(sort: [SortDescriptor(\ProfileWidgetConfig.updatedAt, order: .reverse)])
    private var widgetConfigs: [ProfileWidgetConfig]
    @Query(sort: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)])
    private var storedProfiles: [UserProfile]

    @State private var displayName = ""
    @State private var avatarImageData: Data?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var hasLoadedProfile = false
    @State private var dashboardContent = ProfileDashboardContent.empty
    @State private var showingWidgetManager = false

    @State private var errorMessage = ""
    @State private var showingError = false

    private var profileRepository: ProfileRepository {
        ProfileRepository(modelContext: modelContext)
    }

    private var widgetRepository: ProfileWidgetRepository {
        ProfileWidgetRepository(modelContext: modelContext)
    }

    private var metricsService: WorkoutMetricsService {
        WorkoutMetricsService(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Profile", subtitle: "Personalize the app and review your progress widgets.")

                VStack(alignment: .leading, spacing: 12) {
                    avatarEditorSection

                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()
                        .accessibilityIdentifier("profile-display-name-field")

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("profile-save-button")
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WGJSectionHeader("Widgets")
                        Spacer()
                        Button("Manage") {
                            showingWidgetManager = true
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                    }

                    if dashboardContent.enabledWidgets.isEmpty {
                        WGJEmptyStateCard(
                            title: "No widgets enabled",
                            message: "Enable widgets to show PRs, weekly progress, and exercise graphs on your profile.",
                            icon: "square.grid.2x2"
                        )
                    }

                    ForEach(dashboardContent.enabledWidgets) { config in
                        switch config.kind {
                        case .prs:
                            prWidget
                        case .weeklyGoals:
                            weeklyGoalsWidget
                        case .exerciseOneRMTrend:
                            exerciseTrendWidget(
                                title: "1RM Trend",
                                subtitle: "Best estimated 1RM for \(config.selectedExerciseNameSnapshot ?? "your lift")",
                                accent: WGJTheme.accentCyan,
                                series: dashboardContent.trendSeriesByKind[config.kind],
                                emptyMessage: "Log weighted sets for this exercise to start the line."
                            )
                        case .exerciseVolumeTrend:
                            exerciseTrendWidget(
                                title: "Volume Trend",
                                subtitle: "Weighted volume for \(config.selectedExerciseNameSnapshot ?? "your lift")",
                                accent: WGJTheme.accentBlue,
                                series: dashboardContent.trendSeriesByKind[config.kind],
                                emptyMessage: "Complete weighted sets for this exercise to populate volume."
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("App")

                    WGJNavigationTile(
                        title: "Settings",
                        systemImage: "gear",
                        subtitle: "Training goals, privacy, support, and data controls.",
                        accessibilityID: "profile-settings-tile"
                    ) {
                        SettingsView()
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadProfileIfNeeded()
        }
        .task(id: widgetStateStamp) {
            loadWidgetState()
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await persistAvatar(from: newItem)
            }
        }
        .sheet(isPresented: $showingWidgetManager) {
            NavigationStack {
                ProfileWidgetManagerView()
            }
            .onDisappear {
                loadWidgetState()
            }
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var widgetStateStamp: ProfileWidgetStateStamp {
        ProfileWidgetStateStamp(
            sessions: trackedSessions,
            widgetConfigs: widgetConfigs,
            profiles: storedProfiles
        )
    }

    private var avatarEditorSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                avatarView
                    .frame(width: 76, height: 76)

                avatarActions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                avatarView
                    .frame(width: 76, height: 76)

                avatarActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var avatarActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label("Choose Avatar", systemImage: "photo")
            }
            .buttonStyle(WGJGhostButtonStyle())

            if avatarImageData != nil {
                Button(role: .destructive) {
                    removeAvatar()
                } label: {
                    Label("Remove Avatar", systemImage: "trash")
                }
                .buttonStyle(WGJGhostButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImageData, let image = UIImage(data: avatarImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                }
        } else {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .overlay {
                    Circle()
                        .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                }
        }
    }

    private var prWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Personal Records", subtitle: "Estimated 1RM from logged workouts")

            if dashboardContent.personalRecords.isEmpty {
                Text("Complete workouts to populate PRs.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                ForEach(dashboardContent.personalRecords.prefix(5)) { record in
                    HStack {
                        Text(record.exerciseName)
                            .foregroundStyle(WGJTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(formatWeight(record.estimatedOneRepMax)) \(record.loadUnit.shortLabel)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentCyan)
                    }
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var weeklyGoalsWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Weekly Goal", subtitle: "Track workouts per week")

            Text("Target: \(weeklyGoal) workouts/week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            if dashboardContent.weeklyProgress.isEmpty {
                Text("No completed workouts yet.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                Chart(dashboardContent.weeklyProgress) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Workouts", point.completedWorkouts)
                    )
                    .foregroundStyle(WGJTheme.accentBlue)

                    RuleMark(y: .value("Goal", point.goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(WGJTheme.accentGold.opacity(0.75))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var weeklyGoal: Int {
        max(1, dashboardContent.weeklyGoal)
    }

    private func exerciseTrendWidget(
        title: String,
        subtitle: String,
        accent: Color,
        series: ExerciseMetricSeries?,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title, subtitle: subtitle)

            if let series {
                if series.points.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Latest")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WGJTheme.textSecondary)

                            Spacer()

                            Text("\(formatWeight(series.points.last?.value ?? 0)) \(series.loadUnit.shortLabel)")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(accent)
                        }

                        if let deltaText = trendDeltaText(for: series) {
                            Text(deltaText)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }

                        Chart(series.points) { point in
                            AreaMark(
                                x: .value("Workout", point.completedAt),
                                y: .value(title, point.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Workout", point.completedAt),
                                y: .value(title, point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("Workout", point.completedAt),
                                y: .value(title, point.value)
                            )
                            .foregroundStyle(accent)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: min(max(series.points.count, 2), 4))) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(WGJTheme.outlineStrong.opacity(0.35))
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    .foregroundStyle(WGJTheme.textSecondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(WGJTheme.outlineStrong.opacity(0.35))
                                AxisValueLabel()
                                    .foregroundStyle(WGJTheme.textSecondary)
                            }
                        }
                        .frame(height: 170)
                    }
                } else if let latest = series.points.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formatWeight(latest.value)) \(series.loadUnit.shortLabel)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(accent)

                        Text("Log one more weighted session for this exercise to unlock the chart.")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                } else {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            } else {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        do {
            let profile = try profileRepository.loadOrCreateProfile()
            displayName = profile.displayName
            avatarImageData = profile.avatarImageData
            dashboardContent.weeklyGoal = profile.weeklyWorkoutGoal
            loadWidgetState()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func saveProfile() {
        do {
            try profileRepository.updateDisplayName(displayName)
            if let profile = try profileRepository.currentProfile() {
                displayName = profile.displayName
                dashboardContent.weeklyGoal = profile.weeklyWorkoutGoal
            }
            loadWidgetState()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func removeAvatar() {
        do {
            try profileRepository.updateAvatar(imageData: nil)
            avatarImageData = nil
            selectedAvatarItem = nil
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func persistAvatar(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            try profileRepository.updateAvatar(imageData: data)
            avatarImageData = data
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func loadWidgetState() {
        do {
            let enabled = try widgetRepository.enabledConfigurations()
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 8, weeks: 8)
            var nextTrendSeries: [ProfileWidgetKind: ExerciseMetricSeries] = [:]

            for config in enabled {
                guard let selectedExerciseUUID = config.selectedCatalogExerciseUUID else { continue }

                switch config.kind {
                case .exerciseOneRMTrend:
                    nextTrendSeries[config.kind] = try metricsService.exerciseOneRepMaxTrend(
                        for: selectedExerciseUUID,
                        preferredExerciseName: config.selectedExerciseNameSnapshot,
                        limit: 8
                    )
                case .exerciseVolumeTrend:
                    nextTrendSeries[config.kind] = try metricsService.exerciseVolumeTrend(
                        for: selectedExerciseUUID,
                        preferredExerciseName: config.selectedExerciseNameSnapshot,
                        limit: 8
                    )
                case .prs, .weeklyGoals:
                    break
                }
            }

            dashboardContent = ProfileDashboardContent.make(
                enabledWidgets: enabled,
                dashboard: dashboard,
                trendSeriesByKind: nextTrendSeries
            )
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.oneDecimalString(value)
    }

    private func trendDeltaText(for series: ExerciseMetricSeries) -> String? {
        guard let first = series.points.first, let last = series.points.last, series.points.count >= 2 else {
            return nil
        }

        let delta = last.value - first.value
        guard abs(delta) >= 0.1 else {
            return "Holding steady across the last \(series.points.count) logged workouts."
        }

        let direction = delta > 0 ? "up" : "down"
        return "\(formatWeight(abs(delta))) \(series.loadUnit.shortLabel) \(direction) across your last \(series.points.count) logged workouts."
    }
}

struct ProfileWidgetStateStamp: Hashable {
    let completedSessionCount: Int
    let latestCompletedSessionUpdate: TimeInterval
    let widgetCount: Int
    let latestWidgetUpdate: TimeInterval
    let profileCount: Int
    let latestProfileUpdate: TimeInterval

    init(
        sessions: [WorkoutSession],
        widgetConfigs: [ProfileWidgetConfig],
        profiles: [UserProfile]
    ) {
        let completedSessions = sessions.filter { $0.status == .completed }
        completedSessionCount = completedSessions.count
        latestCompletedSessionUpdate = completedSessions
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
        widgetCount = widgetConfigs.count
        latestWidgetUpdate = widgetConfigs
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
        profileCount = profiles.count
        latestProfileUpdate = profiles
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
    }
}

struct ProfileDashboardContent {
    var enabledWidgets: [ProfileWidgetConfig]
    var personalRecords: [WorkoutPRRecord]
    var weeklyProgress: [WeeklyWorkoutProgressPoint]
    var trendSeriesByKind: [ProfileWidgetKind: ExerciseMetricSeries]
    var weeklyGoal: Int

    static let empty = ProfileDashboardContent(
        enabledWidgets: [],
        personalRecords: [],
        weeklyProgress: [],
        trendSeriesByKind: [:],
        weeklyGoal: 4
    )

    static func make(
        enabledWidgets: [ProfileWidgetConfig],
        dashboard: ProfileDashboardSnapshot,
        trendSeriesByKind: [ProfileWidgetKind: ExerciseMetricSeries]
    ) -> ProfileDashboardContent {
        ProfileDashboardContent(
            enabledWidgets: enabledWidgets,
            personalRecords: dashboard.personalRecords,
            weeklyProgress: dashboard.weeklyProgress,
            trendSeriesByKind: trendSeriesByKind,
            weeklyGoal: max(1, dashboard.weeklyGoal)
        )
    }
}

#Preview {
    NavigationStack {
        ProfileView()
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
        BlockedBro.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
