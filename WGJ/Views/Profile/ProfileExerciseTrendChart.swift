import Charts
import SwiftUI

struct ProfileExerciseTrendChart: View {
    let series: ExerciseMetricSeries
    let metric: ProfileExerciseTrendMetric
    let title: String
    let accent: Color
    @State private var selectedDate: Date?

    private var displayedPoint: ExerciseMetricPoint? {
        guard let selectedDate else { return series.points.last }
        return series.points.min {
            abs($0.completedAt.timeIntervalSince(selectedDate)) < abs($1.completedAt.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate == nil ? "Latest" : displayedPoint?.completedAt.formatted(date: .abbreviated, time: .omitted) ?? "Latest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Spacer()

                Text(metric.formattedTrendValue(displayedPoint?.value ?? 0, loadUnit: series.loadUnit))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accent)
            }

            if let context = displayedPoint?.context {
                Text(context).font(.subheadline.weight(.medium)).foregroundStyle(WGJTheme.textPrimary)
                    .accessibilityIdentifier("profile-trend-context-\(series.catalogExerciseUUID)-\(metric.rawValue)")
            }
            if let deltaText = series.comparisonText(for: metric) {
                Text(deltaText)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Chart(series.points) { point in
                if selectedDate != nil, point.id == displayedPoint?.id {
                    RuleMark(x: .value("Selected", point.completedAt))
                        .foregroundStyle(WGJTheme.accentGold)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                AreaMark(
                    x: .value("Workout", point.completedAt),
                    y: .value(title, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Workout", point.completedAt),
                    y: .value(title, point.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Workout", point.completedAt),
                    y: .value(title, point.value)
                )
                .foregroundStyle(accent)
                .accessibilityLabel(point.completedAt.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(point.context ?? metric.formattedTrendValue(point.value, loadUnit: series.loadUnit))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(max(series.points.count, 2), 4))) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(WGJTheme.outlineStrong.opacity(0.35))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(WGJTheme.outlineStrong.opacity(0.35))
                    AxisValueLabel()
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .frame(height: 170)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].minX
                            selectedDate = proxy.value(atX: x, as: Date.self)
                        }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-exercise-trend-chart-\(series.catalogExerciseUUID)-\(metric.rawValue)")
            Text("Tap the chart to inspect a workout.")
                .font(.caption).foregroundStyle(WGJTheme.textSecondary)
        }
        .onChange(of: series) { _, _ in selectedDate = nil }
    }
}
