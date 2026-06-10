import Charts
import SwiftData
import SwiftUI

nonisolated struct ProfileWeeklyGoalChartScale: Equatable {
    let domainUpperBound: Int
    let axisValues: [Int]
}

nonisolated enum ProfileWeeklyGoalChartScalePolicy {
    private static let continuousAxisMaximum = 10

    static func scale(goal: Int, completedWorkouts: [Int]) -> ProfileWeeklyGoalChartScale {
        let visibleMaximum = max(1, goal, completedWorkouts.max() ?? 0)
        let domainUpperBound = visibleMaximum + 1

        return ProfileWeeklyGoalChartScale(
            domainUpperBound: domainUpperBound,
            axisValues: axisValues(visibleMaximum: visibleMaximum, goal: goal)
        )
    }

    private static func axisValues(visibleMaximum: Int, goal: Int) -> [Int] {
        if visibleMaximum <= continuousAxisMaximum {
            return Array(0 ... visibleMaximum)
        }

        let maximumTickCount = 5
        let step = max(1, Int(ceil(Double(visibleMaximum) / Double(maximumTickCount - 1))))
        var values = Set<Int>()

        for value in stride(from: 0, through: visibleMaximum, by: step) {
            values.insert(value)
        }

        values.insert(0)
        values.insert(visibleMaximum)
        values.insert(max(1, min(goal, visibleMaximum)))
        return values.sorted()
    }
}

struct ProfileView: View {
    private enum ScrollTarget {
        static let cloudBackupSection = "profile-cloud-backup-section"
        static let cloudBackupDetailsEnd = "profile-cloud-backup-details-end"
        static let profileBottomPadding = "profile-bottom-padding"
    }

    private enum CoachBriefLoadState {
        case idle
        case loading
        case failed
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.userDataSyncStatus) private var userDataSyncStatus
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(AppWarmupState.self) private var appWarmupState

    private var profileBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    @State private var currentProfile: ProfileIdentitySnapshot?
    @State private var dashboardContent = ProfileDashboardContent.empty
    @State private var controller = ProfileViewController()
    @State private var trendSeriesLoadTask: Task<Void, Never>?
    @State private var trendSeriesLoadToken: UUID?
    @State private var coachBriefLoadTask: Task<Void, Never>?
    @State private var coachBriefLoadToken: UUID?
    @State private var dashboardRenderTask: Task<Void, Never>?
    @State private var profileReloadToken: UUID?
    @State private var isLoadingTrendSeries = false
    @State private var shouldRenderDashboardContent = false
    @State private var hasRenderedDashboardContent = false
    @State private var showingWidgetManager = false
    @State private var showingProfileManagement = false
    @State private var showingCoachAnalysis = false
    @State private var coachBriefLoadState: CoachBriefLoadState = .idle
    @State private var coachFollowUpSummaries: [CoachFollowUpKind: CoachNarrativeSummary] = [:]
    @State private var loadingCoachFollowUps: Set<CoachFollowUpKind> = []
    @State private var coachFollowUpTasks: [CoachFollowUpKind: Task<Void, Never>] = [:]
    @State private var coachFollowUpTokens: [CoachFollowUpKind: UUID] = [:]
    @State private var hasLoadedProfile = false
    @State private var needsExplicitRefresh = true
    @State private var lastLoadedProfileUpdatedAt: Date?
    @State private var lastRefreshAt: Date?
    @State private var lastHandledProfileInvalidationVersion = 0
    @State private var localCloudBackupSummary = UserDataCloudBackupContentSummary.empty
    @State private var remoteCloudBackupSummary: UserDataCloudBackupContentSummary?
    @State private var isLoadingCloudBackupSummary = false
    @State private var isRefreshingCloudBackupMetadata = false
    @State private var isForcingCloudBackup = false
    @State private var showsCloudBackupDetails = false

    @State private var errorMessage = ""
    @State private var showingError = false
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WGJRootHeader("Profile", subtitle: "Your training snapshot, progress, and app controls.")

                    identityCard
                    highlightsCard
                    dashboardSection
                    appSection
                    cloudBackupSection(scrollProxy: scrollProxy)
                    Color.clear
                        .frame(height: 96)
                        .id(ScrollTarget.profileBottomPadding)
                }
                .padding(.top, 8)
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjScreenBackground()
            .accessibilityIdentifier("profile-content-root")
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            applyWarmProfileSnapshotIfAvailable()
            Task {
                await refreshCloudBackupSummary()
                await refreshCloudBackupMetadata()
            }
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await handleInitialActivation()
        }
        .task(id: appWarmupState.profileCompletionVersion) {
            guard appWarmupState.profileCompletionVersion > 0 else { return }
            applyWarmProfileSnapshotIfAvailable()
            guard isTabActive else { return }
            await hydrateProfileIfNeeded(force: false)
        }
        .task(id: appWarmupState.profileInvalidationVersion) {
            await handleProfileInvalidated(version: appWarmupState.profileInvalidationVersion)
        }
        .onDisappear {
            cancelDashboardRender(isTabExit: true)
            cancelTrendSeriesLoad()
            cancelCoachBriefLoad()
            cancelCoachFollowUpLoads()
        }
        .sheet(isPresented: $showingWidgetManager) {
            NavigationStack {
                ProfileWidgetManagerView()
            }
            .wgjSheetSurface()
            .onDisappear {
                markProfileDirtyAndReloadIfActive()
            }
        }
        .sheet(isPresented: $showingProfileManagement) {
            NavigationStack {
                ProfileManagementView()
            }
            .wgjSheetSurface()
            .onDisappear {
                markProfileDirtyAndReloadIfActive()
            }
        }
        .sheet(isPresented: $showingCoachAnalysis) {
            if let coachBrief = dashboardContent.coachBrief {
                ProfileCoachAnalysisSheet(
                    presentation: coachBrief,
                    followUpSummaries: coachFollowUpSummaries,
                    loadingKinds: loadingCoachFollowUps,
                    runFollowUp: loadCoachFollowUp
                )
                .wgjSheetSurface()
                .onDisappear {
                    cancelCoachFollowUpLoads()
                }
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

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
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
                }

                GridRow {
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
            }
            .frame(maxWidth: .infinity)

            ProfileHighlightsMetaRow(title: "Active Since", value: activeSinceText)
            ProfileHighlightsMetaRow(title: "Top Exercise", value: topExerciseSummaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityIdentifier("profile-dashboard-manage-button")
            }

            if !shouldRenderDashboardContent {
                dashboardDeferredPlaceholder
            } else if dashboardContent.enabledWidgets.isEmpty {
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

            if shouldRenderDashboardContent {
                ForEach(dashboardContent.enabledWidgets) { config in
                    dashboardWidget(config)
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardWidget(_ config: ProfileWidgetConfigSnapshot) -> some View {
        switch config.kind {
        case .prs:
            prWidget
        case .weeklyGoals:
            weeklyGoalsWidget
        case .weeklyMuscleHeatmap:
            weeklyMuscleHeatmapWidget
        case .coachBrief:
            coachBriefWidget
        case .exerciseOneRMTrend, .exerciseVolumeTrend:
            exerciseTrendWidget(
                title: trendTitle(for: config.exerciseTrendMetric),
                subtitle: trendSubtitle(for: config),
                accent: trendAccent(for: config.exerciseTrendMetric),
                series: dashboardContent.trendSeriesByWidgetID[config.id],
                emptyMessage: trendEmptyMessage(for: config.exerciseTrendMetric)
            )
        case .streaks:
            streaksWidget
        case .topExercises:
            topExercisesWidget
        case .consistencyCalendar:
            consistencyCalendarWidget
        }
    }

    private var dashboardDeferredPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Preparing dashboard")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
            }

            Text("Your profile is ready. Widgets will appear in a moment.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
        .accessibilityIdentifier("profile-dashboard-deferred-placeholder")
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                let scale = ProfileWeeklyGoalChartScalePolicy.scale(
                    goal: goal,
                    completedWorkouts: dashboardContent.weeklyProgress.map(\.completedWorkouts)
                )
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
                    AxisMarks(position: .leading, values: scale.axisValues) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0 ... scale.domainUpperBound)
                .frame(height: 160)
                .drawingGroup()
                .allowsHitTesting(false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }

    private var coachBriefWidget: some View {
        Group {
            if let coachBrief = dashboardContent.coachBrief {
                ProfileCoachBriefWidgetView(presentation: coachBrief) {
                    showingCoachAnalysis = true
                }
            } else if coachBriefLoadState == .loading {
                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Coach Brief", subtitle: "Preparing your weekly training recap")

                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reviewing your recent sessions…")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wgjCardContainer()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Coach Brief", subtitle: "Weekly recap unavailable right now")

                    Text("Your dashboard stats are still local and up to date. Pull to refresh or finish another workout to try again.")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wgjCardContainer()
            }
        }
    }

    private var weeklyMuscleHeatmapWidget: some View {
        ProfileWeeklyMuscleHeatmapWidget(snapshot: dashboardContent.weeklyMuscleHeatmap)
    }

    private var streaksWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Streaks", subtitle: "How steady your training has been lately")

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
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
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }

    private var consistencyCalendarWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Consistency Calendar", subtitle: "Your last six weeks of training, day by day")

            if !dashboardContent.hasActivityDayWorkouts {
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

                VStack(spacing: 6) {
                    ForEach(Array(dashboardContent.activityDayRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            ForEach(row) { day in
                                ProfileConsistencyDayCell(
                                    day: day,
                                    maxWorkoutCount: dashboardContent.maxActivityDayWorkoutCount
                                )
                            }
                        }
                    }
                }

                Text("Darker squares mean busier training days.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func cloudBackupSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Cloud Backup")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer(minLength: 12)

                Button {
                    Task {
                        await forceCloudBackup()
                    }
                } label: {
                    if isForcingCloudBackup {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Back Up Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
                .disabled(!cloudSyncEnabled || isForcingCloudBackup)
                .accessibilityIdentifier("profile-cloud-backup-now-button")
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: cloudBackupStatusIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(cloudBackupStatusTint)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(cloudBackupStatusTint.opacity(0.14))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(cloudBackupStatusTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(cloudBackupStatusDetail)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.field.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.26), lineWidth: 1)
                    }
            }

            Text("Backup comparison")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            cloudBackupComparisonTable(scrollProxy: scrollProxy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
        .id(ScrollTarget.cloudBackupSection)
        .accessibilityIdentifier("profile-cloud-backup-section")
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

    private var cloudBackupStatusTitle: String {
        if isForcingCloudBackup {
            return "Backing up now"
        }
        return userDataSyncStatus.title
    }

    private var cloudBackupStatusDetail: String {
        if isRefreshingCloudBackupMetadata {
            return "Checking latest backup..."
        }
        return "Last backup: \(latestCloudBackupText)"
    }

    private var latestCloudBackupText: String {
        if let latestExport = userDataSyncStatus.latestSuccessfulExportAt {
            return latestExport.formatted(.relative(presentation: .named))
        }
        return "Never"
    }

    private var cloudBackupComparisonRows: [ProfileCloudBackupComparisonRow] {
        ProfileCloudBackupComparisonRow.primaryRows(
            cloud: remoteCloudBackupSummary,
            device: localCloudBackupSummary
        )
    }

    private var cloudBackupDetailRows: [ProfileCloudBackupComparisonRow] {
        ProfileCloudBackupComparisonRow.detailRows(
            cloud: remoteCloudBackupSummary,
            device: localCloudBackupSummary
        )
    }

    private var cloudBackupComparisonText: String {
        guard let remoteCloudBackupSummary else {
            return cloudSyncEnabled ? "No cloud backup found" : "Cloud backup unavailable"
        }

        let localTotal = localCloudBackupSummary.totalBackedUpItemCount
        let remoteTotal = remoteCloudBackupSummary.totalBackedUpItemCount
        guard localTotal != remoteTotal else {
            return "Cloud matches this device"
        }

        if localTotal > remoteTotal {
            return "\(localTotal - remoteTotal) local item\(localTotal - remoteTotal == 1 ? "" : "s") not backed up yet"
        }

        return "\(remoteTotal - localTotal) cloud item\(remoteTotal - localTotal == 1 ? "" : "s") not on this device"
    }

    private var cloudBackupComparisonIcon: String {
        guard let remoteCloudBackupSummary else {
            return "icloud.slash"
        }
        return remoteCloudBackupSummary == localCloudBackupSummary
            ? "checkmark.seal.fill"
            : "arrow.left.arrow.right.circle.fill"
    }

    private var cloudBackupComparisonTint: Color {
        guard let remoteCloudBackupSummary else {
            return WGJTheme.textSecondary
        }
        return remoteCloudBackupSummary == localCloudBackupSummary ? WGJTheme.success : WGJTheme.accentGold
    }

    private func cloudBackupComparisonTable(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label(cloudBackupComparisonText, systemImage: cloudBackupComparisonIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cloudBackupComparisonTint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            ProfileCloudBackupComparisonHeader()

            VStack(spacing: 0) {
                ForEach(cloudBackupComparisonRows) { row in
                    ProfileCloudBackupComparisonRowView(
                        row: row,
                        isLoading: isLoadingCloudBackupSummary || isRefreshingCloudBackupMetadata
                    )
                }
            }
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.field.opacity(0.42))
            }

            Button {
                let shouldShowDetails = !showsCloudBackupDetails
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                    showsCloudBackupDetails = shouldShowDetails
                }
                scrollCloudBackupDetailsAfterToggle(
                    showingDetails: shouldShowDetails,
                    scrollProxy: scrollProxy
                )
            } label: {
                HStack(spacing: 8) {
                    Text(showsCloudBackupDetails ? "Hide backup contents" : "Show backup contents")
                        .font(.caption.weight(.semibold))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showsCloudBackupDetails ? 180 : 0))
                }
                .foregroundStyle(WGJTheme.accentCyan)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-cloud-backup-details-toggle")

            if showsCloudBackupDetails {
                VStack(spacing: 0) {
                    ForEach(cloudBackupDetailRows) { row in
                        ProfileCloudBackupComparisonRowView(
                            row: row,
                            isLoading: isLoadingCloudBackupSummary || isRefreshingCloudBackupMetadata
                        )
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                        .fill(WGJTheme.field.opacity(0.42))
                }
                .id(ScrollTarget.cloudBackupDetailsEnd)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func scrollCloudBackupDetailsAfterToggle(
        showingDetails: Bool,
        scrollProxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
                if showingDetails {
                    scrollProxy.scrollTo(ScrollTarget.profileBottomPadding, anchor: .bottom)
                } else {
                    scrollProxy.scrollTo(ScrollTarget.cloudBackupSection, anchor: .bottom)
                }
            }
        }
    }

    private var cloudBackupStatusIcon: String {
        if isForcingCloudBackup {
            return "arrow.triangle.2.circlepath"
        }
        switch userDataSyncStatus.state {
        case .backedUp:
            return "checkmark.icloud.fill"
        case .pending:
            return "icloud.and.arrow.up"
        case .degraded:
            return "exclamationmark.icloud.fill"
        case .localOnly:
            return cloudSyncEnabled ? "icloud" : "internaldrive"
        }
    }

    private var cloudBackupStatusTint: Color {
        if isForcingCloudBackup {
            return WGJTheme.accentBlue
        }
        switch userDataSyncStatus.state {
        case .backedUp:
            return WGJTheme.success
        case .pending:
            return WGJTheme.accentBlue
        case .degraded:
            return WGJTheme.accentGold
        case .localOnly:
            return cloudSyncEnabled ? WGJTheme.accentCyan : WGJTheme.textSecondary
        }
    }

    private var topExerciseSummaryText: String {
        guard let topExercise = dashboardContent.topExercises.first else {
            return "No workout history yet"
        }

        let sessionText = topExercise.sessionCount == 1 ? "1 session" : "\(topExercise.sessionCount) sessions"
        return "\(topExercise.exerciseName) · \(sessionText)"
    }

    @MainActor
    private func handleInitialActivation() async {
        await joinStartupProfileWarmupIfNeeded()
        await hydrateProfileIfNeeded(force: false)
    }

    @MainActor
    private func joinStartupProfileWarmupIfNeeded() async {
        guard FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: hasLoadedProfile,
            hasCurrentProfile: currentProfile != nil,
            isProfileWarmupActive: appWarmupState.isProfileWarmupActive,
            hasFreshWarmSnapshot: appWarmupState.freshProfile() != nil
        ) else {
            return
        }

        await WGJPerformance.measureAsync("profile.join-startup-warmup") {
            await appWarmupState.waitForActiveProfileWarmup()
        }
        applyWarmProfileSnapshotIfAvailable()
    }

    @MainActor
    private func hydrateProfileIfNeeded(force: Bool) async {
        await WGJPerformance.measureAsync("profile.full-hydration") {
            await reloadProfileIfNeeded(force: force)
        }
    }

    @MainActor
    private func reloadProfileIfNeeded(force: Bool) async {
        let warmSnapshot = appWarmupState.freshProfile()
        let didApplyWarmSnapshot = applyWarmProfileSnapshotIfAvailable()
        if !ProfileReloadPolicy.shouldReloadAfterApplyingWarmSnapshot(
            force: force,
            didApplyWarmSnapshot: didApplyWarmSnapshot
        ) {
            scheduleDashboardRenderIfNeeded()
            return
        }

        if FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: hasLoadedProfile,
            hasCurrentProfile: currentProfile != nil,
            isProfileWarmupActive: appWarmupState.isProfileWarmupActive,
            hasFreshWarmSnapshot: warmSnapshot != nil
        ) {
            scheduleDashboardRenderIfNeeded()
            return
        }

        let currentProfileUpdatedAt = warmSnapshot?.profile.updatedAt ?? currentProfile?.updatedAt
        guard force || ProfileReloadPolicy.shouldReload(
            hasLoadedProfile: hasLoadedProfile,
            needsExplicitRefresh: needsExplicitRefresh,
            currentProfileUpdatedAt: currentProfileUpdatedAt,
            lastLoadedProfileUpdatedAt: lastLoadedProfileUpdatedAt,
            lastRefreshAt: lastRefreshAt
        ) else {
            scheduleDashboardRenderIfNeeded()
            return
        }

        await reloadProfile()
    }

    @MainActor
    private func reloadProfile() async {
        let reloadToken = UUID()
        profileReloadToken = reloadToken

        do {
            cancelTrendSeriesLoad()
            cancelCoachBriefLoad()
            coachBriefLoadState = .idle
            showingCoachAnalysis = false
            coachFollowUpSummaries = [:]
            cancelCoachFollowUpLoads()

            let backgroundStore = profileBackgroundStore
            let profile = try await controller.loadPublishedProfileIdentity(
                cloudSyncEnabled: cloudSyncEnabled,
                backgroundStore: backgroundStore
            )
            guard profileReloadToken == reloadToken else { return }
            currentProfile = profile
            dashboardContent.weeklyGoal = profile.weeklyWorkoutGoal
            let dashboardContent = try await controller.loadDashboardContent(
                profile: profile,
                backgroundStore: backgroundStore
            )
            guard profileReloadToken == reloadToken else { return }
            self.dashboardContent = dashboardContent
            persistWarmProfileSnapshotIfNeeded()
            hasLoadedProfile = true
            needsExplicitRefresh = false
            lastLoadedProfileUpdatedAt = profile.updatedAt
            lastRefreshAt = .now
            scheduleDashboardRender(enabledWidgets: dashboardContent.enabledWidgets)
        } catch {
            guard profileReloadToken == reloadToken else { return }
            showError(error)
        }
    }

    @MainActor
    private func refreshCloudBackupSummary() async {
        isLoadingCloudBackupSummary = true
        do {
            let backgroundStore = profileBackgroundStore
            localCloudBackupSummary = try await backgroundStore.perform("profile.cloud-backup-summary") { context in
                try UserDataCloudBackupContentSummary.loadLocal(context: context)
            }
        } catch {
            localCloudBackupSummary = .empty
        }
        isLoadingCloudBackupSummary = false
    }

    @MainActor
    private func refreshCloudBackupMetadata() async {
        guard cloudSyncEnabled, !isRefreshingCloudBackupMetadata else { return }

        isRefreshingCloudBackupMetadata = true
        do {
            let snapshot = try await UserDataCloudBackupService(
                localContainer: modelContext.container,
                backupStore: CloudKitUserDataCloudBackupStore()
            ).latestBackupSnapshot()
            if let snapshot {
                remoteCloudBackupSummary = snapshot.contentSummary
                AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp(at: snapshot.updatedAt))
            } else {
                remoteCloudBackupSummary = nil
                AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp(at: nil))
            }
        } catch {
            AppRuntimeState.shared.updateUserDataSyncStatus(.degraded("Cloud backup status check failed: \(error.localizedDescription)"))
        }
        isRefreshingCloudBackupMetadata = false
    }

    @MainActor
    private func forceCloudBackup() async {
        guard cloudSyncEnabled, !isForcingCloudBackup else { return }

        isForcingCloudBackup = true
        AppRuntimeState.shared.updateUserDataSyncStatus(.pending())
        do {
            let exportedSnapshot = try await UserDataCloudBackupService(
                localContainer: modelContext.container,
                backupStore: CloudKitUserDataCloudBackupStore()
            ).exportCurrentBackup()
            remoteCloudBackupSummary = exportedSnapshot.contentSummary
            AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp(at: exportedSnapshot.updatedAt))
            await refreshCloudBackupSummary()
        } catch {
            AppRuntimeState.shared.updateUserDataSyncStatus(.degraded("Manual cloud backup failed: \(error.localizedDescription)"))
        }
        isForcingCloudBackup = false
    }

    @MainActor
    @discardableResult
    private func applyWarmProfileSnapshotIfAvailable() -> Bool {
        guard !hasLoadedProfile, currentProfile == nil else { return false }
        guard let warmSnapshot = appWarmupState.freshProfile() else { return false }
        currentProfile = warmSnapshot.profile
        dashboardContent = warmSnapshot.dashboard
        hasLoadedProfile = true
        needsExplicitRefresh = false
        lastLoadedProfileUpdatedAt = warmSnapshot.profile.updatedAt
        lastRefreshAt = warmSnapshot.warmedAt
        scheduleDashboardRender(enabledWidgets: warmSnapshot.dashboard.enabledWidgets)
        return true
    }

    @MainActor
    private func scheduleDashboardRenderIfNeeded() {
        guard hasLoadedProfile else { return }
        guard !shouldRenderDashboardContent else { return }
        scheduleDashboardRender(enabledWidgets: dashboardContent.enabledWidgets)
    }

    @MainActor
    private func persistWarmProfileSnapshotIfNeeded() {
        guard let currentProfile else { return }
        appWarmupState.storeProfile(
            ProfileWarmSnapshot(
                profile: currentProfile,
                dashboard: dashboardContent,
                warmedAt: .now
            )
        )
    }

    private func scheduleCoachBriefLoad(enabledWidgets: [ProfileWidgetConfigSnapshot]) {
        cancelCoachBriefLoad()
        guard shouldRenderDashboardContent else {
            coachBriefLoadState = .idle
            return
        }
        guard enabledWidgets.contains(where: { $0.kind == .coachBrief }) else {
            coachBriefLoadState = .idle
            return
        }

        coachBriefLoadState = .loading
        let token = UUID()
        coachBriefLoadToken = token
        let backgroundStore = profileBackgroundStore
        coachBriefLoadTask = Task.detached(priority: .utility) {
            do {
                let coachBrief = try await controller.loadCoachBriefPresentation(
                    enabledWidgets: enabledWidgets,
                    backgroundStore: backgroundStore
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard coachBriefLoadToken == token else { return }
                    dashboardContent.coachBrief = coachBrief
                    coachBriefLoadState = coachBrief == nil ? .failed : .idle
                    persistWarmProfileSnapshotIfNeeded()
                    coachBriefLoadTask = nil
                    coachBriefLoadToken = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard coachBriefLoadToken == token else { return }
                    coachBriefLoadTask = nil
                    coachBriefLoadToken = nil
                }
            } catch {
                await MainActor.run {
                    guard coachBriefLoadToken == token else { return }
                    dashboardContent.coachBrief = nil
                    coachBriefLoadState = .failed
                    coachBriefLoadTask = nil
                    coachBriefLoadToken = nil
                }
            }
        }
    }

    private func cancelCoachBriefLoad() {
        coachBriefLoadTask?.cancel()
        coachBriefLoadTask = nil
        coachBriefLoadToken = nil
    }

    private func loadCoachFollowUp(_ kind: CoachFollowUpKind) {
        guard let coachBrief = dashboardContent.coachBrief else { return }
        guard coachFollowUpSummaries[kind] == nil else { return }
        guard !loadingCoachFollowUps.contains(kind) else { return }
        guard coachFollowUpTasks[kind] == nil else { return }

        let revisionKey = coachBrief.snapshot.revisionKey
        let token = UUID()
        loadingCoachFollowUps.insert(kind)
        coachFollowUpTokens[kind] = token
        let backgroundStore = profileBackgroundStore
        let snapshot = coachBrief.snapshot
        coachFollowUpTasks[kind] = Task.detached(priority: .utility) {
            func clearLoadingState() async {
                await MainActor.run {
                    guard coachFollowUpTokens[kind] == token else { return }
                    loadingCoachFollowUps.remove(kind)
                    coachFollowUpTasks[kind] = nil
                    coachFollowUpTokens[kind] = nil
                }
            }

            do {
                let summary = try await controller.loadCoachFollowUpSummary(
                    kind: kind,
                    snapshot: snapshot,
                    backgroundStore: backgroundStore
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard coachFollowUpTokens[kind] == token else { return }
                    guard dashboardContent.coachBrief?.snapshot.revisionKey == revisionKey else { return }
                    coachFollowUpSummaries[kind] = summary
                }
            } catch is CancellationError {
                await clearLoadingState()
                return
            } catch {
                await clearLoadingState()
                return
            }
            await clearLoadingState()
        }
    }

    private func cancelCoachFollowUpLoads() {
        for task in coachFollowUpTasks.values {
            task.cancel()
        }
        coachFollowUpTasks = [:]
        coachFollowUpTokens = [:]
        loadingCoachFollowUps = []
    }

    private func markProfileDirtyAndReloadIfActive() {
        appWarmupState.invalidateProfile()
        let invalidationVersion = appWarmupState.profileInvalidationVersion
        Task.detached(priority: .utility) {
            await handleProfileInvalidated(version: invalidationVersion)
        }
    }

    @MainActor
    private func handleProfileInvalidated(version: Int) async {
        guard version > 0, version != lastHandledProfileInvalidationVersion else {
            return
        }
        lastHandledProfileInvalidationVersion = version
        needsExplicitRefresh = true
        shouldRenderDashboardContent = hasRenderedDashboardContent
        guard isTabActive else { return }
        await reloadProfileIfNeeded(force: true)
    }

    private func scheduleDashboardRender(enabledWidgets: [ProfileWidgetConfigSnapshot]) {
        cancelDashboardRender()
        cancelTrendSeriesLoad()
        cancelCoachBriefLoad()
        coachBriefLoadState = .idle

        guard isTabActive else {
            shouldRenderDashboardContent = hasRenderedDashboardContent
            return
        }

        let delay = ProfileDashboardRenderPolicy.renderDelay(
            hasRenderedDashboardContent: hasRenderedDashboardContent,
            hasFreshWarmSnapshot: appWarmupState.freshProfile() != nil
        )
        let renderToken = profileReloadToken
        dashboardRenderTask = Task.detached(priority: .utility) {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isTabActive else { return }
                guard profileReloadToken == renderToken else { return }
                shouldRenderDashboardContent = true
                hasRenderedDashboardContent = true
                dashboardRenderTask = nil
                scheduleCoachBriefLoad(enabledWidgets: enabledWidgets)
                scheduleTrendSeriesLoad()
            }
        }
    }

    private func cancelDashboardRender(isTabExit: Bool = false) {
        dashboardRenderTask?.cancel()
        dashboardRenderTask = nil
        shouldRenderDashboardContent = ProfileDashboardRenderPolicy.visibilityAfterCancellingRender(
            hasRenderedDashboardContent: hasRenderedDashboardContent,
            isTabExit: isTabExit
        )
    }

    private func cancelTrendSeriesLoad() {
        trendSeriesLoadTask?.cancel()
        trendSeriesLoadTask = nil
        trendSeriesLoadToken = nil
        controller.setTrendSeriesCacheOwner(nil)
        isLoadingTrendSeries = false
    }

    private func scheduleTrendSeriesLoad() {
        let enabledWidgets = dashboardContent.enabledWidgets
        let widgetsNeedingSeries = enabledWidgets.filter { config in
            config.kind.requiresExerciseSelection
                && dashboardContent.trendSeriesByWidgetID[config.id] == nil
        }
        guard !widgetsNeedingSeries.isEmpty else {
            isLoadingTrendSeries = false
            return
        }

        let reloadToken = profileReloadToken
        cancelTrendSeriesLoad()
        isLoadingTrendSeries = true
        let loadToken = UUID()
        trendSeriesLoadToken = loadToken
        controller.setTrendSeriesCacheOwner(loadToken)
        let backgroundStore = profileBackgroundStore
        trendSeriesLoadTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            let isTabStillActive = await MainActor.run {
                isTabActive && profileReloadToken == reloadToken && trendSeriesLoadToken == loadToken
            }
            guard isTabStillActive else { return }

            do {
                let trendSeriesByWidgetID = try await controller.loadTrendSeries(
                    enabledWidgets: widgetsNeedingSeries,
                    cacheOwner: loadToken,
                    backgroundStore: backgroundStore
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard profileReloadToken == reloadToken else { return }
                    guard trendSeriesLoadToken == loadToken else { return }
                    dashboardContent.trendSeriesByWidgetID.merge(trendSeriesByWidgetID) { _, new in new }
                    persistWarmProfileSnapshotIfNeeded()
                }
            } catch {
                await MainActor.run {
                    guard profileReloadToken == reloadToken else { return }
                    guard trendSeriesLoadToken == loadToken else { return }
                    showError(error)
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    guard trendSeriesLoadToken == loadToken else { return }
                    isLoadingTrendSeries = false
                    trendSeriesLoadTask = nil
                    trendSeriesLoadToken = nil
                }
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

    private func trendTitle(for metric: ProfileExerciseTrendMetric) -> String {
        switch metric {
        case .oneRepMax:
            return "1RM Trend"
        case .maxWeight:
            return "Max Weight Trend"
        case .volume:
            return "Volume Trend"
        case .maxReps:
            return "Max Reps Trend"
        }
    }

    private func trendSubtitle(for config: ProfileWidgetConfigSnapshot) -> String {
        let exerciseName = config.selectedExerciseNameSnapshot ?? "your lift"
        switch config.exerciseTrendMetric {
        case .oneRepMax:
            return "Estimated max strength for \(exerciseName)"
        case .maxWeight:
            return "Best logged load for \(exerciseName)"
        case .volume:
            return "Training volume for \(exerciseName)"
        case .maxReps:
            return "Best completed reps for \(exerciseName)"
        }
    }

    private func trendAccent(for metric: ProfileExerciseTrendMetric) -> Color {
        switch metric {
        case .oneRepMax:
            return WGJTheme.accentCyan
        case .maxWeight:
            return WGJTheme.accentGold
        case .volume:
            return WGJTheme.accentBlue
        case .maxReps:
            return WGJTheme.success
        }
    }

    private func trendEmptyMessage(for metric: ProfileExerciseTrendMetric) -> String {
        switch metric {
        case .oneRepMax:
            return "Log weighted sets for this lift to start the trend."
        case .maxWeight:
            return "Log weighted sets for this lift to chart your best load."
        case .volume:
            return "Log weighted sets for this lift to chart your volume."
        case .maxReps:
            return "Log completed sets for this exercise to chart your reps."
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

}

@MainActor
@Observable
final class ProfileViewController {
    nonisolated private struct TrendSeriesLoadResult: Sendable {
        let trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]
        let cache: [ProfileDashboardTrendSeriesCacheKey: ExerciseMetricSeries]
    }

    private var trendSeriesCache: [ProfileDashboardTrendSeriesCacheKey: ExerciseMetricSeries] = [:]
    private var trendSeriesCacheOwner: UUID?

    func invalidateTrendSeriesCache() {
        trendSeriesCache.removeAll()
        trendSeriesCacheOwner = nil
    }

    func setTrendSeriesCacheOwner(_ owner: UUID?) {
        trendSeriesCacheOwner = owner
    }

    func loadPublishedProfileIdentity(
        cloudSyncEnabled: Bool,
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileIdentitySnapshot {
        try await backgroundStore.performAsync("profile.identity") { backgroundContext in
            try await ProfileRepository(modelContext: backgroundContext).bootstrapProfileIdentitySnapshot(
                cloudSyncEnabled: cloudSyncEnabled
            )
        }
    }

    func loadDashboardContent(
        profile: ProfileIdentitySnapshot,
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileDashboardContent {
        try await backgroundStore.perform("profile.dashboard") { backgroundContext in
            let widgetRepository = ProfileWidgetRepository(modelContext: backgroundContext)
            let metricsService = WorkoutMetricsService(modelContext: backgroundContext)
            let enabled = try widgetRepository.enabledConfigurationSnapshots()
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8)
            var nextContent = ProfileDashboardContent.make(
                enabledWidgets: enabled,
                dashboard: dashboard,
                trendSeriesByWidgetID: [:]
            )
            nextContent.weeklyGoal = profile.weeklyWorkoutGoal
            return nextContent
        }
    }

    func loadTrendSeries(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        cacheOwner: UUID,
        backgroundStore: AppBackgroundStore
    ) async throws -> [UUID: ExerciseMetricSeries] {
        let cachedSeries = trendSeriesCache
        let result = try await backgroundStore.perform("profile.trends") { backgroundContext in
            let metricsService = WorkoutMetricsService(modelContext: backgroundContext)
            var trendSeriesByWidgetID: [UUID: ExerciseMetricSeries] = [:]
            var nextCache = cachedSeries
            var currentCacheKeys: Set<ProfileDashboardTrendSeriesCacheKey> = []

            for config in enabledWidgets {
                guard config.kind.isExerciseTrend else { continue }
                guard let selectedExerciseUUID = config.selectedCatalogExerciseUUID else { continue }
                let cacheKey = ProfileDashboardTrendSeriesCacheKey(
                    metric: config.exerciseTrendMetric,
                    catalogExerciseUUID: selectedExerciseUUID
                )
                currentCacheKeys.insert(cacheKey)

                if let cachedSeries = nextCache[cacheKey] {
                    trendSeriesByWidgetID[config.id] = cachedSeries.withPreferredName(
                        config.selectedExerciseNameSnapshot
                    )
                    continue
                }

                let series = try metricsService.exerciseMetricTrend(
                    for: selectedExerciseUUID,
                    metric: config.exerciseTrendMetric,
                    preferredExerciseName: config.selectedExerciseNameSnapshot,
                    limit: 8
                )

                nextCache[cacheKey] = series
                trendSeriesByWidgetID[config.id] = series
            }

            nextCache = nextCache.filter { currentCacheKeys.contains($0.key) }

            return TrendSeriesLoadResult(
                trendSeriesByWidgetID: trendSeriesByWidgetID,
                cache: nextCache
            )
        }
        if trendSeriesCacheOwner == cacheOwner {
            trendSeriesCache = result.cache
        }
        return result.trendSeriesByWidgetID
    }

    func loadCoachBriefPresentation(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileCoachPresentation? {
        guard enabledWidgets.contains(where: { $0.kind == .coachBrief }) else {
            return nil
        }

        return try await backgroundStore.performAsync("profile.coach.presentation") { backgroundContext in
            try await Self.loadCoachBriefPresentation(
                modelContext: backgroundContext,
                enabledWidgets: enabledWidgets
            )
        }
    }

    func loadCoachFollowUpSummary(
        kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot,
        backgroundStore: AppBackgroundStore
    ) async throws -> CoachNarrativeSummary {
        try await backgroundStore.performAsync("profile.coach.followup") { backgroundContext in
            try await AppleCoachNarrativeService(modelContext: backgroundContext).followUp(
                for: kind,
                snapshot: snapshot
            )
        }
    }

    private static func loadCoachBriefPresentation(
        modelContext: ModelContext,
        enabledWidgets: [ProfileWidgetConfigSnapshot]
    ) async throws -> ProfileCoachPresentation? {
        guard enabledWidgets.contains(where: { $0.kind == .coachBrief }) else {
            return nil
        }

        let snapshot: WeeklyCoachInsightSnapshot
        snapshot = try WGJPerformance.measure("profile.coach.snapshot") {
            try WeeklyCoachInsightService(modelContext: modelContext).weeklyInsightSnapshot()
        }

        let recap = try await AppleCoachNarrativeService(modelContext: modelContext).recapForDisplay(for: snapshot)
        return ProfileCoachPresentation(snapshot: snapshot, recap: recap)
    }
}

private extension ExerciseMetricSeries {
    nonisolated func withPreferredName(_ preferredName: String?) -> ExerciseMetricSeries {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return self }

        return ExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: trimmed,
            loadUnit: loadUnit,
            points: points
        )
    }
}

nonisolated enum ProfileDashboardTrendSeriesBuilder {
    static func build(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        metricsService: WorkoutMetricsService
    ) throws -> [UUID: ExerciseMetricSeries] {
        var trendSeriesByWidgetID: [UUID: ExerciseMetricSeries] = [:]
        var seriesByWidgetConfig: [ProfileDashboardTrendSeriesCacheKey: ExerciseMetricSeries] = [:]

        for config in enabledWidgets {
            guard config.kind.isExerciseTrend else { continue }
            guard let selectedExerciseUUID = config.selectedCatalogExerciseUUID else { continue }

            let cacheKey = ProfileDashboardTrendSeriesCacheKey(
                metric: config.exerciseTrendMetric,
                catalogExerciseUUID: selectedExerciseUUID
            )
            if let cached = seriesByWidgetConfig[cacheKey] {
                trendSeriesByWidgetID[config.id] = cached.withPreferredName(
                    config.selectedExerciseNameSnapshot
                )
                continue
            }

            let series = try metricsService.exerciseMetricTrend(
                for: selectedExerciseUUID,
                metric: config.exerciseTrendMetric,
                preferredExerciseName: config.selectedExerciseNameSnapshot,
                limit: 8
            )
            seriesByWidgetConfig[cacheKey] = series
            trendSeriesByWidgetID[config.id] = series
        }

        return trendSeriesByWidgetID
    }
}

nonisolated private struct ProfileDashboardTrendSeriesCacheKey: Hashable, Sendable {
    let metric: ProfileExerciseTrendMetric
    let catalogExerciseUUID: String
}

nonisolated struct ProfileDashboardContent: Sendable {
    var enabledWidgets: [ProfileWidgetConfigSnapshot]
    var personalRecords: [WorkoutPRRecord]
    var weeklyProgress: [WeeklyWorkoutProgressPoint]
    var weeklyMuscleHeatmap: ProfileWeeklyMuscleHeatmapSnapshot
    var trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]
    var coachBrief: ProfileCoachPresentation?
    var weeklyGoal: Int
    var overviewStats: ProfileOverviewStats
    var topExercises: [ProfileTopExerciseStat]
    var activityDays: [ProfileActivityDay]
    var activityDayRows: [[ProfileActivityDay]]
    var maxActivityDayWorkoutCount: Int
    var hasActivityDayWorkouts: Bool

    static let empty = ProfileDashboardContent(
        enabledWidgets: [],
        personalRecords: [],
        weeklyProgress: [],
        weeklyMuscleHeatmap: .empty,
        trendSeriesByWidgetID: [:],
        coachBrief: nil,
        weeklyGoal: 4,
        overviewStats: .empty,
        topExercises: [],
        activityDays: [],
        activityDayRows: [],
        maxActivityDayWorkoutCount: 1,
        hasActivityDayWorkouts: false
    )

    nonisolated static func make(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        dashboard: ProfileDashboardSnapshot,
        trendSeriesByWidgetID: [UUID: ExerciseMetricSeries],
        coachBrief: ProfileCoachPresentation? = nil
    ) -> ProfileDashboardContent {
        let activityDayRows = stride(from: 0, to: dashboard.activityDays.count, by: 7).map { startIndex in
            Array(dashboard.activityDays[startIndex ..< min(startIndex + 7, dashboard.activityDays.count)])
        }
        let maxActivityDayWorkoutCount = max(1, dashboard.activityDays.map(\.workoutCount).max() ?? 0)
        let hasActivityDayWorkouts = dashboard.activityDays.contains { $0.workoutCount > 0 }

        return ProfileDashboardContent(
            enabledWidgets: enabledWidgets,
            personalRecords: Array(dashboard.personalRecords.prefix(5)),
            weeklyProgress: dashboard.weeklyProgress,
            weeklyMuscleHeatmap: dashboard.weeklyMuscleHeatmap,
            trendSeriesByWidgetID: trendSeriesByWidgetID,
            coachBrief: coachBrief,
            weeklyGoal: max(1, dashboard.weeklyGoal),
            overviewStats: dashboard.overviewStats,
            topExercises: Array(dashboard.topExercises.prefix(3)),
            activityDays: dashboard.activityDays,
            activityDayRows: activityDayRows,
            maxActivityDayWorkoutCount: maxActivityDayWorkoutCount,
            hasActivityDayWorkouts: hasActivityDayWorkouts
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

private extension UserDataCloudBackupContentSummary {
    static let empty = UserDataCloudBackupContentSummary(
        profileCount: 0,
        profileWidgetCount: 0,
        customExerciseCount: 0,
        templateFolderCount: 0,
        workoutTemplateCount: 0,
        templateCardioBlockCount: 0,
        templateExerciseCount: 0,
        templateComponentCount: 0,
        templateSetCount: 0,
        templateDropStageCount: 0,
        completedWorkoutCount: 0,
        workoutCardioBlockCount: 0,
        workoutExerciseCount: 0,
        workoutSetCount: 0,
        workoutDropStageCount: 0
    )

    var totalBackedUpItemCount: Int {
        profileCount
            + profileWidgetCount
            + customExerciseCount
            + templateFolderCount
            + workoutTemplateCount
            + templateCardioBlockCount
            + templateExerciseCount
            + templateComponentCount
            + templateSetCount
            + templateDropStageCount
            + completedWorkoutCount
            + workoutCardioBlockCount
            + workoutExerciseCount
            + workoutSetCount
            + workoutDropStageCount
    }

    nonisolated static func loadLocal(context: ModelContext) throws -> UserDataCloudBackupContentSummary {
        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        let workoutSessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        return UserDataCloudBackupContentSummary(
            profileCount: try context.fetch(FetchDescriptor<UserProfile>()).count,
            profileWidgetCount: try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).count,
            customExerciseCount: exercises.filter(\.isCustomExercise).count,
            templateFolderCount: try context.fetch(FetchDescriptor<TemplateFolder>()).count,
            workoutTemplateCount: try context.fetch(FetchDescriptor<WorkoutTemplate>()).count,
            templateCardioBlockCount: try context.fetch(FetchDescriptor<TemplateCardioBlock>()).count,
            templateExerciseCount: try context.fetch(FetchDescriptor<TemplateExercise>()).count,
            templateComponentCount: try context.fetch(FetchDescriptor<TemplateExerciseComponent>()).count,
            templateSetCount: try context.fetch(FetchDescriptor<TemplateExerciseSet>()).count,
            templateDropStageCount: try context.fetch(FetchDescriptor<TemplateExerciseDropStage>()).count,
            completedWorkoutCount: workoutSessions.filter { $0.status == .completed }.count,
            workoutCardioBlockCount: try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>()).count,
            workoutExerciseCount: try context.fetch(FetchDescriptor<WorkoutSessionExercise>()).count,
            workoutSetCount: try context.fetch(FetchDescriptor<WorkoutSessionSet>()).count,
            workoutDropStageCount: try context.fetch(FetchDescriptor<WorkoutSessionDropStage>()).count
        )
    }
}

private struct ProfileCloudBackupComparisonRow: Identifiable, Equatable {
    let id: String
    let title: String
    let cloudCount: Int?
    let deviceCount: Int

    var hasDifference: Bool {
        guard let cloudCount else { return false }
        return cloudCount != deviceCount
    }

    static func primaryRows(
        cloud: UserDataCloudBackupContentSummary?,
        device: UserDataCloudBackupContentSummary
    ) -> [ProfileCloudBackupComparisonRow] {
        [
            ProfileCloudBackupComparisonRow(
                id: "completed-workouts",
                title: "Workouts",
                cloudCount: cloud?.completedWorkoutCount,
                deviceCount: device.completedWorkoutCount
            ),
            ProfileCloudBackupComparisonRow(
                id: "workout-templates",
                title: "Templates",
                cloudCount: cloud?.workoutTemplateCount,
                deviceCount: device.workoutTemplateCount
            ),
            ProfileCloudBackupComparisonRow(
                id: "custom-exercises",
                title: "Custom exercises",
                cloudCount: cloud?.customExerciseCount,
                deviceCount: device.customExerciseCount
            ),
        ]
    }

    static func detailRows(
        cloud: UserDataCloudBackupContentSummary?,
        device: UserDataCloudBackupContentSummary
    ) -> [ProfileCloudBackupComparisonRow] {
        [
            ProfileCloudBackupComparisonRow(id: "profiles", title: "Profiles", cloudCount: cloud?.profileCount, deviceCount: device.profileCount),
            ProfileCloudBackupComparisonRow(id: "profile-widgets", title: "Profile widgets", cloudCount: cloud?.profileWidgetCount, deviceCount: device.profileWidgetCount),
            ProfileCloudBackupComparisonRow(id: "template-folders", title: "Template folders", cloudCount: cloud?.templateFolderCount, deviceCount: device.templateFolderCount),
            ProfileCloudBackupComparisonRow(id: "template-cardio", title: "Template cardio blocks", cloudCount: cloud?.templateCardioBlockCount, deviceCount: device.templateCardioBlockCount),
            ProfileCloudBackupComparisonRow(id: "template-exercises", title: "Template exercises", cloudCount: cloud?.templateExerciseCount, deviceCount: device.templateExerciseCount),
            ProfileCloudBackupComparisonRow(id: "template-components", title: "Template components", cloudCount: cloud?.templateComponentCount, deviceCount: device.templateComponentCount),
            ProfileCloudBackupComparisonRow(id: "template-sets", title: "Template sets", cloudCount: cloud?.templateSetCount, deviceCount: device.templateSetCount),
            ProfileCloudBackupComparisonRow(id: "template-drop-stages", title: "Template drop stages", cloudCount: cloud?.templateDropStageCount, deviceCount: device.templateDropStageCount),
            ProfileCloudBackupComparisonRow(id: "workout-cardio", title: "Workout cardio blocks", cloudCount: cloud?.workoutCardioBlockCount, deviceCount: device.workoutCardioBlockCount),
            ProfileCloudBackupComparisonRow(id: "workout-exercises", title: "Workout exercises", cloudCount: cloud?.workoutExerciseCount, deviceCount: device.workoutExerciseCount),
            ProfileCloudBackupComparisonRow(id: "workout-sets", title: "Workout sets", cloudCount: cloud?.workoutSetCount, deviceCount: device.workoutSetCount),
            ProfileCloudBackupComparisonRow(id: "workout-drop-stages", title: "Workout drop stages", cloudCount: cloud?.workoutDropStageCount, deviceCount: device.workoutDropStageCount),
        ]
    }
}

private struct ProfileCloudBackupComparisonHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Cloud")
                .frame(width: 58, alignment: .trailing)
            Text("Device")
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(WGJTheme.textSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, 10)
    }
}

private struct ProfileCloudBackupComparisonRowView: View {
    let row: ProfileCloudBackupComparisonRow
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(countText(row.cloudCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)

                Text("\(row.deviceCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            if row.hasDifference {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(WGJTheme.accentGold.opacity(0.10))
            }
        }
    }

    private var valueTint: Color {
        row.hasDifference ? WGJTheme.accentGold : WGJTheme.textSecondary
    }

    private func countText(_ count: Int?) -> String {
        count.map(String.init) ?? "-"
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
            .frame(maxWidth: .infinity)
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
