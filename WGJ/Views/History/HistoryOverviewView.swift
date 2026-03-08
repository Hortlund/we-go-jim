import Foundation
import SwiftData
import SwiftUI

struct HistoryOverviewView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)])
    private var sessions: [WorkoutSession]

    @State private var selectedMonthFilter: Date?
    @State private var showingMonthPicker = false
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
                        showingMonthPicker = true
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }

                if let selectedMonthFilter {
                    Text(selectedMonthFilter.formatted(.dateTime.year().month(.wide)).uppercased())
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                if renderedSections.isEmpty {
                    WGJEmptyStateCard(
                        title: "No completed workouts yet",
                        message: "Finish an active session to build up your history.",
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
        .sheet(isPresented: $showingMonthPicker) {
            monthPickerSheet
        }
        .task(id: sessionsVersionKey) {
            recomputeMonthSections()
        }
        .onChange(of: selectedMonthFilter) { _, _ in
            recomputeMonthSections()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var monthPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WGJSectionHeader("Filter by Month")

                    DatePicker(
                        "Month",
                        selection: Binding(
                            get: { selectedMonthFilter ?? Date() },
                            set: { selectedMonthFilter = startOfMonth(for: $0) }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button("Show All") {
                            selectedMonthFilter = nil
                            showingMonthPicker = false
                        }
                        .buttonStyle(WGJGhostButtonStyle())

                        Spacer()

                        Button("Apply") {
                            showingMonthPicker = false
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                    }
                }
                .padding(16)
            }
            .wgjSheetSurface()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
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

    private func recomputeMonthSections() {
        let completedSessions = sessions.filter { $0.status == .completed }
        let filtered = completedSessions.filter { session in
            guard let selectedMonthFilter else { return true }
            return startOfMonth(for: session.endedAt ?? session.startedAt) == selectedMonthFilter
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
        return value.formatted(date: .complete, time: .omitted)
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

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
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
