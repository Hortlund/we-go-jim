import Foundation
import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID

    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [WorkoutSessionExercise]
    @Query private var profiles: [UserProfile]

    @State private var hasBootstrapped = false
    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    @State private var loadedExerciseIDs: [UUID] = []

    @State private var showingExercisePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var exerciseSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var exerciseSwipeRemoving: [UUID: Bool] = [:]

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    private var preferredLoadUnit: TemplateLoadUnit {
        profiles.first?.preferredLoadUnit ?? .kg
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID

        _sessions = Query(filter: #Predicate { item in
            item.id == sessionID
        })
        _sessionExercises = Query(
            filter: #Predicate { item in
                item.sessionID == sessionID
            },
            sort: [SortDescriptor(\WorkoutSessionExercise.sortOrder, order: .forward)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                if let session {
                    headerCard(session)
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
            .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: sessionExercises.map(\.id))
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Workout")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(repository: catalogRepository) { item in
                addExercise(item)
            }
            .wgjSheetSurface()
        }
        .confirmationDialog("Delete workout?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                deleteSession()
            }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: sessionExercises.map(\.id)) {
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
                    systemImage: "flag.checkered",
                    value: "\(session.prHitsCount) PRs",
                    tint: session.prHitsCount > 0 ? WGJTheme.accentCyan : WGJTheme.textSecondary
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

    @MainActor
    private func setDraftsBinding(for exercise: WorkoutSessionExercise) -> Binding<[WorkoutSessionSetDraft]> {
        Binding {
            if let cached = setDraftsByExerciseID[exercise.id] {
                return cached
            }
            let orderedSets = (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            var drafts: [WorkoutSessionSetDraft] = []
            drafts.reserveCapacity(orderedSets.count)
            for set in orderedSets {
                drafts.append(
                    WorkoutSessionSetDraft(
                        id: set.id,
                        isWarmup: set.isWarmup,
                        restSeconds: set.restSeconds,
                        targetReps: set.targetReps,
                        targetWeight: set.targetWeight,
                        targetLoadUnit: set.targetLoadUnit,
                        actualReps: set.actualReps,
                        actualWeight: set.actualWeight,
                        actualLoadUnit: set.actualLoadUnit,
                        isCompleted: set.isCompleted,
                        isLocked: set.isLocked
                    )
                )
            }
            return drafts
        } set: { updated in
            setDraftsByExerciseID[exercise.id] = updated
        }
    }

    @MainActor
    private func restBinding(for exercise: WorkoutSessionExercise) -> Binding<Int> {
        Binding {
            restByExerciseID[exercise.id] ?? exercise.restSeconds
        } set: { updated in
            restByExerciseID[exercise.id] = max(0, min(3600, updated))
        }
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        sessionNameDraft = session?.name ?? ""
        notesDraft = session?.notes ?? ""
    }

    @MainActor
    private func loadExerciseStateIfNeeded() async {
        let currentIDs = sessionExercises.map(\.id)
        guard currentIDs != loadedExerciseIDs else { return }

        var loadedDrafts: [UUID: [WorkoutSessionSetDraft]] = [:]
        var loadedRests: [UUID: Int] = [:]
        var loadedPrevious: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
        let startedAt = session?.startedAt ?? .now
        let requestedExerciseUUIDs = Array(Set(sessionExercises.map(\.catalogExerciseUUID)))
        let previousMaps = (try? sessionRepository.previousSetMaps(
            forExercises: requestedExerciseUUIDs,
            before: startedAt,
            excludingSessionID: sessionID
        )) ?? [:]

        for exercise in sessionExercises {
            let drafts = (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(WorkoutSessionSetDraft.init(model:))
            loadedDrafts[exercise.id] = drafts
            loadedRests[exercise.id] = exercise.restSeconds
            let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
            loadedPrevious[exercise.id] = resolvedPreviousMap(baseMap: base, maxSetCount: drafts.count)
        }

        setDraftsByExerciseID = loadedDrafts
        restByExerciseID = loadedRests
        previousByExerciseID = loadedPrevious
        loadedExerciseIDs = currentIDs
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
        SwipeDeleteRow(
            offset: exerciseSwipeOffsetBinding(for: exercise.id),
            isRemoving: exerciseRemovingBinding(for: exercise.id),
            activeRegionMaxY: 116,
            gestureStrategy: .simultaneous
        ) {
            removeExercise(exerciseID: exercise.id)
        } content: {
            WorkoutSessionExerciseGridEditor(
                exerciseName: exercise.exerciseNameSnapshot,
                muscleSummary: exercise.muscleSummarySnapshot,
                category: exercise.categorySnapshot,
                exerciseIndexTitle: "Exercise \(index + 1)",
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                previousBySetIndex: previousByExerciseID[exercise.id] ?? [:],
                preferredLoadUnit: preferredLoadUnit,
                restSeconds: restBinding(for: exercise),
                setDrafts: setDraftsBinding(for: exercise),
                initiallyExpanded: true,
                onSetDraftsChanged: { drafts in
                    setDraftsByExerciseID[exercise.id] = drafts
                },
                onRestChanged: { rest in
                    restByExerciseID[exercise.id] = rest
                },
                onExerciseDelete: {
                    removeExercise(exerciseID: exercise.id)
                }
            )
        }
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
                let drafts: [WorkoutSessionSetDraft]
                if let cached = setDraftsByExerciseID[exercise.id] {
                    drafts = cached
                } else {
                    let orderedSets = (exercise.sets ?? [])
                        .sorted { $0.sortOrder < $1.sortOrder }
                    var mappedDrafts: [WorkoutSessionSetDraft] = []
                    mappedDrafts.reserveCapacity(orderedSets.count)
                    for set in orderedSets {
                        mappedDrafts.append(
                            WorkoutSessionSetDraft(
                                id: set.id,
                                isWarmup: set.isWarmup,
                                restSeconds: set.restSeconds,
                                targetReps: set.targetReps,
                                targetWeight: set.targetWeight,
                                targetLoadUnit: set.targetLoadUnit,
                                actualReps: set.actualReps,
                                actualWeight: set.actualWeight,
                                actualLoadUnit: set.actualLoadUnit,
                                isCompleted: set.isCompleted,
                                isLocked: set.isLocked
                            )
                        )
                    }
                    drafts = mappedDrafts
                }
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
                loadedExerciseIDs = []
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
                clearExerciseSwipeState(for: exerciseID)
                loadedExerciseIDs = []
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func deleteSession() {
        do {
            try sessionRepository.deleteSession(id: sessionID)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func clearExerciseSwipeState(for exerciseID: UUID) {
        exerciseSwipeOffsets[exerciseID] = nil
        exerciseSwipeRemoving[exerciseID] = nil
    }

    private func exerciseSwipeOffsetBinding(for exerciseID: UUID) -> Binding<CGFloat> {
        Binding(
            get: { exerciseSwipeOffsets[exerciseID] ?? 0 },
            set: { exerciseSwipeOffsets[exerciseID] = $0 }
        )
    }

    private func exerciseRemovingBinding(for exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { exerciseSwipeRemoving[exerciseID] ?? false },
            set: { exerciseSwipeRemoving[exerciseID] = $0 }
        )
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
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
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
