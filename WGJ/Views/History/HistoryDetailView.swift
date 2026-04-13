import Foundation
import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID

    @Query private var sessions: [WorkoutSession]
    @Query private var sessionCardioBlocks: [WorkoutSessionCardioBlock]
    @Query private var sessionExercises: [WorkoutSessionExercise]

    @State private var hasBootstrapped = false
    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var notesByExerciseID: [UUID: String] = [:]
    @State private var hydrationPayloadByExerciseID: [UUID: HistoryExerciseHydrationPayload] = [:]
    @State private var loadedExerciseStateStamp: HistoryExerciseStateStamp?
    @State private var deferredHydrationTask: Task<Void, Never>?
    @State private var expandedExerciseIDs: [UUID: Bool] = [:]
    @State private var hasPendingSummaryRebuild = false

    @State private var showingExercisePicker = false
    @State private var showingArchiveConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID

        _sessions = Query(filter: #Predicate { item in
            item.id == sessionID
        })
        _sessionCardioBlocks = Query(
            filter: #Predicate { item in
                item.sessionID == sessionID
            }
        )
        _sessionExercises = Query(
            filter: #Predicate { item in
                item.sessionID == sessionID
            },
            sort: [SortDescriptor(\WorkoutSessionExercise.sortOrder, order: .forward)]
        )
    }

    var body: some View {
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                if let session {
                    headerCard(session)
                    cardioSection
                    exercisesSectionHeader
                } else {
                    WGJEmptyStateCard(
                        title: "Workout not found",
                        message: "This workout could not be loaded.",
                        icon: "exclamationmark.triangle"
                    )
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
                        .transition(exerciseCardTransition)
                }

                if !sessionExercises.isEmpty {
                    addExerciseButton(title: "Add another exercise")
                        .disabled(session == nil)
                }

                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .disabled(session == nil)
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
        .task(id: historyExerciseStateStamp) {
            await loadExerciseStateIfNeeded()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            deferredHydrationTask?.cancel()
            deferredHydrationTask = nil
        }
        .wgjMinimalKeyboardToolbar()
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var orderedCardioBlocks: [WorkoutSessionCardioBlock] {
        sessionCardioBlocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private var personalRecordSummary: HistoryWorkoutPersonalRecordSummary {
        HistoryWorkoutPersonalRecordSummary(highlightedSetCount: session?.prHitsCount ?? 0)
    }

    @MainActor
    private var historyExerciseStateStamp: HistoryExerciseStateStamp {
        HistoryExerciseStateStamp(exercises: sessionExercises)
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

    private func headerCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Session", subtitle: "Review the saved workout and adjust any logged values") {
                WGJMetricPill(
                    systemImage: personalRecordSummary.highlightedSetCount > 0 ? "trophy.fill" : "flag.checkered",
                    value: personalRecordSummary.label,
                    tint: personalRecordSummary.highlightedSetCount > 0 ? WGJTheme.accentGold : WGJTheme.textSecondary
                )
            }

            TextField("Workout name", text: $sessionNameDraft)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            TextField("Notes", text: $notesDraft, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    WGJMetricPill(
                        systemImage: "calendar",
                        value: (session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened)
                    )

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
        sessionNameDraft = session?.name ?? ""
        notesDraft = session?.notes ?? ""
        if let profile = try? ProfileRepository(modelContext: modelContext).currentProfile() {
            preferredLoadUnit = profile.preferredLoadUnit
        }
    }

    @MainActor
    private func loadExerciseStateIfNeeded() async {
        let currentStamp = HistoryExerciseStateStamp(exercises: sessionExercises)
        let previousStamp = loadedExerciseStateStamp
        let changedExerciseIDs = currentStamp.changedExerciseIDs(comparedTo: previousStamp)
        let removedExerciseIDs = previousStamp.map {
            $0.exerciseIDs.subtracting(currentStamp.exerciseIDs)
        } ?? []

        guard previousStamp == nil || !changedExerciseIDs.isEmpty || !removedExerciseIDs.isEmpty else {
            return
        }

        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil

        let exerciseIDsToRefresh = previousStamp == nil
            ? currentStamp.exerciseIDs
            : changedExerciseIDs

        if !removedExerciseIDs.isEmpty {
            for exerciseID in removedExerciseIDs {
                clearLocalState(for: exerciseID)
                hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
            }
        }

        if !exerciseIDsToRefresh.isEmpty {
            WGJPerformance.measure("history-detail.hydrate.local") {
                for exerciseID in exerciseIDsToRefresh {
                    guard let exercise = currentStamp.exercise(for: exerciseID) else {
                        continue
                    }

                    setDraftsByExerciseID[exerciseID] = makeDrafts(from: exercise)
                    restByExerciseID[exerciseID] = exercise.restSeconds
                    notesByExerciseID[exerciseID] = exercise.notes
                    hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
                }
            }
        }

        hydrationPayloadByExerciseID = hydrationPayloadByExerciseID.filter {
            currentStamp.exerciseIDs.contains($0.key)
        }
        syncExpandedExerciseState()
        loadedExerciseStateStamp = currentStamp
        scheduleDeferredHydration(
            for: currentStamp,
            draftsByExerciseID: setDraftsByExerciseID
        )
    }

    private func resolvedPreviousMap(
        baseMap: [Int: WorkoutPreviousSetSnapshot],
        maxSetCount: Int
    ) -> [Int: WorkoutPreviousSetSnapshot] {
        guard maxSetCount > 0, !baseMap.isEmpty else { return [:] }

        let fallback = baseMap[(baseMap.keys.max() ?? 0)]
        var resolved: [Int: WorkoutPreviousSetSnapshot] = [:]
        resolved.reserveCapacity(maxSetCount)

        for index in 0..<maxSetCount {
            if let exact = baseMap[index] {
                resolved[index] = exact
            } else if let fallback {
                resolved[index] = fallback
            }
        }

        return resolved
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: WorkoutSessionExercise, index: Int) -> some View {
        let isExpanded = expandedExerciseIDs[exercise.id] ?? false
        let drafts = setDraftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
        let restSeconds = restByExerciseID[exercise.id] ?? exercise.restSeconds
        let hydrationPayload = hydrationPayloadByExerciseID[exercise.id]

        if isExpanded {
            WorkoutExerciseRowHostView(
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
                isExpanded: true,
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
                }
            )
        } else {
            let collapsedSummary = HistoryExerciseCollapsedSummary(
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                completedSetCount: drafts.filter(\.isCompleted).count,
                totalSetCount: drafts.count,
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
        }

    }

    @MainActor
    private func scheduleDeferredHydration(
        for stamp: HistoryExerciseStateStamp,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) {
        let exerciseIDsToHydrate = HistoryExerciseHydrationPlanner.pendingExerciseIDs(
            orderedExerciseIDs: sessionExercises.map(\.id),
            expandedExerciseIDs: expandedExerciseIDs,
            hydratedExerciseIDs: Set(hydrationPayloadByExerciseID.keys)
        )

        guard !exerciseIDsToHydrate.isEmpty else {
            deferredHydrationTask?.cancel()
            deferredHydrationTask = nil
            return
        }

        deferredHydrationTask?.cancel()
        deferredHydrationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }

            let loadedPayloads = WGJPerformance.measure("history-detail.hydrate.rows") {
                loadHydrationPayloadByExerciseID(
                    using: draftsByExerciseID,
                    exerciseIDs: exerciseIDsToHydrate
                )
            }
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }
            hydrationPayloadByExerciseID.merge(loadedPayloads) { _, new in new }
            deferredHydrationTask = nil
        }
    }

    @MainActor
    private func loadHydrationPayloadByExerciseID(
        using draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        exerciseIDs: Set<UUID>
    ) -> [UUID: HistoryExerciseHydrationPayload] {
        guard !exerciseIDs.isEmpty else { return [:] }

        let startedAt = session?.startedAt ?? .now
        let targetExercises = sessionExercises.filter { exerciseIDs.contains($0.id) }
        let requestedExerciseUUIDs = Array(Set(targetExercises.map(\.catalogExerciseUUID)))
        let previousMaps = (try? sessionRepository.previousSetMaps(
            forExercises: requestedExerciseUUIDs,
            before: startedAt,
            excludingSessionID: sessionID
        )) ?? [:]

        let personalRecordsByExerciseID = loadPersonalRecordPresentation(for: exerciseIDs)

        var payloadByExerciseID: [UUID: HistoryExerciseHydrationPayload] = [:]
        payloadByExerciseID.reserveCapacity(targetExercises.count)

        for exercise in targetExercises {
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
            payloadByExerciseID[exercise.id] = HistoryExerciseHydrationPayload(
                previousPerformanceResolution: .resolved(
                    resolvedPreviousMap(baseMap: base, maxSetCount: drafts.count)
                ),
                personalRecords: personalRecordsByExerciseID[exercise.id]
                    ?? HistoryExercisePersonalRecordPresentation(summaryKinds: [], setKindsBySetID: [:])
            )
        }

        return payloadByExerciseID
    }

    private func saveChanges() {
        do {
            var didPersistChanges = hasPendingSummaryRebuild

            if let session {
                if !sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   sessionNameDraft != session.name {
                    try sessionRepository.updateSessionName(sessionID: sessionID, name: sessionNameDraft)
                    didPersistChanges = true
                }
                if notesDraft != session.notes {
                    try sessionRepository.updateSessionNotes(sessionID: sessionID, notes: notesDraft)
                    didPersistChanges = true
                }
            }

            for exercise in sessionExercises {
                let drafts = setDraftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
                let persistedDrafts = makeDrafts(from: exercise)
                if drafts != persistedDrafts {
                    try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
                    didPersistChanges = true
                }
            }

            for exercise in sessionExercises {
                let rest = restByExerciseID[exercise.id] ?? exercise.restSeconds
                if rest != exercise.restSeconds {
                    try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: rest)
                    didPersistChanges = true
                }
            }

            for exercise in sessionExercises {
                let notes = notesByExerciseID[exercise.id] ?? exercise.notes
                if notes != exercise.notes {
                    try sessionRepository.updateExerciseNotes(sessionExerciseID: exercise.id, notes: notes)
                    didPersistChanges = true
                }
            }

            if didPersistChanges {
                try sessionRepository.recalculateSessionSummary(sessionID: sessionID)
                hasPendingSummaryRebuild = false
            }
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        var capturedError: Error?

        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.addExercise(sessionID: sessionID, catalogItem: item)
                hasPendingSummaryRebuild = true
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func removeExercise(exerciseID: UUID) {
        var capturedError: Error?

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                clearLocalState(for: exerciseID)
                hydrationPayloadByExerciseID.removeValue(forKey: exerciseID)
                hasPendingSummaryRebuild = true
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
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
        let validIDs = Set(sessionExercises.map(\.id))
        expandedExerciseIDs = expandedExerciseIDs.filter { validIDs.contains($0.key) }

        for (index, exercise) in sessionExercises.enumerated() where expandedExerciseIDs[exercise.id] == nil {
            expandedExerciseIDs[exercise.id] = index == 0
        }
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
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

    @MainActor
    private func loadPersonalRecordPresentation(
        for exerciseIDs: Set<UUID>
    ) -> [UUID: HistoryExercisePersonalRecordPresentation] {
        guard !exerciseIDs.isEmpty else { return [:] }
        guard let achievements = try? WorkoutMetricsService(modelContext: modelContext).sessionSetPRAchievements(sessionID: sessionID) else {
            return [:]
        }

        var groupedSetKindsByExerciseID: [UUID: [UUID: [WorkoutPersonalRecordKind]]] = [:]
        var groupedSummaryKindsByExerciseID: [UUID: Set<WorkoutPersonalRecordKind>] = [:]

        for achievement in achievements where exerciseIDs.contains(achievement.sessionExerciseID) {
            groupedSetKindsByExerciseID[achievement.sessionExerciseID, default: [:]][achievement.setID] = achievement.kinds
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

    @MainActor
    private func orderedSessionSets(for exercise: WorkoutSessionExercise) -> [WorkoutSessionSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    @MainActor
    private func makeDrafts(from exercise: WorkoutSessionExercise) -> [WorkoutSessionSetDraft] {
        orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
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
        guard updated, let loadedExerciseStateStamp else { return }
        scheduleDeferredHydration(
            for: loadedExerciseStateStamp,
            draftsByExerciseID: setDraftsByExerciseID
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

private struct HistoryExerciseHydrationPayload: Equatable {
    let previousPerformanceResolution: WorkoutPreviousPerformanceResolution
    let personalRecords: HistoryExercisePersonalRecordPresentation
}

private struct HistoryExerciseStateStamp: Hashable {
    private let entries: [Entry]
    private let entriesByID: [UUID: Entry]
    private let exercisesByID: [UUID: WorkoutSessionExercise]

    @MainActor
    init(exercises: [WorkoutSessionExercise]) {
        entries = exercises.map(Entry.init(exercise:))
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    var exerciseIDs: Set<UUID> {
        Set(entries.map(\.id))
    }

    func exercise(for exerciseID: UUID) -> WorkoutSessionExercise? {
        exercisesByID[exerciseID]
    }

    func changedExerciseIDs(comparedTo previous: HistoryExerciseStateStamp?) -> Set<UUID> {
        guard let previous else {
            return exerciseIDs
        }

        var changed = exerciseIDs.symmetricDifference(previous.exerciseIDs)

        for exerciseID in exerciseIDs.intersection(previous.exerciseIDs) {
            guard entriesByID[exerciseID] != previous.entriesByID[exerciseID] else {
                continue
            }
            changed.insert(exerciseID)
        }

        return changed
    }

    static func == (lhs: HistoryExerciseStateStamp, rhs: HistoryExerciseStateStamp) -> Bool {
        lhs.entries == rhs.entries
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(entries)
    }

    private struct Entry: Hashable {
        let id: UUID
        let exerciseUpdatedAt: TimeInterval
        let restSeconds: Int
        let setCount: Int
        let latestSetUpdate: TimeInterval

        @MainActor
        init(exercise: WorkoutSessionExercise) {
            id = exercise.id
            exerciseUpdatedAt = exercise.updatedAt.timeIntervalSinceReferenceDate
            restSeconds = exercise.restSeconds
            let sets = exercise.sets ?? []
            setCount = sets.count
            latestSetUpdate = sets
                .map { $0.updatedAt.timeIntervalSinceReferenceDate }
                .max() ?? 0
        }
    }
}

private struct HistoryExercisePersonalRecordPresentation: Equatable {
    let summaryKinds: [WorkoutPersonalRecordKind]
    let setKindsBySetID: [UUID: [WorkoutPersonalRecordKind]]

    var highlightedSetCount: Int {
        setKindsBySetID.count
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
    let completedSetCount: Int
    let totalSetCount: Int
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
        "\(completedSetCount)/\(totalSetCount) sets"
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
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftCardioBlock.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionCardioBlock.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
