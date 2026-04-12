import Charts
import SwiftUI

struct ExerciseDetailStatsSection: View {
    let snapshot: ExerciseDetailStatsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Workout Stats",
                subtitle: "Exercise-owned progress from your completed workouts."
            )

            if let snapshot {
                overviewCard(snapshot)

                if snapshot.oneRepMaxTrend != nil || snapshot.volumeTrend != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let series = snapshot.oneRepMaxTrend {
                            ExerciseMetricTrendCard(
                                title: "Strength Trend",
                                subtitle: "Best estimated 1RM across recent workouts.",
                                accent: WGJTheme.accentGold,
                                series: series
                            )
                        }

                        if let series = snapshot.volumeTrend {
                            ExerciseMetricTrendCard(
                                title: "Volume Trend",
                                subtitle: "Total weighted volume across recent workouts.",
                                accent: WGJTheme.accentBlue,
                                series: series
                            )
                        }
                    }
                }
            } else {
                Text("No completed workout history for this exercise yet.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wgjCardContainer()
            }
        }
    }

    private func overviewCard(_ snapshot: ExerciseDetailStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    WGJMetricPill(
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        value: snapshot.lastPerformedAt.formatted(date: .abbreviated, time: .omitted)
                    )
                    WGJMetricPill(
                        systemImage: "number.circle.fill",
                        value: "\(snapshot.sessionCount) logged session" + (snapshot.sessionCount == 1 ? "" : "s")
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    WGJMetricPill(
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        value: snapshot.lastPerformedAt.formatted(date: .abbreviated, time: .omitted)
                    )
                    WGJMetricPill(
                        systemImage: "number.circle.fill",
                        value: "\(snapshot.sessionCount) logged session" + (snapshot.sessionCount == 1 ? "" : "s")
                    )
                }
            }

            if let bestPerformance = snapshot.bestPerformance {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bestPerformanceTitle(bestPerformance))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentGold)
                        .textCase(.uppercase)

                    Text(bestPerformanceValue(bestPerformance))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    if let detail = bestPerformanceDetail(bestPerformance) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    Text("Logged \(bestPerformance.achievedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(WGJTheme.cardStrong.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(WGJTheme.accentGold.opacity(0.18), lineWidth: 1)
                        )
                )
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private func bestPerformanceTitle(_ performance: ExerciseDetailBestPerformance) -> String {
        switch performance.kind {
        case .weighted:
            return "Best Weighted Performance"
        case .bodyweight:
            return "Best Bodyweight Performance"
        }
    }

    private func bestPerformanceValue(_ performance: ExerciseDetailBestPerformance) -> String {
        switch performance.kind {
        case .weighted:
            guard let weight = performance.weight else {
                return "\(performance.reps) reps"
            }
            return "\(WGJFormatters.decimalString(weight)) \(performance.loadUnit.shortLabel) x \(performance.reps)"
        case .bodyweight:
            return "\(performance.reps) reps"
        }
    }

    private func bestPerformanceDetail(_ performance: ExerciseDetailBestPerformance) -> String? {
        switch performance.kind {
        case .weighted:
            guard let estimatedOneRepMax = performance.estimatedOneRepMax else {
                return nil
            }
            return "Estimated 1RM \(WGJFormatters.oneDecimalString(estimatedOneRepMax)) \(performance.loadUnit.shortLabel)"
        case .bodyweight:
            return nil
        }
    }
}

private struct ExerciseMetricTrendCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let series: ExerciseMetricSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title, subtitle: subtitle)

            if let latest = series.points.last {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Latest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        Spacer()

                        Text("\(WGJFormatters.decimalString(latest.value)) \(series.loadUnit.shortLabel)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(accent)
                    }

                    Chart(series.points) { point in
                        AreaMark(
                            x: .value("Workout", point.completedAt),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.18), accent.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Workout", point.completedAt),
                            y: .value(title, point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("Workout", point.completedAt),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(accent)
                    }
                    .frame(height: 160)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(max(series.points.count, 2), 4))) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(WGJTheme.outlineStrong.opacity(0.35))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(WGJTheme.outlineStrong.opacity(0.26))
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(WGJFormatters.decimalString(number))
                                        .foregroundStyle(WGJTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }
}
