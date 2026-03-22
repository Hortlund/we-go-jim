import Combine
import Foundation
import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID
    private let guidanceService = TrainingGuidanceService()

    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [WorkoutSessionExercise]
    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]
    @Query private var profiles: [UserProfile]

    @State private var hasBootstrapped = false
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var lastPersistedDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]

    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var lastPersistedRestByExerciseID: [UUID: Int] = [:]
    @State private var pendingRestTasks: [UUID: Task<Void, Never>] = [:]

    @State private var previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    @State private var loadedExerciseIDs: [UUID] = []
    @State private var catalogByUUID: [String: ExerciseCatalogItem] = [:]
    @State private var cardStateController = ActiveWorkoutExerciseCardStateController()

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var showingExercisePicker = false
    @State private var showingFinishConfirmation = false
    @State private var isCancelArmed = false
    @State private var showingSaveTemplateSheet = false
    @State private var exerciseSettingsDraft: ActiveWorkoutExerciseSettingsDraft?
    @State private var pendingTemplateUpdatePreview: WorkoutTemplateSyncPreview?
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?
    @State private var isKeyboardVisible = false

    @State private var errorMessage = ""
    @State private var showingError = false

    private let restTimerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var templateSyncService: WorkoutTemplateSyncService {
        WorkoutTemplateSyncService(modelContext: modelContext)
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
            VStack(alignment: .leading, spacing: 16) {
                if let session {
                    ActiveWorkoutHeaderCard(
                        sessionNameDraft: $sessionNameDraft,
                        notesDraft: $notesDraft,
                        session: session,
                        exerciseCount: sessionExercises.count,
                        onSubmit: persistSessionMeta
                    )
                    exercisesSectionHeader
                } else {
                    WGJEmptyStateCard(
                        title: "Workout session not found",
                        message: "This active workout could not be loaded.",
                        icon: "exclamationmark.triangle"
                    )
                }

                if sessionExercises.isEmpty {
                    WGJEmptyStateCard(
                        title: "No exercises added",
                        message: "Add exercises to start logging sets in this workout.",
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
            }
            .padding(16)
            .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: sessionExercises.map(\.id))
            .animation(
                WGJMotion.overlayAnimation(reduceMotion: reduceMotion),
                value: coordinator.restTimerPopup?.id
            )
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Active Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    minimizeWorkout()
                } label: {
                    Label("Minimize", systemImage: "chevron.down")
                }
                .accessibilityIdentifier("active-workout-minimize-button")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                finishToolbarButton
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                ActiveWorkoutBottomDock(
                    session: session,
                    isCancelArmed: isCancelArmed,
                    reduceMotion: reduceMotion,
                    onArmCancel: {
                        dismissKeyboard()
                        showingFinishConfirmation = false
                        isCancelArmed = true
                    },
                    onKeepWorkout: {
                        isCancelArmed = false
                    },
                    onDiscardWorkout: {
                        cancelWorkout()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .wgjTrackKeyboardVisibility($isKeyboardVisible)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(repository: catalogRepository) { exercise in
                addExercise(exercise)
            }
            .wgjSheetSurface()
        }
        .sheet(item: $exerciseSettingsDraft) { draft in
            ActiveWorkoutExerciseSettingsSheet(
                draft: draft,
                onSave: saveExerciseSettings
            )
            .wgjSheetSurface()
        }
        .sheet(isPresented: $showingSaveTemplateSheet) {
            ActiveWorkoutSaveTemplateSheet(
                templateNameDraft: $templateNameDraft,
                templateFolderID: $templateFolderID,
                folders: folders,
                onSkip: finalizeCompletion,
                onSave: saveSessionAsTemplate
            )
            .interactiveDismissDisabled()
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: sessionExercises.map(\.id)) {
            await loadExerciseStateIfNeeded()
        }
        .onDisappear {
            isCancelArmed = false
            flushPendingSaves()
        }
        .onReceive(restTimerTick) { date in
            coordinator.handleRestTimerExpirationIfNeeded(at: date)
        }
        .alert("Workout Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Update Template?", isPresented: templateUpdatePromptBinding, presenting: pendingTemplateUpdatePreview) { preview in
            Button("Update Template") {
                applyTemplateUpdate(preview)
            }
            Button("Keep Template", role: .cancel) {
                pendingTemplateUpdatePreview = nil
                finalizeCompletion()
            }
        } message: {
            Text($0.summary)
        }
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: isKeyboardVisible)
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var exercisesSectionHeader: some View {
        Group {
            if sessionExercises.isEmpty {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Add exercises and log each set inline."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Swipe the exercise header to delete an exercise, or swipe a set row to delete a set."
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

    private var finishToolbarButton: some View {
        Button("Finish") {
            presentFinishConfirmation()
        }
        .disabled(session == nil || sessionExercises.isEmpty)
        .accessibilityIdentifier("active-workout-finish-button")
        .popover(isPresented: $showingFinishConfirmation, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            ActiveWorkoutFinishPopover(
                onFinish: confirmFinishWorkout,
                onCancel: { showingFinishConfirmation = false }
            )
            .presentationCompactAdaptation(.popover)
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
        .accessibilityIdentifier("active-workout-add-exercise-button")
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
        coordinator.present(sessionID: sessionID)

        guard let session else { return }
        sessionNameDraft = session.name
        notesDraft = session.notes
        if session.templateID == nil {
            templateNameDraft = session.name == "Empty Workout" ? "New Template" : session.name
        }
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
        let loadedCatalog = (try? catalogRepository.exerciseMap(for: requestedExerciseUUIDs)) ?? [:]
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
        lastPersistedDraftsByExerciseID = loadedDrafts
        restByExerciseID = loadedRests
        lastPersistedRestByExerciseID = loadedRests
        previousByExerciseID = loadedPrevious
        catalogByUUID = loadedCatalog
        let completedExerciseIDs = Set(
            loadedDrafts.compactMap { exerciseID, drafts in
                isExerciseCompleted(drafts) ? exerciseID : nil
            }
        )
        cardStateController.sync(
            exerciseIDs: currentIDs,
            completedExerciseIDs: completedExerciseIDs,
            firstIncompleteExerciseID: firstIncompleteExerciseID(
                from: sessionExercises,
                draftsByExerciseID: loadedDrafts
            )
        )
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

    @MainActor
    private func persistDrafts(sessionExerciseID: UUID, drafts: [WorkoutSessionSetDraft]) {
        if lastPersistedDraftsByExerciseID[sessionExerciseID] == drafts {
            return
        }

        pendingSaveTasks[sessionExerciseID]?.cancel()
        pendingSaveTasks[sessionExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }

            let latest = setDraftsByExerciseID[sessionExerciseID] ?? drafts
            guard lastPersistedDraftsByExerciseID[sessionExerciseID] != latest else {
                pendingSaveTasks[sessionExerciseID] = nil
                return
            }

            do {
                try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExerciseID, drafts: latest)
                lastPersistedDraftsByExerciseID[sessionExerciseID] = latest
                pendingSaveTasks[sessionExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    private func exerciseSection(_ exercise: WorkoutSessionExercise, index: Int) -> some View {
        WorkoutSessionExerciseGridEditor(
            exerciseName: exercise.exerciseNameSnapshot,
            muscleSummary: exercise.muscleSummarySnapshot,
            category: exercise.categorySnapshot,
            exerciseIndexTitle: "Exercise \(index + 1)",
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            previousBySetIndex: previousByExerciseID[exercise.id] ?? [:],
            overloadFeedback: overloadFeedback(for: exercise),
            preferredLoadUnit: preferredLoadUnit,
            restSeconds: restBinding(for: exercise),
            setDrafts: setDraftsBinding(for: exercise),
            isExpanded: expansionBinding(for: exercise.id),
            showsInlineExerciseControls: false,
            showsSetProgressChip: false,
            manualCompletionMode: true,
            enablesHeaderSwipeDelete: true,
            onSetDraftsChanged: { drafts in
                setDraftsByExerciseID[exercise.id] = drafts
                cardStateController.updateCompletion(
                    for: exercise.id,
                    isCompleted: isExerciseCompleted(drafts)
                )
                persistDrafts(sessionExerciseID: exercise.id, drafts: drafts)
            },
            onRestChanged: { rest in
                persistRest(sessionExerciseID: exercise.id, restSeconds: rest)
            },
            onSetCompletionChange: { setID, setLabel, restSeconds, isCompleted in
                if isCompleted {
                    coordinator.startRestTimer(
                        seconds: restSeconds,
                        exerciseName: exercise.exerciseNameSnapshot,
                        setLabel: setLabel,
                        sourceSetID: setID
                    )
                } else {
                    coordinator.clearRestTimer(sourceSetID: setID)
                }
            },
            onExerciseSettings: {
                showExerciseSettings(for: exercise)
            },
            onExerciseDelete: {
                removeExercise(exerciseID: exercise.id)
            }
        )
    }

    @MainActor
    private func persistRest(sessionExerciseID: UUID, restSeconds: Int) {
        let normalized = max(0, min(3600, restSeconds))
        if lastPersistedRestByExerciseID[sessionExerciseID] == normalized {
            return
        }

        pendingRestTasks[sessionExerciseID]?.cancel()
        pendingRestTasks[sessionExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }

            let latest = restByExerciseID[sessionExerciseID] ?? normalized
            guard lastPersistedRestByExerciseID[sessionExerciseID] != latest else {
                pendingRestTasks[sessionExerciseID] = nil
                return
            }

            do {
                try sessionRepository.updateExerciseRest(sessionExerciseID: sessionExerciseID, restSeconds: latest)
                reloadExerciseState(sessionExerciseID: sessionExerciseID)
                pendingRestTasks[sessionExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func flushPendingSaves() {
        for task in pendingSaveTasks.values {
            task.cancel()
        }
        pendingSaveTasks.removeAll()

        for task in pendingRestTasks.values {
            task.cancel()
        }
        pendingRestTasks.removeAll()

        for (exerciseID, drafts) in setDraftsByExerciseID {
            guard lastPersistedDraftsByExerciseID[exerciseID] != drafts else { continue }
            do {
                try sessionRepository.saveSetDrafts(sessionExerciseID: exerciseID, drafts: drafts)
                lastPersistedDraftsByExerciseID[exerciseID] = drafts
            } catch {
                showError(error)
            }
        }

        for (exerciseID, rest) in restByExerciseID {
            guard lastPersistedRestByExerciseID[exerciseID] != rest else { continue }
            do {
                try sessionRepository.updateExerciseRest(sessionExerciseID: exerciseID, restSeconds: rest)
                reloadExerciseState(sessionExerciseID: exerciseID)
            } catch {
                showError(error)
            }
        }
    }

    private func persistSessionMeta() {
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
        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? []).map(\.id))

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                setDraftsByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedDraftsByExerciseID.removeValue(forKey: exerciseID)
                restByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedRestByExerciseID.removeValue(forKey: exerciseID)
                previousByExerciseID.removeValue(forKey: exerciseID)
                loadedExerciseIDs = []
            } catch {
                capturedError = error
            }
        }

        if let restTimerSourceSetID = coordinator.restTimerSourceSetID,
           removedSetIDs.contains(restTimerSourceSetID) {
            coordinator.clearRestTimer(sourceSetID: restTimerSourceSetID)
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private var templateUpdatePromptBinding: Binding<Bool> {
        Binding(
            get: { pendingTemplateUpdatePreview != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTemplateUpdatePreview = nil
                }
            }
        )
    }

    private var isTrainingGuidanceEnabled: Bool {
        profiles.first?.isTrainingGuidanceEnabled ?? true
    }

    private func expansionBinding(for exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { cardStateController.isExpanded(for: exerciseID) },
            set: { cardStateController.setExpanded($0, for: exerciseID) }
        )
    }

    @MainActor
    private func overloadFeedback(for exercise: WorkoutSessionExercise) -> ActiveWorkoutProgressiveOverloadPresentation? {
        guard isTrainingGuidanceEnabled else { return nil }
        guard let catalogExercise = catalogByUUID[exercise.catalogExerciseUUID] else { return nil }

        let drafts = setDraftsByExerciseID[exercise.id]
            ?? (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }.map(WorkoutSessionSetDraft.init(model:))

        let cue = guidanceService.progressiveOverloadCue(
            for: catalogExercise,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            setDrafts: drafts
        )
        return ActiveWorkoutProgressiveOverloadPresentation.make(
            from: cue,
            isExerciseCompleted: isExerciseCompleted(drafts)
        )
    }

    private func isExerciseCompleted(_ drafts: [WorkoutSessionSetDraft]) -> Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isCompleted)
    }

    @MainActor
    private func firstIncompleteExerciseID(
        from exercises: [WorkoutSessionExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> UUID? {
        for exercise in exercises {
            let drafts = draftsByExerciseID[exercise.id]
                ?? (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }.map(WorkoutSessionSetDraft.init(model:))
            if !isExerciseCompleted(drafts) {
                return exercise.id
            }
        }
        return nil
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private func showExerciseSettings(for exercise: WorkoutSessionExercise) {
        dismissKeyboard()
        exerciseSettingsDraft = ActiveWorkoutExerciseSettingsDraft(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot,
            minRepsText: exercise.targetRepMin.map(String.init) ?? "",
            maxRepsText: exercise.targetRepMax.map(String.init) ?? "",
            restSeconds: restByExerciseID[exercise.id] ?? exercise.restSeconds
        )
    }

    private func saveExerciseSettings(_ draft: ActiveWorkoutExerciseSettingsDraft) {
        do {
            pendingRestTasks[draft.exerciseID]?.cancel()
            pendingRestTasks[draft.exerciseID] = nil
            let minReps = parsedRepValue(from: draft.minRepsText)
            let maxReps = parsedRepValue(from: draft.maxRepsText)
            try sessionRepository.updateExerciseRepRange(
                sessionExerciseID: draft.exerciseID,
                minReps: minReps,
                maxReps: maxReps
            )
            try sessionRepository.updateExerciseRest(
                sessionExerciseID: draft.exerciseID,
                restSeconds: draft.restSeconds
            )
            reloadExerciseState(sessionExerciseID: draft.exerciseID)
            exerciseSettingsDraft = nil
        } catch {
            showError(error)
        }
    }

    private func reloadExerciseState(sessionExerciseID: UUID) {
        do {
            let drafts = try sessionRepository.setDrafts(sessionExerciseID: sessionExerciseID)
            setDraftsByExerciseID[sessionExerciseID] = drafts
            lastPersistedDraftsByExerciseID[sessionExerciseID] = drafts
            cardStateController.updateCompletion(
                for: sessionExerciseID,
                isCompleted: isExerciseCompleted(drafts)
            )

            if let exercise = try sessionRepository.sessionExercises(sessionID: sessionID).first(where: { $0.id == sessionExerciseID }) {
                restByExerciseID[sessionExerciseID] = exercise.restSeconds
                lastPersistedRestByExerciseID[sessionExerciseID] = exercise.restSeconds
            }
        } catch {
            showError(error)
        }
    }

    private func finishWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.finishSession(sessionID: sessionID, notes: notesDraft)
            if session?.templateID == nil {
                showingSaveTemplateSheet = true
            } else if let preview = try templateSyncService.previewTemplateUpdate(forSessionID: sessionID) {
                pendingTemplateUpdatePreview = preview
            } else {
                finalizeCompletion()
            }
        } catch {
            showError(error)
        }
    }

    private func saveSessionAsTemplate() {
        dismissKeyboard()
        do {
            _ = try templateRepository.createTemplate(
                fromSessionID: sessionID,
                name: templateNameDraft,
                folderID: templateFolderID
            )
            finalizeCompletion()
        } catch {
            showError(error)
        }
    }

    private func finalizeCompletion() {
        dismissKeyboard()
        isCancelArmed = false
        showingSaveTemplateSheet = false
        exerciseSettingsDraft = nil
        pendingTemplateUpdatePreview = nil
        coordinator.clearActiveWorkout()
        coordinator.selectedTab = .history
        dismiss()
    }

    private func minimizeWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        coordinator.collapseActiveWorkout()
        dismiss()
    }

    private func cancelWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.cancelSession(sessionID: sessionID)
            coordinator.clearActiveWorkout()
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func parsedRepValue(from text: String) -> Int? {
        let cleaned = text.filter(\.isNumber)
        return cleaned.isEmpty ? nil : Int(cleaned)
    }

    private func applyTemplateUpdate(_ preview: WorkoutTemplateSyncPreview) {
        pendingTemplateUpdatePreview = nil
        do {
            try templateSyncService.applyTemplateUpdate(preview)
            finalizeCompletion()
        } catch {
            showError(error)
        }
    }

    private func dismissKeyboard() {
        WGJKeyboard.dismiss()
    }

    private func presentFinishConfirmation() {
        dismissKeyboard()
        isCancelArmed = false
        showingFinishConfirmation = true
    }

    private func confirmFinishWorkout() {
        showingFinishConfirmation = false
        finishWorkout()
    }
}

private struct ActiveWorkoutHeaderCard: View {
    @Binding var sessionNameDraft: String
    @Binding var notesDraft: String

    let session: WorkoutSession
    let exerciseCount: Int
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Session")

            TextField("Workout name", text: $sessionNameDraft)
                .textInputAutocapitalization(.words)
                .wgjPillField()
                .accessibilityIdentifier("active-workout-name-field")
                .onSubmit(onSubmit)

            TextField("Notes", text: $notesDraft, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()
                .onSubmit(onSubmit)

            HStack {
                Text("\(exerciseCount) exercises")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)

                Spacer()
            }

            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }
}

private struct ActiveWorkoutBottomDock: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    let session: WorkoutSession?
    let isCancelArmed: Bool
    let reduceMotion: Bool
    let onArmCancel: () -> Void
    let onKeepWorkout: () -> Void
    let onDiscardWorkout: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let popup = coordinator.restTimerPopup {
                WGJTransientBanner(
                    title: popup.title,
                    message: popup.message,
                    icon: "bell.badge.fill",
                    tint: WGJTheme.success
                )
                .transition(WGJMotion.cardTransition(reduceMotion: reduceMotion))
            }

            if let session {
                ActiveWorkoutActivityTimerDock(session: session)
            }

            if isCancelArmed {
                cancelConfirmation
            } else {
                Button(action: onArmCancel) {
                    Label("Cancel Workout", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(WGJTheme.danger)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WGJTheme.field.opacity(0.74))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(WGJTheme.danger.opacity(0.38), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AnyShapeStyle(.ultraThinMaterial))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WGJTheme.accentBlue.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var cancelConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WGJTheme.danger)

                Text("Discard this workout and all logged sets?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button("Keep Workout", action: onKeepWorkout)
                    .buttonStyle(WGJGhostButtonStyle())

                Button("Discard Workout", action: onDiscardWorkout)
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .tint(WGJTheme.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.field.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.danger.opacity(0.32), lineWidth: 1)
                )
        )
    }
}

private struct ActiveWorkoutFinishPopover: View {
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(WGJTheme.success)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish Workout?")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("This will close the active workout and add it to your history.")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button("Not yet", action: onCancel)
                    .buttonStyle(WGJGhostButtonStyle())

                Button("Finish and Save", action: onFinish)
                    .buttonStyle(WGJCompactPrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .wgjCardContainer(strong: true, cornerRadius: 18)
        .padding(6)
    }
}

private struct ActiveWorkoutActivityTimerDock: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = coordinator.restTimerRemaining(at: context.date)
            let isResting = remaining != nil
            let accent = isResting ? WGJTheme.success : WGJTheme.accentCyan
            let secondaryText = isResting
                ? coordinator.restTimerContextLabel() ?? "Recover before the next set"
                : "Workout in progress"
            let primaryValue = isResting
                ? formattedRest(remaining ?? 0)
                : WGJDurationFormatter.elapsedString(since: session.startedAt, now: context.date)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isResting ? "Rest Timer" : "Elapsed Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)

                    Text(secondaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.84)
                }
                Spacer(minLength: 12)
                Text(primaryValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .wgjSingleLineText(scale: 0.84)

                if isResting {
                    Button {
                        coordinator.clearRestTimer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(
                        WGJIconButtonStyle(
                            tint: WGJTheme.textSecondary,
                            background: WGJTheme.cardStrong,
                            outline: WGJTheme.outline
                        )
                    )
                    .accessibilityLabel("Dismiss rest timer")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(isResting ? 0.16 : 0.12),
                                        WGJTheme.cardStrong.opacity(0.80),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accent.opacity(isResting ? 0.28 : 0.22), lineWidth: 1)
                    }
                    .shadow(color: WGJTheme.shadowStrong.opacity(0.14), radius: 16, x: 0, y: 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isResting
                    ? "Rest timer \(primaryValue). \(secondaryText)"
                    : "Elapsed time \(primaryValue)"
            )
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct ActiveWorkoutSaveTemplateSheet: View {
    @Binding var templateNameDraft: String
    @Binding var templateFolderID: UUID?

    let folders: [TemplateFolder]
    let onSkip: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WGJSectionHeader("Save as Template", subtitle: "Use this workout as a reusable plan")

                    TextField("Template name", text: $templateNameDraft)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()
                        .accessibilityIdentifier("active-workout-template-name-field")

                    Picker("Folder", selection: $templateFolderID) {
                        Text("Unfiled").tag(Optional<UUID>.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional.some(folder.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .wgjPillField()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjSheetSurface()
            .navigationTitle("Complete Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

private struct ActiveWorkoutExerciseSettingsDraft: Identifiable, Equatable {
    let exerciseID: UUID
    var exerciseName: String
    var minRepsText: String
    var maxRepsText: String
    var restSeconds: Int

    var id: UUID { exerciseID }
}

private struct ActiveWorkoutExerciseSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ActiveWorkoutExerciseSettingsDraft

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]
    private let onSave: (ActiveWorkoutExerciseSettingsDraft) -> Void

    init(
        draft: ActiveWorkoutExerciseSettingsDraft,
        onSave: @escaping (ActiveWorkoutExerciseSettingsDraft) -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WGJSectionHeader("Exercise Settings", subtitle: draft.exerciseName)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rep Range")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        HStack(spacing: 10) {
                            TextField("Min", text: $draft.minRepsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .wgjPillField()

                            Text("to")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WGJTheme.accentGold)

                            TextField("Max", text: $draft.maxRepsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .wgjPillField()
                        }
                    }
                    .padding(14)
                    .wgjCardContainer()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default Rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        Menu {
                            ForEach(restPresets, id: \.self) { value in
                                Button(formattedRest(value)) {
                                    draft.restSeconds = value
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Label(formattedRest(draft.restSeconds), systemImage: "timer")
                                    .monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(WGJTheme.field)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(WGJTheme.accentBlue.opacity(0.24), lineWidth: 1)
                                    )
                            )
                        }

                        HStack(spacing: 8) {
                            restAdjustButton(symbol: "minus.circle") {
                                draft.restSeconds = max(0, draft.restSeconds - 15)
                            }

                            restAdjustButton(symbol: "plus.circle.fill") {
                                draft.restSeconds = min(3600, draft.restSeconds + 15)
                            }

                            Spacer(minLength: 8)
                        }
                    }
                    .padding(14)
                    .wgjCardContainer()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Exercise Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .wgjMinimalKeyboardToolbar()
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func restAdjustButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(WGJTheme.textSecondary)
    }
}

#Preview {
    NavigationStack {
        ActiveWorkoutView(sessionID: UUID())
    }
    .environment(ActiveWorkoutCoordinator())
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
