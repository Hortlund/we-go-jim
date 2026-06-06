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
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Goal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let snapshot = entry.snapshot {
                HStack(alignment: .center, spacing: 10) {
                    progressRing(snapshot: snapshot, lineWidth: 8)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.progressText)
                            .font(.title3.weight(.bold))
                            .minimumScaleFactor(0.75)
                        Text(snapshot.statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(4)
    }

    private var systemMedium: some View {
        HStack(spacing: 18) {
            if let snapshot = entry.snapshot {
                progressRing(snapshot: snapshot, lineWidth: 10)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly Goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.progressText)
                        .font(.title.weight(.bold))
                    Text(mediumStatus(snapshot))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(weekRange(snapshot))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            } else {
                emptyState
                Spacer(minLength: 0)
            }
        }
        .padding(4)
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
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2.weight(.semibold))
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
