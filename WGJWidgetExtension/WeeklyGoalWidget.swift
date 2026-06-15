import SwiftUI
import WidgetKit

private enum WGJWidgetPalette {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let accentBlue = Color(red: 0.29, green: 0.57, blue: 1.0)
    static let ringTrack = Color.white.opacity(0.16)
    static let goalLine = Color.white.opacity(0.32)
    static let priorBar = Color(red: 0.29, green: 0.57, blue: 1.0).opacity(0.42)
    static let templatePrimary = Color.white
    static let templateSecondary = Color.white.opacity(0.82)
    static let templateMuted = Color.white.opacity(0.46)
}

private enum WGJWidgetLayout {
    static let mediumInfoWidth: CGFloat = 104
}

private struct WGJWidgetBackground: View {
    var body: some View {
        fullColorBackground
    }

    private var fullColorBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.100, blue: 0.210),
                Color(red: 0.040, green: 0.220, blue: 0.330),
                Color(red: 0.020, green: 0.035, blue: 0.075),
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
        weeklyGoalWidgetConfiguration(kind: kind)
    }
}

private func weeklyGoalWidgetConfiguration(kind: String) -> some WidgetConfiguration {
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

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("WGJ")
                    .font(.caption.weight(.black))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                WGJWidgetBrandBadge(size: 22)
            }

            Spacer(minLength: 0)
            ZStack {
                progressRing(snapshot: snapshot, lineWidth: 9)
                    .frame(width: 74, height: 74)
                    .widgetAccentable()
                Text(snapshot.progressText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(primaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            VStack(spacing: 2) {
                Text("Weekly Goal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(snapshot.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var systemMedium: some View {
        let snapshot = entry.snapshot

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    WGJWidgetBrandBadge(size: 20)
                    Text("Weekly Goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text(snapshot.progressText)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(primaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("\(snapshot.completedWorkouts) of \(snapshot.weeklyGoal) workouts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(snapshot.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(width: WGJWidgetLayout.mediumInfoWidth, alignment: .leading)

            WeeklyGoalWidgetBarChart(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
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
                .stroke(ringTrackStyle, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progressFraction)
                .stroke(
                    accentStyle,
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
            WGJWidgetPalette.templatePrimary
        case .vibrant:
            WGJWidgetPalette.templatePrimary
        default:
            WGJWidgetPalette.textPrimary
        }
    }

    private var secondaryTextStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.textSecondary
        case .accented:
            WGJWidgetPalette.templateSecondary
        case .vibrant:
            WGJWidgetPalette.templateSecondary
        default:
            WGJWidgetPalette.textSecondary
        }
    }

    private var accentStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.accentBlue
        case .accented:
            WGJWidgetPalette.templatePrimary
        case .vibrant:
            WGJWidgetPalette.templatePrimary
        default:
            WGJWidgetPalette.accentBlue
        }
    }

    private var ringTrackStyle: Color {
        switch currentRenderingMode {
        case .fullColor:
            WGJWidgetPalette.ringTrack
        case .accented, .vibrant:
            WGJWidgetPalette.templateMuted
        default:
            WGJWidgetPalette.ringTrack
        }
    }

}

private struct WeeklyGoalWidgetBarChart: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

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
                                    .fill(barFill(for: week))
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
                            .foregroundStyle(secondaryTextStyle)
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
                .fill(goalLineStyle)
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

    private func barFill(for week: WeeklyGoalWidgetWeek) -> Color {
        switch renderingMode {
        case .fullColor:
            return week == snapshot.recentWeeks.last
                ? WGJWidgetPalette.accentBlue
                : WGJWidgetPalette.priorBar
        case .accented, .vibrant:
            return week == snapshot.recentWeeks.last
                ? WGJWidgetPalette.templatePrimary
                : WGJWidgetPalette.templateMuted
        default:
            return week == snapshot.recentWeeks.last
                ? WGJWidgetPalette.accentBlue
                : WGJWidgetPalette.priorBar
        }
    }

    private var goalLineStyle: Color {
        switch renderingMode {
        case .fullColor:
            WGJWidgetPalette.goalLine
        case .accented, .vibrant:
            WGJWidgetPalette.templateSecondary
        default:
            WGJWidgetPalette.goalLine
        }
    }

    private var secondaryTextStyle: Color {
        switch renderingMode {
        case .fullColor:
            WGJWidgetPalette.textSecondary
        case .accented, .vibrant:
            WGJWidgetPalette.templateSecondary
        default:
            WGJWidgetPalette.textSecondary
        }
    }
}

private struct WGJWidgetBrandBadge: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if renderingMode == .fullColor {
            fullColorLogo
        } else {
            adaptedLogo
        }
    }

    @ViewBuilder
    private var fullColorLogo: some View {
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

    @ViewBuilder
    private var adaptedLogo: some View {
        if #available(iOS 18.0, *) {
            Image("WidgetLogo")
                .resizable()
                .widgetAccentedRenderingMode(WidgetAccentedRenderingMode.desaturated)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .accessibilityHidden(true)
        } else {
            logoImage
        }
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
