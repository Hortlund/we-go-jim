import Foundation
import SwiftData
import SwiftUI

struct HistoryOverviewView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)])
    private var sessions: [WorkoutSession]

    @State private var selectedDayFilter: Date?
    @State private var showingWorkoutCalendar = false
    @State private var displayedCalendarMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var renderedSections: [HistoryMonthSection] = []
    @State private var errorMessage = ""
    @State private var showingError = false

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("History", subtitle: "Review completed sessions, volume, and best sets.") {
                    Button("Calendar") {
                        openWorkoutCalendar()
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }

                if let selectedDayFilter {
                    selectedDayFilterCard(selectedDayFilter)
                }

                if renderedSections.isEmpty {
                    WGJEmptyStateCard(
                        title: selectedDayFilter == nil ? "No completed workouts yet" : "No workouts on this day",
                        message: selectedDayFilter == nil
                            ? "Finish an active session to build up your history."
                            : "Pick another logged day in the calendar or clear the filter.",
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                }

                ForEach(renderedSections) { section in
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
        .task(id: sessionsVersionKey) {
            recomputeMonthSections()
        }
        .onChange(of: selectedDayFilter) { _, _ in
            recomputeMonthSections()
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
                workoutCountsByDay: workoutCountsByDay,
                onClose: { showingWorkoutCalendar = false }
            )
        }
        .presentationDetents([.large])
    }

    private func historyCard(_ card: HistorySessionCardData) -> some View {
        NavigationLink {
            HistoryDetailView(sessionID: card.sessionID)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .lineLimit(1)

                        Text(card.dateText)
                            .font(.headline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    Spacer()

                    Menu {
                        Button(role: .destructive) {
                            deleteSession(card.sessionID)
                        } label: {
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
                    .buttonStyle(.plain)
                    .foregroundStyle(WGJTheme.accentBlue)
                }

                HStack(spacing: 16) {
                    WGJMetricPill(systemImage: "clock.fill", value: card.durationText)
                    WGJMetricPill(systemImage: "scalemass.fill", value: card.volumeText)
                    WGJMetricPill(systemImage: "trophy.fill", value: card.prsText, tint: WGJTheme.accentGold)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exercise")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        ForEach(Array(card.exerciseRows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                                .font(.body)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Best Set")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        ForEach(Array(card.bestSetRows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                                .font(.body)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .wgjCardContainer(strong: true)
        }
        .buttonStyle(.plain)
    }

    private var sessionsVersionKey: [String] {
        sessions.map {
            "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.status.rawValue)"
        }
    }

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    private var workoutCountsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for session in completedSessions {
            let day = startOfDay(for: session.endedAt ?? session.startedAt)
            counts[day, default: 0] += 1
        }
        return counts
    }

    private func recomputeMonthSections() {
        let filtered = completedSessions.filter { session in
            guard let selectedDayFilter else { return true }
            return startOfDay(for: session.endedAt ?? session.startedAt) == startOfDay(for: selectedDayFilter)
        }

        let grouped = Dictionary(grouping: filtered) { session in
            startOfMonth(for: session.endedAt ?? session.startedAt)
        }

        renderedSections = grouped.keys.sorted(by: >).map { key in
            let orderedSessions = grouped[key, default: []].sorted { lhs, rhs in
                (lhs.endedAt ?? lhs.startedAt) > (rhs.endedAt ?? rhs.startedAt)
            }

            return HistoryMonthSection(
                id: key.formatted(date: .numeric, time: .omitted),
                title: key.formatted(.dateTime.year().month(.wide)),
                cards: orderedSessions.map(makeCardData)
            )
        }
    }

    private func makeCardData(_ session: WorkoutSession) -> HistorySessionCardData {
        HistorySessionCardData(
            id: session.id.uuidString,
            sessionID: session.id,
            name: session.name,
            dateText: formattedSessionDate(session),
            durationText: formattedDuration(session.durationSeconds),
            volumeText: formattedVolume(session.totalVolume),
            prsText: "\(session.prHitsCount) PRs",
            exerciseRows: exerciseSummaryRows(for: session),
            bestSetRows: bestSetSummaryRows(for: session)
        )
    }

    private func formattedSessionDate(_ session: WorkoutSession) -> String {
        let value = session.endedAt ?? session.startedAt
        return value.formatted(date: .abbreviated, time: .shortened)
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
        let text = WGJFormatters.integerString(volume)
        return "\(text) kg"
    }

    private func exerciseSummaryRows(for session: WorkoutSession) -> [String] {
        let exercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return exercises.prefix(6).map { exercise in
            let count = (exercise.sets ?? []).count
            return "\(count) x \(exercise.exerciseNameSnapshot)"
        }
    }

    private func bestSetSummaryRows(for session: WorkoutSession) -> [String] {
        let exercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
        return exercises.prefix(6).map { exercise in
            bestSetLine(for: exercise)
        }
    }

    private func bestSetLine(for exercise: WorkoutSessionExercise) -> String {
        let sets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var bestScore = -1.0
        var bestLine = "-"

        for set in sets {
            let reps = set.actualReps ?? set.targetReps
            let weight = set.actualWeight ?? set.targetWeight
            let unit = set.actualWeight != nil ? set.actualLoadUnit : set.targetLoadUnit

            if let reps, let weight {
                let score = weight * Double(max(1, reps))
                if score > bestScore {
                    bestScore = score
                    bestLine = "\(formatWeight(weight)) \(unit.shortLabel) x \(reps)"
                }
            } else if let reps, bestScore < 0 {
                bestLine = "\(reps) reps"
            }
        }

        return bestLine
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
    }

    private func openWorkoutCalendar() {
        let referenceDate = selectedDayFilter
            ?? completedSessions.first.map { $0.endedAt ?? $0.startedAt }
            ?? Date()
        displayedCalendarMonth = startOfMonth(for: referenceDate)
        showingWorkoutCalendar = true
    }

    private func selectedDayFilterCard(_ day: Date) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Text("\(workoutCountsByDay[startOfDay(for: day), default: 0]) logged workout\(workoutCountsByDay[startOfDay(for: day), default: 0] == 1 ? "" : "s")")
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
            try sessionRepository.deleteSession(id: id)
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }
}

private struct HistoryMonthSection: Identifiable {
    let id: String
    let title: String
    let cards: [HistorySessionCardData]
}

private struct HistorySessionCardData: Identifiable {
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

        while !days.isEmpty && days.count % 7 != 0 {
            days.append(.placeholder(UUID().uuidString))
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

                Text("Select a day to filter history. Badges show how many workouts were logged on that date.")
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
                VStack(spacing: 6) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.subheadline.weight(day.isSelected ? .bold : .semibold))
                        .foregroundStyle(day.isSelected ? WGJTheme.textInverse : WGJTheme.textPrimary)

                    if day.workoutCount > 0 {
                        Text(day.workoutCount == 1 ? "1 workout" : "\(day.workoutCount) workouts")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(day.isSelected ? WGJTheme.textInverse : WGJTheme.accentBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dayBackground(for: day))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(dayBorder(for: day), lineWidth: day.isToday ? 1.4 : 1)
                        }
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 58)
        }
    }

    private func dayBackground(for day: HistoryCalendarDay) -> Color {
        if day.isSelected {
            return WGJTheme.accentBlue.opacity(0.92)
        }
        if day.workoutCount > 0 {
            return WGJTheme.accentBlue.opacity(0.12)
        }
        return WGJTheme.field.opacity(0.54)
    }

    private func dayBorder(for day: HistoryCalendarDay) -> Color {
        if day.isSelected {
            return Color.white.opacity(0.18)
        }
        if day.isToday {
            return WGJTheme.accentCyan.opacity(0.42)
        }
        if day.workoutCount > 0 {
            return WGJTheme.accentBlue.opacity(0.28)
        }
        return WGJTheme.outline.opacity(0.68)
    }

    private func moveMonth(by value: Int) {
        guard let moved = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        let components = calendar.dateComponents([.year, .month], from: moved)
        displayedMonth = calendar.date(from: components) ?? moved
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
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
