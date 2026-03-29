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
    @State private var overloadFeedbackByExerciseID: [UUID: ActiveWorkoutProgressiveOverloadPresentation] = [:]
    @State private var loadedExerciseStateStamp: ActiveWorkoutExerciseStateStamp?
    @State private var catalogByUUID: [String: ExerciseCatalogItem] = [:]
    @State private var cardStateController = ActiveWorkoutExerciseCardStateController()

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var showingExercisePicker = false
    @State private var showingFinishConfirmation = false
    @State private var isCancelArmed = false
    @State private var isEndingSession = false
    @State private var showingSaveTemplateSheet = false
    @State private var pendingCompletionAfterSaveTemplateSheet = false
    @State private var pendingCompletionTask: Task<Void, Never>?
    @State private var exerciseSettingsDraft: ActiveWorkoutExerciseSettingsDraft?
    @State private var pendingTemplateUpdatePreview: WorkoutTemplateSyncPreview?
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?
    @State private var isKeyboardVisible = false

    @State private var errorMessage = ""
    @State private var showingError = false

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
            .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: exerciseListAnimationToken)
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
            if !isKeyboardVisible, !isEndingSession, let session, session.status == .active {
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
        .sheet(isPresented: $showingSaveTemplateSheet, onDismiss: handleSaveTemplateSheetDismissed) {
            ActiveWorkoutSaveTemplateSheet(
                templateNameDraft: $templateNameDraft,
                templateFolderID: $templateFolderID,
                folders: folders,
                onSkip: skipSavingSessionAsTemplate,
                onSave: saveSessionAsTemplate
            )
            .interactiveDismissDisabled()
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: session?.statusRaw) {
            await reconcileSessionLifecycleIfNeeded()
        }
        .task(id: exerciseHydrationStamp) {
            await loadExerciseStateIfNeeded()
        }
        .task(id: isTrainingGuidanceEnabled) {
            await refreshOverloadFeedback()
        }
        .onDisappear {
            isCancelArmed = false
            pendingCompletionTask?.cancel()
            pendingCompletionTask = nil
            flushPendingSaves()
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
        .background {
            WorkoutRestTimerExpiryObserver()
        }
        .wgjMinimalKeyboardToolbar()
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var exerciseHydrationStamp: ActiveWorkoutExerciseStateStamp {
        ActiveWorkoutExerciseStateStamp(exercises: sessionExercises)
    }

    private var exerciseListAnimationToken: ActiveWorkoutListAnimationToken {
        ActiveWorkoutListAnimationToken(exercises: sessionExercises)
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
        .disabled(isEndingSession || session == nil || sessionExercises.isEmpty || session?.status != .active)
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
            return makeDrafts(from: exercise)
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
        isEndingSession = session.status != .active
        sessionNameDraft = session.name
        notesDraft = session.notes
        if session.templateID == nil {
            templateNameDraft = session.name == "Empty Workout" ? "New Template" : session.name
        }
        handleTerminalSessionStateIfNeeded(session)
    }

    @MainActor
    private func loadExerciseStateIfNeeded() async {
        let currentStamp = exerciseHydrationStamp
        guard currentStamp != loadedExerciseStateStamp else { return }

        let result = WGJPerformance.measure("active-workout.hydrate") { () -> ActiveWorkoutHydrationResult in
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
                let drafts = makeDrafts(from: exercise)
                loadedDrafts[exercise.id] = drafts
                loadedRests[exercise.id] = exercise.restSeconds
                let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
                loadedPrevious[exercise.id] = resolvedPreviousMap(baseMap: base, maxSetCount: drafts.count)
            }

            return ActiveWorkoutHydrationResult(
                draftsByExerciseID: loadedDrafts,
                restsByExerciseID: loadedRests,
                previousByExerciseID: loadedPrevious,
                catalogByUUID: loadedCatalog
            )
        }

        setDraftsByExerciseID = result.draftsByExerciseID
        lastPersistedDraftsByExerciseID = result.draftsByExerciseID
        restByExerciseID = result.restsByExerciseID
        lastPersistedRestByExerciseID = result.restsByExerciseID
        previousByExerciseID = result.previousByExerciseID
        catalogByUUID = result.catalogByUUID
        overloadFeedbackByExerciseID = buildOverloadFeedbacks(
            exercises: sessionExercises,
            draftsByExerciseID: result.draftsByExerciseID,
            catalogByUUID: result.catalogByUUID
        )
        let completedExerciseIDs = Set(
            result.draftsByExerciseID.compactMap { exerciseID, drafts in
                isExerciseCompleted(drafts) ? exerciseID : nil
            }
        )
        cardStateController.sync(
            exerciseIDs: sessionExercises.map(\.id),
            completedExerciseIDs: completedExerciseIDs,
            firstIncompleteExerciseID: firstIncompleteExerciseID(
                from: sessionExercises,
                draftsByExerciseID: result.draftsByExerciseID
            )
        )
        loadedExerciseStateStamp = currentStamp
    }

    @MainActor
    private func reconcileSessionLifecycleIfNeeded() async {
        guard hasBootstrapped else { return }

        guard let latestSession = try? sessionRepository.session(id: sessionID) else {
            coordinator.clearActiveWorkout()
            dismiss()
            return
        }

        guard latestSession.status != .active else {
            isEndingSession = false
            return
        }

        handleTerminalSessionStateIfNeeded(latestSession)
    }

    @MainActor
    private func handleTerminalSessionStateIfNeeded(_ latestSession: WorkoutSession) {
        guard latestSession.status != .active else { return }

        dismissKeyboard()
        showingFinishConfirmation = false
        isCancelArmed = false
        isEndingSession = true
        coordinator.clearRestTimer()

        guard !pendingCompletionAfterSaveTemplateSheet else { return }
        guard !showingSaveTemplateSheet, pendingTemplateUpdatePreview == nil else { return }

        guard latestSession.status == .completed else {
            coordinator.clearActiveWorkout()
            dismiss()
            return
        }

        if latestSession.templateID == nil {
            if templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                templateNameDraft = latestSession.name == "Empty Workout" ? "New Template" : latestSession.name
            }
            showingSaveTemplateSheet = true
            return
        }

        do {
            if let preview = try templateSyncService.previewTemplateUpdate(forSessionID: sessionID) {
                pendingTemplateUpdatePreview = preview
            } else {
                finalizeCompletion()
            }
        } catch {
            showError(error)
        }
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
            overloadFeedback: overloadFeedbackByExerciseID[exercise.id],
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
                syncOverloadFeedback(for: exercise, drafts: drafts)
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
                let previousDefaultRest = lastPersistedRestByExerciseID[sessionExerciseID] ?? normalized
                try sessionRepository.updateExerciseRest(sessionExerciseID: sessionExerciseID, restSeconds: latest)
                lastPersistedRestByExerciseID[sessionExerciseID] = latest
                applyPersistedRestChange(
                    sessionExerciseID: sessionExerciseID,
                    previousDefaultRest: previousDefaultRest,
                    updatedRest: latest
                )
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
                let previousDefaultRest = lastPersistedRestByExerciseID[exerciseID] ?? rest
                try sessionRepository.updateExerciseRest(sessionExerciseID: exerciseID, restSeconds: rest)
                lastPersistedRestByExerciseID[exerciseID] = rest
                applyPersistedRestChange(
                    sessionExerciseID: exerciseID,
                    previousDefaultRest: previousDefaultRest,
                    updatedRest: rest
                )
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
        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? []).map(\.id))

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                setDraftsByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedDraftsByExerciseID.removeValue(forKey: exerciseID)
                restByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedRestByExerciseID.removeValue(forKey: exerciseID)
                previousByExerciseID.removeValue(forKey: exerciseID)
                overloadFeedbackByExerciseID.removeValue(forKey: exerciseID)
                loadedExerciseStateStamp = nil
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

    @MainActor
    private func refreshOverloadFeedback() async {
        overloadFeedbackByExerciseID = buildOverloadFeedbacks(
            exercises: sessionExercises,
            draftsByExerciseID: setDraftsByExerciseID,
            catalogByUUID: catalogByUUID
        )
    }

    @MainActor
    private func buildOverloadFeedbacks(
        exercises: [WorkoutSessionExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        catalogByUUID: [String: ExerciseCatalogItem]
    ) -> [UUID: ActiveWorkoutProgressiveOverloadPresentation] {
        guard isTrainingGuidanceEnabled else { return [:] }

        var feedbackByExerciseID: [UUID: ActiveWorkoutProgressiveOverloadPresentation] = [:]
        feedbackByExerciseID.reserveCapacity(exercises.count)

        for exercise in exercises {
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            guard
                let catalogExercise = catalogByUUID[exercise.catalogExerciseUUID],
                let feedback = makeOverloadFeedback(
                    for: exercise,
                    drafts: drafts,
                    catalogExercise: catalogExercise
                )
            else {
                continue
            }

            feedbackByExerciseID[exercise.id] = feedback
        }

        return feedbackByExerciseID
    }

    @MainActor
    private func syncOverloadFeedback(
        for exercise: WorkoutSessionExercise,
        drafts: [WorkoutSessionSetDraft]
    ) {
        guard
            isTrainingGuidanceEnabled,
            let catalogExercise = catalogByUUID[exercise.catalogExerciseUUID],
            let feedback = makeOverloadFeedback(
                for: exercise,
                drafts: drafts,
                catalogExercise: catalogExercise
            )
        else {
            overloadFeedbackByExerciseID.removeValue(forKey: exercise.id)
            return
        }

        overloadFeedbackByExerciseID[exercise.id] = feedback
    }

    private func expansionBinding(for exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { cardStateController.isExpanded(for: exerciseID) },
            set: { cardStateController.setExpanded($0, for: exerciseID) }
        )
    }

    private func makeOverloadFeedback(
        for exercise: WorkoutSessionExercise,
        drafts: [WorkoutSessionSetDraft],
        catalogExercise: ExerciseCatalogItem
    ) -> ActiveWorkoutProgressiveOverloadPresentation? {
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
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
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
            let previousDefaultRest = lastPersistedRestByExerciseID[draft.exerciseID] ?? draft.restSeconds
            try sessionRepository.updateExerciseRest(
                sessionExerciseID: draft.exerciseID,
                restSeconds: draft.restSeconds
            )
            restByExerciseID[draft.exerciseID] = draft.restSeconds
            lastPersistedRestByExerciseID[draft.exerciseID] = draft.restSeconds
            applyPersistedRestChange(
                sessionExerciseID: draft.exerciseID,
                previousDefaultRest: previousDefaultRest,
                updatedRest: draft.restSeconds
            )
            if let exercise = sessionExercises.first(where: { $0.id == draft.exerciseID }) {
                syncOverloadFeedback(
                    for: exercise,
                    drafts: setDraftsByExerciseID[draft.exerciseID] ?? makeDrafts(from: exercise)
                )
            }
            exerciseSettingsDraft = nil
        } catch {
            showError(error)
        }
    }

    private func finishWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        guard !isEndingSession else { return }
        if let session, session.status != .active {
            handleTerminalSessionStateIfNeeded(session)
            return
        }
        isEndingSession = true
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.finishSession(sessionID: sessionID, notes: notesDraft)
            if let latestSession = try sessionRepository.session(id: sessionID) {
                handleTerminalSessionStateIfNeeded(latestSession)
            } else {
                finalizeCompletion()
            }
        } catch {
            isEndingSession = false
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
            requestCompletionAfterSaveTemplateSheetDismissal()
        } catch {
            showError(error)
        }
    }

    private func skipSavingSessionAsTemplate() {
        dismissKeyboard()
        requestCompletionAfterSaveTemplateSheetDismissal()
    }

    private func handleSaveTemplateSheetDismissed() {
        guard pendingCompletionAfterSaveTemplateSheet else { return }
        pendingCompletionTask?.cancel()
        pendingCompletionTask = nil
        finalizeCompletion()
    }

    private func requestCompletionAfterSaveTemplateSheetDismissal() {
        pendingCompletionAfterSaveTemplateSheet = true
        showingSaveTemplateSheet = false
        pendingCompletionTask?.cancel()
        pendingCompletionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, pendingCompletionAfterSaveTemplateSheet, !showingSaveTemplateSheet else { return }
            finalizeCompletion()
        }
    }

    private func finalizeCompletion() {
        pendingCompletionTask?.cancel()
        pendingCompletionTask = nil
        dismissKeyboard()
        isCancelArmed = false
        showingSaveTemplateSheet = false
        pendingCompletionAfterSaveTemplateSheet = false
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
        guard !isEndingSession else { return }
        if let session, session.status != .active {
            handleTerminalSessionStateIfNeeded(session)
            return
        }
        isEndingSession = true
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.cancelSession(sessionID: sessionID)
            coordinator.clearActiveWorkout()
            dismiss()
        } catch WorkoutSessionRepositoryError.invalidSessionState {
            if let latestSession = try? sessionRepository.session(id: sessionID) {
                handleTerminalSessionStateIfNeeded(latestSession)
            } else {
                coordinator.clearActiveWorkout()
                dismiss()
            }
        } catch {
            isEndingSession = false
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        if let repositoryError = error as? WorkoutSessionRepositoryError {
            switch repositoryError {
            case .invalidSessionState:
                if let latestSession = try? sessionRepository.session(id: sessionID) {
                    handleTerminalSessionStateIfNeeded(latestSession)
                } else {
                    coordinator.clearActiveWorkout()
                    dismiss()
                }
                return
            case .sessionNotFound:
                coordinator.clearActiveWorkout()
                dismiss()
                return
            default:
                break
            }
        }

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
        guard !isEndingSession else { return }
        isCancelArmed = false
        showingFinishConfirmation = true
    }

    private func confirmFinishWorkout() {
        showingFinishConfirmation = false
        finishWorkout()
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
    private func applyPersistedRestChange(
        sessionExerciseID: UUID,
        previousDefaultRest: Int,
        updatedRest: Int
    ) {
        guard var drafts = setDraftsByExerciseID[sessionExerciseID] else { return }

        var changed = false
        for index in drafts.indices where !drafts[index].isLocked && drafts[index].restSeconds == previousDefaultRest {
            drafts[index].restSeconds = updatedRest
            changed = true
        }

        guard changed else { return }
        setDraftsByExerciseID[sessionExerciseID] = drafts
        lastPersistedDraftsByExerciseID[sessionExerciseID] = drafts
        cardStateController.updateCompletion(
            for: sessionExerciseID,
            isCompleted: isExerciseCompleted(drafts)
        )
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
                                .wgjRoundedGlass(
                                    cornerRadius: 12,
                                    tint: WGJTheme.danger.opacity(0.12),
                                    interactive: true
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .wgjGlassContainer(spacing: 8)
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
                .wgjRoundedGlass(cornerRadius: 14, tint: WGJTheme.danger.opacity(0.14))
        )
    }
}

struct WorkoutRestTimerExpiryObserver: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onReceive(timer) { date in
                coordinator.handleRestTimerExpirationIfNeeded(at: date)
            }
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
                    .wgjRoundedGlass(cornerRadius: 18, tint: accent.opacity(isResting ? 0.16 : 0.12))
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

private struct ActiveWorkoutHydrationResult {
    let draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    let restsByExerciseID: [UUID: Int]
    let previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]]
    let catalogByUUID: [String: ExerciseCatalogItem]
}

private struct ActiveWorkoutExerciseStateStamp: Hashable {
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

private struct ActiveWorkoutListAnimationToken: Hashable {
    let count: Int
    let latestUpdate: TimeInterval

    init(exercises: [WorkoutSessionExercise]) {
        count = exercises.count
        latestUpdate = exercises
            .map { exercise in
                max(
                    exercise.updatedAt.timeIntervalSinceReferenceDate,
                    (exercise.sets ?? []).map { $0.updatedAt.timeIntervalSinceReferenceDate }.max() ?? 0
                )
            }
            .max() ?? 0
    }
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
