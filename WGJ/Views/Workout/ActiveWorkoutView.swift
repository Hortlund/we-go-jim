import Combine
import Foundation
import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID
    @Query private var sessions: [ActiveWorkoutDraftSession]
    @Query private var sessionCardioBlocks: [ActiveWorkoutDraftCardioBlock]
    @Query private var sessionExercises: [ActiveWorkoutDraftExercise]
    @Query private var profiles: [UserProfile]

    @State private var hasBootstrapped = false
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var notesByExerciseID: [UUID: String] = [:]
    @State private var lastPersistedExerciseStateByID: [UUID: ActiveWorkoutExercisePersistenceSnapshot] = [:]
    @State private var pendingExercisePersistenceTasks: [UUID: Task<Void, Never>] = [:]

    @State private var previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution] = [:]
    @State private var componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
    @State private var catalogMatchesByUUID: [String: ExerciseCatalogItem] = [:]
    @State private var loadedExerciseStateStamp: ActiveWorkoutExerciseStateStamp?
    @State private var deferredHydrationTask: Task<Void, Never>?
    @State private var cardStateController = ActiveWorkoutExerciseCardStateController()

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var pendingSessionNotesSaveTask: Task<Void, Never>?
    @State private var pickerTarget: ActiveWorkoutPickerTarget?
    @State private var showingFinishConfirmation = false
    @State private var pendingFinishAfterConfirmation = false
    @State private var isCancelArmed = false
    @State private var isEndingSession = false
    @State private var completedSessionID: UUID?
    @State private var showingSaveTemplateSheet = false
    @State private var pendingCompletionAfterSaveTemplateSheet = false
    @State private var pendingCompletionTask: Task<Void, Never>?
    @State private var exerciseSettingsDraft: ActiveWorkoutExerciseSettingsDraft?
    @State private var exerciseComponentPickerDraft: ActiveWorkoutExerciseComponentPickerDraft?
    @State private var cardioSettingsDraft: WorkoutCardioSettingsDraft?
    @State private var exerciseReorderRequest: ExerciseReorderRequest?
    @State private var pendingTemplateUpdatePreview: WorkoutTemplateSyncPreview?
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?
    @State private var saveTemplateFolders: [TemplateFolder] = []
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg
    @State private var isKeyboardVisible = false
    @State private var shouldTrackVisibleScrollTarget = false

    @State private var errorMessage = ""
    @State private var showingError = false

    private let interactivePersistenceDebounce = Duration.seconds(1)
    private let cancelSectionFocusSpacerHeight: CGFloat = 160
    private let cancelSectionDockClearanceHeight: CGFloat = 96
    private let cancelSectionScrollTarget = ActiveWorkoutScrollTarget.cancelSection
    private let guidanceService = TrainingGuidanceService()

    private var activeWorkoutRepository: ActiveWorkoutDraftRepository {
        ActiveWorkoutDraftRepository(modelContext: modelContext)
    }

    private var currentProfile: UserProfile? {
        UserProfileSelection.currentProfile(in: profiles)
    }

    private var completedSessionRepository: WorkoutSessionRepository {
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

    private var componentRotationResolver: TemplateExerciseComponentRotationResolver {
        TemplateExerciseComponentRotationResolver(modelContext: modelContext)
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
            sort: [SortDescriptor(\ActiveWorkoutDraftExercise.sortOrder, order: .forward)]
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                // Exercise cards change height aggressively as sets complete, and a non-lazy
                // stack keeps the scroll position stable when a completed card collapses.
                VStack(alignment: .leading, spacing: 16) {
                    if let session {
                        ActiveWorkoutHeaderCard(
                            sessionNameDraft: $sessionNameDraft,
                            notesDraft: $notesDraft,
                            session: session,
                            exerciseCount: sessionExercises.count,
                            cardioCount: orderedCardioBlocks.count,
                            missingCardioPhases: missingCardioPhases,
                            onSubmit: persistSessionMeta,
                            onAddCardio: showCardioPicker
                        )
                        .id(ActiveWorkoutScrollTarget.header)
                        if preWorkoutCardio != nil {
                            cardioSection(for: .preWorkout, scrollProxy: scrollProxy)
                        }
                        exercisesSectionHeader
                    } else if isEndingSession || completedSessionID != nil {
                        WGJEmptyStateCard(
                            title: "Wrapping up workout",
                            message: "Saving the session and preparing the next step.",
                            icon: "checkmark.circle"
                        )
                    } else {
                        WGJEmptyStateCard(
                            title: "Workout session not found",
                            message: "This active workout could not be loaded.",
                            icon: "exclamationmark.triangle"
                        )
                    }

                    if session != nil && sessionExercises.isEmpty {
                        WGJEmptyStateCard(
                            title: "No exercises added",
                            message: orderedCardioBlocks.isEmpty
                                ? "Add exercises to start logging sets in this workout."
                                : "Add exercises to keep building the main section of this workout.",
                            icon: "list.bullet.rectangle"
                        ) {
                            Button("Add Exercise") {
                                pickerTarget = .exercise
                            }
                            .buttonStyle(WGJPrimaryButtonStyle())
                            .accessibilityIdentifier("active-workout-empty-add-exercise-button")
                        }
                    }

                    ForEach(Array(sessionExercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseRow(
                            for: exercise,
                            index: index,
                            scrollProxy: scrollProxy
                        )
                    }

                    if session != nil && !sessionExercises.isEmpty {
                        addExerciseButton(title: "Add another exercise")
                            .disabled(session == nil)
                    }

                    if postWorkoutCardio != nil {
                        cardioSection(for: .postWorkout, scrollProxy: scrollProxy)
                    }

                    if session != nil && !isEndingSession {
                        ActiveWorkoutCancelSection(
                            isCancelArmed: isCancelArmed,
                            onCancelConfirmationPresented: {
                                focusCancelSection(using: scrollProxy)
                            },
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
                        .id(cancelSectionScrollTarget)

                        Color.clear
                            .frame(height: cancelSectionBottomSpacerHeight)
                            .accessibilityHidden(true)
                    }
                }
                .scrollTargetLayout()
                .padding(16)
            }
            .scrollPosition(id: scrollPositionBinding, anchor: .top)
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
                Group {
                    if shouldShowBottomDock, let session {
                        ActiveWorkoutBottomDock(
                            session: session,
                            reduceMotion: reduceMotion
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: isKeyboardVisible)
                .animation(
                    WGJMotion.overlayAnimation(reduceMotion: reduceMotion),
                    value: restTimerState.restTimerPopup?.id
                )
            }
            .wgjTrackKeyboardVisibility($isKeyboardVisible)
            .sheet(item: $pickerTarget, onDismiss: {
                dismissKeyboard()
                isKeyboardVisible = false
            }) { target in
                ExercisePickerView(repository: catalogRepository) { exercise in
                    handlePickedExercise(exercise, target: target)
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
            .sheet(item: $exerciseComponentPickerDraft) { draft in
                ActiveWorkoutExerciseComponentPickerSheet(draft: draft) { componentID in
                    saveExerciseComponentSelection(
                        exerciseID: draft.exerciseID,
                        componentID: componentID
                    )
                }
                .wgjSheetSurface()
            }
            .sheet(item: $cardioSettingsDraft) { draft in
                WorkoutCardioSettingsSheet(draft: draft) { updatedDurationSeconds in
                    saveCardioDuration(
                        phase: draft.phase,
                        targetDurationSeconds: updatedDurationSeconds
                    )
                }
                .wgjSheetSurface()
            }
            .sheet(item: $exerciseReorderRequest) { request in
                ExerciseReorderSheet(
                    request: request,
                    items: exerciseReorderItems,
                    contextName: "workout",
                    accessibilityIDPrefix: "active-workout-reorder"
                ) { position in
                    moveExercise(exerciseID: request.exerciseID, toPosition: position)
                }
            }
            .sheet(isPresented: $showingSaveTemplateSheet, onDismiss: handleSaveTemplateSheetDismissed) {
                ActiveWorkoutSaveTemplateSheet(
                    templateNameDraft: $templateNameDraft,
                    templateFolderID: $templateFolderID,
                    folders: saveTemplateFolders,
                    onSkip: skipSavingSessionAsTemplate,
                    onSave: saveSessionAsTemplate
                )
                .interactiveDismissDisabled()
            }
            .sheet(item: $pendingTemplateUpdatePreview) { preview in
                ActiveWorkoutTemplateSyncReviewSheet(
                    preview: preview,
                    onKeepTemplate: {
                        pendingTemplateUpdatePreview = nil
                        presentWorkoutCompletionSummary()
                    },
                    onUpdateTemplate: {
                        applyTemplateUpdate(preview)
                    }
                )
                .interactiveDismissDisabled()
            }
            .task {
                await bootstrapIfNeeded()
            }
            .task(id: session?.id) {
                await reconcileSessionLifecycleIfNeeded()
            }
            .task(id: exerciseHydrationStamp) {
                await loadExerciseStateIfNeeded(using: scrollProxy)
            }
            .onChange(of: isKeyboardVisible) { _, isVisible in
                guard isCancelArmed, !isVisible else { return }
                focusCancelSection(using: scrollProxy)
            }
            .onChange(of: notesDraft) { _, _ in
                scheduleSessionNotesPersistence()
            }
            .onChange(of: showingFinishConfirmation) { oldValue, newValue in
                handleFinishConfirmationChange(from: oldValue, to: newValue)
            }
            .onDisappear {
                shouldTrackVisibleScrollTarget = false
                isCancelArmed = false
                pendingFinishAfterConfirmation = false
                pendingCompletionTask?.cancel()
                pendingCompletionTask = nil
                deferredHydrationTask?.cancel()
                deferredHydrationTask = nil
                flushPendingSaves()
            }
            .alert("Workout Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .background {
                WorkoutRestTimerExpiryObserver()
            }
            .wgjMinimalKeyboardToolbar()
        }
    }

    private var scrollPositionBinding: Binding<ActiveWorkoutScrollTarget?> {
        Binding(
            get: { activeWorkoutPresentationState.scrollTarget },
            set: { newValue in
                guard shouldTrackVisibleScrollTarget || newValue == activeWorkoutPresentationState.scrollTarget else {
                    return
                }
                activeWorkoutPresentationState.scrollTarget = newValue
            }
        )
    }

    private var session: ActiveWorkoutDraftSession? {
        sessions.first
    }

    @MainActor
    private var orderedCardioBlocks: [ActiveWorkoutDraftCardioBlock] {
        sessionCardioBlocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    @MainActor
    private var preWorkoutCardio: ActiveWorkoutDraftCardioBlock? {
        orderedCardioBlocks.first(where: { $0.phase == .preWorkout })
    }

    @MainActor
    private var postWorkoutCardio: ActiveWorkoutDraftCardioBlock? {
        orderedCardioBlocks.first(where: { $0.phase == .postWorkout })
    }

    @MainActor
    private var hasWorkoutContent: Bool {
        !sessionExercises.isEmpty || !orderedCardioBlocks.isEmpty
    }

    @MainActor
    private var missingCardioPhases: [WorkoutCardioPhase] {
        WorkoutCardioPhase.allCases.filter { cardioBlock(for: $0) == nil }
    }

    private var shouldShowBottomDock: Bool {
        guard !isKeyboardVisible, !isEndingSession, session != nil else {
            return false
        }

        return true
    }

    private var cancelSectionBottomSpacerHeight: CGFloat {
        if isCancelArmed {
            return cancelSectionFocusSpacerHeight
        }

        return shouldShowBottomDock ? cancelSectionDockClearanceHeight : 24
    }

    private var exerciseHydrationStamp: ActiveWorkoutExerciseStateStamp {
        ActiveWorkoutExerciseStateStamp(exercises: sessionExercises)
    }

    private var exercisesSectionHeader: some View {
        Group {
            if sessionExercises.isEmpty {
                WGJActionHeader(
                    "Exercises",
                    subtitle: areMainExercisesUnlocked
                        ? "Add exercises and log each set inline."
                        : "Complete the pre-workout cardio block to unlock set logging."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: areMainExercisesUnlocked
                        ? "Swipe the exercise header to delete an exercise, or use exercise actions to move it anywhere in the workout."
                        : "Main exercises stay visible, but set logging unlocks after the pre-workout cardio block."
                ) {
                    Button {
                        pickerTarget = .exercise
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
        let finishConfirmationContent = makeFinishConfirmationContent()

        return Button("Finish") {
            presentFinishConfirmation()
        }
        .disabled(isEndingSession || session == nil || !hasWorkoutContent)
        .accessibilityIdentifier("active-workout-finish-button")
        .popover(isPresented: $showingFinishConfirmation, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            ActiveWorkoutFinishPopover(
                content: finishConfirmationContent,
                onFinish: confirmFinishWorkout,
                onCancel: { showingFinishConfirmation = false }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
    }

    private func addExerciseButton(title: String) -> some View {
        Button {
            pickerTarget = .exercise
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
        .accessibilityIdentifier("active-workout-add-exercise-button")
    }

    @MainActor
    @ViewBuilder
    private func cardioSection(
        for phase: WorkoutCardioPhase,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        if let cardioBlock = cardioBlock(for: phase) {
            ActiveWorkoutCardioPhaseCard(
                phase: phase,
                exerciseName: cardioBlock.exerciseNameSnapshot,
                descriptor: cardioDescriptor(
                    category: cardioBlock.categorySnapshot,
                    muscleSummary: cardioBlock.muscleSummarySnapshot
                ),
                targetDurationSeconds: cardioBlock.targetDurationSeconds,
                statusText: cardioStatusText(for: cardioBlock),
                statusTint: cardioStatusTint(for: cardioBlock),
                footnote: cardioFootnote(for: cardioBlock),
                isCompleted: cardioBlock.isCompleted,
                canComplete: canToggleCompletion(for: cardioBlock),
                completionTitle: "Complete \(cardioBlock.phase.shortTitle)",
                completionAccessibilityLabel: cardioCompletionAccessibilityLabel(for: cardioBlock),
                undoAccessibilityLabel: cardioCompletionAccessibilityLabel(for: cardioBlock),
                completionAccessibilityIdentifier: "active-workout-\(cardioBlock.phase.rawValue)-toggle-button",
                accessibilityIdentifier: "active-workout-\(phase.rawValue)-card",
                onToggleCompletion: {
                    toggleCardioCompletion(for: cardioBlock, scrollProxy: scrollProxy)
                }
            ) {
                cardioSectionActionsButton(for: cardioBlock)
            }
            .id(cardioScrollTarget(for: phase))
        }
    }

    @MainActor
    private func cardioSectionActionsButton(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> some View {
        let accessibilityIdentifier = "active-workout-\(cardioBlock.phase.rawValue)-actions-button"

        return Menu {
            Button("Edit Duration") {
                cardioSettingsDraft = makeCardioSettingsDraft(from: cardioBlock)
            }

            Button("Change Exercise") {
                showCardioPicker(for: cardioBlock.phase)
            }

            Button("Remove", role: .destructive) {
                removeCardioBlock(phase: cardioBlock.phase)
            }
        } label: {
            ActiveWorkoutCardioHeaderActionIcon(tint: cardioHeaderTint(for: cardioBlock))
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Cardio Actions")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func cardioHeaderTint(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> Color {
        if cardioBlock.isCompleted {
            return WGJTheme.success
        }

        switch cardioBlock.phase {
        case .preWorkout:
            return WGJTheme.accentBlue
        case .postWorkout:
            return WGJTheme.accentGold
        }
    }

    private func cardioCompletionAccessibilityLabel(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> String {
        if cardioBlock.isCompleted {
            return "Mark \(cardioBlock.phase.shortTitle) Incomplete"
        }

        return "Complete \(cardioBlock.phase.shortTitle)"
    }

    @MainActor
    private func exerciseRow(
        for exercise: ActiveWorkoutDraftExercise,
        index: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let exerciseID = exercise.id
        let exerciseName = exercise.exerciseNameSnapshot
        let drafts = resolvedDrafts(for: exercise)
        let guidance = WGJPerformance.measure("active-workout.guidance") {
            guidancePresentation(for: exercise, drafts: drafts)
        }

        return WorkoutExerciseRowHostView(
            exerciseID: exerciseID,
            exerciseAccessibilityIdentifier: "active-workout-exercise-\(exercise.catalogExerciseUUID)",
            exerciseName: exerciseName,
            muscleSummary: exercise.muscleSummarySnapshot,
            category: exercise.categorySnapshot,
            exerciseIndexTitle: "Exercise \(index + 1)",
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            previousPerformanceResolution: previousResolutionByExerciseID[exerciseID] ?? .loading,
            guidance: guidance,
            preferredLoadUnit: preferredLoadUnit,
            supplementaryContent: componentResolutionByExerciseID[exerciseID].map { resolution in
                AnyView(
                    ActiveWorkoutExerciseComponentSummaryView(
                        resolution: resolution,
                        showsSuggestedComponent: false
                    )
                )
            },
            supplementaryContentKey: componentResolutionByExerciseID[exerciseID].map { resolution in
                "\(resolution.selectedComponent.catalogExerciseUUID)-\(resolution.availableComponents.count)"
            },
            exerciseNotes: resolvedNotes(for: exercise),
            restSeconds: resolvedRest(for: exercise),
            setDrafts: drafts,
            isExpanded: cardStateController.isExpanded(for: exerciseID),
            manualCompletionMode: true,
            isBozarModeEnabled: currentProfile?.isBozarModeEnabled ?? false,
            isSetEditingEnabled: areMainExercisesUnlocked,
            canMoveExerciseUp: index > 0,
            canMoveExerciseDown: index < sessionExercises.count - 1,
            onExerciseNotesCommitted: { notes in
                updateNotesValue(notes, for: exerciseID)
                scheduleExercisePersistence(sessionExerciseID: exerciseID)
            },
            onSetDraftsCommitted: { drafts in
                handleDraftsChanged(drafts, for: exercise, scrollProxy: scrollProxy)
            },
            onRestCommitted: { rest in
                updateRestValue(rest, for: exerciseID)
                scheduleExercisePersistence(sessionExerciseID: exerciseID)
            },
            onExpandedChanged: { isExpanded in
                cardStateController.setExpanded(isExpanded, for: exerciseID)
            },
            onSetCompletionChange: { setID, setLabel, restSeconds, isCompleted in
                if isCompleted {
                    WorkoutFeedbackCenter.shared.setCompleted()
                    restTimerState.startRestTimer(
                        seconds: restSeconds,
                        exerciseName: exerciseName,
                        setLabel: setLabel,
                        sourceSetID: setID
                    )
                } else {
                    restTimerState.clearRestTimer(sourceSetID: setID)
                }
            },
            onExerciseSettings: {
                showExerciseSettings(for: exercise)
            },
            onExerciseComponentPicker: componentResolutionByExerciseID[exerciseID]?.availableComponents.count ?? 0 > 1
                ? { showExerciseComponentPicker(for: exercise) }
                : nil,
            onExerciseMoveUp: {
                moveExerciseUp(index)
            },
            onExerciseMoveDown: {
                moveExerciseDown(index)
            },
            onExerciseMoveToPosition: sessionExercises.count > 1 ? {
                presentExerciseReorder(for: exercise)
            } : nil,
            onExerciseDelete: {
                removeExercise(exerciseID: exerciseID)
            }
        )
        .equatable()
        .id(ActiveWorkoutScrollTarget.exercise(exerciseID))
        .transition(exerciseCardTransition)
    }

    @MainActor
    private func resolvedDrafts(for exercise: ActiveWorkoutDraftExercise) -> [WorkoutSessionSetDraft] {
        if let cached = setDraftsByExerciseID[exercise.id] {
            return cached
        }
        return makeDrafts(from: exercise)
    }

    @MainActor
    private func resolvedRest(for exercise: ActiveWorkoutDraftExercise) -> Int {
        restByExerciseID[exercise.id] ?? exercise.restSeconds
    }

    @MainActor
    private func resolvedNotes(for exercise: ActiveWorkoutDraftExercise) -> String {
        notesByExerciseID[exercise.id] ?? exercise.notes
    }

    @MainActor
    private func currentPersistenceSnapshot(for exercise: ActiveWorkoutDraftExercise) -> ActiveWorkoutExercisePersistenceSnapshot {
        ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: resolvedDrafts(for: exercise),
            restSeconds: resolvedRest(for: exercise),
            notes: resolvedNotes(for: exercise)
        )
    }

    @MainActor
    private func currentPersistenceSnapshot(for exerciseID: UUID) -> ActiveWorkoutExercisePersistenceSnapshot? {
        guard let exercise = sessionExercises.first(where: { $0.id == exerciseID }) else {
            return nil
        }
        return currentPersistenceSnapshot(for: exercise)
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
    private var areMainExercisesUnlocked: Bool {
        preWorkoutCardio?.isCompleted ?? true
    }

    @MainActor
    private var areAllMainExercisesCompleted: Bool {
        guard !sessionExercises.isEmpty else {
            return true
        }

        return sessionExercises.allSatisfy { exercise in
            isExerciseCompleted(resolvedDrafts(for: exercise))
        }
    }

    @MainActor
    private var isPostWorkoutCardioUnlocked: Bool {
        areMainExercisesUnlocked && areAllMainExercisesCompleted
    }

    @MainActor
    private func cardioBlock(for phase: WorkoutCardioPhase) -> ActiveWorkoutDraftCardioBlock? {
        orderedCardioBlocks.first(where: { $0.phase == phase })
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        activeWorkoutPresentationState.present(sessionID: sessionID)

        guard let session else { return }
        sessionNameDraft = session.name
        notesDraft = session.notes
        if let profile = try? ProfileRepository(modelContext: modelContext).currentProfile() {
            preferredLoadUnit = profile.preferredLoadUnit
        }
        if session.templateID == nil {
            templateNameDraft = session.name == "Empty Workout" ? "New Template" : session.name
        }
    }

    @MainActor
    private func loadExerciseStateIfNeeded(using scrollProxy: ScrollViewProxy) async {
        shouldTrackVisibleScrollTarget = false
        discardRemovedExerciseState(keeping: Set(sessionExercises.map(\.id)))
        let currentStamp = exerciseHydrationStamp
        guard currentStamp != loadedExerciseStateStamp else { return }
        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil

        let result = WGJPerformance.measure("active-workout.hydrate.local") { () -> ActiveWorkoutHydrationResult in
            var loadedDrafts: [UUID: [WorkoutSessionSetDraft]] = [:]
            var loadedRests: [UUID: Int] = [:]
            var loadedNotes: [UUID: String] = [:]
            var loadedPersistenceState: [UUID: ActiveWorkoutExercisePersistenceSnapshot] = [:]
            let catalogByUUID = (try? catalogRepository.exerciseMap(
                for: sessionExercises.map(\.catalogExerciseUUID)
            )) ?? [:]

            for exercise in sessionExercises {
                let normalizedDrafts = normalizedDraftsForActiveLogging(
                    makeDrafts(from: exercise),
                    catalogExercise: catalogByUUID[exercise.catalogExerciseUUID]
                )
                loadedDrafts[exercise.id] = normalizedDrafts
                loadedRests[exercise.id] = exercise.restSeconds
                loadedNotes[exercise.id] = exercise.notes
                loadedPersistenceState[exercise.id] = ActiveWorkoutExercisePersistenceSnapshot(
                    setDrafts: normalizedDrafts,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes
                )
            }

            return ActiveWorkoutHydrationResult(
                draftsByExerciseID: loadedDrafts,
                restsByExerciseID: loadedRests,
                notesByExerciseID: loadedNotes,
                persistenceStateByExerciseID: loadedPersistenceState,
                previousResolutionByExerciseID: Dictionary(
                    uniqueKeysWithValues: sessionExercises.map { ($0.id, WorkoutPreviousPerformanceResolution.loading) }
                ),
                catalogMatchesByUUID: catalogByUUID
            )
        }

        setDraftsByExerciseID = result.draftsByExerciseID
        restByExerciseID = result.restsByExerciseID
        notesByExerciseID = result.notesByExerciseID
        lastPersistedExerciseStateByID = result.persistenceStateByExerciseID
        catalogMatchesByUUID = result.catalogMatchesByUUID
        previousResolutionByExerciseID = result.previousResolutionByExerciseID
        componentResolutionByExerciseID = componentResolutionByExerciseID.filter { result.draftsByExerciseID[$0.key] != nil }
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
        seedOrRepairScrollTarget(
            draftsByExerciseID: result.draftsByExerciseID
        )
        await Task.yield()
        guard !Task.isCancelled, currentStamp == exerciseHydrationStamp else { return }
        restoreScrollTarget(using: scrollProxy)
        await Task.yield()
        guard !Task.isCancelled, currentStamp == exerciseHydrationStamp else { return }
        shouldTrackVisibleScrollTarget = true
        scheduleDeferredHydration(
            for: currentStamp,
            draftsByExerciseID: result.draftsByExerciseID
        )
    }

    @MainActor
    private func scheduleDeferredHydration(
        for stamp: ActiveWorkoutExerciseStateStamp,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) {
        deferredHydrationTask?.cancel()
        deferredHydrationTask = Task { @MainActor in
            try? await Task.sleep(for: previousPerformanceHydrationDelay)
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }

            let loadedPreviousResolution = WGJPerformance.measure("active-workout.hydrate.history") {
                loadPreviousResolutionByExerciseID(using: draftsByExerciseID)
            }
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }
            previousResolutionByExerciseID = loadedPreviousResolution

            await Task.yield()
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }

            let loadedComponentResolutions = WGJPerformance.measure("active-workout.hydrate.components") {
                loadComponentResolutionByExerciseID()
            }
            guard !Task.isCancelled, loadedExerciseStateStamp == stamp else { return }
            componentResolutionByExerciseID = loadedComponentResolutions
            deferredHydrationTask = nil
        }
    }

    @MainActor
    private func reconcileSessionLifecycleIfNeeded() async {
        guard hasBootstrapped else { return }

        guard session != nil else {
            guard completedSessionID == nil, !isEndingSession else {
                return
            }
            activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
            dismiss()
            return
        }
    }

    private func handleCompletedSessionTransition(sessionID: UUID) {
        dismissKeyboard()
        showingFinishConfirmation = false
        isCancelArmed = false
        isEndingSession = true
        completedSessionID = sessionID
        restTimerState.clearRestTimer()

        guard !pendingCompletionAfterSaveTemplateSheet else { return }
        guard !showingSaveTemplateSheet, pendingTemplateUpdatePreview == nil else { return }

        guard let latestSession = try? completedSessionRepository.session(id: sessionID) else {
            presentWorkoutCompletionSummary()
            return
        }

        if latestSession.templateID == nil {
            if templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                templateNameDraft = latestSession.name == "Empty Workout" ? "New Template" : latestSession.name
            }
            loadSaveTemplateFoldersIfNeeded()
            showingSaveTemplateSheet = true
            return
        }

        do {
            if let preview = try templateSyncService.previewTemplateUpdate(forSessionID: latestSession.id) {
                pendingTemplateUpdatePreview = preview
            } else {
                presentWorkoutCompletionSummary()
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
    private func loadPreviousResolutionByExerciseID(
        using draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> [UUID: WorkoutPreviousPerformanceResolution] {
        let startedAt = session?.startedAt ?? .now
        let requestedExerciseUUIDs = Array(Set(sessionExercises.map(\.catalogExerciseUUID)))
        let previousMaps = (try? activeWorkoutRepository.previousSetMaps(
            forExercises: requestedExerciseUUIDs,
            before: startedAt,
            excludingSessionID: sessionID
        )) ?? [:]

        var loadedPreviousResolution: [UUID: WorkoutPreviousPerformanceResolution] = [:]
        loadedPreviousResolution.reserveCapacity(sessionExercises.count)

        for exercise in sessionExercises {
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
            loadedPreviousResolution[exercise.id] = .resolved(
                resolvedPreviousMap(
                    baseMap: base,
                    maxSetCount: drafts.count
                )
            )
        }

        return loadedPreviousResolution
    }

    @MainActor
    private func loadComponentResolutionByExerciseID() -> [UUID: ExerciseComponentRotationResolution] {
        guard let session else {
            return [:]
        }

        var loaded: [UUID: ExerciseComponentRotationResolution] = [:]
        loaded.reserveCapacity(sessionExercises.count)

        for exercise in sessionExercises {
            guard let resolution = try? componentRotationResolver.resolution(
                for: exercise,
                templateID: session.templateID,
                before: session.startedAt,
                excludingSessionID: sessionID
            ) else {
                continue
            }

            loaded[exercise.id] = resolution
        }

        return loaded
    }

    @MainActor
    private func scheduleExercisePersistence(sessionExerciseID: UUID) {
        guard let snapshot = currentPersistenceSnapshot(for: sessionExerciseID) else {
            return
        }

        let persisted = lastPersistedExerciseStateByID[sessionExerciseID] ?? snapshot
        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: snapshot,
            persisted: persisted
        )
        guard changes.hasChanges else {
            pendingExercisePersistenceTasks.removeValue(forKey: sessionExerciseID)?.cancel()
            return
        }

        pendingExercisePersistenceTasks[sessionExerciseID]?.cancel()
        pendingExercisePersistenceTasks[sessionExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: interactivePersistenceDebounce)
            guard !Task.isCancelled else { return }
            pendingExercisePersistenceTasks[sessionExerciseID] = nil
            persistExerciseSnapshotIfNeeded(sessionExerciseID: sessionExerciseID)
        }
    }

    @MainActor
    private func persistExerciseSnapshotIfNeeded(sessionExerciseID: UUID) {
        guard let snapshot = currentPersistenceSnapshot(for: sessionExerciseID) else {
            return
        }

        let persisted = lastPersistedExerciseStateByID[sessionExerciseID] ?? snapshot
        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: snapshot,
            persisted: persisted
        )
        guard changes.hasChanges else { return }

        do {
            try WGJPerformance.measure("active-workout.persist.exercise") {
                try activeWorkoutRepository.persistExerciseSnapshot(
                    sessionExerciseID: sessionExerciseID,
                    snapshot: snapshot,
                    persistDrafts: changes.persistDrafts,
                    persistRest: changes.persistRest,
                    persistNotes: changes.persistNotes
                )
            }
            lastPersistedExerciseStateByID[sessionExerciseID] = snapshot
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func flushPendingSaves() {
        pendingSessionNotesSaveTask?.cancel()
        pendingSessionNotesSaveTask = nil
        persistSessionNotesIfNeeded()

        for task in pendingExercisePersistenceTasks.values {
            task.cancel()
        }
        pendingExercisePersistenceTasks.removeAll()

        for exercise in sessionExercises {
            persistExerciseSnapshotIfNeeded(sessionExerciseID: exercise.id)
        }
    }

    private func persistSessionMeta() {
        do {
            if let session {
                if !sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   sessionNameDraft != session.name {
                    try activeWorkoutRepository.updateSessionName(sessionID: sessionID, name: sessionNameDraft)
                }
                persistSessionNotesIfNeeded()
            }
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func scheduleSessionNotesPersistence() {
        pendingSessionNotesSaveTask?.cancel()
        pendingSessionNotesSaveTask = Task { @MainActor in
            try? await Task.sleep(for: interactivePersistenceDebounce)
            guard !Task.isCancelled else { return }
            pendingSessionNotesSaveTask = nil
            persistSessionNotesIfNeeded()
        }
    }

    @MainActor
    private func persistSessionNotesIfNeeded() {
        guard let session, notesDraft != session.notes else {
            return
        }

        do {
            try activeWorkoutRepository.updateSessionNotes(sessionID: sessionID, notes: notesDraft)
        } catch {
            showError(error)
        }
    }

    private func handlePickedExercise(_ item: ExerciseCatalogItem, target: ActiveWorkoutPickerTarget) {
        switch target {
        case .exercise:
            addExercise(item)
        case .cardio(let phase):
            upsertCardioBlock(phase: phase, catalogItem: item)
        }
    }

    private func showCardioPicker(for phase: WorkoutCardioPhase) {
        dismissKeyboard()
        pickerTarget = .cardio(phase)
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        var capturedError: Error?

        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            do {
                try activeWorkoutRepository.addExercise(sessionID: sessionID, catalogItem: item)
                loadedExerciseStateStamp = nil
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func moveExerciseUp(_ index: Int) {
        guard index > 0 else { return }
        moveExercise(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    private func moveExerciseDown(_ index: Int) {
        guard index < sessionExercises.count - 1 else { return }
        moveExercise(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }

    private func moveExercise(exerciseID: UUID, toPosition position: Int) {
        guard let currentIndex = sessionExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        guard position >= 0, position < sessionExercises.count, position != currentIndex else { return }

        let destination = position > currentIndex ? position + 1 : position
        moveExercise(fromOffsets: IndexSet(integer: currentIndex), toOffset: destination)
    }

    private func moveExercise(fromOffsets: IndexSet, toOffset: Int) {
        var capturedError: Error?

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try activeWorkoutRepository.moveExercise(
                    sessionID: sessionID,
                    fromOffsets: fromOffsets,
                    toOffset: toOffset
                )
                loadedExerciseStateStamp = nil
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func presentExerciseReorder(for exercise: ActiveWorkoutDraftExercise) {
        exerciseReorderRequest = ExerciseReorderRequest(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot
        )
    }

    private func removeExercise(exerciseID: UUID) {
        var capturedError: Error?

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try activeWorkoutRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                discardExerciseState(for: exerciseID)
                loadedExerciseStateStamp = nil
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func upsertCardioBlock(phase: WorkoutCardioPhase, catalogItem: ExerciseCatalogItem) {
        do {
            let existing = try activeWorkoutRepository.cardioBlock(sessionID: sessionID, phase: phase)
            try activeWorkoutRepository.upsertCardioBlock(
                sessionID: sessionID,
                draft: WorkoutCardioBlockDraft(
                    id: existing?.id ?? UUID(),
                    phase: phase,
                    catalogExerciseUUID: catalogItem.remoteUUID,
                    exerciseNameSnapshot: catalogItem.displayName,
                    categorySnapshot: catalogItem.categoryName,
                    muscleSummarySnapshot: catalogItem.primaryMuscleNames,
                    targetDurationSeconds: existing?.targetDurationSeconds ?? phase.defaultDurationSeconds,
                    isCompleted: false
                )
            )
        } catch {
            showError(error)
        }
    }

    private func removeCardioBlock(phase: WorkoutCardioPhase) {
        do {
            try activeWorkoutRepository.removeCardioBlock(sessionID: sessionID, phase: phase)
        } catch {
            showError(error)
        }
    }

    private func saveCardioDuration(phase: WorkoutCardioPhase, targetDurationSeconds: Int) {
        do {
            guard let cardioBlock = try activeWorkoutRepository.cardioBlock(sessionID: sessionID, phase: phase) else {
                return
            }

            try activeWorkoutRepository.upsertCardioBlock(
                sessionID: sessionID,
                draft: WorkoutCardioBlockDraft(
                    id: cardioBlock.id,
                    phase: cardioBlock.phase,
                    catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
                    exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
                    categorySnapshot: cardioBlock.categorySnapshot,
                    muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
                    targetDurationSeconds: targetDurationSeconds,
                    isCompleted: cardioBlock.isCompleted
                )
            )
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func toggleCardioCompletion(
        for cardioBlock: ActiveWorkoutDraftCardioBlock,
        scrollProxy: ScrollViewProxy
    ) {
        guard canToggleCompletion(for: cardioBlock) || cardioBlock.isCompleted else {
            return
        }

        do {
            let updatedCompletion = !cardioBlock.isCompleted
            try activeWorkoutRepository.setCardioCompletion(
                sessionID: sessionID,
                phase: cardioBlock.phase,
                isCompleted: updatedCompletion
            )

            if updatedCompletion {
                WorkoutFeedbackCenter.shared.exerciseCompleted()
                focusNextPhase(
                    afterCompleting: cardioBlock.phase,
                    scrollProxy: scrollProxy
                )
            }
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func handleDraftsChanged(
        _ drafts: [WorkoutSessionSetDraft],
        for exercise: ActiveWorkoutDraftExercise,
        scrollProxy: ScrollViewProxy
    ) {
        updateDraftsValue(drafts, for: exercise.id)
        let isCompleted = isExerciseCompleted(drafts)
        let previouslyCompleted = cardStateController.didCompleteCurrentCycle(for: exercise.id)
        if previouslyCompleted != isCompleted {
            let completedExerciseIDs = completedExerciseIDs(
                updating: exercise.id,
                with: drafts
            )
            let shouldFocusPostWorkoutCardio =
                isCompleted
                && postWorkoutCardio != nil
                && completedExerciseIDs.count == sessionExercises.count
            withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
                let nextExerciseID = cardStateController.updateCompletion(
                    for: exercise.id,
                    isCompleted: isCompleted,
                    orderedExerciseIDs: sessionExercises.map(\.id),
                    completedExerciseIDs: completedExerciseIDs
                )
                if shouldFocusPostWorkoutCardio {
                    scrollToTarget(
                        cardioScrollTarget(for: .postWorkout),
                        using: scrollProxy
                    )
                } else if let nextExerciseID {
                    scrollToTarget(
                        ActiveWorkoutScrollTarget.exercise(nextExerciseID),
                        using: scrollProxy
                    )
                }
            }
            if isCompleted {
                WorkoutFeedbackCenter.shared.exerciseCompleted()
            }
        }
        scheduleExercisePersistence(sessionExerciseID: exercise.id)
    }

    private func isExerciseCompleted(_ drafts: [WorkoutSessionSetDraft]) -> Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isCompleted)
    }

    private var isTrainingGuidanceEnabled: Bool {
        currentProfile?.isTrainingGuidanceEnabled ?? true
    }

    @MainActor
    private func guidancePresentation(
        for exercise: ActiveWorkoutDraftExercise,
        drafts: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutExerciseGuidancePresentation? {
        guard isTrainingGuidanceEnabled else { return nil }

        if let catalogExercise = catalogMatchesByUUID[exercise.catalogExerciseUUID] {
            return guidanceService.activeWorkoutGuidance(
                for: catalogExercise,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                setDrafts: drafts
            )
        }

        let snapshot = TrainingGuidanceCatalogSnapshot(
            exerciseName: exercise.exerciseNameSnapshot,
            categoryName: exercise.categorySnapshot,
            equipmentSummary: "",
            primaryMuscleNames: exercise.muscleSummarySnapshot
        )
        return guidanceService.activeWorkoutGuidance(
            for: snapshot,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            setDrafts: drafts
        )
    }

    @MainActor
    private func completedExerciseIDs(
        updating exerciseID: UUID,
        with drafts: [WorkoutSessionSetDraft]
    ) -> Set<UUID> {
        Set(
            sessionExercises.compactMap { candidate in
                let candidateDrafts: [WorkoutSessionSetDraft]
                if candidate.id == exerciseID {
                    candidateDrafts = drafts
                } else {
                    candidateDrafts = setDraftsByExerciseID[candidate.id] ?? makeDrafts(from: candidate)
                }

                return isExerciseCompleted(candidateDrafts) ? candidate.id : nil
            }
        )
    }

    @MainActor
    private func firstIncompleteExerciseID(
        from exercises: [ActiveWorkoutDraftExercise],
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

    @MainActor
    private func allExercisesCompleted(
        from exercises: [ActiveWorkoutDraftExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> Bool {
        exercises.allSatisfy { exercise in
            let drafts = draftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            return isExerciseCompleted(drafts)
        }
    }

    @MainActor
    private func preferredInitialScrollTarget(
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> ActiveWorkoutScrollTarget? {
        if let preWorkoutCardio, !preWorkoutCardio.isCompleted {
            return cardioScrollTarget(for: .preWorkout)
        }

        if let firstIncompleteExerciseID = firstIncompleteExerciseID(
            from: sessionExercises,
            draftsByExerciseID: draftsByExerciseID
        ) {
            return .exercise(firstIncompleteExerciseID)
        }

        if let postWorkoutCardio,
           !postWorkoutCardio.isCompleted,
           allExercisesCompleted(from: sessionExercises, draftsByExerciseID: draftsByExerciseID) {
            return cardioScrollTarget(for: .postWorkout)
        }

        if let firstExerciseID = sessionExercises.first?.id {
            return .exercise(firstExerciseID)
        }

        if preWorkoutCardio != nil {
            return cardioScrollTarget(for: .preWorkout)
        }

        if postWorkoutCardio != nil {
            return cardioScrollTarget(for: .postWorkout)
        }

        return session != nil ? .header : nil
    }

    @MainActor
    private func seedOrRepairScrollTarget(
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) {
        if let savedScrollTarget = activeWorkoutPresentationState.scrollTarget,
           isValidScrollTarget(savedScrollTarget) {
            return
        }

        activeWorkoutPresentationState.scrollTarget = preferredInitialScrollTarget(
            draftsByExerciseID: draftsByExerciseID
        )
    }

    @MainActor
    private func restoreScrollTarget(using scrollProxy: ScrollViewProxy) {
        guard let scrollTarget = activeWorkoutPresentationState.scrollTarget else { return }
        scrollProxy.scrollTo(scrollTarget, anchor: .top)
    }

    @MainActor
    private func isValidScrollTarget(_ target: ActiveWorkoutScrollTarget) -> Bool {
        switch target {
        case .header:
            return session != nil
        case .preWorkoutCardio:
            return preWorkoutCardio != nil
        case .exercise(let exerciseID):
            return sessionExercises.contains(where: { $0.id == exerciseID })
        case .postWorkoutCardio:
            return postWorkoutCardio != nil
        case .cancelSection:
            return session != nil && !isEndingSession
        }
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var previousPerformanceHydrationDelay: Duration {
        guard AppRuntimeConfig.isRunningTests,
              let rawValue = ProcessInfo.processInfo.environment["UITEST_ACTIVE_WORKOUT_PREVIOUS_PERFORMANCE_DELAY_MS"],
              let milliseconds = Int(rawValue)
        else {
            return .milliseconds(80)
        }

        return .milliseconds(max(0, milliseconds))
    }

    private func showExerciseSettings(for exercise: ActiveWorkoutDraftExercise) {
        dismissKeyboard()
        exerciseSettingsDraft = ActiveWorkoutExerciseSettingsDraft(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot,
            minRepsText: exercise.targetRepMin.map(String.init) ?? "",
            maxRepsText: exercise.targetRepMax.map(String.init) ?? "",
            restSeconds: restByExerciseID[exercise.id] ?? exercise.restSeconds
        )
    }

    private func showExerciseComponentPicker(for exercise: ActiveWorkoutDraftExercise) {
        dismissKeyboard()
        guard let resolution = componentResolutionByExerciseID[exercise.id],
              resolution.availableComponents.count > 1 else {
            return
        }

        exerciseComponentPickerDraft = ActiveWorkoutExerciseComponentPickerDraft(
            exerciseID: exercise.id,
            resolution: resolution
        )
    }

    private func saveExerciseSettings(_ draft: ActiveWorkoutExerciseSettingsDraft) {
        do {
            pendingExercisePersistenceTasks[draft.exerciseID]?.cancel()
            pendingExercisePersistenceTasks[draft.exerciseID] = nil
            let minReps = parsedRepValue(from: draft.minRepsText)
            let maxReps = parsedRepValue(from: draft.maxRepsText)
            try activeWorkoutRepository.updateExerciseRepRange(
                sessionExerciseID: draft.exerciseID,
                minReps: minReps,
                maxReps: maxReps
            )
            try activeWorkoutRepository.updateExerciseRest(
                sessionExerciseID: draft.exerciseID,
                restSeconds: draft.restSeconds
            )
            restByExerciseID[draft.exerciseID] = draft.restSeconds
            applyPersistedRestChange(
                sessionExerciseID: draft.exerciseID,
                updatedRest: draft.restSeconds
            )
            if let snapshot = currentPersistenceSnapshot(for: draft.exerciseID) {
                lastPersistedExerciseStateByID[draft.exerciseID] = snapshot
            }
            exerciseSettingsDraft = nil
        } catch {
            showError(error)
        }
    }

    private func saveExerciseComponentSelection(exerciseID: UUID, componentID: UUID) {
        do {
            try activeWorkoutRepository.overrideExerciseComponent(
                sessionExerciseID: exerciseID,
                componentID: componentID
            )
            exerciseComponentPickerDraft = nil
            loadedExerciseStateStamp = nil
        } catch {
            showError(error)
        }
    }

    private func finishWorkout() {
        dismissKeyboard()
        pendingFinishAfterConfirmation = false
        isCancelArmed = false
        guard !isEndingSession else { return }
        isEndingSession = true
        persistSessionMeta()
        flushPendingSaves()
        restTimerState.clearRestTimer()

        do {
            let finishedSessionID = try activeWorkoutRepository.finishSession(sessionID: sessionID, notes: notesDraft)
            handleCompletedSessionTransition(sessionID: finishedSessionID)
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

    private func loadSaveTemplateFoldersIfNeeded() {
        guard saveTemplateFolders.isEmpty else { return }
        saveTemplateFolders = (try? templateRepository.folders()) ?? []
    }

    private func skipSavingSessionAsTemplate() {
        dismissKeyboard()
        requestCompletionAfterSaveTemplateSheetDismissal()
    }

    private func handleSaveTemplateSheetDismissed() {
        guard pendingCompletionAfterSaveTemplateSheet else { return }
        pendingCompletionTask?.cancel()
        pendingCompletionTask = nil
        presentWorkoutCompletionSummary()
    }

    private func requestCompletionAfterSaveTemplateSheetDismissal() {
        pendingCompletionAfterSaveTemplateSheet = true
        showingSaveTemplateSheet = false
        pendingCompletionTask?.cancel()
        pendingCompletionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, pendingCompletionAfterSaveTemplateSheet, !showingSaveTemplateSheet else { return }
            presentWorkoutCompletionSummary()
        }
    }

    private func presentWorkoutCompletionSummary() {
        pendingCompletionTask?.cancel()
        pendingCompletionTask = nil
        dismissKeyboard()
        isCancelArmed = false
        showingSaveTemplateSheet = false
        pendingCompletionAfterSaveTemplateSheet = false
        exerciseSettingsDraft = nil
        exerciseComponentPickerDraft = nil
        pendingTemplateUpdatePreview = nil
        workoutCompletionPresentationState.queueAfterActiveWorkoutDismiss(sessionID: completedSessionID ?? sessionID)
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
    }

    private func minimizeWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        activeWorkoutPresentationState.collapseActiveWorkout()
        dismiss()
    }

    private func cancelWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        guard !isEndingSession else { return }
        isEndingSession = true
        persistSessionMeta()
        flushPendingSaves()
        restTimerState.clearRestTimer()

        do {
            try activeWorkoutRepository.cancelSession(sessionID: sessionID)
            activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
            dismiss()
        } catch {
            isEndingSession = false
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        if let repositoryError = error as? WorkoutSessionRepositoryError {
            switch repositoryError {
            case .sessionNotFound:
                activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
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
            presentWorkoutCompletionSummary()
        } catch {
            showError(error)
        }
    }

    private func dismissKeyboard() {
        WGJKeyboard.dismiss()
    }

    private var exerciseReorderItems: [ExerciseReorderListItem] {
        sessionExercises.map { exercise in
            ExerciseReorderListItem(id: exercise.id, name: exercise.exerciseNameSnapshot)
        }
    }

    @MainActor
    private func discardRemovedExerciseState(keeping currentIDs: Set<UUID>) {
        let knownIDs =
            Set(setDraftsByExerciseID.keys)
            .union(restByExerciseID.keys)
            .union(notesByExerciseID.keys)
            .union(lastPersistedExerciseStateByID.keys)
            .union(previousResolutionByExerciseID.keys)
            .union(componentResolutionByExerciseID.keys)
            .union(pendingExercisePersistenceTasks.keys)

        for exerciseID in knownIDs where !currentIDs.contains(exerciseID) {
            discardExerciseState(for: exerciseID)
        }
    }

    @MainActor
    private func discardExerciseState(for exerciseID: UUID) {
        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? []).map(\.id))

        pendingExercisePersistenceTasks.removeValue(forKey: exerciseID)?.cancel()
        setDraftsByExerciseID[exerciseID] = nil
        restByExerciseID[exerciseID] = nil
        notesByExerciseID[exerciseID] = nil
        lastPersistedExerciseStateByID[exerciseID] = nil
        previousResolutionByExerciseID[exerciseID] = nil
        componentResolutionByExerciseID[exerciseID] = nil

        if let restTimerSourceSetID = restTimerState.restTimerSourceSetID,
           removedSetIDs.contains(restTimerSourceSetID) {
            restTimerState.clearRestTimer(sourceSetID: restTimerSourceSetID)
        }
    }

    private func presentFinishConfirmation() {
        dismissKeyboard()
        guard !isEndingSession else { return }
        pendingFinishAfterConfirmation = false
        isCancelArmed = false
        showingFinishConfirmation = true
    }

    private func confirmFinishWorkout() {
        guard !isEndingSession else { return }
        pendingFinishAfterConfirmation = true
        showingFinishConfirmation = false
    }

    @MainActor
    private func handleFinishConfirmationChange(from oldValue: Bool, to newValue: Bool) {
        guard oldValue, !newValue, pendingFinishAfterConfirmation else { return }
        pendingFinishAfterConfirmation = false

        Task { @MainActor in
            await Task.yield()
            guard !showingFinishConfirmation else { return }
            finishWorkout()
        }
    }

    @MainActor
    private func focusCancelSection(using scrollProxy: ScrollViewProxy) {
        scrollToTarget(
            cancelSectionScrollTarget,
            using: scrollProxy,
            anchor: .center,
            animation: WGJMotion.overlayAnimation(reduceMotion: reduceMotion)
        )

        Task { @MainActor in
            await Task.yield()
            guard isCancelArmed else { return }
            scrollToTarget(
                cancelSectionScrollTarget,
                using: scrollProxy,
                anchor: .center,
                animation: WGJMotion.overlayAnimation(reduceMotion: reduceMotion)
            )
        }
    }

    @MainActor
    private func makeFinishConfirmationContent() -> ActiveWorkoutFinishConfirmationContent {
        ActiveWorkoutFinishConfirmationContent(
            exerciseDrafts: sessionExercises.map { exercise in
                setDraftsByExerciseID[exercise.id] ?? makeDrafts(from: exercise)
            },
            cardioBlocks: orderedCardioBlocks.map(WorkoutCardioBlockDraft.init(model:))
        )
    }

    @MainActor
    private func orderedSessionSets(for exercise: ActiveWorkoutDraftExercise) -> [ActiveWorkoutDraftSet] {
        (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    @MainActor
    private func makeDrafts(from exercise: ActiveWorkoutDraftExercise) -> [WorkoutSessionSetDraft] {
        orderedSessionSets(for: exercise).map(WorkoutSessionSetDraft.init(model:))
    }

    private func normalizedDraftsForActiveLogging(
        _ drafts: [WorkoutSessionSetDraft],
        catalogExercise: ExerciseCatalogItem?
    ) -> [WorkoutSessionSetDraft] {
        guard TemplateLoadUnit.inferredDefault(
            fromEquipmentSummary: catalogExercise?.equipmentSummary ?? ""
        ) == .bodyweight else {
            return drafts
        }

        var normalized = drafts
        var changed = false

        for index in normalized.indices {
            guard normalized[index].targetWeight == nil, normalized[index].actualWeight == nil else {
                continue
            }

            if normalized[index].targetLoadUnit != .bodyweight {
                normalized[index].targetLoadUnit = .bodyweight
                changed = true
            }

            if normalized[index].actualLoadUnit != .bodyweight {
                normalized[index].actualLoadUnit = .bodyweight
                changed = true
            }
        }

        return changed ? normalized : drafts
    }

    @MainActor
    private func applyPersistedRestChange(
        sessionExerciseID: UUID,
        updatedRest: Int
    ) {
        guard var drafts = setDraftsByExerciseID[sessionExerciseID] else { return }

        var changed = false
        for index in drafts.indices where !drafts[index].isLocked {
            drafts[index].restSeconds = updatedRest
            changed = true
        }

        guard changed else { return }
        setDraftsByExerciseID[sessionExerciseID] = drafts
        let isCompleted = isExerciseCompleted(drafts)
        if cardStateController.didCompleteCurrentCycle(for: sessionExerciseID) != isCompleted {
            cardStateController.updateCompletion(
                for: sessionExerciseID,
                isCompleted: isCompleted
            )
        }
    }

    private func cardioScrollTarget(for phase: WorkoutCardioPhase) -> ActiveWorkoutScrollTarget {
        switch phase {
        case .preWorkout:
            return .preWorkoutCardio
        case .postWorkout:
            return .postWorkoutCardio
        }
    }

    @MainActor
    private func focusNextPhase(
        afterCompleting phase: WorkoutCardioPhase,
        scrollProxy: ScrollViewProxy
    ) {
        switch phase {
        case .preWorkout:
            if let firstIncompleteExerciseID = firstIncompleteExerciseID(
                from: sessionExercises,
                draftsByExerciseID: setDraftsByExerciseID
            ) {
                scrollToTarget(
                    ActiveWorkoutScrollTarget.exercise(firstIncompleteExerciseID),
                    using: scrollProxy
                )
            } else if postWorkoutCardio != nil {
                scrollToTarget(
                    cardioScrollTarget(for: .postWorkout),
                    using: scrollProxy
                )
            }
        case .postWorkout:
            break
        }
    }

    @MainActor
    private func scrollToTarget(
        _ target: ActiveWorkoutScrollTarget,
        using scrollProxy: ScrollViewProxy,
        anchor: UnitPoint = .top,
        animation: Animation? = nil
    ) {
        activeWorkoutPresentationState.scrollTarget = target
        let resolvedAnimation = animation ?? WGJMotion.cardAnimation(reduceMotion: reduceMotion)
        withAnimation(resolvedAnimation) {
            scrollProxy.scrollTo(target, anchor: anchor)
        }
    }

    @MainActor
    private func canToggleCompletion(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> Bool {
        switch cardioBlock.phase {
        case .preWorkout:
            return true
        case .postWorkout:
            return isPostWorkoutCardioUnlocked
        }
    }

    @MainActor
    private func cardioStatusText(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> String {
        if cardioBlock.isCompleted {
            return "Complete"
        }

        switch cardioBlock.phase {
        case .preWorkout:
            return "Ready"
        case .postWorkout:
            return isPostWorkoutCardioUnlocked ? "Ready" : "Locked"
        }
    }

    @MainActor
    private func cardioStatusTint(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> Color {
        if cardioBlock.isCompleted {
            return WGJTheme.success
        }

        switch cardioBlock.phase {
        case .preWorkout:
            return WGJTheme.accentBlue
        case .postWorkout:
            return isPostWorkoutCardioUnlocked ? WGJTheme.accentGold : WGJTheme.textSecondary
        }
    }

    private func cardioSectionSubtitle(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "Separate warmup cardio that gates the main exercise roster."
        case .postWorkout:
            return "Separate cooldown cardio that unlocks after the exercises are done."
        }
    }

    private func cardioEmptyStateMessage(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "Add a short low-effort warmup like bike, walk, or crosstrainer."
        case .postWorkout:
            return "Add a longer cooldown like incline treadmill or an easy bike finish."
        }
    }

    @MainActor
    private func cardioFootnote(for cardioBlock: ActiveWorkoutDraftCardioBlock) -> String {
        switch cardioBlock.phase {
        case .preWorkout:
            return cardioBlock.isCompleted
                ? "Warmup complete. Main exercise logging is unlocked."
                : "Finish this warmup block before logging or completing sets."
        case .postWorkout:
            if cardioBlock.isCompleted {
                return "Cooldown complete. This workout is fully wrapped."
            }

            return isPostWorkoutCardioUnlocked
                ? "Main exercises are complete. Finish this cooldown block when you're done."
                : "This cooldown block unlocks after every main exercise is complete."
        }
    }

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }

    @MainActor
    private func makeCardioSettingsDraft(from cardioBlock: ActiveWorkoutDraftCardioBlock) -> WorkoutCardioSettingsDraft {
        WorkoutCardioSettingsDraft(
            phase: cardioBlock.phase,
            exerciseName: cardioBlock.exerciseNameSnapshot,
            descriptor: cardioDescriptor(
                category: cardioBlock.categorySnapshot,
                muscleSummary: cardioBlock.muscleSummarySnapshot
            ),
            targetDurationSeconds: cardioBlock.targetDurationSeconds
        )
    }
}

private struct ActiveWorkoutHeaderCard: View {
    @Binding var sessionNameDraft: String
    @Binding var notesDraft: String

    let session: ActiveWorkoutDraftSession
    let exerciseCount: Int
    let cardioCount: Int
    let missingCardioPhases: [WorkoutCardioPhase]
    let onSubmit: () -> Void
    let onAddCardio: (WorkoutCardioPhase) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Session") {
                if !missingCardioPhases.isEmpty {
                    addCardioButton
                }
            }

            TextField("Workout name", text: $sessionNameDraft)
                .textInputAutocapitalization(.words)
                .wgjPillField()
                .accessibilityIdentifier("active-workout-name-field")
                .onSubmit(onSubmit)

            TextField("Notes", text: $notesDraft, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()
                .accessibilityIdentifier("active-workout-notes-field")
                .onSubmit(onSubmit)

            HStack(spacing: 10) {
                Text("\(exerciseCount) exercises")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)

                if cardioCount > 0 {
                    Text("\(cardioCount) cardio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                }

                Spacer()
            }

            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var addCardioButton: some View {
        WGJActionMenuButton("Add Cardio", titleVisibility: .hidden) {
            ForEach(missingCardioPhases) { phase in
                Button("Add \(phase.title)") {
                    onAddCardio(phase)
                }
            }
        } label: {
            Label("Add Cardio", systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
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
        .accessibilityIdentifier("active-workout-add-cardio-button")
    }
}

private struct ActiveWorkoutBottomDock: View {
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutDraftSession?
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let popup = restTimerState.restTimerPopup {
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
        }
        .wgjGlassContainer(spacing: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(WGJTheme.bgBase.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WGJTheme.accentBlue.opacity(0.18))
                .frame(height: 1)
        }
    }
}

private struct ActiveWorkoutCancelSection: View {
    let isCancelArmed: Bool
    let onCancelConfirmationPresented: () -> Void
    let onArmCancel: () -> Void
    let onKeepWorkout: () -> Void
    let onDiscardWorkout: () -> Void

    var body: some View {
        Group {
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
                .accessibilityIdentifier("active-workout-cancel-button")
            }
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
                    .accessibilityIdentifier("active-workout-keep-button")

                Button("Discard Workout", action: onDiscardWorkout)
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .tint(WGJTheme.danger)
                    .accessibilityIdentifier("active-workout-discard-button")
            }
        }
        .onAppear(perform: onCancelConfirmationPresented)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("active-workout-cancel-confirmation")
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
    @Environment(RestTimerState.self) private var restTimerState

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onReceive(timer) { date in
                restTimerState.handleRestTimerExpirationIfNeeded(at: date)
            }
    }
}

private struct ActiveWorkoutFinishPopover: View {
    let content: ActiveWorkoutFinishConfirmationContent
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: content.iconSystemName)
                    .font(.title3)
                    .foregroundStyle(content.hasIncompleteWork ? WGJTheme.warning : WGJTheme.success)

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(content.message)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(content.cancelButtonTitle, action: onCancel)
                    .buttonStyle(WGJGhostButtonStyle())

                if content.hasIncompleteWork {
                    Button(content.confirmButtonTitle, action: onFinish)
                        .buttonStyle(WGJDestructiveButtonStyle())
                } else {
                    Button(content.confirmButtonTitle, action: onFinish)
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .wgjCardContainer(strong: true, cornerRadius: 18)
        .padding(6)
    }
}

struct ActiveWorkoutFinishConfirmationContent: Equatable {
    let incompleteExerciseCount: Int
    let incompleteSetCount: Int
    let incompleteCardioCount: Int

    init(
        exerciseDrafts: [[WorkoutSessionSetDraft]],
        cardioBlocks: [WorkoutCardioBlockDraft] = []
    ) {
        var incompleteExerciseCount = 0
        var incompleteSetCount = 0

        for drafts in exerciseDrafts {
            let unfinishedSetCount = drafts.filter { !$0.isCompleted }.count
            if unfinishedSetCount > 0 || drafts.isEmpty {
                incompleteExerciseCount += 1
                incompleteSetCount += unfinishedSetCount
            }
        }

        self.incompleteExerciseCount = incompleteExerciseCount
        self.incompleteSetCount = incompleteSetCount
        self.incompleteCardioCount = cardioBlocks.filter { !$0.isCompleted }.count
    }

    var hasIncompleteWork: Bool {
        incompleteExerciseCount > 0 || incompleteSetCount > 0 || incompleteCardioCount > 0
    }

    var title: String {
        hasIncompleteWork ? "Finish With Unfinished Work?" : "Finish Workout?"
    }

    var message: String {
        guard hasIncompleteWork else {
            return "This will close the active workout and add it to your history."
        }

        if incompleteSetCount > 0 && incompleteCardioCount > 0 {
            return "You still have \(countText(incompleteSetCount, singular: "unfinished set")) across \(countText(incompleteExerciseCount, singular: "exercise")), plus \(countText(incompleteCardioCount, singular: "unfinished cardio section")). Finish anyway or go back and finish them."
        }

        if incompleteSetCount > 0 {
            return "You still have \(countText(incompleteSetCount, singular: "unfinished set")) across \(countText(incompleteExerciseCount, singular: "exercise")). Finish anyway or go back and finish them."
        }

        if incompleteExerciseCount > 0 && incompleteCardioCount > 0 {
            return "You still have \(countText(incompleteExerciseCount, singular: "unfinished exercise")) and \(countText(incompleteCardioCount, singular: "unfinished cardio section")). Finish anyway or go back before closing this workout."
        }

        if incompleteExerciseCount > 0 {
            return "You still have \(countText(incompleteExerciseCount, singular: "unfinished exercise")). Finish anyway or go back before closing this workout."
        }

        return "You still have \(countText(incompleteCardioCount, singular: "unfinished cardio section")). Finish anyway or go back before closing this workout."
    }

    var confirmButtonTitle: String {
        hasIncompleteWork ? "Finish Anyway" : "Finish and Save"
    }

    var cancelButtonTitle: String {
        hasIncompleteWork ? "Keep Logging" : "Not yet"
    }

    var iconSystemName: String {
        hasIncompleteWork ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private func countText(_ count: Int, singular: String) -> String {
        "\(count) \(singular)" + (count == 1 ? "" : "s")
    }
}

private struct ActiveWorkoutActivityTimerDock: View {
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutDraftSession

    var body: some View {
        let restTimerEndsAt = restTimerState.restTimerEndsAt
        let restTimerContextLabel = restTimerState.restTimerContextLabel()

        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = restTimerEndsAt.map { restTimerEndsAt in
                let seconds = Int(ceil(restTimerEndsAt.timeIntervalSince(context.date)))
                return seconds > 0 ? seconds : nil
            } ?? nil
            let isResting = remaining != nil
            let accent = isResting ? WGJTheme.success : WGJTheme.accentCyan
            let secondaryText = isResting
                ? restTimerContextLabel ?? "Recover before the next set"
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
                        restTimerState.clearRestTimer()
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
                    .fill(WGJTheme.cardStrong.opacity(0.97))
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
                    .shadow(color: WGJTheme.shadowStrong.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isResting
                    ? "Rest timer \(primaryValue). \(secondaryText)"
                    : "Elapsed time \(primaryValue)"
            )
            .accessibilityIdentifier(isResting ? "active-workout-rest-timer" : "active-workout-elapsed-timer")
            .allowsHitTesting(isResting)
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

private enum ActiveWorkoutPickerTarget: Identifiable {
    case exercise
    case cardio(WorkoutCardioPhase)

    var id: String {
        switch self {
        case .exercise:
            return "exercise"
        case .cardio(let phase):
            return "cardio-\(phase.rawValue)"
        }
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
    let notesByExerciseID: [UUID: String]
    let persistenceStateByExerciseID: [UUID: ActiveWorkoutExercisePersistenceSnapshot]
    let previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]
    let catalogMatchesByUUID: [String: ExerciseCatalogItem]
}

private struct ActiveWorkoutExerciseStateStamp: Hashable {
    private let entries: [Entry]

    @MainActor
    init(exercises: [ActiveWorkoutDraftExercise]) {
        entries = exercises.map(Entry.init(exercise:))
    }

    private struct Entry: Hashable {
        let id: UUID
        let catalogExerciseUUID: String
        let orderedComponentIDs: [UUID]
        let orderedSetIDs: [UUID]

        @MainActor
        init(exercise: ActiveWorkoutDraftExercise) {
            id = exercise.id
            catalogExerciseUUID = exercise.catalogExerciseUUID
            orderedComponentIDs = (exercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.id)
            orderedSetIDs = (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.id)
        }
    }
}

private struct ActiveWorkoutExerciseSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ActiveWorkoutExerciseSettingsDraft

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
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

                        WGJActionMenuButton("Default Rest") {
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
    .environment(WorkoutCompletionPresentationState())
    .environment(ActiveWorkoutPresentationState())
    .environment(RestTimerState())
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
