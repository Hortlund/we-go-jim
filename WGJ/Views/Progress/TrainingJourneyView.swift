import Charts
import SwiftData
import SwiftUI

struct TrainingJourneyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrationID: UUID?
    @State private var snapshot: TrainingJourneySnapshot?
    @State private var selectedYear: Date?
    @State private var selectedMonth: JourneyMonth?
    @State private var filter = JourneyFilter.all
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var loadGeneration = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let snapshot, snapshot.workoutCount > 0 {
                    JourneyLifetimeSummary(snapshot: snapshot)
                    TrainingYearRecapEntryView(snapshot: snapshot, selectedYearID: selectedYear)
                    calendarSection(snapshot)
                    JourneyInsightsSection(snapshot: snapshot)
                    JourneyTimeline(milestones: snapshot.milestones, filter: $filter)
                } else if let snapshot {
                    WGJEmptyStateCard(title: "Your story starts here",
                        message: "Finish your first workout to start your journey. Every session becomes part of the bigger picture.",
                        icon: "sparkles")
                    JourneyInsightsSection(snapshot: snapshot)
                } else if let errorMessage {
                    WGJEmptyStateCard(title: "Couldn't load your journey", message: errorMessage,
                        icon: "exclamationmark.circle") {
                        Button("Try Again") { loadID = UUID() }.buttonStyle(WGJPrimaryButtonStyle())
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .overlay {
            if let celebrationID, !reduceMotion { JourneyConfetti(token: celebrationID) }
        }
        .onDisappear { celebrationID = nil }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Your Journey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let snapshot, snapshot.workoutCount > 0 { yearPicker(snapshot) }
            }
        }
        .accessibilityIdentifier("training-journey-screen")
        .task(id: loadID) { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .wgjWorkoutHistoryDidChange)) { _ in loadID = UUID() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadID = UUID() }
        }
        .sheet(item: $selectedMonth) { month in
            JourneyMonthDetail(month: month)
        }
    }

    private func calendarSection(_ snapshot: TrainingJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Days you showed up").font(.title3.bold())
            if let year = snapshot.years.first(where: { $0.id == selectedYear }) ?? snapshot.years.first {
                JourneyYearCalendar(year: year) { selectedMonth = $0 }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { calendarLegend }
                VStack(alignment: .leading, spacing: 8) { calendarLegend }
            }
            Text("Tap a month to explore your workouts.")
                .font(.caption).foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private func yearPicker(_ snapshot: TrainingJourneySnapshot) -> some View {
        Menu {
            ForEach(snapshot.years) { year in
                Button(year.title) { selectedYear = year.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text((snapshot.years.first { $0.id == selectedYear } ?? snapshot.years.first)?.title ?? "")
                Image(systemName: "chevron.down").font(.caption.bold())
            }.font(.subheadline.bold()).foregroundStyle(WGJTheme.accentBlue)
        }.accessibilityLabel("Calendar year")
            .accessibilityIdentifier("journey-year-picker")
    }

    @ViewBuilder private var calendarLegend: some View {
        legend("Strength", color: WGJTheme.accentBlue)
        legend("Cardio", color: WGJTheme.accentCyan)
        legend("Mixed", color: WGJTheme.accentGold)
    }

    private func legend(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(WGJTheme.textSecondary)
        }
    }

    @MainActor private func load() async {
        let requestID = UUID()
        loadGeneration = requestID
        let store = appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
        do {
            let loaded = try await store.performRead("training-journey.load") { context in
                try TrainingJourneyLoader.load(context: context)
            }
            guard !Task.isCancelled, requestID == loadGeneration else { return }
            snapshot = loaded
            let newMilestones = JourneyCelebrationPreferences().claim(loaded.milestones, scope: loaded.celebrationScope)
            if newMilestones > 0 && !reduceMotion { celebrationID = UUID() }
            if !loaded.years.contains(where: { $0.id == selectedYear }) { selectedYear = loaded.years.first?.id }
            if let month = selectedMonth {
                selectedMonth = loaded.years.flatMap(\.months).first { $0.id == month.id }
            }
            errorMessage = nil
        } catch is CancellationError { } catch {
            guard !Task.isCancelled, requestID == loadGeneration else { return }
            errorMessage = String(localized: "Your workout history couldn't be read. Please try again.")
        }
    }
}

private struct JourneyLifetimeSummary: View {
    let snapshot: TrainingJourneySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EVERY SESSION ADDS UP")
                    .font(.caption.weight(.bold)).tracking(2).foregroundStyle(WGJTheme.accentCyan)
                Text("Look how far you've come.").font(.largeTitle.bold())
                if let first = snapshot.firstWorkoutDate {
                    Text("Training since \(first.formatted(.dateTime.month(.wide).year()))")
                        .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 22) {
                stat(snapshot.workoutCount.formatted(), title: "Workouts", icon: "dumbbell.fill")
                stat(JourneyFormatting.time(snapshot.durationSeconds), title: "Training time", icon: "clock.fill")
                stat(snapshot.activeDays.formatted(), title: "Active days", icon: "calendar")
                stat(JourneyFormatting.distance(snapshot.walkRunDistanceMeters, unit: snapshot.distanceUnit),
                    title: "Walking & running", icon: "figure.run")
                stat(JourneyFormatting.distance(snapshot.otherCardioDistanceMeters, unit: snapshot.distanceUnit),
                    title: "Cycling & other cardio", icon: "bicycle")
                stat(snapshot.milestones.filter { $0.personalRecord != nil }.count.formatted(),
                    title: "Journey PRs", icon: "trophy.fill")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [WGJTheme.accentBlue.opacity(0.15), WGJTheme.card],
                    startPoint: .topTrailing, endPoint: .bottomLeading))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(WGJTheme.outline.opacity(0.5)))
        }
    }

    private func stat(_ value: String, title: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title.bold()).foregroundStyle(WGJTheme.textPrimary)
            Label(title, systemImage: icon).font(.caption).foregroundStyle(WGJTheme.textSecondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct JourneyYearCalendar: View {
    let year: JourneyYear
    let onSelect: (JourneyMonth) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: 20) {
            ForEach(year.months) { month in
                Button { onSelect(month) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(month.date.formatted(.dateTime.month(.abbreviated)))
                            .font(.caption.bold()).foregroundStyle(WGJTheme.textPrimary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                            ForEach(0..<42, id: \.self) { index in
                                let dayIndex = index - month.leadingDays
                                let day = month.days.indices.contains(dayIndex) ? month.days[dayIndex] : nil
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(day.map(dayColor) ?? .clear)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                        Text("\(month.activeDays) active days")
                            .font(.caption2).foregroundStyle(WGJTheme.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(month.date.formatted(.dateTime.month(.wide).year())), \(month.workouts.count) workouts, \(month.activeDays) active days")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this month's workouts")
                .accessibilityIdentifier("journey-month-\(Calendar.current.component(.month, from: month.date))")
            }
        }
    }

    private func dayColor(_ day: JourneyDay) -> Color {
        guard day.workoutCount > 0 else { return WGJTheme.fieldStrong }
        if day.hasStrength && day.hasCardio { return WGJTheme.accentGold }
        return day.hasCardio ? WGJTheme.accentCyan : WGJTheme.accentBlue
    }
}

private enum JourneyFilter: String, CaseIterable, Identifiable {
    case all = "All", records = "PRs", strength = "Strength", cardio = "Cardio", milestones = "Milestones"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .records: String(localized: "PRs")
        case .strength: String(localized: "Strength")
        case .cardio: String(localized: "Cardio")
        case .milestones: String(localized: "Milestones")
        }
    }
    func includes(_ event: JourneyMilestone) -> Bool {
        switch self {
        case .all: true
        case .records: event.personalRecord != nil
        case .strength: event.kind == .strength
        case .cardio: event.kind == .cardio
        case .milestones: event.kind != .strength && event.kind != .cardio
        }
    }
}

private struct JourneyTimeline: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let milestones: [JourneyMilestone]
    @Binding var filter: JourneyFilter
    @State private var expandedDays: Set<Date> = []
    private var groups: [(date: Date, events: [JourneyMilestone])] {
        Dictionary(grouping: milestones.filter(filter.includes), by: { Calendar.current.startOfDay(for: $0.date) })
            .map { (date: $0.key, events: $0.value) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let groups = groups
        LazyVStack(alignment: .leading, spacing: 18) {
            Text("The moments that matter").font(.title3.bold())
            if dynamicTypeSize.isAccessibilitySize {
                WGJActionMenuButton(String(localized: "Show moments")) {
                    ForEach(JourneyFilter.allCases) { item in
                        Button(item.title) { filter = item }
                    }
                } label: {
                    Label(filter.title, systemImage: "chevron.down").padding(.vertical, 10)
                }
                    .foregroundStyle(WGJTheme.accentCyan)
                    .accessibilityLabel("Show moments").accessibilityValue(filter.title)
                    .accessibilityIdentifier("journey-filter-picker")
            } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JourneyFilter.allCases) { item in
                        Button { filter = item } label: {
                            Text(item.title).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(filter == item ? WGJTheme.textInverse : WGJTheme.textPrimary)
                                .background(filter == item ? WGJTheme.accentCyan : WGJTheme.fieldStrong, in: Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(filter == item ? .isSelected : [])
                            .accessibilityIdentifier("journey-filter-\(item.rawValue)")
                    }
                }
            }
            }
            if groups.isEmpty {
                Text("Your next milestone is still ahead. Keep showing up.")
                    .font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            }
            ForEach(Array(groups.enumerated()), id: \.element.date) { index, group in
                let day = group.date
                let events = group.events
                let sessions = Dictionary(grouping: events, by: \.sessionID).values.sorted {
                    let left = $0.first!, right = $1.first!
                    return left.date == right.date ? left.sessionID.uuidString < right.sessionID.uuidString : left.date > right.date
                }
                if index == 0 || Calendar.current.component(.year, from: groups[index - 1].date) != Calendar.current.component(.year, from: day) {
                    Text(day.formatted(.dateTime.year())).font(.title2.bold()).padding(.top, 8)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle().fill(WGJTheme.accentCyan).frame(width: 9, height: 9)
                        Rectangle().fill(WGJTheme.outline).frame(width: 1).frame(maxHeight: .infinity)
                    }.frame(width: 10).padding(.top, 5).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(day.formatted(.dateTime.day().month(.wide)))
                            .font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.textSecondary)
                        ForEach(expandedDays.contains(day) ? sessions : Array(sessions.prefix(3)), id: \.first!.sessionID) { moments in
                            JourneySessionMoments(events: moments)
                        }
                        if sessions.count > 3 {
                            Button(expandedDays.contains(day) ? String(localized: "Show less") : String(localized: "Show all \(sessions.count) workouts")) {
                                if expandedDays.contains(day) { expandedDays.remove(day) } else { expandedDays.insert(day) }
                            }.font(.subheadline).foregroundStyle(WGJTheme.accentBlue)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct JourneySessionMoments: View {
    let events: [JourneyMilestone]
    @State private var expanded = false

    private var ordered: [JourneyMilestone] {
        events.sorted {
            if ($0.personalRecord != nil) != ($1.personalRecord != nil) { return $0.personalRecord != nil }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if events.count > 1 {
                Text("\(events.count) moments from this workout")
                    .font(.subheadline.weight(.medium)).foregroundStyle(WGJTheme.textSecondary)
            }
            ForEach(expanded ? ordered : Array(ordered.prefix(3))) { event in
                JourneyMilestoneRow(event: event)
            }
            if events.count > 3 {
                Button(expanded ? String(localized: "Show less") : String(localized: "Show all \(events.count) moments")) {
                    expanded.toggle()
                }.font(.subheadline).foregroundStyle(WGJTheme.accentBlue)
            }
        }
    }
}

struct JourneyMilestoneRow: View {
    let event: JourneyMilestone
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                HistoryDetailView(sessionID: event.sessionID)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: event.kind.systemImage).foregroundStyle(WGJTheme.accentCyan).frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        if let caption = event.playfulTitle {
                            Text(caption).font(.caption.weight(.medium)).foregroundStyle(WGJTheme.accentBlue)
                        }
                        Text(event.title).font(.headline).foregroundStyle(WGJTheme.textPrimary)
                        Text(event.detail).font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                }
            }.buttonStyle(.plain).accessibilityHint("Opens the original workout")
                .accessibilityIdentifier("journey-milestone-\(event.kind.rawValue)")
            if event.chart.count > 1 {
                Chart(event.chart) { point in
                    LineMark(x: .value("Date", point.date), y: .value(event.chartUnit ?? "Weight", point.value))
                        .foregroundStyle(WGJTheme.accentBlue).lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) {
                        AxisValueLabel().foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 65)
                .accessibilityLabel("\(event.title). \(event.detail)")
            }
            if let record = event.personalRecord {
                PersonalRecordShareButton(record: record, achievedAtText: event.date.formatted(date: .abbreviated, time: .shortened), playfulTitle: event.playfulTitle)
            } else {
                JourneyMilestoneShareButton(event: event)
            }
            if let activityID = event.activityID {
                JourneyRoutePreview(sessionID: event.sessionID, activityID: activityID)
            }
        }.padding(16).wgjCardContainer()
    }
}

private struct JourneyRoutePreview: View {
    let sessionID: UUID
    let activityID: UUID
    @State private var route: CardioRoute?
    var body: some View {
        Group {
            if let route {
                CardioRouteMap(route: route).frame(height: 150).allowsHitTesting(false)
            }
        }.task(id: activityID) {
            guard let saved = try? await CardioRouteStore.shared.load(activityID: activityID),
                  saved.sessionID == sessionID, saved.activityID == activityID,
                  !saved.isRecording, !saved.points.isEmpty, !Task.isCancelled else { route = nil; return }
            route = saved
        }
    }
}

private struct JourneyMonthDetail: View {
    let month: JourneyMonth
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(month.workouts.count) workouts · \(month.activeDays) active days")
                        .font(.title3.bold())
                    if month.workouts.isEmpty {
                        Text("No workouts recorded this month.").foregroundStyle(WGJTheme.textSecondary)
                    } else {
                        Chart(month.days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Workouts", day.workoutCount))
                                .foregroundStyle(WGJTheme.accentBlue)
                        }.frame(height: 160).accessibilityLabel("Workouts per day")
                        ForEach(month.workouts.sorted { $0.date > $1.date }) { workout in
                            NavigationLink {
                                HistoryDetailView(sessionID: workout.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: workout.hasCardio && !workout.hasStrength ? "figure.run" : "dumbbell.fill")
                                        .foregroundStyle(WGJTheme.accentBlue)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(workout.name).font(.headline).foregroundStyle(WGJTheme.textPrimary)
                                        Text("\(workout.date.formatted(date: .abbreviated, time: .shortened)) · \(JourneyFormatting.time(workout.durationSeconds))")
                                            .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                                }.padding(14).wgjCardContainer()
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(16)
            }.wgjScreenBackground().wgjNavigationChrome()
                .navigationTitle(month.date.formatted(.dateTime.month(.wide).year()))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }.wgjSheetSurface()
    }
}

#Preview("Lifetime summary") {
    JourneyLifetimeSummary(snapshot: TrainingJourneySnapshot(workoutCount: 148, activeDays: 132,
        durationSeconds: 64 * 3_600, walkRunDistanceMeters: 182_400,
        firstWorkoutDate: Calendar.current.date(byAdding: .year, value: -1, to: .now),
        years: [], milestones: [], distanceUnit: .kilometers))
        .padding().wgjScreenBackground()
}
