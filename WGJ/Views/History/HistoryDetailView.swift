import Foundation
import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    private let sessionID: UUID

    @State private var hasBootstrapped = false
    @State private var didLoadSnapshot = false
    @State private var snapshot: HistoryDetailSnapshotBuilder.Snapshot?
    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var notesByExerciseID: [UUID: String] = [:]
    @State private var hydrationPayloadByExerciseID: [UUID: HistoryDetailSnapshotBuilder.ExerciseHydrationPayload] = [:]
    @State private var personalRecordPresentationByExerciseID: [UUID: HistoryExercisePersonalRecordPresentation] = [:]
    @State private var loadedExerciseStateStamp: HistoryExerciseInteractionStamp?
    @State private var expandedExerciseIDs: [UUID: Bool] = [:]
    @State private var hasPendingSummaryRebuild = false
    @State private var isSavingChanges = false
    @State private var rowFlushCoordinator = WorkoutExerciseRowFlushCoordinator()

    @State private var showingExercisePicker = false
    @State private var showingArchiveConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var session: HistoryDetailSnapshotBuilder.SessionSnapshot? {
        snapshot?.session
    }

    private var sessionExercises: [HistoryDetailSnapshotBuilder.ExerciseSnapshot] {
        snapshot?.exercises ?? []
    }

    private var orderedCardioBlocks: [HistoryDetailSnapshotBuilder.CardioBlockSnapshot] {
        snapshot?.cardioBlocks ?? []
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                if let session {
                    headerCard(session)
                    workoutMuscleHeatmapCard
                    cardioSection
                    exercisesSectionHeader
                } else if didLoadSnapshot {
                    WGJEmptyStateCard(
                        title: "Workout not found",
                        message: "This workout could not be loaded.",
                        icon: "exclamationmark.triangle"
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }

                if sessionExercises.isEmpty {
                    WGJEmptyStateCard(
                        title: "No exercises logged",
                        message: "Add exercises to update this workout and save corrected sets or rest values.",
                        icon: "list.bullet.rectangle"
                    ) {
                        Button("Add Exercise") {
                            showingExercisePicker = true
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                    }
                }

                ForEach(Array(sessionExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseSection(exercise, index: index)
                        .id(exercise.id)
                }

                if !sessionExercises.isEmpty {
                    addExerciseButton(title: "Add another exercise")
                        .disabled(session == nil)
                }

                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .disabled(session == nil || isSavingChanges)
                .accessibilityIdentifier("history-detail-save-changes-button")
            }
            .padding(WGJSpacing.page)
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingArchiveConfirmation = true
                } label: {
                    Label("Hide", systemImage: "archivebox")
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(repository: catalogRepository) { item in
                addExercise(item)
            }
            .wgjSheetSurface()
        }
        .confirmationDialog("Hide workout?", isPresented: $showingArchiveConfirmation, titleVisibility: .visible) {
            Button("Hide Workout") {
                archiveSession()
            }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            await bootstrapIfNeeded()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .wgjMinimalKeyboardToolbar()
    }

    private var personalRecordSummary: HistoryWorkoutPersonalRecordSummary {
        HistoryWorkoutPersonalRecordSummary(highlightedSetCount: session?.prHitsCount ?? 0)
    }

    @MainActor
    private var historyExerciseStateStamp: HistoryExerciseInteractionStamp {
        HistoryExerciseInteractionStamp(
            entries: sessionExercises.map { exercise in
                HistoryExerciseInteractionStamp.Entry(
                    id: exercise.id,
                    updatedAt: exercise.updatedAt,
                    restSeconds: exercise.restSeconds,
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax
                )
            }
        )
    }

    private var exercisesSectionHeader: some View {
        Group {
            if sessionExercises.isEmpty {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Add exercises and update the logged sets below."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Swipe from the top of a card to delete, or use the card menu."
                ) {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(session == nil)
                }
            }
        }
    }

    private func addExerciseButton(title: String) -> some View {
        Button {
            showingExercisePicker = true
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
    }

    private func headerCard(_ session: HistoryDetailSnapshotBuilder.SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Session", subtitle: "Review the saved workout and adjust any logged values") {
                WGJMetricPill(
                    systemImage: personalRecordSummary.highlightedSetCount > 0 ? "trophy.fill" : "flag.checkered",
                    value: personalRecordSummary.label,
                    tint: personalRecordSummary.highlightedSetCount > 0 ? WGJTheme.accentGold : WGJTheme.textSecondary
                )
            }

            WGJResponsiveTextField(
                placeholder: "Workout name",
                text: $sessionNameDraft,
                capitalization: .words
            )

            WGJResponsiveTextField(
                placeholder: "Notes",
                text: $notesDraft,
                axis: .vertical,
                lineLimit: 2...5,
                capitalization: .sentences
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    WGJMetricPill(
                        systemImage: "calendar",
                        value: (session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened)
                    )

                    WGJMetricPill(
                        systemImage: "clock.fill",
                        value: HistoryWorkoutDurationPresentation.formattedDuration(
                            durationSeconds: session.durationSeconds,
                            startedAt: session.startedAt,
                            endedAt: session.endedAt
                        )
                    )
                    .accessibilityIdentifier("history-detail-duration-pill")

                    WGJMetricPill(
                        systemImage: "list.number",
                        value: "\(sessionExercises.count) exercises"
                    )

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    WGJMetricPill(
                        systemImage: "calendar",
                        value: (session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened)
                    )

                    WGJMetricPill(
                        systemImage: "clock.fill",
                        value: HistoryWorkoutDurationPresentation.formattedDuration(
                            durationSeconds: session.durationSeconds,
                            startedAt: session.startedAt,
                            endedAt: session.endedAt
                        )
                    )
                    .accessibilityIdentifier("history-detail-duration-pill")

                    WGJMetricPill(
                        systemImage: "list.number",
                        value: "\(sessionExercises.count) exercises"
                    )
                }
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var workoutMuscleHeatmapCard: some View {
        if let muscleHeatmap = snapshot?.muscleHeatmap {
            WorkoutMuscleHeatmapCard(
                title: "Muscle Map",
                subtitle: "Heatmap from completed working sets in this workout.",
                snapshot: muscleHeatmap,
                emptyMessage: "No completed working sets with muscle data for this workout."
            )
        }
    }

    @ViewBuilder
    private var cardioSection: some View {
        if !orderedCardioBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Cardio Phases",
                    subtitle: "Timed warmup and cooldown blocks saved with this workout."
                )

                ForEach(orderedCardioBlocks, id: \.id) { cardioBlock in
                    WorkoutCardioPhaseCard(
                        phase: cardioBlock.phase,
                        exerciseName: cardioBlock.exerciseNameSnapshot,
                        descriptor: cardioDescriptor(
                            category: cardioBlock.categorySnapshot,
                            muscleSummary: cardioBlock.muscleSummarySnapshot
                        ),
                        targetDurationSeconds: cardioBlock.targetDurationSeconds,
                        statusText: cardioBlock.isCompleted ? "Complete" : "Not finished",
                        statusTint: cardioBlock.isCompleted ? WGJTheme.success : WGJTheme.warning,
                        footnote: cardioBlock.isCompleted ? nil : "This session was finished before this cardio phase was completed."
                    )
                }
            }
        }
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await reloadSnapshot()
    }

    @MainActor
    private func reloadSnapshot() async {
        do {
            let loadedSnapshot: HistoryDetailSnapshotBuilder.Snapshot
            if let appBackgroundStore {
                loadedSnapshot = try await appBackgroundStore.perform("history-detail.snapshot") { backgroundContext in
                    try Self.loadSnapshot(modelContext: backgroundContext, sessionID: sessionID)
                }
            } else {
                loadedSnapshot = try Self.loadSnapshot(modelContext: modelContext, sessionID: sessionID)
            }

            applySnapshot(loadedSnapshot)
        } catch WorkoutSessionRepositoryError.sessionNotFound {
            snapshot = nil
            didLoadSnapshot = true
            clearLocalStateForAllExercises()
        } catch {
            didLoadSnapshot = true
            showError(error)
        }
    }

    @MainActor
    private func applySnapshot(_ loadedSnapshot: HistoryDetailSnapshotBuilder.Snapshot) {
        snapshot = loadedSnapshot
        didLoadSnapshot = true
        sessionNameDraft = loadedSnapshot.session.name
        notesDraft = loadedSnapshot.session.notes
        preferredLoadUnit = loadedSnapshot.preferredLoadUnit
        setDraftsByExerciseID = loadedSnapshot.localState.setDraftsByExerciseID
        restByExerciseID = loadedSnapshot.localState.restByExerciseID
        notesByExerciseID = loadedSnapshot.localState.notesByExerciseID
        hydrationPayloadByExerciseID = loadedSnapshot.hydrationPayloadByExerciseID
        personalRecordPresentationByExerciseID = loadedSnapshot.hydrationPayloadByExerciseID
            .mapValues(\.personalRecords)

        let validIDs = Set(loadedSnapshot.exercises.map(\.id))
        for exerciseID in Set(setDraftsByExerciseID.keys)
            .union(restByExerciseID.keys)
            .union(notesByExerciseID.keys)
            .union(hydrationPayloadByExerciseID.keys)
            .union(personalRecordPresentationByExerciseID.keys)
        where !validIDs.contains(exerciseID) {
            clearLocalState(for: exerciseID)
            hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
            personalRecordPresentationByExerciseID.removeValue(forKey: exerciseID)
        }

        syncExpandedExerciseState()
        loadedExerciseStateStamp = historyExerciseStateStamp
    }

    private func clearLocalStateForAllExercises() {
        setDraftsByExerciseID.removeAll()
        restByExerciseID.removeAll()
        notesByExerciseID.removeAll()
        hydrationPayloadByExerciseID.removeAll()
        personalRecordPresentationByExerciseID.removeAll()
        expandedExerciseIDs.removeAll()
        loadedExerciseStateStamp = nil
    }

    nonisolated private static func loadSnapshot(
        modelContext: ModelContext,
        sessionID: UUID
    ) throws -> HistoryDetailSnapshotBuilder.Snapshot {
        try HistoryDetailSnapshotBuilder.load(modelContext: modelContext, sessionID: sessionID)
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: HistoryDetailSnapshotBuilder.ExerciseSnapshot, index: Int) -> some View {
        let isExpanded = expandedExerciseIDs[exercise.id] ?? false
        let hasLoadedLocalState = setDraftsByExerciseID.keys.contains(exercise.id)
        let drafts = setDraftsByExerciseID[exercise.id] ?? []
        let restSeconds = restByExerciseID[exercise.id] ?? exercise.restSeconds
        let hydrationPayload = hydrationPayloadByExerciseID[exercise.id]

        VStack(alignment: .leading, spacing: 8) {
            exerciseStructureBadgeRow(for: exercise)

            if isExpanded, hasLoadedLocalState {
                HistoryExerciseDetailEditorCard(
                    exerciseID: exercise.id,
                    exerciseAccessibilityIdentifier: "history-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exercise.exerciseNameSnapshot,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: "Exercise \(index + 1)",
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    previousPerformanceResolution: hydrationPayload?.previousPerformanceResolution ?? .loading,
                    personalRecordSummaryKinds: hydrationPayload?.personalRecords.summaryKinds ?? [],
                    personalRecordKindsBySetID: hydrationPayload?.personalRecords.setKindsBySetID ?? [:],
                    preferredLoadUnit: preferredLoadUnit,
                    exerciseNotes: notesByExerciseID[exercise.id] ?? exercise.notes,
                    restSeconds: restSeconds,
                    setDrafts: drafts,
                    onExerciseNotesCommitted: { notes in
                        updateNotesValue(notes, for: exercise.id)
                    },
                    onSetDraftsCommitted: { drafts in
                        updateDraftsValue(drafts, for: exercise.id)
                    },
                    onRestCommitted: { rest in
                        updateRestValue(rest, for: exercise.id)
                    },
                    onExpandedChanged: { handleExpandedChange($0, for: exercise.id) },
                    onExerciseDelete: {
                        removeExercise(exerciseID: exercise.id)
                    },
                    flushCoordinator: rowFlushCoordinator
                )
            } else if isExpanded {
                HistoryExerciseLoadingCard(
                    exerciseAccessibilityIdentifier: "history-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exercise.exerciseNameSnapshot,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: "Exercise \(index + 1)",
                    onCollapse: {
                        handleExpandedChange(false, for: exercise.id)
                    },
                    onDelete: {
                        removeExercise(exerciseID: exercise.id)
                    }
                )
                .equatable()
            } else {
                let collapsedSummary = HistoryExerciseCollapsedSummary(
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    completedSetCount: exercise.totalSetCount > 0 ? exercise.completedSetCount : nil,
                    totalSetCount: exercise.totalSetCount > 0 ? exercise.totalSetCount : nil,
                    restSeconds: restSeconds,
                    notes: notesByExerciseID[exercise.id] ?? exercise.notes
                )

                HistoryCollapsedExerciseCard(
                    exerciseAccessibilityIdentifier: "history-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exercise.exerciseNameSnapshot,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: "Exercise \(index + 1)",
                    summary: collapsedSummary,
                    onExpand: {
                        handleExpandedChange(true, for: exercise.id)
                    },
                    onDelete: {
                        removeExercise(exerciseID: exercise.id)
                    }
                )
                .equatable()
            }
        }
    }

    @ViewBuilder
    private func exerciseStructureBadgeRow(
        for exercise: HistoryDetailSnapshotBuilder.ExerciseSnapshot
    ) -> some View {
        let supersetMembership = exercise.supersetGroupID.flatMap { groupID in
            exercise.supersetPosition.map { position in
                ExerciseSupersetMembershipDraft(
                    groupID: groupID,
                    position: position,
                    roundRestSeconds: 0
                )
            }
        }
        let presentation = WorkoutExerciseStructurePresentation(
            supersetMembership: supersetMembership,
            hasDropset: exercise.hasDropsets
        )

        if presentation.isSuperset || presentation.hasDropset {
            HStack(spacing: 8) {
                if presentation.isSuperset {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                }
                if let position = presentation.supersetPosition {
                    structureBadge(position.label, tint: WGJTheme.accentCyan)
                }
                if presentation.hasDropset {
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

    private func saveChanges() {
        guard !isSavingChanges else { return }
        isSavingChanges = true

        Task { @MainActor in
            defer {
                isSavingChanges = false
            }

            do {
                rowFlushCoordinator.flushAll()
                let command = makeSaveCommand()
                let didPersistChanges: Bool
                if let appBackgroundStore {
                    didPersistChanges = try await appBackgroundStore.performWrite("history-detail.save") { backgroundContext in
                        try Self.saveChanges(
                            command: command,
                            modelContext: backgroundContext
                        )
                    }
                } else {
                    didPersistChanges = try Self.saveChanges(
                        command: command,
                        modelContext: modelContext
                    )
                }

                if didPersistChanges {
                    hasPendingSummaryRebuild = false
                }
                await reloadSnapshot()
            } catch {
                showError(error)
            }
        }
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        var capturedError: Error?

        do {
            try sessionRepository.addExercise(sessionID: sessionID, catalogItem: item)
            hasPendingSummaryRebuild = true
        } catch {
            capturedError = error
        }

        if let capturedError {
            showError(capturedError)
        } else {
            Task { @MainActor in
                await reloadSnapshot()
            }
        }
    }

    private func removeExercise(exerciseID: UUID) {
        var capturedError: Error?

        do {
            try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
            clearLocalState(for: exerciseID)
            hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
            hasPendingSummaryRebuild = true
        } catch {
            capturedError = error
        }

        if let capturedError {
            showError(capturedError)
        } else {
            Task { @MainActor in
                await reloadSnapshot()
            }
        }
    }

    private func archiveSession() {
        do {
            try sessionRepository.archiveSession(id: sessionID)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func syncExpandedExerciseState() {
        let orderedIDs = sessionExercises.map(\.id)
        let validIDs = Set(orderedIDs)
        expandedExerciseIDs = expandedExerciseIDs.filter { validIDs.contains($0.key) }

        let initialState = HistoryDetailExpansionPolicy.initialExpansionState(orderedExerciseIDs: orderedIDs)
        for exerciseID in orderedIDs where expandedExerciseIDs[exerciseID] == nil {
            expandedExerciseIDs[exerciseID] = initialState[exerciseID] ?? false
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func clearLocalState(for exerciseID: UUID) {
        setDraftsByExerciseID.removeValue(forKey: exerciseID)
        restByExerciseID.removeValue(forKey: exerciseID)
        notesByExerciseID.removeValue(forKey: exerciseID)
    }

    nonisolated private static func orderedSessionSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated private static func makeDrafts(from exercise: WorkoutSessionExercise) -> [WorkoutSessionSetDraft] {
        orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
    }

    @MainActor
    private func makeDrafts(from exercise: WorkoutSessionExercise) -> [WorkoutSessionSetDraft] {
        Self.makeDrafts(from: exercise)
    }

    @MainActor
    private func updateDraftsValue(_ updated: [WorkoutSessionSetDraft], for exerciseID: UUID) {
        guard setDraftsByExerciseID[exerciseID] != updated else { return }
        setDraftsByExerciseID[exerciseID] = updated
    }

    @MainActor
    private func updateRestValue(_ updated: Int, for exerciseID: UUID) {
        let normalized = max(0, min(3600, updated))
        guard restByExerciseID[exerciseID] != normalized else { return }
        restByExerciseID[exerciseID] = normalized
    }

    @MainActor
    private func updateNotesValue(_ updated: String, for exerciseID: UUID) {
        guard notesByExerciseID[exerciseID] != updated else { return }
        notesByExerciseID[exerciseID] = updated
    }

    @MainActor
    private func handleExpandedChange(_ updated: Bool, for exerciseID: UUID) {
        guard expandedExerciseIDs[exerciseID] != updated else { return }
        expandedExerciseIDs[exerciseID] = updated
    }

    @MainActor
    private func makeSaveCommand() -> HistorySaveCommand {
        let changedExerciseIDs = Set<UUID>(setDraftsByExerciseID.keys)
            .union(restByExerciseID.keys)
            .union(notesByExerciseID.keys)
        let snapshots = Dictionary<UUID, HistoryExerciseSaveSnapshot>(
            sessionExercises.compactMap { exercise -> (UUID, HistoryExerciseSaveSnapshot)? in
                guard changedExerciseIDs.contains(exercise.id),
                      let drafts = setDraftsByExerciseID[exercise.id] else {
                    return nil
                }

                return (
                    exercise.id,
                    HistoryExerciseSaveSnapshot(
                        setDrafts: drafts,
                        restSeconds: restByExerciseID[exercise.id] ?? exercise.restSeconds,
                        notes: notesByExerciseID[exercise.id] ?? exercise.notes
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        return HistorySaveCommand(
            sessionID: sessionID,
            sessionName: sessionNameDraft,
            sessionNotes: notesDraft,
            shouldRecalculateSummary: hasPendingSummaryRebuild,
            exerciseSnapshotsByID: snapshots
        )
    }

    nonisolated private static func saveChanges(
        command: HistorySaveCommand,
        modelContext: ModelContext
    ) throws -> Bool {
        let sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try sessionRepository.session(id: command.sessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let exercises = try sessionRepository.sessionExercises(sessionID: command.sessionID)
        var didPersistChanges = command.shouldRecalculateSummary

        let trimmedName = command.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != session.name {
            try sessionRepository.updateSessionName(sessionID: command.sessionID, name: trimmedName)
            didPersistChanges = true
        }

        if command.sessionNotes != session.notes {
            try sessionRepository.updateSessionNotes(sessionID: command.sessionID, notes: command.sessionNotes)
            didPersistChanges = true
        }

        for exercise in exercises {
            guard let snapshot = command.exerciseSnapshotsByID[exercise.id] else { continue }

            let persistedDrafts = Self.makeDrafts(from: exercise)
            if snapshot.setDrafts != persistedDrafts {
                try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: snapshot.setDrafts)
                didPersistChanges = true
            }

            if snapshot.restSeconds != exercise.restSeconds {
                try sessionRepository.updateExerciseRest(
                    sessionExerciseID: exercise.id,
                    restSeconds: snapshot.restSeconds
                )
                didPersistChanges = true
            }

            if snapshot.notes != exercise.notes {
                try sessionRepository.updateExerciseNotes(sessionExerciseID: exercise.id, notes: snapshot.notes)
                didPersistChanges = true
            }
        }

        if didPersistChanges {
            try sessionRepository.recalculateSessionSummary(sessionID: command.sessionID)
        }

        return didPersistChanges
    }

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }
}

nonisolated private struct HistoryDetailSnapshot: Equatable, Sendable {
    let session: HistoryDetailSessionSnapshot
    let cardioBlocks: [HistoryDetailCardioBlockSnapshot]
    let exercises: [HistoryDetailExerciseSnapshot]
    let preferredLoadUnit: TemplateLoadUnit
}

nonisolated private struct HistoryDetailSessionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let prHitsCount: Int
    let notes: String
    let updatedAt: Date

    nonisolated init(model: WorkoutSession) {
        self.id = model.id
        self.name = model.name
        self.startedAt = model.startedAt
        self.endedAt = model.endedAt
        self.durationSeconds = model.durationSeconds
        self.prHitsCount = model.prHitsCount
        self.notes = model.notes
        self.updatedAt = model.updatedAt
    }
}

nonisolated private struct HistoryDetailCardioBlockSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let phase: WorkoutCardioPhase
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let targetDurationSeconds: Int
    let isCompleted: Bool
    let updatedAt: Date

    nonisolated init(model: WorkoutSessionCardioBlock) {
        self.id = model.id
        self.phase = model.phase
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.targetDurationSeconds = model.targetDurationSeconds
        self.isCompleted = model.isCompleted
        self.updatedAt = model.updatedAt
    }
}

nonisolated private struct HistoryDetailExerciseSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let totalSetCount: Int
    let completedSetCount: Int
    let hasDropsets: Bool
    let supersetGroupID: UUID?
    let supersetPosition: SupersetExercisePosition?
    let updatedAt: Date

    nonisolated init(model: WorkoutSessionExercise) {
        self.id = model.id
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.notes = model.notes
        self.targetRepMin = model.targetRepMin
        self.targetRepMax = model.targetRepMax
        self.restSeconds = model.restSeconds
        self.totalSetCount = model.totalSetCount
        self.completedSetCount = model.completedSetCount
        self.hasDropsets = model.hasDropsets
        self.supersetGroupID = model.supersetGroupID
        self.supersetPosition = model.supersetPosition
        self.updatedAt = model.updatedAt
    }
}

private struct HistoryExerciseHydrationPayload: Equatable, Sendable {
    let previousPerformanceResolution: WorkoutPreviousPerformanceResolution
    let personalRecords: HistoryExercisePersonalRecordPresentation
}

private struct HistoryExerciseSaveSnapshot: Sendable {
    let setDrafts: [WorkoutSessionSetDraft]
    let restSeconds: Int
    let notes: String
}

private struct HistorySaveCommand: Sendable {
    let sessionID: UUID
    let sessionName: String
    let sessionNotes: String
    let shouldRecalculateSummary: Bool
    let exerciseSnapshotsByID: [UUID: HistoryExerciseSaveSnapshot]
}

enum HistoryWorkoutDurationPresentation {
    static func formattedDuration(_ session: WorkoutSession) -> String {
        formattedDuration(
            durationSeconds: session.durationSeconds,
            startedAt: session.startedAt,
            endedAt: session.endedAt
        )
    }

    static func formattedDuration(
        durationSeconds: Int,
        startedAt: Date,
        endedAt: Date?
    ) -> String {
        let resolvedSeconds = resolvedDurationSeconds(
            durationSeconds: durationSeconds,
            startedAt: startedAt,
            endedAt: endedAt
        )
        let mins = resolvedSeconds / 60
        let hours = mins / 60
        let remMins = mins % 60
        if hours > 0 {
            return "\(hours)h \(remMins)m"
        }
        return "\(remMins)m"
    }

    private static func resolvedDurationSeconds(
        durationSeconds: Int,
        startedAt: Date,
        endedAt: Date?
    ) -> Int {
        if durationSeconds > 0 {
            return durationSeconds
        }
        guard let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

nonisolated struct HistoryExercisePersonalRecordPresentation: Equatable, Sendable {
    let summaryKinds: [WorkoutPersonalRecordKind]
    let setKindsBySetID: [UUID: [WorkoutPersonalRecordKind]]

    var highlightedSetCount: Int {
        setKindsBySetID.count
    }

    static func presentationsByExerciseID(
        from achievements: [SessionSetPRAchievement],
        exerciseIDs: Set<UUID>
    ) -> [UUID: HistoryExercisePersonalRecordPresentation] {
        guard !exerciseIDs.isEmpty else { return [:] }

        var groupedSetKindsByExerciseID: [UUID: [UUID: [WorkoutPersonalRecordKind]]] = [:]
        var groupedSummaryKindsByExerciseID: [UUID: Set<WorkoutPersonalRecordKind>] = [:]

        for achievement in achievements where exerciseIDs.contains(achievement.sessionExerciseID) {
            var setKinds = groupedSetKindsByExerciseID[achievement.sessionExerciseID, default: [:]]
            setKinds[achievement.setID] = achievement.kinds
            groupedSetKindsByExerciseID[achievement.sessionExerciseID] = setKinds
            groupedSummaryKindsByExerciseID[achievement.sessionExerciseID, default: []].formUnion(achievement.kinds)
        }

        var presentationByExerciseID: [UUID: HistoryExercisePersonalRecordPresentation] = [:]
        presentationByExerciseID.reserveCapacity(exerciseIDs.count)
        for exerciseID in exerciseIDs {
            presentationByExerciseID[exerciseID] = HistoryExercisePersonalRecordPresentation(
                summaryKinds: Array(groupedSummaryKindsByExerciseID[exerciseID, default: []]).sorted(),
                setKindsBySetID: groupedSetKindsByExerciseID[exerciseID, default: [:]]
            )
        }

        return presentationByExerciseID
    }
}

private struct HistoryWorkoutPersonalRecordSummary {
    let highlightedSetCount: Int

    var label: String {
        guard highlightedSetCount > 0 else {
            return "No PR sets"
        }

        return "\(highlightedSetCount) PR set\(highlightedSetCount == 1 ? "" : "s")"
    }
}

private struct HistoryExerciseCollapsedSummary: Equatable {
    let targetRepMin: Int?
    let targetRepMax: Int?
    let completedSetCount: Int?
    let totalSetCount: Int?
    let restSeconds: Int
    let notes: String

    var repRangeText: String {
        switch (targetRepMin, targetRepMax) {
        case let (min?, max?):
            return min == max ? "\(min) reps" : "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "Up to \(max)"
        case (nil, nil):
            return "Open reps"
        }
    }

    var setProgressText: String {
        guard let completedSetCount, let totalSetCount else {
            return "Loading sets"
        }

        return "\(completedSetCount)/\(totalSetCount) sets"
    }

    var restText: String {
        guard restSeconds > 0 else {
            return "No rest"
        }

        let mins = max(0, restSeconds) / 60
        let secs = max(0, restSeconds) % 60
        return "Rest \(String(format: "%d:%02d", mins, secs))"
    }

    var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct HistoryExerciseLoadingCard: View, Equatable {
    let exerciseAccessibilityIdentifier: String
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String
    let onCollapse: () -> Void
    let onDelete: () -> Void

    static func == (lhs: HistoryExerciseLoadingCard, rhs: HistoryExerciseLoadingCard) -> Bool {
        lhs.exerciseAccessibilityIdentifier == rhs.exerciseAccessibilityIdentifier
            && lhs.exerciseName == rhs.exerciseName
            && lhs.muscleSummary == rhs.muscleSummary
            && lhs.category == rhs.category
            && lhs.exerciseIndexTitle == rhs.exerciseIndexTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exerciseIndexTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentCyan)

                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .wgjSingleLineText(scale: 0.8)
                        .accessibilityIdentifier(exerciseAccessibilityIdentifier)

                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)

                    Text("Loading sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(WGJTheme.field)
                                .overlay(
                                    Capsule()
                                        .stroke(WGJTheme.outline.opacity(0.24), lineWidth: 1)
                                )
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete exercise", systemImage: "trash")
                        }
                    } label: {
                        headerIcon(symbol: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-actions-button")

                    Button(action: onCollapse) {
                        headerIcon(symbol: "chevron.up.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-expand-button")
                }
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private var summaryLine: String {
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        if !category.isEmpty {
            return category
        }

        return "Saved exercise"
    }

    private func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WGJTheme.field)
            )
    }
}

private struct HistoryCollapsedExerciseCard: View, Equatable {
    let exerciseAccessibilityIdentifier: String
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String
    let summary: HistoryExerciseCollapsedSummary
    let onExpand: () -> Void
    let onDelete: () -> Void

    static func == (lhs: HistoryCollapsedExerciseCard, rhs: HistoryCollapsedExerciseCard) -> Bool {
        lhs.exerciseAccessibilityIdentifier == rhs.exerciseAccessibilityIdentifier
            && lhs.exerciseName == rhs.exerciseName
            && lhs.muscleSummary == rhs.muscleSummary
            && lhs.category == rhs.category
            && lhs.exerciseIndexTitle == rhs.exerciseIndexTitle
            && lhs.summary == rhs.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exerciseIndexTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentCyan)

                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .wgjSingleLineText(scale: 0.8)
                        .accessibilityIdentifier(exerciseAccessibilityIdentifier)

                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            infoChip(summary.repRangeText, tint: WGJTheme.accentGold)
                            infoChip(summary.setProgressText, tint: WGJTheme.accentBlue)
                            infoChip(summary.restText, tint: WGJTheme.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            infoChip(summary.repRangeText, tint: WGJTheme.accentGold)
                            infoChip(summary.setProgressText, tint: WGJTheme.accentBlue)
                            infoChip(summary.restText, tint: WGJTheme.textSecondary)
                        }
                    }

                    if let notes = summary.trimmedNotes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete exercise", systemImage: "trash")
                        }
                    } label: {
                        headerIcon(symbol: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-actions-button")

                    Button(action: onExpand) {
                        headerIcon(symbol: "chevron.down.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-expand-button")
                }
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private var summaryLine: String {
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        if !category.isEmpty {
            return category
        }

        return "Saved exercise"
    }

    private func infoChip(_ title: String, tint: Color) -> some View {
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

    private func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WGJTheme.field)
            )
    }
}

private struct HistoryExerciseDetailEditorCard: View {
    let exerciseID: UUID
    let exerciseAccessibilityIdentifier: String
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let previousPerformanceResolution: WorkoutPreviousPerformanceResolution
    let personalRecordSummaryKinds: [WorkoutPersonalRecordKind]
    let personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]]
    let preferredLoadUnit: TemplateLoadUnit
    let exerciseNotes: String
    let restSeconds: Int
    let setDrafts: [WorkoutSessionSetDraft]
    let onExerciseNotesCommitted: (String) -> Void
    let onSetDraftsCommitted: ([WorkoutSessionSetDraft]) -> Void
    let onRestCommitted: (Int) -> Void
    let onExpandedChanged: (Bool) -> Void
    let onExerciseDelete: () -> Void
    let flushCoordinator: WorkoutExerciseRowFlushCoordinator?

    @State private var localRestSeconds: Int
    @State private var localSetDrafts: [WorkoutSessionSetDraft]
    @State private var localExerciseNotes: String
    @State private var editingCoordinator: WorkoutExerciseEditingCoordinator

    init(
        exerciseID: UUID,
        exerciseAccessibilityIdentifier: String,
        exerciseName: String,
        muscleSummary: String,
        category: String,
        exerciseIndexTitle: String,
        targetRepMin: Int?,
        targetRepMax: Int?,
        previousPerformanceResolution: WorkoutPreviousPerformanceResolution,
        personalRecordSummaryKinds: [WorkoutPersonalRecordKind],
        personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]],
        preferredLoadUnit: TemplateLoadUnit,
        exerciseNotes: String,
        restSeconds: Int,
        setDrafts: [WorkoutSessionSetDraft],
        onExerciseNotesCommitted: @escaping (String) -> Void,
        onSetDraftsCommitted: @escaping ([WorkoutSessionSetDraft]) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onExpandedChanged: @escaping (Bool) -> Void,
        onExerciseDelete: @escaping () -> Void,
        flushCoordinator: WorkoutExerciseRowFlushCoordinator?
    ) {
        self.exerciseID = exerciseID
        self.exerciseAccessibilityIdentifier = exerciseAccessibilityIdentifier
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.exerciseIndexTitle = exerciseIndexTitle
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.previousPerformanceResolution = previousPerformanceResolution
        self.personalRecordSummaryKinds = personalRecordSummaryKinds
        self.personalRecordKindsBySetID = personalRecordKindsBySetID
        self.preferredLoadUnit = preferredLoadUnit
        self.exerciseNotes = exerciseNotes
        self.restSeconds = restSeconds
        self.setDrafts = setDrafts
        self.onExerciseNotesCommitted = onExerciseNotesCommitted
        self.onSetDraftsCommitted = onSetDraftsCommitted
        self.onRestCommitted = onRestCommitted
        self.onExpandedChanged = onExpandedChanged
        self.onExerciseDelete = onExerciseDelete
        self.flushCoordinator = flushCoordinator
        _localRestSeconds = State(initialValue: restSeconds)
        _localSetDrafts = State(initialValue: setDrafts)
        _localExerciseNotes = State(initialValue: exerciseNotes)
        _editingCoordinator = State(
            initialValue: WorkoutExerciseEditingCoordinator(
                setDrafts: setDrafts,
                restSeconds: restSeconds,
                notes: exerciseNotes,
                onDraftsCommitted: onSetDraftsCommitted,
                onRestCommitted: onRestCommitted,
                onNotesCommitted: onExerciseNotesCommitted,
                onCompletionChanged: { _, _, _, _ in }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !personalRecordSummaryKinds.isEmpty {
                personalRecordChipGroup(personalRecordSummaryKinds)
            }

            controlRow

            WGJExerciseNotesEditor(
                placeholder: "Add notes for this exercise",
                accessibilityIdentifier: "\(exerciseAccessibilityIdentifier)-notes-field",
                notes: Binding(
                    get: { localExerciseNotes },
                    set: { updateNotes($0) }
                )
            )

            setsSection
        }
        .padding(16)
        .wgjCardContainer(strong: true)
        .onAppear {
            flushCoordinator?.register(exerciseID: exerciseID) {
                flushPendingEdits()
            }
        }
        .onDisappear {
            flushPendingEdits()
            flushCoordinator?.unregister(exerciseID: exerciseID)
        }
        .onChange(of: setDrafts) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: newValue,
                restSeconds: restSeconds,
                notes: exerciseNotes
            )
            guard localSetDrafts != newValue else { return }
            localSetDrafts = newValue
        }
        .onChange(of: restSeconds) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: newValue,
                notes: exerciseNotes
            )
            guard localRestSeconds != newValue else { return }
            localRestSeconds = newValue
        }
        .onChange(of: exerciseNotes) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: restSeconds,
                notes: newValue
            )
            guard localExerciseNotes != newValue else { return }
            localExerciseNotes = newValue
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(exerciseIndexTitle.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentCyan)

                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .wgjSingleLineText(scale: 0.8)
                    .accessibilityIdentifier(exerciseAccessibilityIdentifier)

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Menu {
                    Button(role: .destructive, action: onExerciseDelete) {
                        Label("Delete exercise", systemImage: "trash")
                    }
                } label: {
                    headerIcon(symbol: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-actions-button")

                Button {
                    flushPendingEdits()
                    onExpandedChanged(false)
                } label: {
                    headerIcon(symbol: "chevron.up.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-expand-button")
            }
        }
    }

    private var controlRow: some View {
        HStack(alignment: .top, spacing: 10) {
            infoControl(title: "Rep Range", value: repRangeText, tint: WGJTheme.accentGold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                HStack(spacing: 8) {
                    Button {
                        updateRest(localRestSeconds - 15)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(restPresets, id: \.self) { value in
                            Button(formattedRest(value)) {
                                updateRest(value)
                            }
                        }
                    } label: {
                        Label(formattedRest(localRestSeconds), systemImage: "timer")
                            .monospacedDigit()
                    }
                    .menuIndicator(.hidden)

                    Button {
                        updateRest(localRestSeconds + 15)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.field)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logged Sets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer()

                Text("\(localSetDrafts.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            ForEach(Array(localSetDrafts.enumerated()), id: \.element.id) { index, draft in
                setCard(draft, index: index)
            }

            Button {
                addSet()
            } label: {
                Label("Add Set", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.field)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(WGJTheme.textPrimary)
        }
    }

    private func setCard(_ draft: WorkoutSessionSetDraft, index: Int) -> some View {
        let personalRecordKinds = personalRecordKindsBySetID[draft.id] ?? []
        let previous = previousPerformanceResolution.previous(at: index)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                setBadge(draft, index: index)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(setTitle(draft, index: index))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .wgjSingleLineText(scale: 0.84)

                        if draft.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WGJTheme.accentGold)
                        }

                        if !personalRecordKinds.isEmpty {
                            Image(systemName: "trophy.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WGJTheme.accentGold)
                        }
                    }

                    if let previousText = previousSummary(previous) {
                        Text(previousText)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .monospacedDigit()
                    }

                    if let metadata = metadataLine(for: draft) {
                        Text(metadata)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    Button(draft.isWarmup ? "Mark Working Set" : "Mark Warmup") {
                        updateSet(draft.id) { $0.isWarmup.toggle() }
                    }
                    Button(draft.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                        updateSet(draft.id) { $0.isCompleted.toggle() }
                    }
                    Button(role: .destructive) {
                        removeSet(draft.id)
                    } label: {
                        Label("Delete Set", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(WGJTheme.accentBlue)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WGJTheme.field)
                        )
                }
                .menuIndicator(.hidden)
                .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-set-\(index + 1)-actions-button")
            }

            HStack(alignment: .top, spacing: 12) {
                metricField(title: "Weight") {
                    TextField("0", text: weightBinding(for: draft.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .disabled(draft.isLocked)
                        .wgjPillField()
                        .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-set-\(index + 1)-weight-field")
                }

                metricField(title: "Reps") {
                    TextField("0", text: repsBinding(for: draft.id))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .disabled(draft.isLocked)
                        .wgjPillField()
                        .accessibilityIdentifier("\(exerciseAccessibilityIdentifier)-set-\(index + 1)-reps-field")
                }
            }

            if !draft.dropStages.isEmpty {
                Text("\(draft.dropStages.count) dropset stage\(draft.dropStages.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentGold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(draft.isCompleted ? WGJTheme.success.opacity(0.14) : WGJTheme.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            draft.isCompleted ? WGJTheme.success.opacity(0.34) : WGJTheme.outline.opacity(0.20),
                            lineWidth: 1
                        )
                )
        )
    }

    private func metricField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoControl(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.10))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func personalRecordChipGroup(_ kinds: [WorkoutPersonalRecordKind]) -> some View {
        let indexedKinds = Array(kinds.sorted().enumerated())
        return HStack(spacing: 8) {
            ForEach(indexedKinds, id: \.offset) { _, kind in
                Text(kind.chipTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(WGJTheme.accentGold.opacity(0.14))
                    )
            }
        }
    }

    private func setBadge(_ draft: WorkoutSessionSetDraft, index: Int) -> some View {
        Text(draft.isWarmup ? "W" : "\(workingSetNumber(at: index))")
            .font(.headline.weight(.bold))
            .foregroundStyle(draft.isWarmup ? WGJTheme.accentGold : WGJTheme.textPrimary)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WGJTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(draft.isWarmup ? WGJTheme.accentGold.opacity(0.34) : WGJTheme.outline.opacity(0.24), lineWidth: 1)
                    )
            )
    }

    private func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WGJTheme.field)
            )
    }

    private func updateNotes(_ updated: String) {
        localExerciseNotes = updated
        editingCoordinator.stageNotesCommit(updated)
    }

    private func updateRest(_ updated: Int) {
        let normalized = max(0, min(3600, updated))
        localRestSeconds = normalized
        localSetDrafts = localSetDrafts.map { draft in
            var copy = draft
            copy.restSeconds = normalized
            return copy
        }
        editingCoordinator.stageRestCommit(normalized)
        editingCoordinator.stageDrafts(localSetDrafts)
    }

    private func addSet() {
        var newDraft = localSetDrafts.last ?? WorkoutSessionSetDraft(restSeconds: localRestSeconds)
        newDraft = WorkoutSessionSetDraft(
            isWarmup: false,
            restSeconds: localRestSeconds,
            targetReps: newDraft.targetReps,
            targetWeight: newDraft.targetWeight,
            targetLoadUnit: newDraft.targetLoadUnit,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: preferredLoadUnit,
            isCompleted: false,
            isLocked: false,
            dropStages: []
        )
        localSetDrafts.append(newDraft)
        editingCoordinator.stageDrafts(localSetDrafts)
    }

    private func removeSet(_ setID: UUID) {
        localSetDrafts.removeAll { $0.id == setID }
        editingCoordinator.stageDrafts(localSetDrafts)
    }

    private func updateSet(_ setID: UUID, update: (inout WorkoutSessionSetDraft) -> Void) {
        guard let index = localSetDrafts.firstIndex(where: { $0.id == setID }) else { return }
        update(&localSetDrafts[index])
        editingCoordinator.stageDrafts(localSetDrafts)
    }

    private func flushPendingEdits() {
        guard editingCoordinator.hasPendingChanges else { return }
        editingCoordinator.flushCommits()
    }

    private func weightBinding(for setID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let draft = localSetDrafts.first(where: { $0.id == setID }),
                      let value = draft.actualWeight
                else { return "" }
                return WGJFormatters.decimalString(value)
            },
            set: { rawValue in
                updateSet(setID) { draft in
                    let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
                    if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.actualWeight = nil
                    } else {
                        draft.actualWeight = Double(normalized.filter { $0.isNumber || $0 == "." })
                    }
                    if draft.targetLoadUnit == .bodyweight {
                        draft.actualLoadUnit = .bodyweight
                    } else {
                        draft.actualLoadUnit = preferredLoadUnit
                    }
                }
            }
        )
    }

    private func repsBinding(for setID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let draft = localSetDrafts.first(where: { $0.id == setID }),
                      let value = draft.actualReps
                else { return "" }
                return String(value)
            },
            set: { rawValue in
                updateSet(setID) { draft in
                    let cleaned = rawValue.filter(\.isNumber)
                    draft.actualReps = cleaned.isEmpty ? nil : Int(cleaned)
                }
            }
        )
    }

    private var summaryLine: String {
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        if !category.isEmpty {
            return category
        }

        return "Saved exercise"
    }

    private var repRangeText: String {
        switch (targetRepMin, targetRepMax) {
        case let (min?, max?):
            return min == max ? "\(min) reps" : "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "Up to \(max)"
        case (nil, nil):
            return "Open reps"
        }
    }

    private var restPresets: [Int] {
        [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
    }

    private func setTitle(_ draft: WorkoutSessionSetDraft, index: Int) -> String {
        draft.isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber(at: index))"
    }

    private func workingSetNumber(at index: Int) -> Int {
        guard localSetDrafts.indices.contains(index) else { return index + 1 }
        return localSetDrafts.prefix(index + 1).filter { !$0.isWarmup }.count
    }

    private func previousSummary(_ previous: WorkoutPreviousSetSnapshot?) -> String? {
        guard let previous else { return nil }
        if let weight = previous.weight, let reps = previous.reps {
            return "Previous \(WGJFormatters.decimalString(weight)) \(previous.unit.shortLabel) x \(reps)"
        }
        if let reps = previous.reps {
            return "Previous \(reps) reps"
        }
        return nil
    }

    private func metadataLine(for draft: WorkoutSessionSetDraft) -> String? {
        var parts: [String] = []
        if let reps = draft.targetReps {
            parts.append("Target \(reps) reps")
        }
        if let weight = draft.targetWeight {
            parts.append("Target \(WGJFormatters.decimalString(weight)) \(draft.targetLoadUnit.shortLabel)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formattedRest(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(sessionID: UUID())
    }
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateCardioBlock.self,
        TemplateExercise.self,
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        TemplateSupersetGroup.self,
        TemplateExerciseDropStage.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftCardioBlock.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        ActiveWorkoutDraftSupersetGroup.self,
        ActiveWorkoutDraftDropStage.self,
        WorkoutSession.self,
        WorkoutSessionCardioBlock.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
        WorkoutSessionSupersetGroup.self,
        WorkoutSessionDropStage.self,
    ], inMemory: true)
}
