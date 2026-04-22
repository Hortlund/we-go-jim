import SwiftData
import SwiftUI
import UIKit

struct WorkoutCompletionSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppTabState.self) private var appTabState
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState

    let sessionID: UUID

    @State private var snapshot: WorkoutCompletionSnapshot?
    @State private var hasTriggeredCelebration = false
    @State private var celebrationBurstCount = 0
    @State private var showsConfetti = false
    @State private var confettiPresentationID = UUID()
    @State private var confettiDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let snapshot {
                        heroCard(snapshot)
                        statGrid(snapshot)
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

            if showsConfetti && !reduceMotion {
                WorkoutCompletionConfettiOverlay()
                    .id(confettiPresentationID)
                    .frame(height: 280)
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
                    .accessibilityIdentifier("workout-completion-confetti-overlay")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAction
        }
        .task {
            await loadSnapshotIfNeeded()
        }
        .onDisappear {
            confettiDismissTask?.cancel()
            confettiDismissTask = nil
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
        Button {
            triggerCelebration()
        } label: {
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

                Label(
                    reduceMotion ? "Tap to celebrate again" : "Tap for more confetti",
                    systemImage: "sparkles"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentCyan)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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

        do {
            guard let builtSnapshot = try WorkoutCompletionSnapshotBuilder.build(
                sessionID: sessionID,
                modelContext: modelContext
            ) else {
                continueToHistory()
                return
            }

            snapshot = builtSnapshot
            triggerCelebrationIfNeeded()
        } catch {
            continueToHistory()
        }
    }

    private func triggerCelebrationIfNeeded() {
        guard !hasTriggeredCelebration else { return }
        hasTriggeredCelebration = true
        triggerCelebration()
    }

    private func triggerCelebration() {
        celebrationBurstCount += 1

        WorkoutFeedbackCenter.shared.workoutCompleted()

        guard !reduceMotion else { return }
        confettiDismissTask?.cancel()

        confettiPresentationID = UUID()
        showsConfetti = true
        let burstCount = celebrationBurstCount

        confettiDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            guard burstCount == celebrationBurstCount else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showsConfetti = false
            }
            confettiDismissTask = nil
        }
    }

    private func continueToHistory() {
        appTabState.selectedTab = .history
        workoutCompletionPresentationState.dismiss()
    }
}

struct WorkoutCompletionSnapshot: Equatable {
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
    let exerciseRecap: [WorkoutCompletionExerciseRecap]
}

struct WorkoutCompletionPersonalRecord: Identifiable, Equatable {
    let id: String
    let exerciseName: String
    let performanceText: String
    let detailText: String
}

struct WorkoutCompletionExerciseRecap: Identifiable, Equatable {
    let id: UUID
    let exerciseName: String
    let completedSetCount: Int
    let totalSetCount: Int
    let bestSetText: String
    let structure: WorkoutExerciseStructurePresentation
}

struct WorkoutCompletionCardioRecap: Identifiable, Equatable {
    let id: String
    let phase: WorkoutCardioPhase
    let exerciseName: String
    let descriptor: String?
    let targetDurationSeconds: Int
    let isCompleted: Bool
}

private struct WorkoutCompletionExerciseData {
    let completedSetCount: Int
    let recap: WorkoutCompletionExerciseRecap
}

@MainActor
enum WorkoutCompletionSnapshotBuilder {
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

private struct WorkoutCompletionConfettiOverlay: View {
    @State private var animate = false

    private let pieces = WorkoutCompletionConfettiPiece.defaults

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: piece.cornerRadius, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(animate ? piece.endRotation : piece.startRotation))
                        .position(
                            x: (proxy.size.width * 0.5) + (piece.originX * proxy.size.width * 0.16),
                            y: -24 + (piece.originY * 20)
                        )
                        .offset(
                            x: animate ? piece.travelX * proxy.size.width * 0.48 : 0,
                            y: animate ? piece.travelY * proxy.size.height : 0
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

    static let defaults: [WorkoutCompletionConfettiPiece] = [
        WorkoutCompletionConfettiPiece(id: 0, width: 10, height: 18, cornerRadius: 4, originX: -0.4, originY: 0.2, travelX: -0.65, travelY: 0.86, startRotation: -12, endRotation: 240, delay: 0.00, duration: 1.7, color: WGJTheme.accentBlue),
        WorkoutCompletionConfettiPiece(id: 1, width: 12, height: 12, cornerRadius: 6, originX: -0.22, originY: 0.5, travelX: -0.32, travelY: 0.92, startRotation: 8, endRotation: 320, delay: 0.04, duration: 1.8, color: WGJTheme.accentGold),
        WorkoutCompletionConfettiPiece(id: 2, width: 8, height: 18, cornerRadius: 4, originX: -0.08, originY: 0.1, travelX: -0.12, travelY: 0.80, startRotation: -18, endRotation: 260, delay: 0.07, duration: 1.55, color: WGJTheme.success),
        WorkoutCompletionConfettiPiece(id: 3, width: 10, height: 14, cornerRadius: 4, originX: 0.10, originY: 0.6, travelX: 0.14, travelY: 0.88, startRotation: 12, endRotation: 280, delay: 0.02, duration: 1.7, color: WGJTheme.accentCyan),
        WorkoutCompletionConfettiPiece(id: 4, width: 12, height: 16, cornerRadius: 5, originX: 0.28, originY: 0.2, travelX: 0.46, travelY: 0.84, startRotation: -10, endRotation: 250, delay: 0.03, duration: 1.75, color: WGJTheme.accentBlue),
        WorkoutCompletionConfettiPiece(id: 5, width: 9, height: 18, cornerRadius: 4, originX: 0.42, originY: 0.4, travelX: 0.70, travelY: 0.90, startRotation: 20, endRotation: 330, delay: 0.09, duration: 1.88, color: WGJTheme.accentGold),
        WorkoutCompletionConfettiPiece(id: 6, width: 10, height: 10, cornerRadius: 5, originX: -0.34, originY: 0.8, travelX: -0.56, travelY: 0.74, startRotation: 0, endRotation: 180, delay: 0.12, duration: 1.45, color: WGJTheme.success),
        WorkoutCompletionConfettiPiece(id: 7, width: 8, height: 20, cornerRadius: 4, originX: -0.16, originY: 0.3, travelX: -0.22, travelY: 0.96, startRotation: 16, endRotation: 300, delay: 0.11, duration: 1.92, color: WGJTheme.accentCyan),
        WorkoutCompletionConfettiPiece(id: 8, width: 12, height: 14, cornerRadius: 4, originX: 0.00, originY: 0.4, travelX: 0.00, travelY: 0.90, startRotation: -6, endRotation: 210, delay: 0.05, duration: 1.65, color: WGJTheme.accentGold),
        WorkoutCompletionConfettiPiece(id: 9, width: 10, height: 18, cornerRadius: 4, originX: 0.18, originY: 0.1, travelX: 0.24, travelY: 0.76, startRotation: 14, endRotation: 280, delay: 0.14, duration: 1.50, color: WGJTheme.accentBlue),
        WorkoutCompletionConfettiPiece(id: 10, width: 9, height: 16, cornerRadius: 4, originX: 0.36, originY: 0.7, travelX: 0.60, travelY: 0.78, startRotation: -8, endRotation: 230, delay: 0.10, duration: 1.58, color: WGJTheme.success),
        WorkoutCompletionConfettiPiece(id: 11, width: 12, height: 12, cornerRadius: 6, originX: -0.48, originY: 0.6, travelX: -0.74, travelY: 0.68, startRotation: 6, endRotation: 190, delay: 0.06, duration: 1.38, color: WGJTheme.accentCyan),
        WorkoutCompletionConfettiPiece(id: 12, width: 8, height: 18, cornerRadius: 4, originX: -0.26, originY: 0.2, travelX: -0.18, travelY: 0.70, startRotation: -14, endRotation: 210, delay: 0.18, duration: 1.32, color: WGJTheme.accentBlue),
        WorkoutCompletionConfettiPiece(id: 13, width: 10, height: 20, cornerRadius: 4, originX: 0.08, originY: 0.3, travelX: 0.18, travelY: 0.72, startRotation: 8, endRotation: 220, delay: 0.16, duration: 1.42, color: WGJTheme.accentGold),
        WorkoutCompletionConfettiPiece(id: 14, width: 11, height: 14, cornerRadius: 4, originX: 0.24, originY: 0.5, travelX: 0.40, travelY: 0.66, startRotation: -10, endRotation: 200, delay: 0.19, duration: 1.34, color: WGJTheme.success),
        WorkoutCompletionConfettiPiece(id: 15, width: 8, height: 16, cornerRadius: 4, originX: -0.02, originY: 0.9, travelX: -0.05, travelY: 0.62, startRotation: 18, endRotation: 170, delay: 0.15, duration: 1.24, color: WGJTheme.accentCyan),
    ]
}
