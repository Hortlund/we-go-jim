import SwiftUI
import WidgetKit

private enum WGJWidgetPalette {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let accentBlue = Color(red: 0.29, green: 0.57, blue: 1.0)
    static let ringTrack = Color.white.opacity(0.16)
    static let goalLine = Color.white.opacity(0.32)
    static let priorBar = Color(red: 0.29, green: 0.57, blue: 1.0).opacity(0.42)
}

private struct WGJWidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch renderingMode {
        case .fullColor:
            fullColorBackground
        case .accented:
            Color.clear
        case .vibrant:
            Color.clear
        default:
            fullColorBackground
        }
    }

    private var fullColorBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.035, blue: 0.070),
                Color(red: 0.030, green: 0.090, blue: 0.170),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WeeklyGoalWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WeeklyGoalWidgetSnapshot
}

struct WeeklyGoalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyGoalWidgetEntry {
        WeeklyGoalWidgetEntry(date: .now, snapshot: WeeklyGoalWidgetContentPolicy.preview())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalWidgetEntry) -> Void) {
        if context.isPreview {
            completion(
                WeeklyGoalWidgetEntry(
                    date: .now,
                    snapshot: WeeklyGoalWidgetContentPolicy.preview()
                )
            )
            return
        }

        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalWidgetEntry>) -> Void) {
        let currentEntry = entry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: currentEntry.date)
            ?? currentEntry.date.addingTimeInterval(3_600)
        completion(Timeline(entries: [currentEntry], policy: .after(nextRefresh)))
    }

    private func entry(date: Date = .now) -> WeeklyGoalWidgetEntry {
        if let store = WeeklyGoalWidgetStore(), let snapshot = try? store.load() {
            return WeeklyGoalWidgetEntry(date: date, snapshot: snapshot)
        }

        return WeeklyGoalWidgetEntry(
            date: date,
            snapshot: WeeklyGoalWidgetContentPolicy.placeholder(generatedAt: date)
        )
    }
}

struct WeeklyGoalWidget: Widget {
    let kind = WeeklyGoalWidgetDescriptor.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyGoalWidgetProvider()) { entry in
            WeeklyGoalWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WGJWidgetBackground()
                }
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
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: WeeklyGoalWidgetEntry

    var body: some View {
        content
            .unredacted()
    }

    @ViewBuilder
    private var content: some View {
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
        let snapshot = entry.snapshot

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("WGJ")
                    .font(.caption.weight(.black))
                    .foregroundStyle(secondaryTextStyle)
                Spacer(minLength: 0)
                WGJWidgetBrandBadge(size: 32)
            }

            Spacer(minLength: 0)
            ZStack {
                progressRing(snapshot: snapshot, lineWidth: 9)
                    .frame(width: 80, height: 80)
                    .widgetAccentable()
                Text(snapshot.progressText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(primaryTextStyle)
                    .minimumScaleFactor(0.65)
                    .widgetAccentable()
            }
            VStack(spacing: 2) {
                Text("Weekly Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextStyle)
                Text(snapshot.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryTextStyle)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(2)
    }

    private var systemMedium: some View {
        let snapshot = entry.snapshot

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    WGJWidgetBrandBadge(size: 28)
                    Spacer(minLength: 0)
                    Text("Workouts\nPer Week")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(primaryTextStyle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("\(snapshot.completedWorkouts)/\(snapshot.weeklyGoal) this week")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accentStyle)
                        .minimumScaleFactor(0.75)
                        .widgetAccentable()
                    Text(mediumStatus(snapshot))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryTextStyle)
                        .lineLimit(1)
                }
                .frame(width: 112, alignment: .leading)

                WeeklyGoalWidgetBarChart(snapshot: snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(2)
    }

    private var accessoryCircular: some View {
        let snapshot = entry.snapshot

        return ZStack {
            progressRing(snapshot: snapshot, lineWidth: 5)
                .widgetAccentable()
            VStack(spacing: -1) {
                Text("\(snapshot.completedWorkouts)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(primaryTextStyle)
                Text("/\(snapshot.weeklyGoal)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryTextStyle)
            }
        }
    }

    private var accessoryRectangular: some View {
        let snapshot = entry.snapshot

        return VStack(alignment: .leading, spacing: 2) {
            Text("Weekly Goal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextStyle)
            Text("\(snapshot.completedWorkouts) of \(snapshot.weeklyGoal) workouts")
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryTextStyle)
            Text(snapshot.statusText)
                .font(.caption2)
                .foregroundStyle(secondaryTextStyle)
        }
    }

    private func progressRing(snapshot: WeeklyGoalWidgetSnapshot, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(WGJWidgetPalette.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progressFraction)
                .stroke(
                    WGJWidgetPalette.accentBlue,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private var currentRenderingMode: WidgetRenderingMode {
        renderingMode
    }

    private var primaryTextStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.textPrimary
        case .accented:
            .white
        case .vibrant:
            .white
        default:
            WGJWidgetPalette.textPrimary
        }
    }

    private var secondaryTextStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.textSecondary
        case .accented:
            .white.opacity(0.78)
        case .vibrant:
            .white.opacity(0.78)
        default:
            WGJWidgetPalette.textSecondary
        }
    }

    private var accentStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.accentBlue
        case .accented:
            .white
        case .vibrant:
            .white
        default:
            WGJWidgetPalette.accentBlue
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
                                    .fill(
                                        week == snapshot.recentWeeks.last
                                            ? WGJWidgetPalette.accentBlue
                                            : WGJWidgetPalette.priorBar
                                    )
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
                            .foregroundStyle(WGJWidgetPalette.textSecondary)
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
                .fill(WGJWidgetPalette.goalLine)
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

private struct WGJWidgetBrandBadge: View {
    let size: CGFloat

    var body: some View {
        if #available(iOS 18.0, *) {
            Image("WidgetLogo")
                .resizable()
                .widgetAccentedRenderingMode(WidgetAccentedRenderingMode.fullColor)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .accessibilityHidden(true)
        } else {
            logoImage
        }
    }

    private var logoImage: some View {
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
