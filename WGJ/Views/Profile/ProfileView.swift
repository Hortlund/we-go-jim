import Charts
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutSession.updatedAt, order: .reverse)])
    private var trackedSessions: [WorkoutSession]
    @Query(sort: [SortDescriptor(\ProfileWidgetConfig.updatedAt, order: .reverse)])
    private var widgetConfigs: [ProfileWidgetConfig]
    @Query(sort: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)])
    private var storedProfiles: [UserProfile]

    @State private var hasLoadedProfile = false
    @State private var dashboardContent = ProfileDashboardContent.empty
    @State private var showingWidgetManager = false
    @State private var showingProfileManagement = false

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
                WGJRootHeader("Profile", subtitle: "Your identity, highlights, and training dashboard.")

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
        .task {
            await loadProfileIfNeeded()
        }
        .task(id: widgetStateStamp) {
            loadWidgetState()
        }
        .sheet(isPresented: $showingWidgetManager) {
            NavigationStack {
                ProfileWidgetManagerView()
            }
            .onDisappear {
                loadWidgetState()
            }
        }
        .sheet(isPresented: $showingProfileManagement) {
            NavigationStack {
                ProfileManagementView()
            }
            .wgjSheetSurface()
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Identity", subtitle: "Your current name, avatar, and athlete type.") {
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
                athleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
            } else {
                Text("No athlete type selected")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Highlights", subtitle: "Quick reads that make the profile feel alive.")

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
            WGJActionHeader("Dashboard", subtitle: "Fixed highlights up top, flexible widgets below.") {
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
                    message: "Enable streaks, favorites, consistency, PRs, and graphs to build your dashboard.",
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

    private var streaksWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Streaks", subtitle: "A tighter read on your consistency")

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
            WGJSectionHeader("Top Exercises", subtitle: "Your most repeated lifts so far")

            if dashboardContent.topExercises.isEmpty {
                Text("Complete workouts to build your exercise leaderboard.")
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
            WGJSectionHeader("Consistency Calendar", subtitle: "Rolling 6-week heatmap of your workout rhythm")

            let maxWorkoutCount = max(1, dashboardContent.activityDays.map(\.workoutCount).max() ?? 0)
            let hasAnyWorkoutActivity = dashboardContent.activityDays.contains { $0.workoutCount > 0 }

            if !hasAnyWorkoutActivity {
                Text("Complete workouts to light up the calendar.")
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

                Text("Darker squares mean more workouts on that day.")
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

    private var appSection: some View {
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

    private var currentProfile: UserProfile? {
        storedProfiles.first
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

    private var widgetStateStamp: ProfileWidgetStateStamp {
        ProfileWidgetStateStamp(
            sessions: trackedSessions,
            widgetConfigs: widgetConfigs,
            profiles: storedProfiles
        )
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        do {
            let profile = try profileRepository.loadOrCreateProfile()
            dashboardContent.weeklyGoal = profile.weeklyWorkoutGoal
            loadWidgetState()
        } catch {
            showError(error)
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
                case .prs, .weeklyGoals, .streaks, .topExercises, .consistencyCalendar:
                    break
                }
            }

            dashboardContent = ProfileDashboardContent.make(
                enabledWidgets: enabled,
                dashboard: dashboard,
                trendSeriesByKind: nextTrendSeries
            )
        } catch {
            showError(error)
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

    private func athleteTypeBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
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
            personalRecords: dashboard.personalRecords,
            weeklyProgress: dashboard.weeklyProgress,
            trendSeriesByKind: trendSeriesByKind,
            weeklyGoal: max(1, dashboard.weeklyGoal),
            overviewStats: dashboard.overviewStats,
            topExercises: dashboard.topExercises,
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
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
