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
    @State private var previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    @State private var personalRecordPresentationByExerciseID: [UUID: HistoryExercisePersonalRecordPresentation] = [:]
    @State private var loadedExerciseStateStamp: HistoryExerciseStateStamp?
    @State private var expandedExerciseIDs: [UUID: Bool] = [:]
    @State private var personalRecordSummary = HistoryWorkoutPersonalRecordSummary(highlightedSetCount: 0)

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
        .task(id: sessionExercises.count) {
            await loadExerciseStateIfNeeded()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var orderedCardioBlocks: [WorkoutSessionCardioBlock] {
        sessionCardioBlocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
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
        guard currentStamp != loadedExerciseStateStamp else { return }

        let result = WGJPerformance.measure("history-detail.hydrate") { () -> HistoryExerciseHydrationResult in
            var loadedDrafts: [UUID: [WorkoutSessionSetDraft]] = [:]
            var loadedRests: [UUID: Int] = [:]
            var loadedPrevious: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
            let personalRecordPresentation = loadPersonalRecordPresentation()
            let startedAt = session?.startedAt ?? .now
            let requestedExerciseUUIDs = Array(Set(sessionExercises.map(\.catalogExerciseUUID)))
            let previousMaps = (try? sessionRepository.previousSetMaps(
                forExercises: requestedExerciseUUIDs,
                before: startedAt,
                excludingSessionID: sessionID
            )) ?? [:]

            for exercise in sessionExercises {
                let drafts = makeDrafts(from: exercise)
                loadedDrafts[exercise.id] = drafts
                loadedRests[exercise.id] = exercise.restSeconds
                let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
                loadedPrevious[exercise.id] = resolvedPreviousMap(baseMap: base, maxSetCount: drafts.count)
            }

            return HistoryExerciseHydrationResult(
                draftsByExerciseID: loadedDrafts,
                restsByExerciseID: loadedRests,
                previousByExerciseID: loadedPrevious,
                personalRecordPresentationByExerciseID: personalRecordPresentation
            )
        }

        setDraftsByExerciseID = result.draftsByExerciseID
        restByExerciseID = result.restsByExerciseID
        previousByExerciseID = result.previousByExerciseID
        personalRecordPresentationByExerciseID = result.personalRecordPresentationByExerciseID
        personalRecordSummary = HistoryWorkoutPersonalRecordSummary(
            highlightedSetCount: result.personalRecordPresentationByExerciseID.values.reduce(0) { partialResult, presentation in
                partialResult + presentation.highlightedSetCount
            }
        )
        syncExpandedExerciseState()
        loadedExerciseStateStamp = currentStamp
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

    private func exerciseSection(_ exercise: WorkoutSessionExercise, index: Int) -> some View {
        let personalRecordPresentation = personalRecordPresentationByExerciseID[exercise.id]
        let previousSets = previousByExerciseID[exercise.id] ?? [:]
        let drafts = setDraftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
        let restSeconds = restByExerciseID[exercise.id] ?? exercise.restSeconds

        return WorkoutExerciseRowHostView(
            exerciseID: exercise.id,
            exerciseAccessibilityIdentifier: "history-exercise-\(exercise.catalogExerciseUUID)",
            exerciseName: exercise.exerciseNameSnapshot,
            muscleSummary: exercise.muscleSummarySnapshot,
            category: exercise.categorySnapshot,
            exerciseIndexTitle: "Exercise \(index + 1)",
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            previousBySetIndex: previousSets,
            personalRecordSummaryKinds: personalRecordPresentation?.summaryKinds ?? [],
            personalRecordKindsBySetID: personalRecordPresentation?.setKindsBySetID ?? [:],
            preferredLoadUnit: preferredLoadUnit,
            restSeconds: restSeconds,
            setDrafts: drafts,
            isExpanded: expandedExerciseIDs[exercise.id] ?? false,
            onSetDraftsCommitted: { drafts in
                setDraftsByExerciseID[exercise.id] = drafts
            },
            onRestCommitted: { rest in
                restByExerciseID[exercise.id] = rest
            },
            onExpandedChanged: { expandedExerciseIDs[exercise.id] = $0 },
            onExerciseDelete: {
                removeExercise(exerciseID: exercise.id)
            }
        )
    }

    private func saveChanges() {
        do {
            if let session {
                if !sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   sessionNameDraft != session.name {
                    try sessionRepository.updateSessionName(sessionID: sessionID, name: sessionNameDraft)
                }
                if notesDraft != session.notes {
                    try sessionRepository.updateSessionNotes(sessionID: sessionID, notes: notesDraft)
                }
            }

            for exercise in sessionExercises {
                let drafts = setDraftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
                try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
            }

            for exercise in sessionExercises {
                let rest = restByExerciseID[exercise.id] ?? exercise.restSeconds
                try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: rest)
            }

            try sessionRepository.recalculateSessionSummary(sessionID: sessionID)
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
                loadedExerciseStateStamp = nil
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
                setDraftsByExerciseID.removeValue(forKey: exerciseID)
                restByExerciseID.removeValue(forKey: exerciseID)
                previousByExerciseID.removeValue(forKey: exerciseID)
                loadedExerciseStateStamp = nil
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

    @MainActor
    private func loadPersonalRecordPresentation() -> [UUID: HistoryExercisePersonalRecordPresentation] {
        guard let achievements = try? WorkoutMetricsService(modelContext: modelContext).sessionSetPRAchievements(sessionID: sessionID) else {
            return [:]
        }

        var groupedSetKindsByExerciseID: [UUID: [UUID: [WorkoutPersonalRecordKind]]] = [:]
        var groupedSummaryKindsByExerciseID: [UUID: Set<WorkoutPersonalRecordKind>] = [:]

        for achievement in achievements {
            groupedSetKindsByExerciseID[achievement.sessionExerciseID, default: [:]][achievement.setID] = achievement.kinds
            groupedSummaryKindsByExerciseID[achievement.sessionExerciseID, default: []].formUnion(achievement.kinds)
        }

        var presentationByExerciseID: [UUID: HistoryExercisePersonalRecordPresentation] = [:]
        for exercise in sessionExercises {
            presentationByExerciseID[exercise.id] = HistoryExercisePersonalRecordPresentation(
                summaryKinds: Array(groupedSummaryKindsByExerciseID[exercise.id, default: []]).sorted(),
                setKindsBySetID: groupedSetKindsByExerciseID[exercise.id, default: [:]]
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

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }
}

private struct HistoryExerciseHydrationResult {
    let draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    let restsByExerciseID: [UUID: Int]
    let previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]]
    let personalRecordPresentationByExerciseID: [UUID: HistoryExercisePersonalRecordPresentation]
}

private struct HistoryExerciseStateStamp: Hashable {
    private let entries: [Entry]

    @MainActor
    init(exercises: [WorkoutSessionExercise]) {
        entries = exercises.map(Entry.init(exercise:))
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
