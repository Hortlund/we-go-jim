import SwiftUI
import UIKit

nonisolated struct WorkoutSharePresentation: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        let title: String
        let value: String
    }

    struct Exercise: Equatable, Sendable {
        let name: String
        let setProgressText: String
        let detailTitle: LocalizedStringResource
        let bestSetText: String

        init(
            name: String,
            setProgressText: String,
            detailTitle: LocalizedStringResource = "BEST SET",
            bestSetText: String
        ) {
            self.name = name
            self.setProgressText = setProgressText
            self.detailTitle = detailTitle
            self.bestSetText = bestSetText
        }
    }

    let sessionName: String
    let completedAtText: String
    let activityLabel: String
    let primaryMetric: Metric
    let supportingMetrics: [Metric]
    let personalRecordCount: Int
    let highlightTitle: String
    let highlightDetail: String
    let exercises: [Exercise]
    let remainingExerciseCount: Int

    var highlightEyebrowText: String {
        switch personalRecordCount {
        case 0:
            String(localized: "SESSION COMPLETE")
        case 1:
            String(localized: "NEW PERSONAL RECORD")
        default:
            String(localized: "\(personalRecordCount) NEW PERSONAL RECORDS")
        }
    }

    var remainingPersonalRecordText: String? {
        let remainingCount = personalRecordCount - 1
        guard remainingCount > 0 else { return nil }

        if remainingCount == 1 {
            return String(localized: "+ 1 more PR")
        }
        return String(localized: "+ \(remainingCount) more PRs")
    }

    static func make(snapshot: WorkoutCompletionSnapshot) -> Self {
        let prCount = snapshot.personalRecords.count
        let firstRecord = snapshot.personalRecords.first
        let completedCardio = snapshot.cardioRecap.filter(\.isCompleted)
        let hasStrength = snapshot.exerciseCount > 0
        let hasCardio = !completedCardio.isEmpty
        let hasMainCardio = completedCardio.contains { $0.role == .main }
        let cardioMetrics = completedCardio.flatMap(\.summary.metrics)
        let preferredCardioMetric = cardioMetrics.first { $0.kind == .distance }
            ?? cardioMetrics.first { $0.kind == .duration }
            ?? cardioMetrics.first
        let secondaryCardioMetric = cardioMetrics.first {
            $0.kind != preferredCardioMetric?.kind && $0.kind != .duration
        }
        let mainCardioActivities = completedCardio
            .filter { $0.role == .main }
            .map { cardio in
                let resultText = cardio.summary.metrics.prefix(2)
                    .map(\.value)
                    .joined(separator: " · ")
                return Exercise(
                    name: cardio.exerciseName,
                    setProgressText: cardio.role.title.uppercased(),
                    detailTitle: "RESULT",
                    bestSetText: resultText.isEmpty ? "Complete" : resultText
                )
            }
        let strengthActivities = snapshot.exerciseRecap.map { recap in
            Exercise(
                name: recap.exerciseName,
                setProgressText: "\(recap.completedSetCount) / \(recap.totalSetCount) sets",
                bestSetText: recap.bestSetText
            )
        }
        let allActivities = mainCardioActivities + strengthActivities
        let visibleExerciseLimit: Int
        switch prCount {
        case 0:
            visibleExerciseLimit = 8
        case 1:
            visibleExerciseLimit = 6
        default:
            visibleExerciseLimit = 4
        }
        let visibleExercises = Array(allActivities.prefix(visibleExerciseLimit))
        let remainingExerciseCount = max(0, allActivities.count - visibleExercises.count)
        let activityLabel: String
        switch (hasStrength, hasMainCardio) {
        case (true, true): activityLabel = "STRENGTH + CARDIO"
        case (true, false): activityLabel = "STRENGTH TRAINING"
        case (false, _): activityLabel = hasCardio ? "CARDIO" : "WORKOUT"
        }

        let primaryMetric: Metric
        if !hasStrength, let preferredCardioMetric {
            primaryMetric = Metric(
                title: preferredCardioMetric.title.uppercased(),
                value: preferredCardioMetric.value
            )
        } else if snapshot.totalVolume > 0 {
            primaryMetric = Metric(title: "TOTAL VOLUME", value: snapshot.totalVolumeText)
        } else if snapshot.completedSetCount > 0 {
            primaryMetric = Metric(title: "COMPLETED SETS", value: "\(snapshot.completedSetCount)")
        } else {
            primaryMetric = Metric(title: "DURATION", value: snapshot.durationText)
        }

        var supportingMetrics: [Metric]
        if !hasStrength, hasCardio {
            supportingMetrics = []
            if preferredCardioMetric?.kind != .duration {
                supportingMetrics.append(Metric(title: "DURATION", value: snapshot.durationText))
            }
            supportingMetrics.append(Metric(title: "ACTIVITIES", value: "\(completedCardio.count)"))
            if let secondaryCardioMetric {
                supportingMetrics.append(Metric(
                    title: secondaryCardioMetric.title.uppercased(),
                    value: secondaryCardioMetric.value
                ))
            }
        } else if hasCardio {
            supportingMetrics = [
                Metric(title: "DURATION", value: snapshot.durationText),
                Metric(title: "SETS", value: "\(snapshot.completedSetCount)"),
                Metric(title: "CARDIO", value: "\(completedCardio.count)"),
            ]
        } else if snapshot.totalVolume > 0 {
            supportingMetrics = [
                Metric(title: "DURATION", value: snapshot.durationText),
                Metric(title: "SETS", value: "\(snapshot.completedSetCount)"),
                Metric(title: "EXERCISES", value: "\(snapshot.exerciseCount)"),
            ]
        } else {
            supportingMetrics = [
                Metric(title: "DURATION", value: snapshot.durationText),
                Metric(title: "EXERCISES", value: "\(snapshot.exerciseCount)"),
                Metric(title: "NEW PRs", value: "\(prCount)"),
            ]
        }

        let cardioHighlight = completedCardio.first
        let cardioHighlightDetail = cardioHighlight.flatMap { cardio -> String? in
            let detail = cardio.summary.metrics.prefix(2)
                .map { "\($0.title) \($0.value)" }
                .joined(separator: " · ")
            return detail.isEmpty ? nil : detail
        }

        return Self(
            sessionName: snapshot.sessionName,
            completedAtText: snapshot.completedAtText,
            activityLabel: activityLabel,
            primaryMetric: primaryMetric,
            supportingMetrics: Array(supportingMetrics.prefix(3)),
            personalRecordCount: prCount,
            highlightTitle: firstRecord?.exerciseName
                ?? cardioHighlight?.exerciseName
                ?? "Workout complete",
            highlightDetail: firstRecord.map { "\($0.performanceText) · \($0.detailText)" }
                ?? cardioHighlightDetail
                ?? "\(snapshot.completedSetCount) completed sets logged",
            exercises: visibleExercises,
            remainingExerciseCount: remainingExerciseCount
        )
    }
}

struct WorkoutSharePreviewItem: Identifiable {
    let id = UUID()
    let presentation: WorkoutSharePresentation
}

private struct WorkoutShareSheetItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

@MainActor
enum WorkoutShareCardRenderer {
    static let canvasSize = CGSize(width: 360, height: 640)

    static func render(_ presentation: WorkoutSharePresentation) -> UIImage? {
        let renderer = ImageRenderer(
            content: WorkoutShareCard(presentation: presentation)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .medium)
        )
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private enum WorkoutShareAlert: String, Identifiable {
    case renderFailed

    var id: String { rawValue }

    var title: String {
        "Couldn’t Create Workout Image"
    }

    var message: String {
        "The workout image could not be created. Please try again."
    }
}

struct WorkoutShareCard: View {
    let presentation: WorkoutSharePresentation

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.045, blue: 0.085),
                    Color(red: 0.035, green: 0.09, blue: 0.15),
                    Color(red: 0.02, green: 0.035, blue: 0.065),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.10, green: 0.48, blue: 0.95).opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 72)
                .offset(x: 145, y: -270)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: -170, y: 290)

            VStack(alignment: .leading, spacing: 0) {
                brand
                Spacer(minLength: 28)
                title
                    .padding(.bottom, 26)
                primaryMetric
                    .padding(.bottom, 24)
                supportingMetrics
                    .padding(.bottom, 18)
                exerciseRecap
                if presentation.personalRecordCount > 0 {
                    highlight
                        .padding(.top, 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
        }
        .clipped()
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(width: 31, height: 31)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("WE GO JIM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Text("TRAINING LOG")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.46))
            }

            Spacer()

            Text(presentation.completedAtText.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(presentation.activityLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color(red: 0.34, green: 0.74, blue: 1.0))
            Text(presentation.sessionName)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
        }
    }

    private var primaryMetric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.primaryMetric.title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.48))
            Text(presentation.primaryMetric.value)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
    }

    private var supportingMetrics: some View {
        HStack(spacing: 0) {
            ForEach(Array(presentation.supportingMetrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 36)
                }
                supportingMetric(
                    title: metric.title,
                    value: metric.value,
                    leadingPadding: index == 0 ? 0 : 12
                )
            }
        }
    }

    private func supportingMetric(
        title: String,
        value: String,
        leadingPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(Color.white.opacity(0.44))
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingPadding)
    }

    private var highlight: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.personalRecordCount > 0 ? "trophy.fill" : "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.35, green: 0.76, blue: 1.0))
                .frame(width: 29, height: 29)
                .background(Circle().fill(Color.white.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.highlightEyebrowText)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color(red: 0.35, green: 0.76, blue: 1.0))
                Text(presentation.highlightTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(presentation.highlightDetail)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let remainingPersonalRecordText = presentation.remainingPersonalRecordText {
                    Text(remainingPersonalRecordText)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var exerciseRecap: some View {
        if !presentation.exercises.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("WORKOUT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(Color(red: 0.35, green: 0.76, blue: 1.0))

                VStack(spacing: 0) {
                    ForEach(Array(presentation.exercises.enumerated()), id: \.offset) { index, exercise in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.35, green: 0.76, blue: 1.0))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.white.opacity(0.08)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                                Text(exercise.setProgressText)
                                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.42))
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(exercise.detailTitle)
                                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(Color.white.opacity(0.34))
                                Text(exercise.bestSetText)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.78))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }
                        .padding(.vertical, 7)
                    }

                    if presentation.remainingExerciseCount > 0 {
                        Text("+ \(presentation.remainingExerciseCount) more activities")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 28)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                )
            }
        }
    }
}

struct WorkoutSharePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: WorkoutSharePresentation

    @State private var shareSheetItem: WorkoutShareSheetItem?
    @State private var alert: WorkoutShareAlert?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                WorkoutShareCard(presentation: presentation)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
            }
            .navigationTitle("Workout Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    shareStory()
                } label: {
                    Label("Share Story", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("workout-share-preview-share-button")
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $shareSheetItem) { item in
            WGJActivityShareSheet(activityItems: [item.image])
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .accessibilityIdentifier("workout-share-preview")
    }

    @MainActor
    private func shareStory() {
        guard let image = WorkoutShareCardRenderer.render(presentation) else {
            alert = .renderFailed
            return
        }
        shareSheetItem = WorkoutShareSheetItem(image: image)
    }
}
