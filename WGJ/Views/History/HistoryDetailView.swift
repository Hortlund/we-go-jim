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
    @State private var loadedLocalState = HistoryDetailSnapshotBuilder.LocalState.empty
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var notesByExerciseID: [UUID: String] = [:]
    @State private var hydrationPayloadByExerciseID: [UUID: HistoryDetailSnapshotBuilder.ExerciseHydrationPayload] = [:]
    @State private var loadingHydrationExerciseIDs: Set<UUID> = []
    @State private var hydrationLoadGeneration = UUID()
    @State private var loadedExerciseStateStamp: HistoryExerciseInteractionStamp?
    @State private var expandedExerciseIDs: [UUID: Bool] = [:]
    @State private var hasPendingSummaryRebuild = false
    @State private var isSavingChanges = false
    @State private var sessionHeaderFlushCoordinator = HistorySessionHeaderFlushCoordinator()
    @State private var rowFlushCoordinator = WorkoutExerciseRowFlushCoordinator()

    @State private var showingExercisePicker = false
    @State private var showingArchiveConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var historyBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
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
        ScrollView {
            // History detail cards expand, collapse, and reload edited rows; keeping this
            // stack non-lazy avoids scroll-position churn while the row heights change.
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
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
                        message: "Add any exercises that are missing from this workout.",
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
        .wgjMinimalKeyboardToolbar()
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
            ExercisePickerView { item in
                addExercise(item)
                return .accepted
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
                    subtitle: "Exercises saved for this workout."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Logged exercises from this workout. Card menus include edit and delete actions."
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
            WGJActionHeader("Session", subtitle: "Saved workout details and logged values") {
                WGJMetricPill(
                    systemImage: personalRecordSummary.highlightedSetCount > 0 ? "trophy.fill" : "flag.checkered",
                    value: personalRecordSummary.label,
                    tint: personalRecordSummary.highlightedSetCount > 0 ? WGJTheme.accentGold : WGJTheme.textSecondary
                )
            }

            HistorySessionHeaderDraftFields(
                sessionName: sessionNameDraft,
                sessionNotes: notesDraft,
                onDraftsCommitted: { name, notes in
                    updateSessionHeaderDrafts(name: name, notes: notes)
                },
                flushCoordinator: sessionHeaderFlushCoordinator
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
                subtitle: "Muscles trained in this workout.",
                snapshot: muscleHeatmap,
                emptyMessage: "Complete sets with muscle data will fill this map."
            )
        }
    }

    @ViewBuilder
    private var cardioSection: some View {
        if !orderedCardioBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Cardio Phases",
                    subtitle: "Warmup and cooldown work from this session."
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
                        footnote: cardioBlock.isCompleted ? nil : "This cardio block was not completed before the workout ended."
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
            let backgroundStore = historyBackgroundStore
            loadedSnapshot = try await backgroundStore.perform("history-detail.snapshot") { backgroundContext in
                try Self.loadSnapshot(modelContext: backgroundContext, sessionID: sessionID)
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
        loadedLocalState = loadedSnapshot.localState
        setDraftsByExerciseID = loadedSnapshot.localState.setDraftsByExerciseID
        restByExerciseID = loadedSnapshot.localState.restByExerciseID
        notesByExerciseID = loadedSnapshot.localState.notesByExerciseID
        hydrationPayloadByExerciseID = loadedSnapshot.hydrationPayloadByExerciseID
        loadingHydrationExerciseIDs.removeAll()
        hydrationLoadGeneration = UUID()

        let validIDs = Set(loadedSnapshot.exercises.map(\.id))
        for exerciseID in Set(setDraftsByExerciseID.keys)
            .union(restByExerciseID.keys)
            .union(notesByExerciseID.keys)
            .union(hydrationPayloadByExerciseID.keys)
        where !validIDs.contains(exerciseID) {
            clearLocalState(for: exerciseID)
            hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
        }

        syncExpandedExerciseState()
        loadedExerciseStateStamp = historyExerciseStateStamp
        schedulePendingHydration()
    }

    private func clearLocalStateForAllExercises() {
        loadedLocalState = .empty
        setDraftsByExerciseID.removeAll()
        restByExerciseID.removeAll()
        notesByExerciseID.removeAll()
        hydrationPayloadByExerciseID.removeAll()
        loadingHydrationExerciseIDs.removeAll()
        hydrationLoadGeneration = UUID()
        expandedExerciseIDs.removeAll()
        loadedExerciseStateStamp = nil
    }

    nonisolated private static func loadSnapshot(
        modelContext: ModelContext,
        sessionID: UUID
    ) throws -> HistoryDetailSnapshotBuilder.Snapshot {
        try HistoryDetailSnapshotBuilder.load(
            modelContext: modelContext,
            sessionID: sessionID,
            hydrationExerciseIDs: []
        )
    }

    nonisolated private static func loadHydrationPayloads(
        modelContext: ModelContext,
        sessionID: UUID,
        exerciseIDs: Set<UUID>
    ) throws -> [UUID: HistoryDetailSnapshotBuilder.ExerciseHydrationPayload] {
        try HistoryDetailSnapshotBuilder.loadHydrationPayloads(
            modelContext: modelContext,
            sessionID: sessionID,
            exerciseIDs: exerciseIDs
        )
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
        sessionHeaderFlushCoordinator.flushDirty()
        rowFlushCoordinator.flushDirty()
        let command = makeSaveCommand()
        let backgroundStore = historyBackgroundStore

        Task.detached(priority: .utility) {
            do {
                let didPersistChanges = try await backgroundStore.performWrite("history-detail.save") { backgroundContext in
                    try Self.saveChanges(
                        command: command,
                        modelContext: backgroundContext
                    )
                }

                await handleSaveChangesCompleted(didPersistChanges: didPersistChanges)
            } catch {
                await handleSaveChangesFailed(error)
            }
        }
    }

    @MainActor
    private func handleSaveChangesCompleted(didPersistChanges: Bool) async {
        isSavingChanges = false
        if didPersistChanges {
            hasPendingSummaryRebuild = false
        }
        await reloadSnapshot()
    }

    @MainActor
    private func handleSaveChangesFailed(_ error: Error) {
        isSavingChanges = false
        showError(error)
    }

    private func addExercise(_ item: ExerciseCatalogSelection) {
        let backgroundStore = historyBackgroundStore
        let catalogExerciseUUID = item.remoteUUID
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-detail.add-exercise") { backgroundContext in
                    try Self.addExercise(
                        sessionID: sessionID,
                        catalogExerciseUUID: catalogExerciseUUID,
                        modelContext: backgroundContext
                    )
                }
                await handleExerciseAdded()
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func handleExerciseAdded() async {
        hasPendingSummaryRebuild = true
        await reloadSnapshot()
    }

    private func removeExercise(exerciseID: UUID) {
        let backgroundStore = historyBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-detail.remove-exercise") { backgroundContext in
                    try WorkoutSessionRepository(modelContext: backgroundContext).removeExercise(
                        sessionID: sessionID,
                        sessionExerciseID: exerciseID
                    )
                }
                await handleExerciseRemoved(exerciseID: exerciseID)
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func handleExerciseRemoved(exerciseID: UUID) async {
        clearLocalState(for: exerciseID)
        hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
        loadingHydrationExerciseIDs.remove(exerciseID)
        hasPendingSummaryRebuild = true
        await reloadSnapshot()
    }

    private func archiveSession() {
        let backgroundStore = historyBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("history-detail.archive") { backgroundContext in
                    try WorkoutSessionRepository(modelContext: backgroundContext).archiveSession(id: sessionID)
                }
                await dismissArchivedSession()
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func dismissArchivedSession() {
        dismiss()
    }

    @MainActor
    private func syncExpandedExerciseState() {
        let orderedIDs = sessionExercises.map(\.id)
        let validIDs = Set(orderedIDs)
        expandedExerciseIDs = expandedExerciseIDs.filter { validIDs.contains($0.key) }

        let initialState = HistoryDetailExpansionPolicy.initialExpansionState(orderedExerciseIDs: orderedIDs)
        for exerciseID in orderedIDs where expandedExerciseIDs[exerciseID] == nil {
            expandedExerciseIDs[exerciseID] = initialState[exerciseID] ?? false
        }
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    @MainActor
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
    private func updateSessionHeaderDrafts(name: String, notes: String) {
        if sessionNameDraft != name {
            sessionNameDraft = name
        }
        if notesDraft != notes {
            notesDraft = notes
        }
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
        if updated {
            schedulePendingHydration()
        } else {
            loadingHydrationExerciseIDs.remove(exerciseID)
        }
    }

    @MainActor
    private func schedulePendingHydration() {
        let orderedIDs = sessionExercises.map(\.id)
        let pendingExerciseIDs = HistoryExerciseHydrationPlanner.pendingExerciseIDs(
            orderedExerciseIDs: orderedIDs,
            expandedExerciseIDs: expandedExerciseIDs,
            hydratedExerciseIDs: Set(hydrationPayloadByExerciseID.keys).union(loadingHydrationExerciseIDs)
        )
        guard !pendingExerciseIDs.isEmpty else { return }

        let generation = hydrationLoadGeneration
        loadingHydrationExerciseIDs.formUnion(pendingExerciseIDs)
        let backgroundStore = historyBackgroundStore
        Task { @MainActor in
            do {
                let payloads = try await backgroundStore.perform("history-detail.hydration") { backgroundContext in
                    try Self.loadHydrationPayloads(
                        modelContext: backgroundContext,
                        sessionID: sessionID,
                        exerciseIDs: pendingExerciseIDs
                    )
                }

                guard hydrationLoadGeneration == generation else { return }
                for (exerciseID, payload) in payloads {
                    hydrationPayloadByExerciseID[exerciseID] = payload
                }
                loadingHydrationExerciseIDs.subtract(pendingExerciseIDs)
            } catch is CancellationError {
                loadingHydrationExerciseIDs.subtract(pendingExerciseIDs)
            } catch {
                loadingHydrationExerciseIDs.subtract(pendingExerciseIDs)
            }
        }
    }

    @MainActor
    private func makeSaveCommand() -> HistorySaveCommand {
        let snapshots = Dictionary<UUID, HistoryExerciseSaveSnapshot>(
            sessionExercises.compactMap { exercise -> (UUID, HistoryExerciseSaveSnapshot)? in
                guard let drafts = setDraftsByExerciseID[exercise.id] else {
                    return nil
                }

                let snapshot = HistoryExerciseSaveSnapshot(
                    setDrafts: drafts,
                    restSeconds: restByExerciseID[exercise.id] ?? exercise.restSeconds,
                    notes: notesByExerciseID[exercise.id] ?? exercise.notes
                )
                let baseline = HistoryExerciseSaveSnapshot(
                    setDrafts: loadedLocalState.setDraftsByExerciseID[exercise.id] ?? [],
                    restSeconds: loadedLocalState.restByExerciseID[exercise.id] ?? exercise.restSeconds,
                    notes: loadedLocalState.notesByExerciseID[exercise.id] ?? exercise.notes
                )
                guard snapshot != baseline else { return nil }

                return (exercise.id, snapshot)
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

    nonisolated private static func addExercise(
        sessionID: UUID,
        catalogExerciseUUID: String,
        modelContext: ModelContext
    ) throws {
        guard let catalogItem = try ExerciseCatalogRepository(modelContext: modelContext)
            .exerciseMap(for: [catalogExerciseUUID])[catalogExerciseUUID] else {
            throw WorkoutSessionRepositoryError.invalidSessionState
        }

        try WorkoutSessionRepository(modelContext: modelContext).addExercise(
            sessionID: sessionID,
            catalogItem: catalogItem
        )
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

private struct HistoryExerciseSaveSnapshot: Equatable, Sendable {
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

@MainActor
private final class HistorySessionHeaderFlushCoordinator {
    private var flushHandler: (@MainActor () -> Void)?
    private(set) var hasDirtyDraft = false

    func register(handler: @escaping @MainActor () -> Void) {
        flushHandler = handler
    }

    func unregister() {
        flushHandler = nil
        hasDirtyDraft = false
    }

    func setDirty(_ isDirty: Bool) {
        hasDirtyDraft = isDirty
    }

    func flushDirty() {
        guard hasDirtyDraft else { return }
        flushHandler?()
        hasDirtyDraft = false
    }
}

private struct HistorySessionHeaderDraftFields: View {
    let sessionName: String
    let sessionNotes: String
    let onDraftsCommitted: (String, String) -> Void
    let flushCoordinator: HistorySessionHeaderFlushCoordinator

    @State private var localName: String
    @State private var localNotes: String

    init(
        sessionName: String,
        sessionNotes: String,
        onDraftsCommitted: @escaping (String, String) -> Void,
        flushCoordinator: HistorySessionHeaderFlushCoordinator
    ) {
        self.sessionName = sessionName
        self.sessionNotes = sessionNotes
        self.onDraftsCommitted = onDraftsCommitted
        self.flushCoordinator = flushCoordinator
        _localName = State(initialValue: sessionName)
        _localNotes = State(initialValue: sessionNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJResponsiveTextField(
                placeholder: "Workout name",
                text: Binding(
                    get: { localName },
                    set: { updateName($0) }
                ),
                capitalization: .words
            )

            WGJResponsiveTextField(
                placeholder: "Notes",
                text: Binding(
                    get: { localNotes },
                    set: { updateNotes($0) }
                ),
                axis: .vertical,
                lineLimit: 2...5,
                capitalization: .sentences
            )
        }
        .onAppear {
            flushCoordinator.register {
                flushPendingDrafts()
            }
            updateDirtyState()
        }
        .onDisappear {
            flushPendingDrafts()
            flushCoordinator.unregister()
        }
        .onChange(of: sessionName) { _, newValue in
            guard !flushCoordinator.hasDirtyDraft else { return }
            localName = newValue
            updateDirtyState()
        }
        .onChange(of: sessionNotes) { _, newValue in
            guard !flushCoordinator.hasDirtyDraft else { return }
            localNotes = newValue
            updateDirtyState()
        }
    }

    private func updateName(_ updated: String) {
        localName = updated
        updateDirtyState()
    }

    private func updateNotes(_ updated: String) {
        localNotes = updated
        updateDirtyState()
    }

    private func flushPendingDrafts() {
        guard flushCoordinator.hasDirtyDraft else { return }
        onDraftsCommitted(localName, localNotes)
        flushCoordinator.setDirty(false)
    }

    private func updateDirtyState() {
        flushCoordinator.setDirty(localName != sessionName || localNotes != sessionNotes)
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
    @State private var metricInputDraftBuffer = WorkoutMetricInputDraftStore()

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
            updateDirtyState()
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
            pruneMetricInputDrafts()
            updateDirtyState()
        }
        .onChange(of: restSeconds) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: newValue,
                notes: exerciseNotes
            )
            guard localRestSeconds != newValue else { return }
            localRestSeconds = newValue
            updateDirtyState()
        }
        .onChange(of: exerciseNotes) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: restSeconds,
                notes: newValue
            )
            guard localExerciseNotes != newValue else { return }
            localExerciseNotes = newValue
            updateDirtyState()
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
                        .accessibilityIdentifier("workout-set-\(index)-weight-field")
                }

                metricField(title: "Reps") {
                    TextField("0", text: repsBinding(for: draft.id))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .disabled(draft.isLocked)
                        .wgjPillField()
                        .accessibilityIdentifier("workout-set-\(index)-reps-field")
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
        updateDirtyState()
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
        updateDirtyState()
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
        updateDirtyState()
    }

    private func removeSet(_ setID: UUID) {
        localSetDrafts.removeAll { $0.id == setID }
        pruneMetricInputDrafts()
        editingCoordinator.stageDrafts(localSetDrafts)
        updateDirtyState()
    }

    private func updateSet(_ setID: UUID, update: (inout WorkoutSessionSetDraft) -> Void) {
        guard let index = localSetDrafts.firstIndex(where: { $0.id == setID }) else { return }
        update(&localSetDrafts[index])
        editingCoordinator.stageDrafts(localSetDrafts)
        updateDirtyState()
    }

    private func flushPendingEdits() {
        flushPendingMetricInputs()
        guard editingCoordinator.hasPendingChanges else { return }
        editingCoordinator.flushCommits()
        flushCoordinator?.setDirty(false, for: exerciseID)
    }

    private func updateDirtyState() {
        flushCoordinator?.setDirty(editingCoordinator.hasPendingChanges, for: exerciseID)
    }

    private func weightBinding(for setID: UUID) -> Binding<String> {
        Binding(
            get: {
                if let draftText = metricInputDraftBuffer.text(for: setID, metric: .weight) {
                    return draftText
                }
                guard let draft = localSetDrafts.first(where: { $0.id == setID }),
                      let value = draft.actualWeight
                else { return "" }
                return WGJFormatters.decimalString(value)
            },
            set: { rawValue in
                metricInputDraftBuffer.stage(rawValue, for: setID, metric: .weight)
                commitBufferedMetricInput(for: setID, metric: .weight, clearsText: false)
            }
        )
    }

    private func repsBinding(for setID: UUID) -> Binding<String> {
        Binding(
            get: {
                if let draftText = metricInputDraftBuffer.text(for: setID, metric: .reps) {
                    return draftText
                }
                guard let draft = localSetDrafts.first(where: { $0.id == setID }),
                      let value = draft.actualReps
                else { return "" }
                return String(value)
            },
            set: { rawValue in
                metricInputDraftBuffer.stage(rawValue, for: setID, metric: .reps)
                commitBufferedMetricInput(for: setID, metric: .reps, clearsText: false)
            }
        )
    }

    @discardableResult
    private func commitBufferedMetricInput(
        for setID: UUID,
        metric: WorkoutMetricInputDraftBuffer.Metric,
        clearsText: Bool
    ) -> Bool {
        var updatedDrafts = localSetDrafts
        let changed = metricInputDraftBuffer.commit(
            setID: setID,
            metric: metric,
            drafts: &updatedDrafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: true,
            clearsText: clearsText
        )
        guard changed else { return false }
        localSetDrafts = updatedDrafts
        editingCoordinator.stageDrafts(localSetDrafts)
        updateDirtyState()
        return true
    }

    private func flushPendingMetricInputs() {
        guard !metricInputDraftBuffer.isEmpty else { return }
        var updatedDrafts = localSetDrafts
        let changed = metricInputDraftBuffer.commitAll(
            drafts: &updatedDrafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: true,
            clearsText: true
        )
        guard changed else { return }
        localSetDrafts = updatedDrafts
        editingCoordinator.stageDrafts(localSetDrafts)
        updateDirtyState()
    }

    private func pruneMetricInputDrafts() {
        metricInputDraftBuffer.prune(keeping: Set(localSetDrafts.map(\.id)))
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
