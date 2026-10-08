import SwiftUI

struct JourneyAchievementsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    enum Page: String, CaseIterable {
        case goals, earned, stats
        var title: String {
            switch self {
            case .goals: String(localized: "Goals")
            case .earned: String(localized: "Earned")
            case .stats: String(localized: "Stats")
            }
        }
        var symbol: String {
            switch self {
            case .goals: "target"
            case .earned: "medal.fill"
            case .stats: "chart.bar.fill"
            }
        }
    }
    let snapshot: TrainingJourneySnapshot
    @State private var page: Page
    @State private var selectedYear: Date?
    @State private var goalFilter = 0
    @State private var recordFilter = 0

    init(snapshot: TrainingJourneySnapshot, initialPage: Page) {
        self.snapshot = snapshot
        _page = State(initialValue: initialPage)
    }

    private var year: JourneyYear? { snapshot.years.first { $0.id == selectedYear } }
    private var earned: [JourneyMilestone] {
        let sessionIDs = year.map { Set($0.months.flatMap(\.workouts).map(\.id)) }
        return snapshot.milestones.filter { event in
            (sessionIDs == nil || sessionIDs!.contains(event.sessionID))
                && (recordFilter == 0 || (recordFilter == 1 ? event.personalRecord != nil : event.personalRecord == nil))
        }
    }
    private var facts: [JourneyFact] {
        guard let selectedYear else { return snapshot.insights.facts }
        return snapshot.insights.years.first { $0.id == selectedYear }?.facts ?? []
    }
    private var series: [JourneyAchievementSeries] {
        JourneyAchievementCatalog.series(snapshot.achievementGoals).filter {
            goalFilter == 2 || (goalFilter == 1 ? $0.latestCleared != nil : $0.nextGoal != nil)
        }
    }
    private var categories: [String] {
        var seen = Set<String>()
        return series.map(\.category).filter { seen.insert($0).inserted }
    }
    private var goalFilterTitle: String {
        [String(localized: "To unlock"), String(localized: "Cleared"), String(localized: "All goals")][goalFilter]
    }
    private var recordFilterTitle: String {
        [String(localized: "All achievements"), String(localized: "PRs"), String(localized: "Milestones")][recordFilter]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                switch page {
                case .goals:
                    Text("\(snapshot.achievementGoals.filter(\.isEarned).count) of \(snapshot.achievementGoals.count) goals cleared")
                        .font(.title3.bold())
                    WGJActionMenuButton(String(localized: "Show goals")) {
                        Button("To unlock") { goalFilter = 0 }
                        Button("Cleared") { goalFilter = 1 }
                        Button("All goals") { goalFilter = 2 }
                    } label: {
                        Label(goalFilterTitle, systemImage: "chevron.down").padding(.vertical, 10)
                    }
                    .foregroundStyle(WGJTheme.accentBlue)
                    .accessibilityLabel("Show goals").accessibilityValue(goalFilterTitle)
                    .accessibilityIdentifier("journey-goal-filter")
                    ForEach(categories, id: \.self) { category in
                        Section {
                            ForEach(series.filter { $0.category == category }) { item in
                                if let goal = goalFilter == 1 ? item.latestCleared : item.currentGoal {
                                    if item.goals.count > 1 {
                                        NavigationLink {
                                            JourneyGoalSeriesView(series: item)
                                        } label: {
                                            JourneyGoalCard(goal: goal, series: item)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("journey-goal-series-\(item.id)")
                                    } else {
                                        JourneyGoalCard(goal: goal)
                                    }
                                }
                            }
                        } header: {
                            Text(category).font(.title3.bold()).padding(.top, 8)
                        }
                    }
                    if series.isEmpty { Text("No goals in this view yet.").foregroundStyle(WGJTheme.textSecondary) }
                case .earned:
                    Text("\(earned.count) achievements").font(.title3.bold())
                    WGJActionMenuButton(String(localized: "Show achievements")) {
                        Button("All achievements") { recordFilter = 0 }
                        Button("PRs") { recordFilter = 1 }
                        Button("Milestones") { recordFilter = 2 }
                    } label: {
                        Label(recordFilterTitle, systemImage: "chevron.down").padding(.vertical, 10)
                    }
                    .foregroundStyle(WGJTheme.accentBlue)
                    .accessibilityLabel("Show achievements").accessibilityValue(recordFilterTitle)
                    .accessibilityIdentifier("journey-earned-filter")
                    ForEach(earned) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                            JourneyMilestoneRow(event: event)
                        }
                    }
                    if earned.isEmpty { Text("Your next achievement is ahead of you.").foregroundStyle(WGJTheme.textSecondary) }
                case .stats:
                    ForEach(facts) { fact in JourneyAchievementCard(fact: fact) }
                    if facts.isEmpty { Text("Complete a workout to start this collection.").foregroundStyle(WGJTheme.textSecondary) }
                }
            }
            .padding(16).padding(.bottom, 80)
        }
        .id(page)
        .safeAreaInset(edge: .top, spacing: 0) {
            pageNavigation.padding(.horizontal, 16).padding(.vertical, 12)
                .background(WGJTheme.bgBase)
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .wgjScreenBackground().wgjNavigationChrome()
        .toolbar {
            if page != .goals {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Year", selection: $selectedYear) {
                        Text("All time").tag(nil as Date?)
                        ForEach(snapshot.years) { Text($0.title).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).accessibilityIdentifier("journey-achievement-year")
                }
            }
        }
    }

    @ViewBuilder private var pageNavigation: some View {
        if dynamicTypeSize.isAccessibilitySize {
            WGJActionMenuButton(String(localized: "Achievement view")) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button(item.title) { page = item }
                }
            } label: {
                HStack {
                    Label(page.title, systemImage: page.symbol)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .padding(14)
                .background(WGJTheme.accentBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityLabel("Achievement view").accessibilityValue(page.title)
            .accessibilityIdentifier("journey-achievement-page-picker")
        } else {
            pageTabs
        }
    }

    private var pageTabs: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.self) { item in
                Button { page = item } label: {
                    ViewThatFits(in: .horizontal) {
                        Label(item.title, systemImage: item.symbol)
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol)
                            Text(item.title)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .foregroundStyle(page == item ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                    .background(page == item ? WGJTheme.accentBlue.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(page == item ? WGJTheme.accentBlue.opacity(0.35) : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(page == item ? .isSelected : [])
                .accessibilityIdentifier("journey-achievement-page-\(item.rawValue)")
            }
        }
        .padding(5)
        .background(WGJTheme.card, in: RoundedRectangle(cornerRadius: 19))
    }
}

private struct JourneyGoalSeriesView: View {
    let series: JourneyAchievementSeries

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("\(series.clearedCount) of \(series.goals.count) goals cleared").font(.title3.bold())
                ForEach(series.goals) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        if goal.id == series.nextGoal?.id {
                            Label("Current goal", systemImage: "target")
                                .font(.subheadline.bold()).foregroundStyle(WGJTheme.accentBlue)
                        }
                        JourneyGoalCard(goal: goal)
                    }
                }
            }.padding(16).padding(.bottom, 80)
        }
        .navigationTitle(series.title).navigationBarTitleDisplayMode(.inline)
        .wgjScreenBackground().wgjNavigationChrome()
    }
}

private struct JourneyGoalCard: View {
    let goal: JourneyAchievementGoal
    var series: JourneyAchievementSeries? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let series {
                Text(series.title).font(.subheadline.weight(.semibold)).foregroundStyle(WGJTheme.accentBlue)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: goal.isEarned ? "checkmark.seal.fill" : "medal")
                    .font(.system(size: 25)).foregroundStyle(WGJTheme.accentBlue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title).font(.headline)
                    Text(goal.isEarned ? "Cleared" : "To unlock")
                        .font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.accentBlue)
                }
            }
            Text(goal.requirement).font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            if let progress = goal.progress, let progressText = goal.progressText {
                ProgressView(value: progress).tint(goal.isEarned ? WGJTheme.accentBlue : WGJTheme.accentGold)
                Text(progressText).font(.caption).foregroundStyle(WGJTheme.textSecondary)
            }
            if let series {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("\(series.clearedCount) of \(series.goals.count) cleared")
                        Spacer()
                        Label("View goals", systemImage: "chevron.right")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(series.clearedCount) of \(series.goals.count) cleared")
                        Label("View goals", systemImage: "chevron.right")
                    }
                }.font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.accentBlue)
            }
        }
        .foregroundStyle(WGJTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(18).wgjCardContainer()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journey-goal-\(goal.id)")
    }
}
