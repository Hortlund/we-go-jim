import Foundation
import SwiftData
import SwiftUI

struct HistoryOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive

    @State private var selectedDayFilter: Date?
    @State private var showingWorkoutCalendar = false
    @State private var displayedCalendarMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var controller = HistoryOverviewController()
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("History", subtitle: "Review completed sessions, volume, and best sets.") {
                    Button("Calendar") {
                        openWorkoutCalendar()
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .accessibilityIdentifier("history-calendar-button")
                }

                if let selectedDayFilter {
                    selectedDayFilterCard(selectedDayFilter)
                }

                if controller.snapshot.sections.isEmpty {
                    WGJEmptyStateCard(
                        title: selectedDayFilter == nil ? "No completed workouts yet" : "No workouts on this day",
                        message: selectedDayFilter == nil
                            ? "Finish an active session to build up your history."
                            : "Pick another logged day in the calendar or clear the filter.",
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                }

                ForEach(controller.snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title.uppercased())
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        ForEach(section.cards) { card in
                            historyCard(card)
                        }
                    }
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
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadSnapshot()
        }
        .onChange(of: selectedDayFilter) { _, _ in
            recomputeSnapshot()
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
                workoutCountsByDay: controller.snapshot.workoutCountsByDay,
                onClose: { showingWorkoutCalendar = false }
            )
        }
        .presentationDetents([.large])
    }

    private func historyCard(_ card: HistorySessionCardData) -> some View {
        HistorySessionCardView(card: card) {
            deleteSession(card.sessionID)
        }
        .equatable()
    }

    private func recomputeSnapshot() {
        controller.snapshot = HistoryOverviewSnapshotBuilder.build(
            sessions: controller.completedSessions,
            selectedDayFilter: selectedDayFilter
        )
    }

    private func openWorkoutCalendar() {
        let referenceDate = selectedDayFilter
            ?? controller.completedSessions.first.map { $0.endedAt ?? $0.startedAt }
            ?? Date()
        displayedCalendarMonth = startOfMonth(for: referenceDate)
        showingWorkoutCalendar = true
    }

    private func selectedDayFilterCard(_ day: Date) -> some View {
        let dayStart = startOfDay(for: day)
        let workoutCount = controller.snapshot.workoutCountsByDay[dayStart, default: 0]

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

    private func deleteSession(_ id: UUID) {
        do {
            try WorkoutSessionRepository(modelContext: modelContext).deleteSession(id: id)
            Task {
                await reloadSnapshot()
            }
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    @MainActor
    private func reloadSnapshot() async {
        do {
            try controller.reload(modelContext: modelContext)
            recomputeSnapshot()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }
}

struct HistoryMonthSection: Identifiable {
    let id: String
    let title: String
    let cards: [HistorySessionCardData]
}

struct HistorySessionCardData: Identifiable, Equatable {
    let id: String
    let sessionID: UUID
    let name: String
    let dateText: String
    let durationText: String
    let volumeText: String
    let prsText: String
    let exerciseRows: [String]
    let bestSetRows: [String]
}

struct HistoryOverviewSnapshot {
    let workoutCountsByDay: [Date: Int]
    let sections: [HistoryMonthSection]

    static let empty = HistoryOverviewSnapshot(
        workoutCountsByDay: [:],
        sections: []
    )
}

struct HistorySessionDataStamp: Hashable {
    let completedSessionCount: Int
    let latestCompletedSessionUpdate: TimeInterval

    init(sessions: [WorkoutSession]) {
        var count = 0
        var latestUpdate = 0.0

        for session in sessions where session.status == .completed {
            count += 1
            latestUpdate = max(latestUpdate, session.updatedAt.timeIntervalSinceReferenceDate)
        }

        completedSessionCount = count
        latestCompletedSessionUpdate = latestUpdate
    }
}

@MainActor
@Observable
final class HistoryOverviewController {
    var completedSessions: [WorkoutSession] = []
    var snapshot = HistoryOverviewSnapshot.empty

    func reload(modelContext: ModelContext) throws {
        completedSessions = try WorkoutSessionRepository(modelContext: modelContext).completedSessions()
        snapshot = HistoryOverviewSnapshotBuilder.build(
            sessions: completedSessions,
            selectedDayFilter: nil
        )
    }
}

@MainActor
enum HistoryOverviewSnapshotBuilder {
    static func build(
        sessions: [WorkoutSession],
        selectedDayFilter: Date?,
        calendar: Calendar = .current
    ) -> HistoryOverviewSnapshot {
        let completedSessions = sessions.filter { $0.status == .completed }
        let selectedDayStart = selectedDayFilter.map { startOfDay(for: $0, calendar: calendar) }

        var workoutCountsByDay: [Date: Int] = [:]
        var sessionsByMonth: [Date: [WorkoutSession]] = [:]
        for session in completedSessions {
            let sessionDate = session.endedAt ?? session.startedAt
            let day = startOfDay(for: sessionDate, calendar: calendar)
            workoutCountsByDay[day, default: 0] += 1
            let shouldIncludeSession = selectedDayStart.map { $0 == day } ?? true
            if shouldIncludeSession {
                let month = startOfMonth(for: sessionDate, calendar: calendar)
                sessionsByMonth[month, default: []].append(session)
            }
        }

        let sections = sessionsByMonth.keys.sorted(by: >).map { key in
            let orderedSessions = sessionsByMonth[key, default: []].sorted { lhs, rhs in
                (lhs.endedAt ?? lhs.startedAt) > (rhs.endedAt ?? rhs.startedAt)
            }

            return HistoryMonthSection(
                id: key.formatted(date: .numeric, time: .omitted),
                title: key.formatted(.dateTime.year().month(.wide)),
                cards: orderedSessions.map(makeCardData)
            )
        }

        return HistoryOverviewSnapshot(
            workoutCountsByDay: workoutCountsByDay,
            sections: sections
        )
    }

    private static func makeCardData(_ session: WorkoutSession) -> HistorySessionCardData {
        let summary = summaryRows(for: session)

        return HistorySessionCardData(
            id: session.id.uuidString,
            sessionID: session.id,
            name: session.name,
            dateText: formattedSessionDate(session),
            durationText: formattedDuration(session.durationSeconds),
            volumeText: formattedVolume(session.totalVolume),
            prsText: "\(session.prHitsCount) PRs",
            exerciseRows: summary.exerciseRows,
            bestSetRows: summary.bestSetRows
        )
    }

    private static func formattedSessionDate(_ session: WorkoutSession) -> String {
        let value = session.endedAt ?? session.startedAt
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        }
        return "\(remMins)m"
    }

    private static func formattedVolume(_ volume: Double) -> String {
        if volume == 0 {
            return "0 kg"
        }
        return "\(WGJFormatters.integerString(volume)) kg"
    }

    private static func summaryRows(for session: WorkoutSession) -> (exerciseRows: [String], bestSetRows: [String]) {
        let exercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var exerciseRows: [String] = []
        var bestSetRows: [String] = []
        exerciseRows.reserveCapacity(min(6, exercises.count))
        bestSetRows.reserveCapacity(min(6, exercises.count))

        for exercise in exercises.prefix(6) {
            let sets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            exerciseRows.append("\(sets.count) x \(exercise.exerciseNameSnapshot)")
            bestSetRows.append(bestSetLine(for: sets))
        }

        return (exerciseRows, bestSetRows)
    }

    private static func bestSetLine(for sets: [WorkoutSessionSet]) -> String {
        WorkoutMetricsService.bestSetText(for: sets)
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
}

private struct HistorySessionCardView: View, Equatable {
    let card: HistorySessionCardData
    let onDelete: () -> Void

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

                    WGJActionMenuButton("Workout Actions") {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(WGJTheme.field)
                            )
                    }
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
    }

    private var summaryRows: [HistorySessionSummaryRow] {
        let rowCount = max(card.exerciseRows.count, card.bestSetRows.count)

        return (0..<rowCount).map { index in
            HistorySessionSummaryRow(
                id: index,
                exercise: card.exerciseRows.indices.contains(index) ? card.exerciseRows[index] : "-",
                bestSet: card.bestSetRows.indices.contains(index) ? card.bestSetRows[index] : "-"
            )
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                summaryExerciseHeader
                summaryBestSetHeader
            }

            ForEach(summaryRows) { row in
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

private struct HistorySessionSummaryRow: Identifiable {
    let id: Int
    let exercise: String
    let bestSet: String
}

private struct HistoryWorkoutCalendarSheet: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDay: Date?

    let workoutCountsByDay: [Date: Int]
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

                        Text(monthTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
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

                Text("Select a day to filter history. Heatmap shading marks logged days, and deeper color means more workouts.")
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
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
