import SwiftData
import SwiftUI
import UIKit

nonisolated enum WorkoutCompletionConfettiOrigin {
    static func tapOrigin(locationInGlobalSpace location: CGPoint, heroFrame: CGRect) -> CGPoint {
        location
    }

    static func overlayOrigin(
        locationInGlobalSpace location: CGPoint,
        overlayFrameInGlobalSpace: CGRect
    ) -> CGPoint {
        guard !overlayFrameInGlobalSpace.isEmpty else { return location }

        return CGPoint(
            x: location.x - overlayFrameInGlobalSpace.minX,
            y: location.y - overlayFrameInGlobalSpace.minY
        )
    }

    static func defaultOrigin(heroFrame: CGRect, fallbackScreenWidth: CGFloat) -> CGPoint {
        guard !heroFrame.isEmpty else {
            return CGPoint(x: fallbackScreenWidth / 2, y: 140)
        }

        return CGPoint(x: heroFrame.midX, y: heroFrame.minY + min(96, heroFrame.height * 0.36))
    }
}

nonisolated enum WorkoutCompletionConfettiIntensity {
    case completedWorkout
    case manualTap
}

nonisolated enum WorkoutCompletionConfettiPolicy {
    static func pieceCount(for intensity: WorkoutCompletionConfettiIntensity) -> Int {
        switch intensity {
        case .completedWorkout:
            return 48
        case .manualTap:
            return 22
        }
    }
}

struct WorkoutCompletionSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppTabState.self) private var appTabState
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState

    let sessionID: UUID

    @State private var snapshot: WorkoutCompletionSnapshot?
    @State private var hasTriggeredCelebration = false
    @State private var celebrationBurstCount = 0
    @State private var confettiBursts: [WorkoutCompletionConfettiBurst] = []
    @State private var confettiDismissTasks: [UUID: Task<Void, Never>] = [:]
    @State private var heroCardFrame: CGRect = .zero

    private var completionBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let snapshot {
                        heroCard(snapshot)
                        statGrid(snapshot)
                        muscleHeatmapSection(snapshot)
                        personalRecordsSection(snapshot)
                        cardioRecapSection(snapshot)
                        exerciseRecapSection(snapshot)
                    } else {
                        loadingState
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .wgjScreenBackground()

            if !confettiBursts.isEmpty && !reduceMotion {
                ZStack {
                    ForEach(confettiBursts) { burst in
                        WorkoutCompletionConfettiOverlay(
                            originInGlobalSpace: burst.origin,
                            pieces: burst.pieces
                        )
                            .id(burst.id)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .accessibilityIdentifier("workout-completion-confetti-overlay")
            }
        }
        .coordinateSpace(name: "workout-completion-summary-space")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAction
        }
        .task {
            await loadSnapshotIfNeeded()
        }
        .onDisappear {
            confettiDismissTasks.values.forEach { $0.cancel() }
            confettiDismissTasks = [:]
        }
        .accessibilityIdentifier("workout-completion-summary")
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Loading your workout recap...")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text("Saving the session and preparing your summary.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .wgjCardContainer(strong: true)
    }

    private var bottomAction: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(WGJTheme.outline.opacity(0.28))

            Button {
                continueToHistory()
            } label: {
                Label("View History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("workout-completion-confirm-button")
            }
            .buttonStyle(WGJPrimaryButtonStyle())
            .accessibilityIdentifier("workout-completion-confirm-button")
            .padding(16)
        }
        .background(WGJTheme.bgBase.opacity(0.98))
    }

    private func heroCard(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        Button { } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.celebrationTitle.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(snapshot.personalRecords.isEmpty ? WGJTheme.accentCyan : WGJTheme.accentGold)

                        Text(snapshot.sessionName)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(snapshot.celebrationSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        WGJTheme.accentBlue.opacity(0.92),
                                        snapshot.personalRecords.isEmpty ? WGJTheme.accentCyan.opacity(0.80) : WGJTheme.accentGold.opacity(0.86),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 74, height: 74)

                        Image(systemName: snapshot.personalRecords.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                            .font(.title.weight(.bold))
                            .foregroundStyle(WGJTheme.textInverse)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        WGJMetricPill(
                            systemImage: "calendar",
                            value: snapshot.completedAtText,
                            tint: WGJTheme.accentCyan
                        )
                        WGJMetricPill(
                            systemImage: snapshot.personalRecords.isEmpty ? "sparkles" : "trophy.fill",
                            value: snapshot.prHeadline,
                            tint: snapshot.personalRecords.isEmpty ? WGJTheme.accentBlue : WGJTheme.accentGold
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        WGJMetricPill(
                            systemImage: "calendar",
                            value: snapshot.completedAtText,
                            tint: WGJTheme.accentCyan
                        )
                        WGJMetricPill(
                            systemImage: snapshot.personalRecords.isEmpty ? "sparkles" : "trophy.fill",
                            value: snapshot.prHeadline,
                            tint: snapshot.personalRecords.isEmpty ? WGJTheme.accentBlue : WGJTheme.accentGold
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: WorkoutCompletionHeroFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
            }
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .fill(WGJTheme.cardStrong.opacity(0.98))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        WGJTheme.accentBlue.opacity(0.18),
                                        WGJTheme.accentCyan.opacity(0.10),
                                        Color.clear,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                            .stroke(WGJTheme.accentBlue.opacity(0.18), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous))
        .onPreferenceChange(WorkoutCompletionHeroFramePreferenceKey.self) { frame in
            heroCardFrame = frame
        }
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global)
                .onEnded { value in
                    triggerCelebration(origin: confettiOrigin(for: value.location), intensity: .manualTap)
                }
        )
        .accessibilityAction {
            triggerCelebration(origin: defaultConfettiOrigin(), intensity: .manualTap)
        }
        .accessibilityIdentifier("workout-completion-hero-card")
        .accessibilityLabel("Workout completion celebration")
        .accessibilityValue("Celebration burst \(celebrationBurstCount)")
        .accessibilityHint(
            reduceMotion
            ? "Double tap to replay the celebration feedback."
            : "Double tap to launch more confetti."
        )
    }

    private func statGrid(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            WorkoutCompletionStatCard(
                title: "Duration",
                value: snapshot.durationText,
                systemImage: "clock.fill",
                tint: WGJTheme.accentCyan
            )
            WorkoutCompletionStatCard(
                title: "Exercises",
                value: "\(snapshot.exerciseCount)",
                systemImage: "list.number",
                tint: WGJTheme.accentBlue
            )
            WorkoutCompletionStatCard(
                title: "Completed Sets",
                value: "\(snapshot.completedSetCount)",
                systemImage: "checkmark.circle.fill",
                tint: WGJTheme.success
            )
            WorkoutCompletionStatCard(
                title: "Volume",
                value: snapshot.totalVolumeText,
                systemImage: "scalemass.fill",
                tint: WGJTheme.accentGold
            )
        }
    }

    private func personalRecordsSection(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("PR Highlights", subtitle: snapshot.prSupportText)

            if snapshot.personalRecords.isEmpty {
                WGJEmptyStateCard(
                    title: snapshot.prHeadline,
                    message: snapshot.prSupportText,
                    icon: "sparkles"
                )
            } else {
                ForEach(snapshot.personalRecords) { record in
                    WorkoutCompletionPersonalRecordCard(record: record)
                }
            }
        }
    }

    private func muscleHeatmapSection(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        WorkoutMuscleHeatmapCard(
            title: "Muscle Heatmap",
            subtitle: "Worked this session",
            snapshot: snapshot.muscleHeatmap,
            emptyMessage: "No working-set muscle data was found for this workout."
        )
    }

    private func exerciseRecapSection(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Exercise Recap", subtitle: "Every exercise you closed out in this session.")

            ForEach(snapshot.exerciseRecap) { recap in
                WorkoutCompletionExerciseRecapCard(recap: recap)
            }
        }
    }

    @ViewBuilder
    private func cardioRecapSection(_ snapshot: WorkoutCompletionSnapshot) -> some View {
        if !snapshot.cardioRecap.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Cardio Phases",
                    subtitle: "The timed warmup and cooldown blocks tracked in this session."
                )

                ForEach(snapshot.cardioRecap) { cardio in
                    WorkoutCardioPhaseCard(
                        phase: cardio.phase,
                        exerciseName: cardio.exerciseName,
                        descriptor: cardio.descriptor,
                        targetDurationSeconds: cardio.targetDurationSeconds,
                        statusText: cardio.isCompleted ? "Complete" : "Not finished",
                        statusTint: cardio.isCompleted ? WGJTheme.success : WGJTheme.warning,
                        footnote: cardio.isCompleted ? nil : "This workout was finished before this cardio phase was completed."
                    )
                }
            }
        }
    }

    @MainActor
    private func loadSnapshotIfNeeded() async {
        guard snapshot == nil else { return }
        let backgroundStore = completionBackgroundStore

        do {
            let builtSnapshot = try await backgroundStore.perform("workout-completion.summary") { backgroundContext in
                try WorkoutCompletionSnapshotBuilder.build(
                    sessionID: sessionID,
                    modelContext: backgroundContext
                )
            }
            guard !Task.isCancelled else { return }
            guard let builtSnapshot else {
                continueToHistory()
                return
            }

            withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
                snapshot = builtSnapshot
            }
            Task { @MainActor in
                await Task.yield()
                triggerCelebrationIfNeeded()
            }
        } catch {
            continueToHistory()
        }
    }

    private func triggerCelebrationIfNeeded() {
        guard !hasTriggeredCelebration else { return }
        hasTriggeredCelebration = true
        triggerCelebration(origin: defaultConfettiOrigin(), intensity: .completedWorkout)
    }

    private func triggerCelebration(
        origin: CGPoint,
        intensity: WorkoutCompletionConfettiIntensity
    ) {
        celebrationBurstCount += 1

        WorkoutFeedbackCenter.shared.workoutCompleted()

        guard !reduceMotion else { return }
        let burst = WorkoutCompletionConfettiBurst(
            origin: origin,
            intensity: intensity
        )
        confettiBursts.append(burst)
        confettiDismissTasks[burst.id]?.cancel()
        confettiDismissTasks[burst.id] = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await self.removeConfettiBurstAfterDelayIfStillNeeded(id: burst.id)
        }
    }

    @MainActor
    private func removeConfettiBurstAfterDelayIfStillNeeded(id: UUID) {
        guard !Task.isCancelled else { return }
        confettiBursts.removeAll { $0.id == id }
        confettiDismissTasks[id] = nil
    }

    private func confettiOrigin(for location: CGPoint) -> CGPoint {
        WorkoutCompletionConfettiOrigin.tapOrigin(
            locationInGlobalSpace: location,
            heroFrame: heroCardFrame
        )
    }

    private func defaultConfettiOrigin() -> CGPoint {
        WorkoutCompletionConfettiOrigin.defaultOrigin(
            heroFrame: heroCardFrame,
            fallbackScreenWidth: UIScreen.main.bounds.width
        )
    }

    private func continueToHistory() {
        appTabState.selectedTab = .history
        workoutCompletionPresentationState.dismiss()
    }
}

struct WorkoutCompletionSnapshot: Equatable, Sendable {
    let sessionID: UUID
    let sessionName: String
    let celebrationTitle: String
    let celebrationSubtitle: String
    let completedAtText: String
    let durationText: String
    let exerciseCount: Int
    let completedSetCount: Int
    let totalVolumeText: String
    let prHeadline: String
    let prSupportText: String
    let personalRecords: [WorkoutCompletionPersonalRecord]
    let cardioRecap: [WorkoutCompletionCardioRecap]
    let muscleHeatmap: WorkoutMuscleHeatmapSnapshot
    let exerciseRecap: [WorkoutCompletionExerciseRecap]
}

struct WorkoutCompletionPersonalRecord: Identifiable, Equatable, Sendable {
    let id: String
    let exerciseName: String
    let performanceText: String
    let detailText: String
}

struct WorkoutCompletionExerciseRecap: Identifiable, Equatable, Sendable {
    let id: UUID
    let exerciseName: String
    let completedSetCount: Int
    let totalSetCount: Int
    let bestSetText: String
    let structure: WorkoutExerciseStructurePresentation
}

struct WorkoutCompletionCardioRecap: Identifiable, Equatable, Sendable {
    let id: String
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let descriptor: String?
    let targetDurationSeconds: Int
    let isCompleted: Bool
}

private struct WorkoutCompletionExerciseData: Sendable {
    let completedSetCount: Int
    let recap: WorkoutCompletionExerciseRecap
}

nonisolated enum WorkoutCompletionSnapshotBuilder {
    static func build(sessionID: UUID, modelContext: ModelContext) throws -> WorkoutCompletionSnapshot? {
        let repository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try repository.session(id: sessionID), session.status == .completed else {
            return nil
        }

        let exercises = try repository.sessionExercises(sessionID: sessionID)
        let cardioBlocks = try repository.sessionCardioBlocks(sessionID: sessionID)
        let exerciseData = exercises.map(makeExerciseData)
        let completedSetCount = exerciseData.reduce(0) { partialResult, data in
            partialResult + data.completedSetCount
        }
        let catalogMuscleMappings = try WorkoutMuscleHeatmapBuilder.catalogMappings(modelContext: modelContext)
        let muscleHeatmapScores = exercises.reduce(into: [ExerciseBodyMapRegion: Double]()) { scores, exercise in
            let exerciseScores = WorkoutMuscleHeatmapBuilder.scores(
                for: exercise,
                catalogMappings: catalogMuscleMappings
            )
            for (region, score) in exerciseScores {
                scores[region, default: 0] += score
            }
        }
        let personalRecords = try WorkoutMetricsService(modelContext: modelContext)
            .sessionSetPRAchievements(sessionID: sessionID)
            .map(makePersonalRecord)

        let prHeadline: String
        let prSupportText: String
        switch personalRecords.count {
        case 0:
            prHeadline = "No new PRs today"
            prSupportText = "You logged \(completedSetCount) completed sets across \(exercises.count) exercise\(exercises.count == 1 ? "" : "s")."
        case 1:
            prHeadline = "1 new PR today"
            prSupportText = "Your new PR from this session is listed below."
        default:
            prHeadline = "\(personalRecords.count) new PRs today"
            prSupportText = "Your new PRs from this session are listed below."
        }

        return WorkoutCompletionSnapshot(
            sessionID: session.id,
            sessionName: session.name,
            celebrationTitle: personalRecords.isEmpty ? "Workout Complete" : "New PRs Logged",
            celebrationSubtitle: personalRecords.isEmpty
                ? "Your session has been saved and is ready in History."
                : "Your session has been saved, and your new PRs are ready in History.",
            completedAtText: (session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened),
            durationText: formattedDuration(session.durationSeconds),
            exerciseCount: exercises.count,
            completedSetCount: completedSetCount,
            totalVolumeText: formattedVolume(session.totalVolume),
            prHeadline: prHeadline,
            prSupportText: prSupportText,
            personalRecords: personalRecords,
            cardioRecap: cardioBlocks.map(makeCardioRecap),
            muscleHeatmap: WorkoutMuscleHeatmapBuilder.snapshot(scores: muscleHeatmapScores),
            exerciseRecap: exerciseData.map(\.recap)
        )
    }

    private static func makeExerciseData(_ exercise: WorkoutSessionExercise) -> WorkoutCompletionExerciseData {
        let sets = orderedSessionSets(for: exercise)
        let completedSets = sets.filter {
            WorkoutSessionSetDraft(model: $0).isCycleCompleted
        }

        return WorkoutCompletionExerciseData(
            completedSetCount: completedSets.count,
            recap: WorkoutCompletionExerciseRecap(
                id: exercise.id,
                exerciseName: exercise.exerciseNameSnapshot,
                completedSetCount: completedSets.count,
                totalSetCount: sets.count,
                bestSetText: WorkoutMetricsService.bestSetText(for: sets, emptyText: "No working set logged"),
                structure: WorkoutExerciseStructurePresentation(
                    supersetMembership: exercise.supersetMembership,
                    hasDropset: sets.contains { !($0.dropStages ?? []).isEmpty }
                )
            )
        )
    }

    private static func makePersonalRecord(_ achievement: SessionSetPRAchievement) -> WorkoutCompletionPersonalRecord {
        WorkoutCompletionPersonalRecord(
            id: achievement.id,
            exerciseName: achievement.exerciseName,
            performanceText: performanceText(for: achievement),
            detailText: detailText(for: achievement)
        )
    }

    private static func makeCardioRecap(_ cardioBlock: WorkoutSessionCardioBlock) -> WorkoutCompletionCardioRecap {
        WorkoutCompletionCardioRecap(
            id: cardioBlock.phase.rawValue,
            phase: cardioBlock.phase,
            exerciseName: cardioBlock.exerciseNameSnapshot,
            descriptor: cardioDescriptor(
                category: cardioBlock.categorySnapshot,
                muscleSummary: cardioBlock.muscleSummarySnapshot
            ),
            targetDurationSeconds: cardioBlock.targetDurationSeconds,
            isCompleted: cardioBlock.isCompleted
        )
    }

    private static func performanceText(for achievement: SessionSetPRAchievement) -> String {
        if let weight = achievement.weight, achievement.loadUnit != .bodyweight {
            return "\(WGJFormatters.decimalString(weight)) \(achievement.loadUnit.shortLabel) x \(achievement.reps)"
        }

        return "\(achievement.reps) reps"
    }

    private static func detailText(for achievement: SessionSetPRAchievement) -> String {
        let kindsText = achievement.kinds.map(\.title).joined(separator: " + ") + " PR"

        if achievement.kinds.contains(.strength), let estimatedOneRepMax = achievement.estimatedOneRepMax {
            return "\(kindsText) · \(WGJFormatters.oneDecimalString(estimatedOneRepMax)) \(achievement.loadUnit.shortLabel) e1RM"
        }

        if achievement.kinds.contains(.volume), let volume = achievement.volume {
            return "\(kindsText) · \(WGJFormatters.integerString(volume)) kg volume"
        }

        return kindsText
    }

    private static func orderedSessionSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    private static func formattedVolume(_ volume: Double) -> String {
        if volume == 0 {
            return "0 kg"
        }
        return "\(WGJFormatters.integerString(volume)) kg"
    }

    private static func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }
}

private struct WorkoutCompletionStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .wgjSingleLineText(scale: 0.78)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.14),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct WorkoutCompletionPersonalRecordCard: View {
    let record: WorkoutCompletionPersonalRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(WGJTheme.accentGold)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(WGJTheme.accentGold.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(record.exerciseName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Text(record.performanceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentGold)

                Text(record.detailText)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Spacer(minLength: 12)
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }
}

private struct WorkoutCompletionExerciseRecapCard: View {
    let recap: WorkoutCompletionExerciseRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recap.exerciseName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("\(recap.completedSetCount) / \(recap.totalSetCount) sets completed")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                Spacer(minLength: 12)

                WGJMetricPill(
                    systemImage: "checkmark.circle.fill",
                    value: "\(recap.completedSetCount)",
                    tint: recap.completedSetCount > 0 ? WGJTheme.success : WGJTheme.textSecondary
                )
            }

            structureBadgeRow

            VStack(alignment: .leading, spacing: 4) {
                Text("Best Set")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Text(recap.bestSetText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var structureBadgeRow: some View {
        if recap.structure.isSuperset || recap.structure.hasDropset {
            HStack(spacing: 8) {
                if recap.structure.isSuperset {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                }
                if let position = recap.structure.supersetPosition {
                    structureBadge(position.label, tint: WGJTheme.accentCyan)
                }
                if recap.structure.hasDropset {
                    structureBadge("Dropset", tint: WGJTheme.accentGold)
                }
            }
        }
    }

    private func structureBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}

private struct WorkoutCompletionHeroFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct WorkoutCompletionConfettiBurst: Identifiable {
    let id = UUID()
    let origin: CGPoint
    let pieces: [WorkoutCompletionConfettiPiece]

    init(origin: CGPoint, intensity: WorkoutCompletionConfettiIntensity) {
        self.origin = origin
        self.pieces = WorkoutCompletionConfettiPiece.random(
            seed: UInt64.random(in: 1...UInt64.max),
            count: WorkoutCompletionConfettiPolicy.pieceCount(for: intensity)
        )
    }
}

private struct WorkoutCompletionConfettiOverlay: View {
    let originInGlobalSpace: CGPoint
    let pieces: [WorkoutCompletionConfettiPiece]

    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            let overlayFrameInGlobal = proxy.frame(in: .global)
            let origin = WorkoutCompletionConfettiOrigin.overlayOrigin(
                locationInGlobalSpace: originInGlobalSpace,
                overlayFrameInGlobalSpace: overlayFrameInGlobal
            )

            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(animate ? piece.endRotation : piece.startRotation))
                        .position(
                            x: origin.x + (piece.originX * 18),
                            y: origin.y + (piece.originY * 18)
                        )
                        .offset(
                            x: animate ? piece.travelX * min(proxy.size.width, 420) : 0,
                            y: animate ? piece.travelY * min(proxy.size.height, 520) : 0
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: piece.duration)
                                .delay(piece.delay),
                            value: animate
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
        .onAppear {
            animate = true
        }
    }
}

private struct WorkoutCompletionConfettiPiece: Identifiable {
    let id: Int
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let travelX: CGFloat
    let travelY: CGFloat
    let startRotation: Double
    let endRotation: Double
    let delay: Double
    let duration: Double
    let color: Color

    static func random(seed: UInt64, count: Int) -> [WorkoutCompletionConfettiPiece] {
        var generator = WorkoutCompletionConfettiRandom(seed: seed)
        let colors = [WGJTheme.accentBlue, WGJTheme.accentGold, WGJTheme.success, WGJTheme.accentCyan]

        return (0..<count).map { index in
            let width = generator.value(in: CGFloat(7)...CGFloat(14))
            let height = generator.value(in: CGFloat(9)...CGFloat(22))
            let direction = generator.value(in: 0.0...(2.0 * Double.pi))
            let distance = generator.value(in: 0.32...1.0)
            let upwardKick = generator.value(in: -0.28...0.14)
            return WorkoutCompletionConfettiPiece(
                id: index,
                width: width,
                height: height,
                cornerRadius: min(width, height) * generator.value(in: 0.18...0.5),
                originX: generator.value(in: -1...1),
                originY: generator.value(in: -0.8...0.8),
                travelX: cos(direction) * distance,
                travelY: abs(sin(direction)) * generator.value(in: 0.42...1.02) + upwardKick,
                startRotation: generator.value(in: -45...45),
                endRotation: generator.value(in: 180...760) * (generator.nextBool() ? 1 : -1),
                delay: generator.value(in: 0...0.18),
                duration: generator.value(in: 1.15...2.1),
                color: colors[index % colors.count]
            )
        }
    }
}

private struct WorkoutCompletionConfettiRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func nextBool() -> Bool {
        nextUnit() >= 0.5
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(value(in: Double(range.lowerBound)...Double(range.upperBound)))
    }

    private mutating func nextUnit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}
