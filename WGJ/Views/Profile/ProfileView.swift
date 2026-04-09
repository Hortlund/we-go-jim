import Charts
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    @State private var currentProfile: UserProfile?
    @State private var dashboardContent = ProfileDashboardContent.empty
    @State private var controller = ProfileViewController()
    @State private var trendSeriesLoadTask: Task<Void, Never>?
    @State private var isLoadingTrendSeries = false
    @State private var showingWidgetManager = false
    @State private var showingProfileManagement = false

    @State private var errorMessage = ""
    @State private var showingError = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Profile", subtitle: "Your training snapshot, progress, and app controls.")

                identityCard
                highlightsCard
                dashboardSection
                appSection
            }
            .padding(.top, 8)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadProfile()
        }
        .onDisappear {
            trendSeriesLoadTask?.cancel()
            trendSeriesLoadTask = nil
            isLoadingTrendSeries = false
        }
        .sheet(isPresented: $showingWidgetManager) {
            NavigationStack {
                ProfileWidgetManagerView()
            }
            .wgjSheetSurface()
            .onDisappear {
                reloadProfileIfActive()
            }
        }
        .sheet(isPresented: $showingProfileManagement) {
            NavigationStack {
                ProfileManagementView()
            }
            .wgjSheetSurface()
            .onDisappear {
                reloadProfileIfActive()
            }
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Identity", subtitle: "How you show up across the app.") {
                Button {
                    showingProfileManagement = true
                } label: {
                    Label("Edit Profile", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
                .accessibilityIdentifier("profile-manage-button")
            }
            identityHero
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var identityHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(imageData: currentProfile?.avatarImageData)
                    .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 8) {
                    identityPreview
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProfileAvatarView(imageData: currentProfile?.avatarImageData)
                    .frame(width: 88, height: 88)

                identityPreview
            }
        }
    }

    private var identityPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(identityPreviewName)
                .font(.title2.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(2)

            if let athleteType = currentProfile?.athleteType {
                ProfileAthleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
            } else {
                Text("No athlete type selected")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Highlights", subtitle: "A quick look at the work you've been putting in.")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ProfileQuickStatTile(
                    title: "Total Workouts",
                    value: "\(dashboardContent.overviewStats.totalWorkouts)",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: WGJTheme.accentBlue
                )
                ProfileQuickStatTile(
                    title: "Total PRs",
                    value: "\(dashboardContent.overviewStats.totalPRHits)",
                    systemImage: "trophy.fill",
                    tint: WGJTheme.accentGold
                )
                ProfileQuickStatTile(
                    title: "Current Streak",
                    value: dayCountText(dashboardContent.overviewStats.currentStreakDays),
                    systemImage: "flame.fill",
                    tint: WGJTheme.success
                )
                ProfileQuickStatTile(
                    title: "Total Time",
                    value: formattedDurationSummary(dashboardContent.overviewStats.totalDurationSeconds),
                    systemImage: "clock.fill",
                    tint: WGJTheme.accentCyan
                )
            }

            ProfileHighlightsMetaRow(title: "Active Since", value: activeSinceText)
            ProfileHighlightsMetaRow(title: "Top Exercise", value: topExerciseSummaryText)
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Dashboard", subtitle: "Keep your key numbers and trends close.") {
                Button {
                    showingWidgetManager = true
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
            }

            if dashboardContent.enabledWidgets.isEmpty {
                WGJEmptyStateCard(
                    title: "No widgets enabled",
                    message: "Turn on widgets for PRs, streaks, favorite lifts, and training trends.",
                    icon: "square.grid.2x2"
                ) {
                    Button("Manage Widgets") {
                        showingWidgetManager = true
                    }
                    .buttonStyle(WGJCompactGhostButtonStyle())
                }
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
                        subtitle: "Estimated max strength for \(config.selectedExerciseNameSnapshot ?? "your lift")",
                        accent: WGJTheme.accentCyan,
                        series: dashboardContent.trendSeriesByKind[config.kind],
                        emptyMessage: "Log weighted sets for this lift to start the trend."
                    )
                case .exerciseVolumeTrend:
                    exerciseTrendWidget(
                        title: "Volume Trend",
                        subtitle: "Training volume for \(config.selectedExerciseNameSnapshot ?? "your lift")",
                        accent: WGJTheme.accentBlue,
                        series: dashboardContent.trendSeriesByKind[config.kind],
                        emptyMessage: "Log weighted sets for this lift to chart your volume."
                    )
                case .streaks:
                    streaksWidget
                case .topExercises:
                    topExercisesWidget
                case .consistencyCalendar:
                    consistencyCalendarWidget
                }
            }
        }
    }

    private var prWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Personal Records", subtitle: "Your strongest logged lifts at a glance")

            if dashboardContent.personalRecords.isEmpty {
                Text("Finish a few workouts and your top lifts will show up here.")
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
            WGJSectionHeader("Weekly Goal", subtitle: "See how each week stacks up against your target")

            Text("Goal: \(weeklyGoal) workouts each week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            if dashboardContent.weeklyProgress.isEmpty {
                Text("Finish a workout to start tracking your weekly pace.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                let goal = self.weeklyGoal
                Chart {
                    ForEach(dashboardContent.weeklyProgress) { point in
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Workouts", point.completedWorkouts)
                        )
                        .foregroundStyle(WGJTheme.accentBlue)
                    }

                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(WGJTheme.accentGold.opacity(0.75))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
                .drawingGroup()
                .allowsHitTesting(false)
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var streaksWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Streaks", subtitle: "How steady your training has been lately")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ProfileQuickStatTile(
                    title: "Current",
                    value: dayCountText(dashboardContent.overviewStats.currentStreakDays),
                    systemImage: "flame.fill",
                    tint: WGJTheme.success
                )
                ProfileQuickStatTile(
                    title: "Longest",
                    value: dayCountText(dashboardContent.overviewStats.longestStreakDays),
                    systemImage: "bolt.fill",
                    tint: WGJTheme.accentGold
                )
                ProfileQuickStatTile(
                    title: "This Month",
                    value: dayCountText(dashboardContent.overviewStats.activeDaysThisMonth),
                    systemImage: "calendar",
                    tint: WGJTheme.accentBlue
                )
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var topExercisesWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Top Exercises", subtitle: "The lifts you come back to most")

            if dashboardContent.topExercises.isEmpty {
                Text("Keep logging sessions and your go-to lifts will rise here.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                ForEach(Array(dashboardContent.topExercises.prefix(3).enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WGJTheme.accentGold)
                            .frame(width: 20, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.exerciseName)
                                .font(.headline)
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Last trained \(exercise.lastPerformedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }

                        Spacer()

                        Text(exercise.sessionCount == 1 ? "1 session" : "\(exercise.sessionCount) sessions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentCyan)
                    }
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var consistencyCalendarWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Consistency Calendar", subtitle: "Your last six weeks of training, day by day")

            let maxWorkoutCount = max(1, dashboardContent.activityDays.map(\.workoutCount).max() ?? 0)
            let hasAnyWorkoutActivity = dashboardContent.activityDays.contains { $0.workoutCount > 0 }

            if !hasAnyWorkoutActivity {
                Text("Train a few days and your calendar will start to fill in.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                HStack {
                    Text(dashboardContent.activityDays.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                    Spacer()
                    Text(dashboardContent.activityDays.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                }
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(dashboardContent.activityDays) { day in
                        ProfileConsistencyDayCell(day: day, maxWorkoutCount: maxWorkoutCount)
                    }
                }

                Text("Darker squares mean busier training days.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
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
                        .drawingGroup()
                        .allowsHitTesting(false)
                    }
                } else if let latest = series.points.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formatWeight(latest.value)) \(series.loadUnit.shortLabel)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(accent)

                        Text("Log one more weighted session for this lift to unlock the chart.")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                } else {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            } else if isLoadingTrendSeries {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading trend data…")
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

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("App")

            WGJNavigationTile(
                title: "Settings",
                systemImage: "gear",
                subtitle: "Goals, privacy, support, and data controls.",
                accessibilityID: "profile-settings-tile"
            ) {
                SettingsView()
            }
        }
    }

    private var identityPreviewName: String {
        let trimmedName = currentProfile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Athlete" : trimmedName
    }

    private var activeSinceText: String {
        guard let firstWorkoutDate = dashboardContent.overviewStats.firstWorkoutDate else {
            return "No workouts yet"
        }

        return firstWorkoutDate.formatted(.dateTime.month(.abbreviated).year())
    }

    private var topExerciseSummaryText: String {
        guard let topExercise = dashboardContent.topExercises.first else {
            return "No workout history yet"
        }

        let sessionText = topExercise.sessionCount == 1 ? "1 session" : "\(topExercise.sessionCount) sessions"
        return "\(topExercise.exerciseName) · \(sessionText)"
    }

    @MainActor
    private func reloadProfile() async {
        do {
            trendSeriesLoadTask?.cancel()
            trendSeriesLoadTask = nil
            isLoadingTrendSeries = false

            let snapshot = try await controller.reloadOverview(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled
            )
            currentProfile = snapshot.profile
            dashboardContent = snapshot.dashboardContent
            scheduleTrendSeriesLoad()
        } catch {
            showError(error)
        }
    }

    private func reloadProfileIfActive() {
        guard isTabActive else { return }
        Task {
            await reloadProfile()
        }
    }

    private func scheduleTrendSeriesLoad() {
        let enabledWidgets = dashboardContent.enabledWidgets
        guard enabledWidgets.contains(where: { $0.kind.requiresExerciseSelection }) else { return }

        trendSeriesLoadTask?.cancel()
        isLoadingTrendSeries = true
        trendSeriesLoadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, isTabActive else { return }

            do {
                let trendSeriesByKind = try controller.loadTrendSeries(
                    modelContext: modelContext,
                    enabledWidgets: enabledWidgets
                )
                guard !Task.isCancelled else { return }
                dashboardContent.trendSeriesByKind = trendSeriesByKind
            } catch {
                showError(error)
            }

            if !Task.isCancelled {
                isLoadingTrendSeries = false
                trendSeriesLoadTask = nil
            }
        }
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.oneDecimalString(value)
    }

    private func dayCountText(_ days: Int) -> String {
        if days == 1 {
            return "1 day"
        }
        return "\(days) days"
    }

    private func formattedDurationSummary(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let totalMinutes = safeSeconds / 60
        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        let totalDays = totalHours / 24
        let remainingHours = totalHours % 24

        if totalDays > 0 {
            if remainingHours > 0 {
                return "\(totalDays)d \(remainingHours)h"
            }
            return "\(totalDays)d"
        }

        if totalHours > 0 {
            return "\(totalHours)h \(remainingMinutes)m"
        }

        return "\(totalMinutes)m"
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

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

struct ProfileOverviewSnapshot {
    let profile: UserProfile?
    let dashboardContent: ProfileDashboardContent
}

@MainActor
@Observable
final class ProfileViewController {
    func reloadOverview(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool
    ) async throws -> ProfileOverviewSnapshot {
        let profileRepository = ProfileRepository(modelContext: modelContext)
        let widgetRepository = ProfileWidgetRepository(modelContext: modelContext)

        let profile = try await profileRepository.bootstrapProfileIdentity(cloudSyncEnabled: cloudSyncEnabled)
        let dashboardContent = try WGJPerformance.measure("profile.dashboard") {
            let metricsService = WorkoutMetricsService(modelContext: modelContext)
            let enabled = try widgetRepository.enabledConfigurations()
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8)
            var nextContent = ProfileDashboardContent.make(
                enabledWidgets: enabled,
                dashboard: dashboard,
                trendSeriesByKind: [:]
            )
            nextContent.weeklyGoal = profile.weeklyWorkoutGoal
            return nextContent
        }

        return ProfileOverviewSnapshot(
            profile: profile,
            dashboardContent: dashboardContent
        )
    }

    func loadTrendSeries(
        modelContext: ModelContext,
        enabledWidgets: [ProfileWidgetConfig]
    ) throws -> [ProfileWidgetKind: ExerciseMetricSeries] {
        try WGJPerformance.measure("profile.trends") {
            let metricsService = WorkoutMetricsService(modelContext: modelContext)
            var trendSeriesByKind: [ProfileWidgetKind: ExerciseMetricSeries] = [:]

            for config in enabledWidgets {
                guard let selectedExerciseUUID = config.selectedCatalogExerciseUUID else { continue }

                switch config.kind {
                case .exerciseOneRMTrend:
                    trendSeriesByKind[config.kind] = try metricsService.exerciseOneRepMaxTrend(
                        for: selectedExerciseUUID,
                        preferredExerciseName: config.selectedExerciseNameSnapshot,
                        limit: 8
                    )
                case .exerciseVolumeTrend:
                    trendSeriesByKind[config.kind] = try metricsService.exerciseVolumeTrend(
                        for: selectedExerciseUUID,
                        preferredExerciseName: config.selectedExerciseNameSnapshot,
                        limit: 8
                    )
                case .prs, .weeklyGoals, .streaks, .topExercises, .consistencyCalendar:
                    break
                }
            }

            return trendSeriesByKind
        }
    }
}

struct ProfileDashboardContent {
    var enabledWidgets: [ProfileWidgetConfig]
    var personalRecords: [WorkoutPRRecord]
    var weeklyProgress: [WeeklyWorkoutProgressPoint]
    var trendSeriesByKind: [ProfileWidgetKind: ExerciseMetricSeries]
    var weeklyGoal: Int
    var overviewStats: ProfileOverviewStats
    var topExercises: [ProfileTopExerciseStat]
    var activityDays: [ProfileActivityDay]

    static let empty = ProfileDashboardContent(
        enabledWidgets: [],
        personalRecords: [],
        weeklyProgress: [],
        trendSeriesByKind: [:],
        weeklyGoal: 4,
        overviewStats: .empty,
        topExercises: [],
        activityDays: []
    )

    static func make(
        enabledWidgets: [ProfileWidgetConfig],
        dashboard: ProfileDashboardSnapshot,
        trendSeriesByKind: [ProfileWidgetKind: ExerciseMetricSeries]
    ) -> ProfileDashboardContent {
        ProfileDashboardContent(
            enabledWidgets: enabledWidgets,
            personalRecords: Array(dashboard.personalRecords.prefix(5)),
            weeklyProgress: dashboard.weeklyProgress,
            trendSeriesByKind: trendSeriesByKind,
            weeklyGoal: max(1, dashboard.weeklyGoal),
            overviewStats: dashboard.overviewStats,
            topExercises: Array(dashboard.topExercises.prefix(3)),
            activityDays: dashboard.activityDays
        )
    }
}

private struct ProfileQuickStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(tint.opacity(0.14))
                }

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(cornerRadius: WGJRadius.control)
    }
}

private struct ProfileHighlightsMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ProfileConsistencyDayCell: View {
    let day: ProfileActivityDay
    let maxWorkoutCount: Int

    private var fill: Color {
        if day.workoutCount <= 0 {
            return WGJTheme.field.opacity(0.48)
        }

        let normalized = Double(day.workoutCount) / Double(max(1, maxWorkoutCount))
        if normalized >= 0.95 {
            return WGJTheme.accentBlue.opacity(0.78)
        }
        if normalized >= 0.6 {
            return WGJTheme.accentBlue.opacity(0.56)
        }
        return WGJTheme.accentBlue.opacity(0.32)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .frame(height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WGJTheme.outline.opacity(day.workoutCount > 0 ? 0.34 : 0.18), lineWidth: 1)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let dateText = day.date.formatted(date: .complete, time: .omitted)
        if day.workoutCount == 1 {
            return "\(dateText), 1 workout"
        }
        return "\(dateText), \(day.workoutCount) workouts"
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
    .environment(\.cloudSyncEnabled, false)
}
