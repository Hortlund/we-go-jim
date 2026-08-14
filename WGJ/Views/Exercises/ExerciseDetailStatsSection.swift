import Charts
import SwiftUI

nonisolated enum ExerciseDetailStatsLoadState: Equatable, Sendable {
    case loading
    case empty
    case ready(ExerciseProgressDataset)
    case failed(message: String)
}

struct ExerciseDetailStatsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ExerciseDetailStatsLoadState
    let onRetry: () -> Void

    @State private var selectedMetric: ExerciseProgressMetric = .estimatedOneRepMax
    @State private var selectedRange: ExerciseProgressRange = .sixMonths
    @State private var selectedDate: Date?
    @State private var configuredDatasetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Progress Timeline", subtitle: "Follow your performance across completed workouts.")
            switch state {
            case .loading: loadingContent
            case .empty: stableMessageCard("Complete a workout with this exercise to start your progress timeline.")
            case .failed:
                VStack(alignment: .leading, spacing: 12) {
                    stableMessageCard("Progress could not be loaded.")
                    Button("Retry", action: onRetry).buttonStyle(WGJGhostButtonStyle())
                }
            case .ready(let dataset):
                readyContent(dataset)
                    .onAppear { configureMetricIfNeeded(for: dataset) }
                    .onChange(of: dataset.exerciseUUID) { _, _ in configureMetricIfNeeded(for: dataset) }
            }
        }
    }

    private func readyContent(_ dataset: ExerciseProgressDataset) -> some View {
        let projection = projection(for: dataset)
        return VStack(alignment: .leading, spacing: 14) {
            controls(dataset: dataset)
            if let summary = projection.summary {
                summaryGrid(summary, projection: projection)
            }
            chartCard(projection)
            if projection.milestones.isEmpty {
                Text(projection.availability.reason ?? "No compatible history in this range.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wgjCardContainer()
            } else {
                milestoneTimeline(projection)
            }
        }
    }

    private func controls(dataset: ExerciseProgressDataset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(ExerciseProgressMetric.allCases) { metric in
                    let availability = projection(for: dataset, metric: metric).availability
                    Button {
                        selectedMetric = metric
                        selectedDate = nil
                    } label: {
                        metric == selectedMetric
                            ? Label(metric.title, systemImage: "checkmark")
                            : Label(metric.title, systemImage: "chart.xyaxis.line")
                    }
                    .disabled(!availability.isAvailable)
                    .accessibilityHint(availability.reason ?? "")
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metric").font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.textSecondary)
                        Text(selectedMetric.title).font(.headline).foregroundStyle(WGJTheme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").foregroundStyle(WGJTheme.accentBlue)
                }
                .padding(12)
                .wgjCardContainer(strong: true)
            }
            .accessibilityIdentifier("exercise-progress-metric-selector")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExerciseProgressRange.allCases) { range in
                        Button(range.title) {
                            selectedRange = range
                            selectedDate = nil
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(range == selectedRange ? WGJTheme.bgBase : WGJTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(range == selectedRange ? WGJTheme.accentBlue : WGJTheme.fieldStrong))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("exercise-progress-range-\(range.rawValue)")
                        .accessibilityValue(range == selectedRange ? "Selected" : "")
                    }
                }
            }
        }
    }

    private func summaryGrid(_ summary: ExerciseProgressSummary, projection: ExerciseProgressProjection) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            summaryCard("Change", value: changeText(summary, projection: projection), accent: changeColor(summary))
            summaryCard("Best", value: valueText(summary.best, projection: projection), accent: WGJTheme.accentGold)
            summaryCard("Sessions", value: "\(summary.sessionCount)")
            summaryCard("Working Sets", value: "\(summary.totalSets)")
            summaryCard("Total Reps", value: "\(summary.totalReps)")
        }
    }

    private func summaryCard(_ title: String, value: String, accent: Color = WGJTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(WGJTheme.textSecondary)
            Text(value).font(.headline.weight(.bold)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .wgjCardContainer()
    }

    private func chartCard(_ projection: ExerciseProgressProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let point = selectedPoint(in: projection) ?? projection.points.last {
                HStack {
                    Text(selectedDate == nil ? "Latest" : point.date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(WGJTheme.textSecondary)
                    Spacer()
                    Text(valueText(point.value, projection: projection)).fontWeight(.bold).foregroundStyle(WGJTheme.accentBlue)
                }
                .font(.subheadline)
            }

            Chart {
                ForEach(projection.chartPoints) { point in
                    AreaMark(x: .value("Date", point.date), y: .value(selectedMetric.title, point.value))
                        .foregroundStyle(LinearGradient(
                            colors: [WGJTheme.accentBlue.opacity(0.20), WGJTheme.accentBlue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    LineMark(x: .value("Date", point.date), y: .value(selectedMetric.title, point.value))
                        .interpolationMethod(.linear)
                        .foregroundStyle(WGJTheme.accentBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Date", point.date), y: .value(selectedMetric.title, point.value))
                        .foregroundStyle(WGJTheme.accentBlue)
                }
                if let point = selectedPoint(in: projection) {
                    RuleMark(x: .value("Selected", point.date))
                        .foregroundStyle(WGJTheme.accentGold.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: 190)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(WGJTheme.outlineStrong.opacity(0.25))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(WGJTheme.outlineStrong.opacity(0.25))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(WGJFormatters.decimalString(number)).foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                }
            }
            .transaction { if reduceMotion { $0.animation = nil } }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exercise-progress-chart")
            .accessibilityLabel(projection.accessibilitySummary)
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private func milestoneTimeline(_ projection: ExerciseProgressProjection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WGJSectionHeader("Timeline", subtitle: "Notable performances in this range.").padding(.bottom, 8)
            ForEach(Array(projection.milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(milestone.kind == .personalRecord ? WGJTheme.accentGold : WGJTheme.accentBlue)
                            .frame(width: 10, height: 10)
                        if index < projection.milestones.count - 1 {
                            Rectangle().fill(WGJTheme.outlineStrong.opacity(0.45)).frame(width: 2).frame(minHeight: 46)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestoneTitle(milestone.kind)).font(.subheadline.weight(.bold)).foregroundStyle(WGJTheme.textPrimary)
                        Text(valueText(milestone.value, projection: projection))
                            .font(.headline)
                            .foregroundStyle(milestone.kind == .personalRecord ? WGJTheme.accentGold : WGJTheme.accentBlue)
                        Text(milestone.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    Spacer()
                }
                .id(milestone.pointID)
            }
        }
        .padding(14)
        .wgjCardContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise-progress-timeline")
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14).fill(WGJTheme.fieldStrong).frame(height: 66)
            RoundedRectangle(cornerRadius: 14).fill(WGJTheme.field).frame(height: 190).overlay { ProgressView() }
        }
        .accessibilityLabel("Loading exercise progress")
    }

    private func stableMessageCard(_ message: String) -> some View {
        VStack(alignment: .leading) {
            Text(message).font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .wgjCardContainer()
    }

    private func projection(for dataset: ExerciseProgressDataset, metric: ExerciseProgressMetric? = nil) -> ExerciseProgressProjection {
        ExerciseProgressProjector.project(
            dataset: dataset,
            metric: metric ?? selectedMetric,
            range: selectedRange,
            now: .now,
            calendar: .current
        )
    }

    private func configureMetricIfNeeded(for dataset: ExerciseProgressDataset) {
        guard configuredDatasetID != dataset.exerciseUUID else { return }
        configuredDatasetID = dataset.exerciseUUID
        if !projection(for: dataset, metric: selectedMetric).availability.isAvailable,
           let first = ExerciseProgressMetric.allCases.first(where: {
               projection(for: dataset, metric: $0).availability.isAvailable
           }) {
            selectedMetric = first
        }
    }

    private func selectedPoint(in projection: ExerciseProgressProjection) -> ExerciseProgressPoint? {
        guard let selectedDate else { return nil }
        return projection.points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func valueText(_ value: Double, projection: ExerciseProgressProjection) -> String {
        switch projection.metric {
        case .estimatedOneRepMax, .heaviestWeight:
            return "\(WGJFormatters.oneDecimalString(value)) \(projection.displayUnit.shortLabel)"
        case .sessionVolume:
            return "\(WGJFormatters.integerString(value)) \(projection.displayUnit.shortLabel)"
        case .bestSetReps, .totalReps:
            return "\(Int(value.rounded())) reps"
        case .workoutFrequency:
            let count = Int(value.rounded())
            return "\(count) workout" + (count == 1 ? "" : "s") + "/week"
        }
    }

    private func changeText(_ summary: ExerciseProgressSummary, projection: ExerciseProgressProjection) -> String {
        (summary.absoluteChange > 0 ? "+" : "") + valueText(summary.absoluteChange, projection: projection)
    }

    private func changeColor(_ summary: ExerciseProgressSummary) -> Color {
        summary.absoluteChange > 0 ? WGJTheme.success : summary.absoluteChange < 0 ? WGJTheme.danger : WGJTheme.textPrimary
    }

    private func milestoneTitle(_ kind: ExerciseProgressMilestoneKind) -> String {
        switch kind {
        case .firstPerformance: "First Performance"
        case .personalRecord: "Personal Record"
        case .materialChange: "Notable Change"
        case .latestPerformance: "Latest Performance"
        }
    }
}
