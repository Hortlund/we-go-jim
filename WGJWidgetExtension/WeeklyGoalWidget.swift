import SwiftUI
import WidgetKit

struct WeeklyGoalWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WeeklyGoalWidgetSnapshot?
}

struct WeeklyGoalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalWidgetEntry {
        WeeklyGoalWidgetEntry(
            date: .now,
            snapshot: WeeklyGoalWidgetContentPolicy.placeholder()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalWidgetEntry>) -> Void) {
        let currentEntry = entry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: currentEntry.date)
            ?? currentEntry.date.addingTimeInterval(3_600)
        completion(Timeline(entries: [currentEntry], policy: .after(nextRefresh)))
    }

    private func entry(date: Date = .now) -> WeeklyGoalWidgetEntry {
        let snapshot = try? WeeklyGoalWidgetStore()?.load()
        return WeeklyGoalWidgetEntry(date: date, snapshot: snapshot)
    }
}

struct WeeklyGoalWidget: Widget {
    let kind = WeeklyGoalWidgetDescriptor.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyGoalWidgetProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WeeklyGoalWidgetDeepLink.profileWeeklyGoalURL)
        }
        .configurationDisplayName("Weekly Goal")
        .description("Track this week's workout target.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct WeeklyGoalWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WeeklyGoalWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            systemSmall
        case .systemMedium:
            systemMedium
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            systemSmall
        }
    }

    private var systemSmall: some View {
        ZStack(alignment: .topTrailing) {
            if let snapshot = entry.snapshot {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ZStack {
                        progressRing(snapshot: snapshot, lineWidth: 9)
                            .frame(width: 78, height: 78)
                        Text(snapshot.progressText)
                            .font(.title3.weight(.bold))
                            .minimumScaleFactor(0.65)
                    }
                    VStack(spacing: 2) {
                        Text("Weekly Goal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(snapshot.statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                emptyState
            }

            WGJWidgetLogoBadge(size: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(2)
    }

    private var systemMedium: some View {
        ZStack(alignment: .topTrailing) {
            if let snapshot = entry.snapshot {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WGJWidgetLogoBadge(size: 28)
                        Spacer(minLength: 0)
                        Text("Workouts\nPer Week")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(snapshot.completedWorkouts)/\(snapshot.weeklyGoal) this week")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.blue)
                            .minimumScaleFactor(0.75)
                        Text(mediumStatus(snapshot))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 112, alignment: .leading)

                    WeeklyGoalWidgetBarChart(snapshot: snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack {
                    emptyState
                    Spacer(minLength: 0)
                    WGJWidgetLogoBadge(size: 36)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(2)
    }

    @ViewBuilder
    private var accessoryCircular: some View {
        if let snapshot = entry.snapshot {
            ZStack {
                progressRing(snapshot: snapshot, lineWidth: 5)
                VStack(spacing: -1) {
                    Text("\(snapshot.completedWorkouts)")
                        .font(.headline.weight(.bold))
                    Text("/\(snapshot.weeklyGoal)")
                        .font(.caption2.weight(.semibold))
                }
            }
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Weekly Goal")
                .font(.caption2.weight(.semibold))
            if let snapshot = entry.snapshot {
                Text("\(snapshot.completedWorkouts) of \(snapshot.weeklyGoal) workouts")
                    .font(.headline.weight(.bold))
                Text(snapshot.statusText)
                    .font(.caption2)
            } else {
                Text("Open WGJ")
                    .font(.headline.weight(.bold))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            WGJWidgetLogoBadge(size: 32)
            Text("Open WGJ")
                .font(.headline.weight(.bold))
            Text("Set weekly goal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func progressRing(snapshot: WeeklyGoalWidgetSnapshot, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progressFraction)
                .stroke(
                    .blue,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private func mediumStatus(_ snapshot: WeeklyGoalWidgetSnapshot) -> String {
        if snapshot.completedWorkouts >= snapshot.weeklyGoal {
            return snapshot.statusText
        }
        let remaining = snapshot.remainingWorkouts
        return "\(snapshot.completedWorkouts) done, \(remaining) left"
    }

    private func weekRange(_ snapshot: WeeklyGoalWidgetSnapshot) -> String {
        let start = snapshot.weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = snapshot.weekEnd.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
        return "\(start)-\(end)"
    }
}

private struct WeeklyGoalWidgetBarChart: View {
    let snapshot: WeeklyGoalWidgetSnapshot

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(1, snapshot.chartMaximumWorkouts)
            let labelHeight: CGFloat = 18
            let chartHeight = max(1, proxy.size.height - labelHeight - 10)

            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    goalLine(chartHeight: chartHeight, maxValue: maxValue)
                    HStack(alignment: .bottom, spacing: 9) {
                        ForEach(snapshot.recentWeeks) { week in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(week == snapshot.recentWeeks.last ? Color.blue : Color.blue.opacity(0.45))
                                    .frame(height: barHeight(for: week, chartHeight: chartHeight, maxValue: maxValue))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: chartHeight)

                HStack(spacing: 0) {
                    ForEach(snapshot.recentWeeks) { week in
                        Text(week.weekStart.formatted(.dateTime.day().month(.defaultDigits)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: labelHeight)
            }
        }
        .accessibilityLabel("Weekly workout history")
        .accessibilityValue("\(snapshot.completedWorkouts) of \(snapshot.weeklyGoal) workouts this week")
    }

    private func goalLine(chartHeight: CGFloat, maxValue: Int) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: max(0, chartHeight - goalLineOffset(chartHeight: chartHeight, maxValue: maxValue)))
            Rectangle()
                .fill(Color.primary.opacity(0.32))
                .frame(height: 1)
            Spacer(minLength: 0)
        }
    }

    private func goalLineOffset(chartHeight: CGFloat, maxValue: Int) -> CGFloat {
        let fraction = min(1, Double(snapshot.weeklyGoal) / Double(maxValue))
        return chartHeight * CGFloat(fraction)
    }

    private func barHeight(for week: WeeklyGoalWidgetWeek, chartHeight: CGFloat, maxValue: Int) -> CGFloat {
        let fraction = min(1, Double(week.completedWorkouts) / Double(maxValue))
        let height = chartHeight * CGFloat(fraction)
        return max(week.completedWorkouts > 0 ? 8 : 2, height)
    }
}

private struct WGJWidgetLogoBadge: View {
    let size: CGFloat

    var body: some View {
        Image("WidgetLogo")
            .resizable()
            .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

@main
struct WGJWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeeklyGoalWidget()
    }
}

#Preview(as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalWidgetEntry(
        date: .now,
        snapshot: WeeklyGoalWidgetContentPolicy.snapshot(
            completedWorkouts: 3,
            weeklyGoal: 4,
            weekStart: .now
        )
    )
}
