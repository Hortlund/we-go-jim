import SwiftUI
import UIKit

nonisolated struct WorkoutSharePresentation: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        let title: String
        let value: String
    }

    struct CardioStory: Equatable, Sendable {
        let sessionID: UUID
        let activityID: UUID
        let activityName: String
        let primaryMetric: Metric
        let supportingMetrics: [Metric]
        let otherActivityCount: Int
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
    var cardioStory: CardioStory? = nil

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
                setProgressText: recap.shareSetBreakdownText,
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
            primaryMetric = Metric(title: "WORKING SETS", value: "\(snapshot.completedSetCount)")
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
                Metric(title: "WORKING SETS", value: "\(snapshot.completedSetCount)"),
                Metric(title: "CARDIO", value: "\(completedCardio.count)"),
            ]
        } else if snapshot.totalVolume > 0 {
            supportingMetrics = [
                Metric(title: "DURATION", value: snapshot.durationText),
                Metric(title: "WORKING SETS", value: "\(snapshot.completedSetCount)"),
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

        let focusedCardio = completedCardio.first { $0.role == .main } ?? completedCardio.first
        let cardioStory = !hasStrength ? focusedCardio.map { cardio in
            let metrics = cardio.summary.metrics
            let primary = metrics.first { $0.kind == .distance }
                ?? metrics.first { $0.kind == .duration } ?? metrics.first
            let supporting = metrics.filter { $0.kind != primary?.kind }
            return CardioStory(
                sessionID: snapshot.sessionID,
                activityID: cardio.id,
                activityName: cardio.exerciseName,
                primaryMetric: primary.map { Metric(title: $0.title.uppercased(), value: $0.value) }
                    ?? Metric(title: "DURATION", value: snapshot.durationText),
                supportingMetrics: Array(supporting.prefix(3).map { Metric(title: $0.title.uppercased(), value: $0.value) }),
                otherActivityCount: max(0, completedCardio.count - 1)
            )
        } : nil

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
                ?? snapshot.shareSetBreakdownText,
            exercises: visibleExercises,
            remainingExerciseCount: remainingExerciseCount,
            cardioStory: cardioStory
        )
    }
}

private extension WorkoutCompletionSnapshot {
    nonisolated var shareSetBreakdownText: String {
        guard completedWarmupSetCount > 0 else {
            return "\(completedSetCount) working set\(completedSetCount == 1 ? "" : "s") logged"
        }
        return "\(completedSetCount) working · \(completedWarmupSetCount) warm-up"
    }
}

private extension WorkoutCompletionExerciseRecap {
    nonisolated var shareSetBreakdownText: String {
        let working = completedSetCount == totalSetCount
            ? "\(completedSetCount) working"
            : "\(completedSetCount)/\(totalSetCount) working"
        guard totalWarmupSetCount > 0 else { return working }
        let warmups = completedWarmupSetCount == totalWarmupSetCount
            ? "\(completedWarmupSetCount) warm-up"
            : "\(completedWarmupSetCount)/\(totalWarmupSetCount) warm-up"
        return "\(working) · \(warmups)"
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
    static let canvasSize = TrainingShareImageRenderer.canvasSize

    static func render(_ presentation: WorkoutSharePresentation, routeImage: UIImage? = nil) -> UIImage? {
        TrainingShareImageRenderer.render(WorkoutShareCard(presentation: presentation, routeImage: routeImage))
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
    var routeImage: UIImage? = nil

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
                if let cardio = presentation.cardioStory {
                    cardioContent(cardio)
                } else {
                    title
                        .padding(.top, 16)
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
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
        }
        .clipped()
    }

    private func cardioContent(_ cardio: WorkoutSharePresentation.CardioStory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title.padding(.top, 20).padding(.bottom, 20)
            if cardio.activityName != presentation.sessionName {
                Text(cardio.activityName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }
            if let routeImage {
                Image(uiImage: routeImage)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 230)
                    .layoutPriority(-1)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1))
                    .accessibilityLabel("Recorded route")
                    .accessibilityIdentifier("workout-share-cardio-route")
                    .padding(.bottom, 20)
            } else {
                Image(systemName: "figure.mixed.cardio")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(WGJTheme.accentCyan)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, 26)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(cardio.primaryMetric.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
                Text(cardio.primaryMetric.value)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(WGJTheme.accentCyan)
                    .lineLimit(1).minimumScaleFactor(0.56)
            }
            .padding(.bottom, 18)
            HStack(spacing: 0) {
                ForEach(Array(cardio.supportingMetrics.enumerated()), id: \.offset) { index, metric in
                    supportingMetric(title: metric.title, value: metric.value, leadingPadding: index == 0 ? 0 : 10)
                }
            }
            Spacer(minLength: 8)
            if cardio.otherActivityCount > 0 {
                Text("+ \(cardio.otherActivityCount) more activities")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-share-cardio-story")
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
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
    @State private var routeImage: UIImage?
    @State private var isLoadingRoute = true

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { geometry in
                    WorkoutShareCard(presentation: presentation, routeImage: routeImage)
                        .frame(width: WorkoutShareCardRenderer.canvasSize.width, height: WorkoutShareCardRenderer.canvasSize.height)
                        .environment(\.dynamicTypeSize, .medium)
                        .scaleEffect(geometry.size.width / WorkoutShareCardRenderer.canvasSize.width, anchor: .topLeading)
                }
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(20)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
            }
            .wgjScreenBackground()
            .wgjNavigationChrome()
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
                .disabled(isLoadingRoute)
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: presentation.cardioStory?.activityID) {
            routeImage = nil
            isLoadingRoute = true
            guard let cardio = presentation.cardioStory,
                  let route = await WorkoutShareRouteImage.loadRoute(for: cardio), !Task.isCancelled else {
                isLoadingRoute = false
                return
            }
            // A route drawing is ready even offline; map tiles improve it when available.
            routeImage = WorkoutShareRouteImage.drawing(route)
            isLoadingRoute = false
            if let mapImage = await WorkoutShareRouteImage.mapSnapshot(route), !Task.isCancelled {
                routeImage = mapImage
            }
        }
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
        guard let image = WorkoutShareCardRenderer.render(presentation, routeImage: routeImage) else {
            alert = .renderFailed
            return
        }
        shareSheetItem = WorkoutShareSheetItem(image: image)
    }
}
