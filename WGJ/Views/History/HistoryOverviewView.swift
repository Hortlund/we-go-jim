import Foundation
import SwiftData
import SwiftUI

struct HistoryOverviewView: View {
    nonisolated private static let historyPageSize = 40

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.isTabActive) private var isTabActive

    @State private var selectedDayFilter: Date?
    @State private var showingWorkoutCalendar = false
    @State private var showingArchivedWorkouts = false
    @State private var displayedCalendarMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var controller = HistoryOverviewController()
    @State private var hasLoadedSnapshot = false
    @State private var needsExplicitRefresh = true
    @State private var lastLoadedContentUpdatedAt: Date?
    @State private var lastRefreshAt: Date?
    @State private var isLoadingMoreHistory = false
    @State private var isLoadingCalendarMonth = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var historyBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("History", subtitle: "Completed sessions, volume, and best sets.") {
                    Button("Calendar") {
                        openWorkoutCalendar()
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("history-calendar-button")

                    Button("Hidden") {
                        showingArchivedWorkouts = true
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("history-hidden-button")
                }

                if let selectedDayFilter {
                    selectedDayFilterCard(selectedDayFilter)
                }

                if controller.snapshot.sections.isEmpty {
                    WGJEmptyStateCard(
                        title: selectedDayFilter == nil ? "No completed workouts yet" : "No workouts on this day",
                        message: selectedDayFilter == nil
                            ? "Completed workouts will appear here."
                            : "No workouts were logged for this date.",
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                }

                ForEach(controller.snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        WGJCompactSectionHeader(section.title)

                        ForEach(section.cards) { card in
                            historyCard(card)
                        }
                    }
                }

                if selectedDayFilter == nil, controller.hasMorePages {
                    historyLoadMoreSentinel
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingWorkoutCalendar) {
            workoutCalendarSheet
        }
        .sheet(isPresented: $showingArchivedWorkouts, onDismiss: {
            Task {
                await reloadSnapshotIfNeeded(force: true)
            }
        }) {
            NavigationStack {
                HistoryArchivedWorkoutsSheet()
            }
            .wgjSheetSurface()
            .presentationDetents([.large])
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadSnapshotIfNeeded(force: false)
        }
        .onChange(of: selectedDayFilter) { _, newDayFilter in
            Task {
                await reloadSnapshotIfNeeded(force: true)
            }
            if let newDayFilter {
                displayedCalendarMonth = startOfMonth(for: newDayFilter)
                Task {
                    await loadCalendarMonthIfNeeded(newDayFilter)
                }
            }
        }
        .onChange(of: displayedCalendarMonth) { _, newMonth in
            Task {
                await loadCalendarMonthIfNeeded(newMonth)
            }
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var workoutCalendarSheet: some View {
        NavigationStack {
            HistoryWorkoutCalendarSheet(
                displayedMonth: $displayedCalendarMonth,
                selectedDay: $selectedDayFilter,
                workoutCountsByDay: controller.calendarWorkoutCountsByDay,
                isLoadingMonth: isLoadingCalendarMonth,
                onClose: { showingWorkoutCalendar = false }
            )
        }
        .presentationDetents([.large])
    }

    private var historyLoadMoreSentinel: some View {
        HStack {
            Spacer()
            if isLoadingMoreHistory {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Loading more history")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .task {
            await loadMoreHistoryIfNeeded()
        }
        .accessibilityIdentifier("history-load-more-sentinel")
    }

    private func historyCard(_ card: HistorySessionCardData) -> some View {
        HistorySessionCardView(card: card) {
            archiveSession(card.sessionID)
        }
        .equatable()
    }

    private func openWorkoutCalendar() {
        let referenceDate = selectedDayFilter
            ?? controller.completedSessions.first.map(\.displayDate)
            ?? Date()
        displayedCalendarMonth = startOfMonth(for: referenceDate)
        showingWorkoutCalendar = true
        Task {
            await loadCalendarMonthIfNeeded(referenceDate)
        }
    }

    private func selectedDayFilterCard(_ day: Date) -> some View {
        let dayStart = startOfDay(for: day)
        let workoutCount = controller.calendarWorkoutCountsByDay[dayStart, default: controller.snapshot.workoutCountsByDay[dayStart, default: 0]]

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Text("\(workoutCount) logged workout\(workoutCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Spacer()

            Button("Show All") {
                selectedDayFilter = nil
            }
            .buttonStyle(WGJGhostButtonStyle())
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func archiveSession(_ id: UUID) {
        let backgroundStore = historyBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-overview.archive") { backgroundContext in
                    try WorkoutSessionRepository(modelContext: backgroundContext).archiveSession(id: id)
                }
                await markNeedsExplicitRefresh()
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func markNeedsExplicitRefresh() {
        needsExplicitRefresh = true
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    @MainActor
    private func reloadSnapshotIfNeeded(force: Bool) async {
        await Task.yield()
        guard !Task.isCancelled else { return }

        let currentContentUpdatedAt = await currentHistoryContentUpdatedAt()
        guard force || TimestampedReloadPolicy.shouldReload(
            hasLoaded: hasLoadedSnapshot,
            needsExplicitRefresh: needsExplicitRefresh,
            currentContentUpdatedAt: currentContentUpdatedAt,
            lastLoadedContentUpdatedAt: lastLoadedContentUpdatedAt,
            lastRefreshAt: lastRefreshAt
        ) else {
            return
        }

        await reloadSnapshot(contentUpdatedAt: currentContentUpdatedAt)
    }

    @MainActor
    private func reloadSnapshot(contentUpdatedAt: Date?) async {
        do {
            let loaded: HistoryOverviewLoadedSnapshot
            let dayFilter = selectedDayFilter
            let backgroundStore = historyBackgroundStore
            loaded = try await backgroundStore.perform("history-overview.snapshot.reload") { backgroundContext in
                try HistoryOverviewSnapshotLoader.load(
                    modelContext: backgroundContext,
                    selectedDayFilter: dayFilter,
                    pageSize: Self.historyPageSize
                )
            }
            controller.apply(loaded)
            hasLoadedSnapshot = true
            needsExplicitRefresh = false
            lastLoadedContentUpdatedAt = contentUpdatedAt
            lastRefreshAt = .now
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    @MainActor
    private func loadMoreHistoryIfNeeded() async {
        guard selectedDayFilter == nil,
              controller.hasMorePages,
              !isLoadingMoreHistory
        else {
            return
        }

        guard let oldestLoadedDate = controller.oldestLoadedDate else { return }
        isLoadingMoreHistory = true
        defer { isLoadingMoreHistory = false }

        do {
            let backgroundStore = historyBackgroundStore
            let loaded = try await backgroundStore.perform("history-overview.snapshot.load-more") { backgroundContext in
                try HistoryOverviewSnapshotLoader.loadPage(
                    modelContext: backgroundContext,
                    before: oldestLoadedDate,
                    pageSize: Self.historyPageSize
                )
            }
            controller.appendPage(loaded)
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    @MainActor
    private func loadCalendarMonthIfNeeded(_ month: Date) async {
        let monthStart = startOfMonth(for: month)
        guard !controller.hasCalendarCounts(for: monthStart) else { return }

        isLoadingCalendarMonth = true
        defer { isLoadingCalendarMonth = false }

        do {
            let backgroundStore = historyBackgroundStore
            let counts = try await backgroundStore.perform("history.calendar-month-counts") { backgroundContext in
                try HistoryOverviewSnapshotLoader.loadWorkoutCountsByDay(
                    modelContext: backgroundContext,
                    month: monthStart
                )
            }
            controller.mergeCalendarWorkoutCounts(counts, month: monthStart)
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    @MainActor
    private func currentHistoryContentUpdatedAt() async -> Date? {
        let backgroundStore = historyBackgroundStore
        return try? await backgroundStore.perform("history-overview.latest-updated-at") { backgroundContext in
            try WorkoutSessionRepository(modelContext: backgroundContext).latestCompletedSessionUpdatedAt()
        }
    }
}

struct HistoryMonthSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let cards: [HistorySessionCardData]
}

nonisolated struct HistorySessionCardData: Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: UUID
    let updatedAtStamp: TimeInterval
    let name: String
    let dateText: String
    let durationText: String
    let volumeText: String
    let prsText: String
    let summaryRows: [HistorySessionSummaryRow]
}

nonisolated struct HistoryOverviewSessionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let updatedAt: Date
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let totalVolume: Double
    let prHitsCount: Int
    let summaryRows: [HistorySessionSummaryRow]

    var displayDate: Date {
        endedAt ?? startedAt
    }
}

nonisolated struct HistoryOverviewSnapshot: Sendable {
    let workoutCountsByDay: [Date: Int]
    let sections: [HistoryMonthSection]

    static let empty = HistoryOverviewSnapshot(
        workoutCountsByDay: [:],
        sections: []
    )
}

nonisolated struct HistoryOverviewPreparedSnapshots: Sendable {
    let allSnapshot: HistoryOverviewSnapshot
    let sectionsByDayStart: [Date: [HistoryMonthSection]]

    static let empty = HistoryOverviewPreparedSnapshots(
        allSnapshot: .empty,
        sectionsByDayStart: [:]
    )

    func snapshot(
        for selectedDayFilter: Date?,
        calendar: Calendar = .current
    ) -> HistoryOverviewSnapshot {
        guard let selectedDayFilter else {
            return allSnapshot
        }

        let dayStart = calendar.startOfDay(for: selectedDayFilter)
        return HistoryOverviewSnapshot(
            workoutCountsByDay: allSnapshot.workoutCountsByDay,
            sections: sectionsByDayStart[dayStart, default: []]
        )
    }
}

@MainActor
@Observable
final class HistoryOverviewController {
    var completedSessions: [HistoryOverviewSessionSnapshot] = []
    var snapshot = HistoryOverviewSnapshot.empty
    var calendarWorkoutCountsByDay: [Date: Int] = [:]
    var hasMorePages = false
    private var preparedSnapshots = HistoryOverviewPreparedSnapshots.empty
    private var loadedCalendarMonths: Set<Date> = []

    var oldestLoadedDate: Date? {
        completedSessions.last?.displayDate
    }

    func apply(_ loaded: HistoryOverviewLoadedSnapshot) {
        completedSessions = loaded.completedSessions
        preparedSnapshots = loaded.preparedSnapshots
        snapshot = preparedSnapshots.snapshot(for: loaded.selectedDayFilter)
        calendarWorkoutCountsByDay = loaded.calendarWorkoutCountsByDay
        loadedCalendarMonths = loaded.loadedCalendarMonths
        hasMorePages = loaded.hasMorePages
    }

    func appendPage(_ loaded: HistoryOverviewLoadedSnapshot) {
        var existingIDs = Set(completedSessions.map(\.id))
        completedSessions.append(contentsOf: loaded.completedSessions.filter { existingIDs.insert($0.id).inserted })
        preparedSnapshots = HistoryOverviewSnapshotBuilder.buildPreparedSnapshots(sessions: completedSessions)
        snapshot = preparedSnapshots.snapshot(for: nil)
        calendarWorkoutCountsByDay.merge(loaded.calendarWorkoutCountsByDay) { current, _ in current }
        loadedCalendarMonths.formUnion(loaded.loadedCalendarMonths)
        hasMorePages = loaded.hasMorePages
    }

    func hasCalendarCounts(for month: Date) -> Bool {
        loadedCalendarMonths.contains(month)
    }

    func mergeCalendarWorkoutCounts(_ counts: [Date: Int], month: Date) {
        calendarWorkoutCountsByDay.merge(counts) { _, new in new }
        loadedCalendarMonths.insert(month)
    }
}

nonisolated struct HistoryOverviewLoadedSnapshot: Sendable {
    let completedSessions: [HistoryOverviewSessionSnapshot]
    let preparedSnapshots: HistoryOverviewPreparedSnapshots
    let selectedDayFilter: Date?
    let calendarWorkoutCountsByDay: [Date: Int]
    let loadedCalendarMonths: Set<Date>
    let hasMorePages: Bool

    var snapshot: HistoryOverviewSnapshot {
        preparedSnapshots.snapshot(for: selectedDayFilter)
    }
}

nonisolated enum HistoryOverviewSnapshotLoader {
    nonisolated static func load(
        modelContext: ModelContext,
        selectedDayFilter: Date?,
        pageSize: Int
    ) throws -> HistoryOverviewLoadedSnapshot {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        let completedSessions: [HistoryOverviewSessionSnapshot]
        let hasMorePages: Bool
        if let selectedDayFilter {
            completedSessions = try repository
                .completedSessions(onDay: selectedDayFilter)
                .map(HistoryOverviewSessionSnapshot.init(session:))
            hasMorePages = false
        } else {
            let page = try repository
                .completedSessions(before: nil, limit: pageSize + 1)
                .map(HistoryOverviewSessionSnapshot.init(session:))
            completedSessions = Array(page.prefix(pageSize))
            hasMorePages = page.count > pageSize
        }
        let preparedSnapshots = HistoryOverviewSnapshotBuilder.buildPreparedSnapshots(
            sessions: completedSessions
        )
        let calendarMonth = selectedDayFilter ?? completedSessions.first?.displayDate ?? Date()
        let month = startOfMonth(for: calendarMonth)
        let counts = try repository.completedWorkoutCountsByDay(inMonthContaining: month)
        return HistoryOverviewLoadedSnapshot(
            completedSessions: completedSessions,
            preparedSnapshots: preparedSnapshots,
            selectedDayFilter: selectedDayFilter,
            calendarWorkoutCountsByDay: counts,
            loadedCalendarMonths: [month],
            hasMorePages: hasMorePages
        )
    }

    nonisolated static func loadPage(
        modelContext: ModelContext,
        before date: Date,
        pageSize: Int
    ) throws -> HistoryOverviewLoadedSnapshot {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        let page = try repository
            .completedSessions(before: date, limit: pageSize + 1)
            .map(HistoryOverviewSessionSnapshot.init(session:))
        let completedSessions = Array(page.prefix(pageSize))
        let preparedSnapshots = HistoryOverviewSnapshotBuilder.buildPreparedSnapshots(
            sessions: completedSessions
        )
        return HistoryOverviewLoadedSnapshot(
            completedSessions: completedSessions,
            preparedSnapshots: preparedSnapshots,
            selectedDayFilter: nil,
            calendarWorkoutCountsByDay: [:],
            loadedCalendarMonths: [],
            hasMorePages: page.count > pageSize
        )
    }

    nonisolated static func loadWorkoutCountsByDay(
        modelContext: ModelContext,
        month: Date
    ) throws -> [Date: Int] {
        try WorkoutSessionRepository(modelContext: modelContext)
            .completedWorkoutCountsByDay(inMonthContaining: month)
    }

    nonisolated private static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

nonisolated enum HistoryOverviewSnapshotBuilder {
    nonisolated static func build(
        sessions: [HistoryOverviewSessionSnapshot],
        selectedDayFilter: Date?,
        calendar: Calendar = .current
    ) -> HistoryOverviewSnapshot {
        buildPreparedSnapshots(sessions: sessions, calendar: calendar)
            .snapshot(for: selectedDayFilter, calendar: calendar)
    }

    nonisolated static func buildPreparedSnapshots(
        sessions: [HistoryOverviewSessionSnapshot],
        calendar: Calendar = .current
    ) -> HistoryOverviewPreparedSnapshots {
        let completedSessions = sessions

        var workoutCountsByDay: [Date: Int] = [:]
        var sessionsByMonth: [Date: [HistoryOverviewSessionSnapshot]] = [:]
        var sessionsByDayStartAndMonth: [Date: [Date: [HistoryOverviewSessionSnapshot]]] = [:]
        for session in completedSessions {
            let sessionDate = session.displayDate
            let day = startOfDay(for: sessionDate, calendar: calendar)
            workoutCountsByDay[day, default: 0] += 1
            let month = startOfMonth(for: sessionDate, calendar: calendar)
            sessionsByMonth[month, default: []].append(session)
            sessionsByDayStartAndMonth[day, default: [:]][month, default: []].append(session)
        }

        let sectionsByDayStart = Dictionary(
            uniqueKeysWithValues: sessionsByDayStartAndMonth.map { dayStart, sessionsByMonth in
                (dayStart, makeSections(from: sessionsByMonth))
            }
        )

        return HistoryOverviewPreparedSnapshots(
            allSnapshot: HistoryOverviewSnapshot(
                workoutCountsByDay: workoutCountsByDay,
                sections: makeSections(from: sessionsByMonth)
            ),
            sectionsByDayStart: sectionsByDayStart
        )
    }

    nonisolated private static func makeSections(
        from sessionsByMonth: [Date: [HistoryOverviewSessionSnapshot]]
    ) -> [HistoryMonthSection] {
        sessionsByMonth.keys.sorted(by: >).map { key in
            makeSection(
                monthStart: key,
                sessions: sessionsByMonth[key, default: []]
            )
        }
    }

    nonisolated private static func makeSection(
        monthStart: Date,
        sessions: [HistoryOverviewSessionSnapshot]
    ) -> HistoryMonthSection {
        let orderedSessions = sessions.sorted { lhs, rhs in
            lhs.displayDate > rhs.displayDate
        }

        return HistoryMonthSection(
            id: monthStart.formatted(date: .numeric, time: .omitted),
            title: monthStart.formatted(.dateTime.year().month(.wide)),
            cards: orderedSessions.map(makeCardData)
        )
    }

    nonisolated static func build(
        sessions: [WorkoutSession],
        selectedDayFilter: Date?,
        calendar: Calendar = .current
    ) -> HistoryOverviewSnapshot {
        build(
            sessions: sessions
                .filter { $0.status == .completed && $0.archivedAt == nil }
                .map(HistoryOverviewSessionSnapshot.init(session:)),
            selectedDayFilter: selectedDayFilter,
            calendar: calendar
        )
    }

    nonisolated private static func makeCardData(_ session: HistoryOverviewSessionSnapshot) -> HistorySessionCardData {
        HistorySessionCardData(
            id: session.id.uuidString,
            sessionID: session.id,
            updatedAtStamp: session.updatedAt.timeIntervalSinceReferenceDate,
            name: session.name,
            dateText: formattedSessionDate(session),
            durationText: formattedDuration(session.durationSeconds),
            volumeText: formattedVolume(session.totalVolume),
            prsText: "\(session.prHitsCount) PR\(session.prHitsCount == 1 ? "" : "s")",
            summaryRows: session.summaryRows
        )
    }

    nonisolated private static func formattedSessionDate(_ session: HistoryOverviewSessionSnapshot) -> String {
        session.displayDate.formatted(date: .abbreviated, time: .shortened)
    }

    nonisolated private static func formattedDuration(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        }
        return "\(remMins)m"
    }

    nonisolated private static func formattedVolume(_ volume: Double) -> String {
        if volume == 0 {
            return "0 kg"
        }
        return "\(WGJFormatters.integerString(volume)) kg"
    }

    nonisolated private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    nonisolated private static func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
}

extension HistoryOverviewSessionSnapshot {
    nonisolated init(session: WorkoutSession) {
        self.init(
            id: session.id,
            updatedAt: session.updatedAt,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            totalVolume: session.totalVolume,
            prHitsCount: session.prHitsCount,
            summaryRows: HistorySessionSummaryBuilder.rows(for: session)
        )
    }
}

private struct HistorySessionCardView: View, Equatable {
    let card: HistorySessionCardData
    let onArchive: () -> Void

    static func == (lhs: HistorySessionCardView, rhs: HistorySessionCardView) -> Bool {
        lhs.card == rhs.card
    }

    var body: some View {
        NavigationLink {
            HistoryDetailView(sessionID: card.sessionID)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .lineLimit(2)

                        Text(card.dateText)
                            .font(.headline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    Spacer()

                    WGJActionMenuButton("Workout Actions", usesPlainButtonStyle: false) {
                        Button(action: onArchive) {
                            Label("Hide", systemImage: "archivebox")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                    }
                    .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue, background: WGJTheme.field))
                    .foregroundStyle(WGJTheme.accentBlue)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        WGJMetricPill(systemImage: "clock.fill", value: card.durationText)
                        WGJMetricPill(systemImage: "scalemass.fill", value: card.volumeText)
                        WGJMetricPill(systemImage: "trophy.fill", value: card.prsText, tint: WGJTheme.accentGold)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 16) {
                            WGJMetricPill(systemImage: "clock.fill", value: card.durationText)
                            WGJMetricPill(systemImage: "scalemass.fill", value: card.volumeText)
                        }
                        WGJMetricPill(systemImage: "trophy.fill", value: card.prsText, tint: WGJTheme.accentGold)
                    }
                }

                summarySection
            }
            .padding(14)
            .wgjCardContainer(strong: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-session-card")
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                summaryExerciseHeader
                summaryBestSetHeader
            }

            ForEach(card.summaryRows) { row in
                HStack(alignment: .top, spacing: 10) {
                    summaryExerciseValue(row.exercise)
                    summaryBestSetValue(row.bestSet)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryExerciseHeader: some View {
        Text("Exercise")
            .font(.headline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryBestSetHeader: some View {
        Text("Best Set")
            .font(.headline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func summaryExerciseValue(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(WGJTheme.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryBestSetValue(_ value: String) -> some View {
        Text(value)
            .font(.body.weight(.medium))
            .foregroundStyle(WGJTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .fixedSize(horizontal: true, vertical: false)
    }

}

nonisolated enum HistorySessionSummaryBuilder {
    nonisolated static func rows(for session: WorkoutSession) -> [HistorySessionSummaryRow] {
        let exercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return exercises.enumerated().map { index, exercise in
            let sets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            return HistorySessionSummaryRow(
                id: index,
                exercise: "\(sets.count) x \(exercise.exerciseNameSnapshot)",
                bestSet: WorkoutMetricsService.bestSetText(for: sets)
            )
        }
    }
}

nonisolated struct HistorySessionSummaryRow: Identifiable, Equatable, Sendable {
    let id: Int
    let exercise: String
    let bestSet: String
}

private struct HistoryArchivedWorkoutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    @State private var archivedSessions: [ArchivedWorkoutSnapshot] = []
    @State private var pendingDeletion: ArchivedWorkoutDeletionCandidate?
    @State private var errorMessage = ""
    @State private var showingError = false

    private var historyBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if archivedSessions.isEmpty {
                    WGJEmptyStateCard(
                        title: "No hidden workouts",
                        message: "Hidden workouts appear here and can be restored anytime.",
                        icon: "archivebox"
                    )
                } else {
                    ForEach(archivedSessions, id: \.id) { session in
                        archivedSessionCard(session)
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .navigationTitle("Hidden Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Delete hidden workout?",
            isPresented: pendingDeletionPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                guard let pendingDeletion else { return }
                deleteSession(pendingDeletion.id)
            }

            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This permanently removes the workout from history.")
        }
        .task {
            await loadArchivedSessions()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func archivedSessionCard(_ session: ArchivedWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(2)

            Text((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 12) {
                WGJMetricPill(systemImage: "clock.fill", value: formattedDuration(session.durationSeconds))
                WGJMetricPill(systemImage: "scalemass.fill", value: formattedVolume(session.totalVolume))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    restoreWorkoutButton(for: session)
                    deleteWorkoutButton(for: session)
                }

                VStack(spacing: 10) {
                    restoreWorkoutButton(for: session)
                    deleteWorkoutButton(for: session)
                }
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("history-hidden-session-card")
    }

    private var pendingDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private func restoreWorkoutButton(for session: ArchivedWorkoutSnapshot) -> some View {
        Button {
            restoreSession(session.id)
        } label: {
            Label("Restore Workout", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .accessibilityIdentifier("history-hidden-restore-button")
    }

    private func deleteWorkoutButton(for session: ArchivedWorkoutSnapshot) -> some View {
        Button {
            pendingDeletion = ArchivedWorkoutDeletionCandidate(id: session.id)
        } label: {
            Label("Delete Permanently", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJDestructiveButtonStyle())
        .accessibilityIdentifier("history-hidden-delete-button")
    }

    @MainActor
    private func loadArchivedSessions() async {
        do {
            let backgroundStore = historyBackgroundStore
            archivedSessions = try await backgroundStore.perform("history-hidden.snapshot") { backgroundContext in
                try Self.loadArchivedSnapshots(modelContext: backgroundContext)
            }
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func restoreSession(_ sessionID: UUID) {
        let backgroundStore = historyBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-hidden.restore") { backgroundContext in
                    try WorkoutSessionRepository(modelContext: backgroundContext).restoreArchivedSession(id: sessionID)
                }
                await removeArchivedSession(id: sessionID)
            } catch {
                await showError(error)
            }
        }
    }

    private func deleteSession(_ sessionID: UUID) {
        let backgroundStore = historyBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-hidden.delete") { backgroundContext in
                    try WorkoutSessionRepository(modelContext: backgroundContext).deleteSession(id: sessionID)
                }
                await removeDeletedArchivedSession(id: sessionID)
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func removeArchivedSession(id sessionID: UUID) {
        archivedSessions.removeAll { $0.id == sessionID }
    }

    @MainActor
    private func removeDeletedArchivedSession(id sessionID: UUID) {
        archivedSessions.removeAll { $0.id == sessionID }
        pendingDeletion = nil
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    nonisolated private static func loadArchivedSnapshots(
        modelContext: ModelContext
    ) throws -> [ArchivedWorkoutSnapshot] {
        try WorkoutSessionRepository(modelContext: modelContext).archivedSessions().map {
            ArchivedWorkoutSnapshot(
                id: $0.id,
                name: $0.name,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                durationSeconds: $0.durationSeconds,
                totalVolume: $0.totalVolume
            )
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        }
        return "\(remMins)m"
    }

    private func formattedVolume(_ volume: Double) -> String {
        if volume == 0 {
            return "0 kg"
        }
        return "\(WGJFormatters.integerString(volume)) kg"
    }
}

private struct ArchivedWorkoutSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let totalVolume: Double
}

private struct ArchivedWorkoutDeletionCandidate: Identifiable {
    let id: UUID
}

private struct HistoryWorkoutCalendarSheet: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDay: Date?

    let workoutCountsByDay: [Date: Int]
    let isLoadingMonth: Bool
    let onClose: () -> Void

    private let calendar = Calendar.current

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.year().month(.wide))
    }

    private var gridDays: [HistoryCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }

        let monthStart = monthInterval.start
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingSlots = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days = (0..<leadingSlots).map { index in
            HistoryCalendarDay.placeholder("leading-\(displayedMonth.timeIntervalSinceReferenceDate)-\(index)")
        }

        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            days.append(
                HistoryCalendarDay(
                    id: dayStart.formatted(date: .numeric, time: .omitted),
                    date: dayStart,
                    workoutCount: workoutCountsByDay[dayStart, default: 0],
                    isToday: calendar.isDateInToday(dayStart),
                    isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? false
                )
            )
        }

        let trailingPlaceholderCount = (7 - (days.count % 7)) % 7
        for index in 0..<trailingPlaceholderCount {
            days.append(
                .placeholder("trailing-\(displayedMonth.timeIntervalSinceReferenceDate)-\(index)")
            )
        }

        return days
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    Spacer()

                    VStack(spacing: 2) {
                        Text("Workout Calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        HStack(spacing: 8) {
                            Text(monthTitle)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)

                            if isLoadingMonth {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }

                Text("Logged days are highlighted. Darker days have more workouts.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)

                VStack(spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WGJTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(gridDays) { day in
                            calendarDayButton(day)
                        }
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                HStack {
                    Button("Show All") {
                        selectedDay = nil
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    Spacer()

                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
            }
            .padding(16)
        }
        .wgjSheetSurface()
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    onClose()
                }
            }
        }
    }

    @ViewBuilder
    private func calendarDayButton(_ day: HistoryCalendarDay) -> some View {
        if let date = day.date {
            Button {
                if let selectedDay, calendar.isDate(selectedDay, inSameDayAs: date) {
                    self.selectedDay = nil
                } else {
                    selectedDay = date
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dayBackground(for: day))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(dayBorder(for: day), lineWidth: day.isToday ? 1.4 : 1)
                        }

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Text("\(calendar.component(.day, from: date))")
                            .font(.headline.weight(day.isSelected ? .bold : .semibold))
                            .foregroundStyle(day.isSelected ? WGJTheme.textInverse : WGJTheme.textPrimary)

                        Spacer(minLength: 0)

                        if day.workoutCount > 0 {
                            Capsule(style: .continuous)
                                .fill(day.isSelected ? WGJTheme.textInverse : workoutMarkerColor(for: day))
                                .frame(width: workoutMarkerWidth(for: day), height: 6)
                                .padding(.bottom, 8)
                        } else {
                            Color.clear
                                .frame(height: 14)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: day, date: date))
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private func dayBackground(for day: HistoryCalendarDay) -> Color {
        if day.isSelected {
            return WGJTheme.accentBlue.opacity(0.92)
        }
        switch activityLevel(for: day.workoutCount) {
        case 4:
            return WGJTheme.accentBlue.opacity(0.46)
        case 3:
            return WGJTheme.accentBlue.opacity(0.34)
        case 2:
            return WGJTheme.accentBlue.opacity(0.22)
        case 1:
            return WGJTheme.accentBlue.opacity(0.12)
        default:
            return WGJTheme.field.opacity(0.54)
        }
    }

    private func dayBorder(for day: HistoryCalendarDay) -> Color {
        if day.isSelected {
            return Color.white.opacity(0.18)
        }
        if day.isToday {
            return WGJTheme.accentCyan.opacity(0.42)
        }
        switch activityLevel(for: day.workoutCount) {
        case 4:
            return WGJTheme.accentBlue.opacity(0.54)
        case 3:
            return WGJTheme.accentBlue.opacity(0.46)
        case 2:
            return WGJTheme.accentBlue.opacity(0.38)
        case 1:
            return WGJTheme.accentBlue.opacity(0.28)
        default:
            return WGJTheme.outline.opacity(0.68)
        }
    }

    private func moveMonth(by value: Int) {
        guard let moved = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        let components = calendar.dateComponents([.year, .month], from: moved)
        displayedMonth = calendar.date(from: components) ?? moved
    }

    private func activityLevel(for workoutCount: Int) -> Int {
        switch workoutCount {
        case ...0:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        case 3:
            return 3
        default:
            return 4
        }
    }

    private func workoutMarkerColor(for day: HistoryCalendarDay) -> Color {
        switch activityLevel(for: day.workoutCount) {
        case 4:
            return WGJTheme.accentBlue
        case 3:
            return WGJTheme.accentBlue.opacity(0.86)
        case 2:
            return WGJTheme.accentBlue.opacity(0.74)
        default:
            return WGJTheme.accentBlue.opacity(0.62)
        }
    }

    private func workoutMarkerWidth(for day: HistoryCalendarDay) -> CGFloat {
        switch activityLevel(for: day.workoutCount) {
        case 4:
            return 22
        case 3:
            return 18
        case 2:
            return 14
        default:
            return 10
        }
    }

    private func accessibilityLabel(for day: HistoryCalendarDay, date: Date) -> String {
        var parts = [date.formatted(date: .complete, time: .omitted)]
        if day.workoutCount > 0 {
            parts.append(day.workoutCount == 1 ? "1 workout logged" : "\(day.workoutCount) workouts logged")
        } else {
            parts.append("No workouts logged")
        }
        if day.isToday {
            parts.append("Today")
        }
        if day.isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }
}

private struct HistoryCalendarDay: Identifiable {
    let id: String
    let date: Date?
    let workoutCount: Int
    let isToday: Bool
    let isSelected: Bool

    static func placeholder(_ id: String) -> HistoryCalendarDay {
        HistoryCalendarDay(id: id, date: nil, workoutCount: 0, isToday: false, isSelected: false)
    }
}

#Preview {
    NavigationStack {
        HistoryOverviewView()
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
