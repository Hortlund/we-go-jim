import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(SubscriptionState.self) private var subscriptionState
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let sessionID: UUID

    @State private var runtimeSession: ActiveWorkoutRuntimeSession?
    @State private var hasBootstrapped = false
    @State private var isBootstrapping = false
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var notesByExerciseID: [UUID: String] = [:]
    @State private var pendingCardioCompletionsByPhase: [WorkoutCardioPhase: Bool] = [:]
    @State private var rowFlushCoordinator = WorkoutExerciseRowFlushCoordinator()

    @State private var previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution] = [:]
    @State private var componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
    @State private var guidanceByExerciseID: [UUID: ActiveWorkoutExerciseGuidancePresentation?] = [:]
    @State private var catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot] = [:]
    @State private var loadedExerciseStateStamp: ActiveWorkoutExerciseInteractionStamp?
    @State private var exerciseHydrationInvalidation = 0
    @State private var deferredHydrationTask: Task<Void, Never>?
    @State private var foregroundNonCriticalInteractionWorkTask: Task<Void, Never>?
    @State private var pendingGuidanceRefreshTask: Task<Void, Never>?
    @State private var pendingUserEditSnapshotTask: Task<Void, Never>?
    @State private var pendingGuidanceRefreshExerciseIDs: Set<UUID> = []
    @State private var shouldRefreshAllGuidance = false
    @State private var cardStateController = ActiveWorkoutExerciseCardStateController()
    @State private var renderProjection = ActiveWorkoutRenderProjection.empty
    @State private var isBatchingRenderProjectionRefresh = false
    @State private var needsBatchedRenderProjectionRefresh = false
    @State private var currentScrollTarget: ActiveWorkoutScrollTarget?
    @State private var restoredScrollTarget: ActiveWorkoutScrollTarget?
    @State private var profilePreferences = ActiveWorkoutProfilePreferences.default

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var pickerTarget: ActiveWorkoutPickerTarget?
    @State private var showingFinishConfirmation = false
    @State private var pendingFinishAfterConfirmation = false
    @State private var isCancelArmed = false
    @State private var isEndingSession = false
    @State private var completedSessionID: UUID?
    @State private var showingSaveTemplateSheet = false
    @State private var pendingCompletionAfterSaveTemplateSheet = false
    @State private var pendingCompletionAfterTemplateReviewSheet = false
    @State private var exerciseSettingsDraft: ActiveWorkoutExerciseSettingsDraft?
    @State private var exerciseComponentPickerDraft: ActiveWorkoutExerciseComponentPickerDraft?
    @State private var cardioSettingsDraft: WorkoutCardioSettingsDraft?
    @State private var exerciseReorderRequest: ExerciseReorderRequest?
    @State private var pendingTemplateUpdatePreview: WorkoutTemplateSyncPreview?
    @State private var pendingTemplateUpdateAfterReviewSheetDismissal: WorkoutTemplateSyncPreview?
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?
    @State private var saveTemplateFolders: [ActiveWorkoutTemplateFolderSnapshot] = []
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isMetricInputFocused = false

    private let cancelSectionFocusSpacerHeight: CGFloat = 160
    private let cancelSectionDockClearanceHeight: CGFloat = 96
    private let cancelSectionScrollTarget = ActiveWorkoutScrollTarget.cancelSection
    private let guidanceService = TrainingGuidanceService()

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
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                // Exercise cards change height aggressively as sets complete, and a non-lazy
                // stack keeps the scroll position stable when a completed card collapses.
                activeWorkoutScrollContent(scrollProxy: scrollProxy)
                .scrollTargetLayout()
                .padding(16)
            }
            .scrollPosition(id: $currentScrollTarget, anchor: .top)
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
            .wgjMinimalKeyboardToolbar()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActiveWorkoutKeyboardAwareBottomDock(
                    session: session,
                    isEndingSession: isEndingSession,
                    restTimerPopupID: restTimerState.restTimerPopup?.id,
                    reduceMotion: reduceMotion,
                    isMetricInputFocused: isMetricInputFocused,
                    onDismissRestTimer: {
                        clearRestTimerAndPersist()
                    }
                )
            }
            .sheet(item: $pickerTarget, onDismiss: {
                dismissKeyboard()
            }) { target in
                ExercisePickerView(
                    repository: catalogRepository,
                    title: target.pickerTitle,
                    actionTitle: target.pickerActionTitle
                ) { exercise in
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
            .sheet(item: $pendingTemplateUpdatePreview, onDismiss: handleTemplateReviewSheetDismissed) { preview in
                templateReviewSheet(for: preview)
            }
            .task {
                await bootstrapIfNeeded()
            }
            .task(id: session?.id) {
                await reconcileSessionLifecycleIfNeeded()
                restorePreparedScrollTargetIfNeeded(using: scrollProxy)
            }
            .task(id: exerciseHydrationStamp) {
                await loadExerciseStateIfNeeded()
            }
            .onChange(of: showingFinishConfirmation) { oldValue, newValue in
                handleFinishConfirmationChange(from: oldValue, to: newValue)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: isMetricInputFocused) { _, isFocused in
                guard !isFocused, canRunNonCriticalInteractionWork else { return }
                scheduleForegroundNonCriticalInteractionWorkResume()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isMetricInputFocused = false
            }
            .onAppear {
                restorePreparedScrollTargetIfNeeded(using: scrollProxy)
            }
            .onDisappear {
                isCancelArmed = false
                pendingFinishAfterConfirmation = false
                pendingCompletionAfterSaveTemplateSheet = false
                pendingCompletionAfterTemplateReviewSheet = false
                pendingTemplateUpdateAfterReviewSheetDismissal = nil
                deferredHydrationTask?.cancel()
                deferredHydrationTask = nil
                foregroundNonCriticalInteractionWorkTask?.cancel()
                foregroundNonCriticalInteractionWorkTask = nil
                pendingGuidanceRefreshTask?.cancel()
                pendingGuidanceRefreshTask = nil
                pendingGuidanceRefreshExerciseIDs = []
                shouldRefreshAllGuidance = false
            }
            .alert("Workout Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                workoutErrorAlertMessage
            }
        }
    }

    @MainActor
    private func activeWorkoutScrollContent(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            activeWorkoutHeaderContent
            emptyWorkoutContent

            ForEach(exerciseDisplayGroups) { group in
                exerciseSection(for: group, scrollProxy: scrollProxy)
            }

            if session != nil && !sessionExercises.isEmpty {
                addExerciseButton(title: "Add another exercise")
                    .disabled(session == nil)
            }

            if postWorkoutCardio != nil {
                cardioSection(for: .postWorkout)
            }

            activeWorkoutCancelContent(scrollProxy: scrollProxy)
        }
    }

    @MainActor
    @ViewBuilder
    private var activeWorkoutHeaderContent: some View {
        if let session {
            ActiveWorkoutHeaderCard(
                sessionNameDraft: $sessionNameDraft,
                notesDraft: $notesDraft,
                session: session,
                exerciseCount: sessionExercises.count,
                cardioCount: orderedCardioBlocks.count,
                missingCardioPhases: missingCardioPhases,
                onSubmit: {
                    persistCommittedUserEditSnapshot()
                },
                onAddCardio: showCardioPicker
            )
            .id(ActiveWorkoutScrollTarget.header)
            if preWorkoutCardio != nil {
                cardioSection(for: .preWorkout)
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
    }

    @MainActor
    @ViewBuilder
    private var emptyWorkoutContent: some View {
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
    }

    @MainActor
    @ViewBuilder
    private func activeWorkoutCancelContent(scrollProxy: ScrollViewProxy) -> some View {
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

    private var workoutErrorAlertMessage: Text {
        Text(errorMessage)
    }

    private func templateReviewSheet(for preview: WorkoutTemplateSyncPreview) -> some View {
        ActiveWorkoutTemplateSyncReviewSheet(
            preview: preview,
            onKeepTemplate: {
                requestCompletionAfterTemplateReviewSheetDismissal()
            },
            onUpdateTemplate: {
                requestTemplateUpdateAfterReviewSheetDismissal(preview)
            }
        )
        .interactiveDismissDisabled()
    }

    private var session: ActiveWorkoutRuntimeSession? {
        renderProjection.session
    }

    @MainActor
    private var sessionExercises: [ActiveWorkoutRuntimeExercise] {
        renderProjection.sessionExercises
    }

    @MainActor
    private var orderedCardioBlocks: [ActiveWorkoutRuntimeCardioBlock] {
        renderProjection.orderedCardioBlocks
    }

    @MainActor
    private var preWorkoutCardio: ActiveWorkoutRuntimeCardioBlock? {
        renderProjection.preWorkoutCardio
    }

    @MainActor
    private var postWorkoutCardio: ActiveWorkoutRuntimeCardioBlock? {
        renderProjection.postWorkoutCardio
    }

    @MainActor
    private var hasWorkoutContent: Bool {
        renderProjection.hasWorkoutContent
    }

    @MainActor
    private var missingCardioPhases: [WorkoutCardioPhase] {
        renderProjection.missingCardioPhases
    }

    @MainActor
    private var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>] {
        renderProjection.exerciseDisplayGroups
    }

    nonisolated static func supersetRoundRestSecondsByGroupID(
        _ pairs: [(id: UUID, roundRestSeconds: Int)]
    ) -> [UUID: Int] {
        Dictionary(pairs.map { ($0.id, $0.roundRestSeconds) }, uniquingKeysWith: { existing, _ in existing })
    }

    @MainActor
    private var supersetContextByExerciseID: [UUID: ActiveWorkoutSupersetContext] {
        renderProjection.supersetContextByExerciseID
    }

    private var shouldShowBottomDock: Bool {
        guard !isEndingSession, session != nil else {
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

    private var exerciseHydrationStamp: ActiveWorkoutExerciseInteractionStamp {
        ActiveWorkoutExerciseInteractionStamp(
            entries: renderProjection.sessionExercises.map { exercise in
                ActiveWorkoutExerciseInteractionStamp.Entry(
                    id: exercise.id,
                    catalogExerciseUUID: exercise.catalogExerciseUUID,
                    restSeconds: exercise.restSeconds,
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    supersetGroupID: exercise.supersetGroupID,
                    supersetPositionRaw: exercise.supersetPositionRaw
                )
            },
            invalidation: exerciseHydrationInvalidation
        )
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
        for phase: WorkoutCardioPhase
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
                isCompleted: resolvedCardioCompletion(for: cardioBlock),
                canComplete: canToggleCompletion(for: cardioBlock),
                completionTitle: "Complete \(cardioBlock.phase.shortTitle)",
                completionAccessibilityLabel: cardioCompletionAccessibilityLabel(for: cardioBlock),
                undoAccessibilityLabel: cardioCompletionAccessibilityLabel(for: cardioBlock),
                completionAccessibilityIdentifier: "active-workout-\(cardioBlock.phase.rawValue)-toggle-button",
                accessibilityIdentifier: "active-workout-\(phase.rawValue)-card",
                onToggleCompletion: {
                    toggleCardioCompletion(for: cardioBlock)
                }
            ) {
                cardioSectionActionsButton(for: cardioBlock)
            }
            .id(cardioScrollTarget(for: phase))
        }
    }

    @MainActor
    private func cardioSectionActionsButton(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> some View {
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

    private func cardioHeaderTint(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> Color {
        if resolvedCardioCompletion(for: cardioBlock) {
            return WGJTheme.success
        }

        switch cardioBlock.phase {
        case .preWorkout:
            return WGJTheme.accentBlue
        case .postWorkout:
            return WGJTheme.accentGold
        }
    }

    private func cardioCompletionAccessibilityLabel(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> String {
        if resolvedCardioCompletion(for: cardioBlock) {
            return "Mark \(cardioBlock.phase.shortTitle) Incomplete"
        }

        return "Complete \(cardioBlock.phase.shortTitle)"
    }

    @MainActor
    @ViewBuilder
    private func exerciseRow(
        for exercise: ActiveWorkoutRuntimeExercise,
        index: Int,
        displayTitle: String? = nil,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let exerciseID = exercise.id
        let exerciseName = exercise.exerciseNameSnapshot
        let guidance = guidanceByExerciseID[exerciseID] ?? nil

        Group {
            if let drafts = renderableDrafts(for: exerciseID) {
                WorkoutExerciseRowHostView(
                    exerciseID: exerciseID,
                    exerciseAccessibilityIdentifier: "active-workout-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exerciseName,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: displayTitle ?? "Exercise \(index + 1)",
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    previousPerformanceResolution: resolvedPreviousPerformanceResolution(for: exerciseID),
                    guidance: guidance,
                    preferredLoadUnit: preferredLoadUnit,
                    componentSummaryResolution: componentResolutionByExerciseID[exerciseID],
                    componentSummaryAccessibilityIdentifierPrefix: "active-workout-exercise-\(exercise.catalogExerciseUUID)-component-summary",
                    exerciseNotes: resolvedNotes(for: exercise),
                    restSeconds: resolvedRest(for: exercise),
                    setDrafts: drafts,
                    isExpanded: cardStateController.isExpanded(for: exerciseID),
                    manualCompletionMode: true,
                    isBozarModeEnabled: profilePreferences.isBozarModeEnabled,
                    isSetEditingEnabled: true,
                    isSetCompletionEnabled: areMainExercisesUnlocked,
                    setCompletionGatePresentation: areMainExercisesUnlocked
                        ? nil
                        : .preWorkoutCardioRequired,
                    canMoveExerciseUp: index > 0,
                    canMoveExerciseDown: index < sessionExercises.count - 1,
                    onExerciseNotesCommitted: { notes in
                        updateNotesValue(notes, for: exerciseID)
                        persistCommittedUserEditSnapshot()
                    },
                    onSetDraftsCommitted: { drafts in
                        handleDraftsChanged(drafts, for: exercise, scrollProxy: scrollProxy)
                    },
                    onRestCommitted: { rest in
                        updateRestValue(rest, for: exerciseID)
                        persistCommittedUserEditSnapshot()
                    },
                    onExpandedChanged: { isExpanded in
                        cardStateController.setExpanded(isExpanded, for: exerciseID)
                        if isExpanded {
                            scheduleExpandedExerciseHydrationIfNeeded()
                        }
                    },
                    onSetCompletionChange: { setID, setLabel, restSeconds, isCompleted in
                        if isCompleted {
                            WorkoutFeedbackCenter.shared.setCompleted()
                            handleSetCompletionChange(
                                sourceID: setID,
                                setLabel: setLabel,
                                restSeconds: restSeconds,
                                exercise: exercise
                            )
                        } else {
                            startRestTimer(
                                seconds: 0,
                                exerciseName: exercise.exerciseNameSnapshot,
                                setLabel: setLabel,
                                sourceSetID: setID
                            )
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
                    onExerciseReplace: {
                        showExerciseReplacementPicker(for: exerciseID)
                    },
                    onExerciseDelete: {
                        removeExercise(exerciseID: exerciseID)
                    },
                    flushCoordinator: rowFlushCoordinator,
                    onInputFocusChange: { isFocused in
                        isMetricInputFocused = isFocused
                    }
                )
            } else {
                ActiveWorkoutExerciseLoadingCard(
                    exerciseAccessibilityIdentifier: "active-workout-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exerciseName,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: displayTitle ?? "Exercise \(index + 1)"
                )
                .equatable()
            }
        }
        .id(ActiveWorkoutScrollTarget.exercise(exerciseID))
        .transition(exerciseCardTransition)
    }

    @MainActor
    @ViewBuilder
    private func exerciseSection(
        for group: WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        switch group {
        case .single(let exercise, let index):
            exerciseRow(
                for: exercise,
                index: index,
                scrollProxy: scrollProxy
            )
        case .superset(let superset):
            VStack(alignment: .leading, spacing: 12) {
                ActiveWorkoutSupersetHeader(
                    roundRestSeconds: superset.roundRestSeconds
                )

                exerciseRow(
                    for: superset.first,
                    index: superset.firstIndex,
                    displayTitle: SupersetExercisePosition.first.label,
                    scrollProxy: scrollProxy
                )

                exerciseRow(
                    for: superset.second,
                    index: superset.secondIndex,
                    displayTitle: SupersetExercisePosition.second.label,
                    scrollProxy: scrollProxy
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .fill(WGJTheme.cardStrong.opacity(0.66))
                    .overlay(
                        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                            .stroke(WGJTheme.accentCyan.opacity(0.18), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("active-workout-superset-group-\(superset.groupID.uuidString.lowercased())")
            .transition(exerciseCardTransition)
        }
    }

    @MainActor
    private func renderableDrafts(for exerciseID: UUID) -> [WorkoutSessionSetDraft]? {
        if let drafts = setDraftsByExerciseID[exerciseID] {
            return drafts
        }

        return activeWorkoutPresentationState
            .preparedFirstRenderSnapshot(for: sessionID)?
            .draftsByExerciseID[exerciseID]
    }

    @MainActor
    private func resolvedDrafts(for exercise: ActiveWorkoutRuntimeExercise) -> [WorkoutSessionSetDraft] {
        renderableDrafts(for: exercise.id) ?? []
    }

    @MainActor
    private func resolvedRest(for exercise: ActiveWorkoutRuntimeExercise) -> Int {
        restByExerciseID[exercise.id]
            ?? activeWorkoutPresentationState
                .preparedFirstRenderSnapshot(for: sessionID)?
                .restsByExerciseID[exercise.id]
            ?? exercise.restSeconds
    }

    @MainActor
    private func resolvedNotes(for exercise: ActiveWorkoutRuntimeExercise) -> String {
        notesByExerciseID[exercise.id]
            ?? activeWorkoutPresentationState
                .preparedFirstRenderSnapshot(for: sessionID)?
                .notesByExerciseID[exercise.id]
            ?? exercise.notes
    }

    @MainActor
    private func updateDraftsValue(_ updated: [WorkoutSessionSetDraft], for exerciseID: UUID) {
        guard setDraftsByExerciseID[exerciseID] != updated else { return }
        setDraftsByExerciseID[exerciseID] = updated
        scheduleGuidanceRefresh(for: exerciseID)
        refreshRenderProjection()
    }

    @MainActor
    private func updateRestValue(_ updated: Int, for exerciseID: UUID) {
        let normalized = max(0, min(3600, updated))
        guard restByExerciseID[exerciseID] != normalized else { return }
        restByExerciseID[exerciseID] = normalized
        refreshRenderProjection()
    }

    @MainActor
    private func updateNotesValue(_ updated: String, for exerciseID: UUID) {
        guard notesByExerciseID[exerciseID] != updated else { return }
        notesByExerciseID[exerciseID] = updated
    }

    @MainActor
    private func refreshRenderProjection() {
        guard !isBatchingRenderProjectionRefresh else {
            needsBatchedRenderProjectionRefresh = true
            return
        }

        renderProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: runtimeSession,
            setDraftsByExerciseID: setDraftsByExerciseID,
            pendingCardioCompletionsByPhase: pendingCardioCompletionsByPhase
        )
    }

    @MainActor
    private func flushBatchedRenderProjectionIfNeeded() {
        guard needsBatchedRenderProjectionRefresh else { return }
        needsBatchedRenderProjectionRefresh = false
        renderProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: runtimeSession,
            setDraftsByExerciseID: setDraftsByExerciseID,
            pendingCardioCompletionsByPhase: pendingCardioCompletionsByPhase
        )
    }

    @MainActor
    private var areMainExercisesUnlocked: Bool {
        renderProjection.areMainExercisesUnlocked
    }

    @MainActor
    private var areAllMainExercisesCompleted: Bool {
        renderProjection.areAllMainExercisesCompleted
    }

    @MainActor
    private var isPostWorkoutCardioUnlocked: Bool {
        renderProjection.isPostWorkoutCardioUnlocked
    }

    @MainActor
    private func cardioBlock(for phase: WorkoutCardioPhase) -> ActiveWorkoutRuntimeCardioBlock? {
        renderProjection.cardioByPhase[phase]
    }

    @MainActor
    private func updateRuntimeSession(_ update: (inout ActiveWorkoutRuntimeSession) -> Void) {
        guard var updatedSession = runtimeSession else { return }
        update(&updatedSession)
        updatedSession.normalizeExerciseSortOrder()
        updatedSession.touch()
        runtimeSession = updatedSession
        refreshRenderProjection()
    }

    @MainActor
    private func applyRuntimeSessionState(_ session: ActiveWorkoutRuntimeSession) {
        runtimeSession = session
        sessionNameDraft = session.name
        notesDraft = session.notes

        setDraftsByExerciseID = Dictionary(
            session.exercises.map { ($0.id, $0.setDrafts) },
            uniquingKeysWith: { first, _ in first }
        )
        restByExerciseID = Dictionary(
            session.exercises.map { ($0.id, $0.restSeconds) },
            uniquingKeysWith: { first, _ in first }
        )
        notesByExerciseID = Dictionary(
            session.exercises.map { ($0.id, $0.notes) },
            uniquingKeysWith: { first, _ in first }
        )
        pendingCardioCompletionsByPhase = [:]
        refreshRenderProjection()
        syncExerciseCardState()
    }

    @MainActor
    private func syncExerciseCardState() {
        let completedExerciseIDs = Set(
            sessionExercises.compactMap { exercise in
                let drafts = setDraftsByExerciseID[exercise.id] ?? []
                return isExerciseCompleted(drafts) ? exercise.id : nil
            }
        )
        cardStateController.sync(
            exerciseIDs: sessionExercises.map(\.id),
            completedExerciseIDs: completedExerciseIDs,
            firstIncompleteExerciseID: areMainExercisesUnlocked
                ? firstIncompleteExerciseID(
                    from: sessionExercises,
                    draftsByExerciseID: setDraftsByExerciseID
                )
                : nil
        )

        let preparedExpandedExerciseIDs = activeWorkoutPresentationState.preparedExpandedExerciseIDs(for: sessionID)
        guard !preparedExpandedExerciseIDs.isEmpty else { return }
        cardStateController.restoreExpandedExerciseIDs(preparedExpandedExerciseIDs)
        activeWorkoutPresentationState.clearPreparedExpandedExerciseIDs(for: sessionID)
    }

    @MainActor
    private func currentRuntimeSnapshot() -> ActiveWorkoutRuntimeSession? {
        guard var snapshot = runtimeSession else { return nil }
        let normalizedName = sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedName.isEmpty {
            snapshot.name = ReviewModerationService.sanitizedForSharing(normalizedName, kind: .workoutName)
        }
        snapshot.notes = notesDraft
        snapshot.cardioBlocks = snapshot.cardioBlocks.map { cardioBlock in
            var updated = cardioBlock
            if let completion = pendingCardioCompletionsByPhase[cardioBlock.phase] {
                updated.isCompleted = completion
                updated.updatedAt = .now
            }
            return updated
        }
        snapshot.exercises = snapshot.exercises.map { exercise in
            var updated = exercise
            updated.setDrafts = setDraftsByExerciseID[exercise.id] ?? exercise.setDrafts
            updated.restSeconds = restByExerciseID[exercise.id] ?? exercise.restSeconds
            updated.notes = notesByExerciseID[exercise.id] ?? exercise.notes
            return updated
        }
        snapshot.normalizeExerciseSortOrder()
        snapshot.touch()
        return snapshot
    }

    @MainActor
    private func currentPreparedFirstRenderSnapshot() -> ActiveWorkoutPreparedFirstRenderSnapshot {
        let currentExerciseIDs = Set(sessionExercises.map(\.id))
        return ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: setDraftsByExerciseID.filter { currentExerciseIDs.contains($0.key) },
            restsByExerciseID: restByExerciseID.filter { currentExerciseIDs.contains($0.key) },
            notesByExerciseID: notesByExerciseID.filter { currentExerciseIDs.contains($0.key) },
            catalogMatchesByUUID: catalogMatchesByUUID,
            previousResolutionByExerciseID: previousResolutionByExerciseID.filter { currentExerciseIDs.contains($0.key) },
            guidanceByExerciseID: guidanceByExerciseID.filter { currentExerciseIDs.contains($0.key) }
        )
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        presentActiveWorkout()

        do {
            if let preparedSession = activeWorkoutPresentationState.preparedRuntimeSession(for: sessionID) {
                applyRuntimeSessionState(preparedSession)
                activeWorkoutPresentationState.clearPreparedRuntimeSession(for: sessionID)
            } else {
                guard let storedSession = try await ActiveWorkoutSnapshotStore.shared.load(),
                      storedSession.id == sessionID else {
                    throw WorkoutSessionRepositoryError.sessionNotFound
                }
                applyRuntimeSessionState(storedSession)
            }
        } catch {
            showError(error)
            return
        }

        guard let session else { return }
        sessionNameDraft = session.name
        notesDraft = session.notes
        await loadActiveWorkoutProfilePreferences()
        if session.templateID == nil {
            templateNameDraft = session.name == "Empty Workout" ? "New Template" : session.name
        }
        hasBootstrapped = true
    }

    @MainActor
    private func loadActiveWorkoutProfilePreferences() async {
        let loadedPreferences: ActiveWorkoutProfilePreferences?
        if let appBackgroundStore {
            loadedPreferences = try? await appBackgroundStore.perform("active-workout.profile-preferences") { backgroundContext in
                Self.profilePreferences(modelContext: backgroundContext)
            }
        } else {
            loadedPreferences = Self.profilePreferences(modelContext: modelContext)
        }

        let resolvedPreferences = Self.resolvedUITestProfilePreferences(loadedPreferences ?? .default)
        guard profilePreferences != resolvedPreferences else {
            preferredLoadUnit = resolvedPreferences.preferredLoadUnit
            return
        }

        profilePreferences = resolvedPreferences
        preferredLoadUnit = resolvedPreferences.preferredLoadUnit
        scheduleGuidanceRefreshForAll()
    }

    nonisolated private static func profilePreferences(modelContext: ModelContext) -> ActiveWorkoutProfilePreferences {
        guard let profile = try? ProfileRepository(modelContext: modelContext).currentProfile() else {
            return .default
        }

        return resolvedUITestProfilePreferences(ActiveWorkoutProfilePreferences(
            preferredLoadUnit: profile.preferredLoadUnit,
            isBozarModeEnabled: profile.isBozarModeEnabled,
            isTrainingGuidanceEnabled: profile.isTrainingGuidanceEnabled
        ))
    }

    nonisolated private static func resolvedUITestProfilePreferences(
        _ preferences: ActiveWorkoutProfilePreferences,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ActiveWorkoutProfilePreferences {
        guard environment["UITEST_ENABLE_BOZAR_MODE"] == "1" else {
            return preferences
        }

        return ActiveWorkoutProfilePreferences(
            preferredLoadUnit: preferences.preferredLoadUnit,
            isBozarModeEnabled: true,
            isTrainingGuidanceEnabled: preferences.isTrainingGuidanceEnabled
        )
    }

    @MainActor
    private func loadExerciseStateIfNeeded() async {
        let trace = WGJPerformance.begin("active-workout.hydrate")
        defer { WGJPerformance.end(trace) }

        discardRemovedExerciseState(keeping: Set(sessionExercises.map(\.id)))
        let currentStamp = exerciseHydrationStamp
        let changedExerciseIDs = currentStamp.changedExerciseIDs(comparedTo: loadedExerciseStateStamp)
        guard !changedExerciseIDs.isEmpty else { return }
        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil

        var exerciseIDsToLoad = changedExerciseIDs
        if let preparedSnapshot = activeWorkoutPresentationState.preparedFirstRenderSnapshot(for: sessionID) {
            let preparedExerciseIDs = exerciseIDsToLoad.intersection(Set(preparedSnapshot.draftsByExerciseID.keys))
            if !preparedExerciseIDs.isEmpty {
                applyPreparedFirstRenderSnapshot(preparedSnapshot, exerciseIDs: preparedExerciseIDs)
                exerciseIDsToLoad.subtract(preparedExerciseIDs)
            }
            if exerciseIDsToLoad.isEmpty {
                activeWorkoutPresentationState.clearPreparedFirstRenderSnapshot(for: sessionID)
                activeWorkoutPresentationState.clearPreparedPreviousPerformanceResolution(for: sessionID)
            }
        }

        let preparedPreviousResolutionByExerciseID = activeWorkoutPresentationState.preparedPreviousPerformanceResolution(
            for: sessionID
        )
        if !preparedPreviousResolutionByExerciseID.isEmpty {
            previousResolutionByExerciseID.merge(preparedPreviousResolutionByExerciseID) { current, _ in current }
            activeWorkoutPresentationState.clearPreparedPreviousPerformanceResolution(for: sessionID)
        }

        if !exerciseIDsToLoad.isEmpty {
            let loadingExerciseIDs = exerciseIDsToLoad
            let loadingExercises = sessionExercises.filter { loadingExerciseIDs.contains($0.id) }
            let result: ActiveWorkoutHydrationResult
            do {
                if let appBackgroundStore {
                    result = try await appBackgroundStore.perform("active-workout.hydrate.local") { backgroundContext in
                        try Self.loadHydrationResult(
                            modelContext: backgroundContext,
                            exercises: loadingExercises
                        )
                    }
                } else {
                    result = try Self.loadHydrationResult(
                        modelContext: modelContext,
                        exercises: loadingExercises
                    )
                }
            } catch {
                showError(error)
                return
            }

            setDraftsByExerciseID.merge(result.draftsByExerciseID) { _, new in new }
            restByExerciseID.merge(result.restsByExerciseID) { _, new in new }
            notesByExerciseID.merge(result.notesByExerciseID) { _, new in new }
            catalogMatchesByUUID.merge(result.catalogMatchesByUUID) { _, new in new }
            refreshRenderProjection()

            for exerciseID in loadingExerciseIDs {
                if previousResolutionByExerciseID[exerciseID] == nil {
                    previousResolutionByExerciseID[exerciseID] = .loading
                }
                componentResolutionByExerciseID[exerciseID] = nil
                guidanceByExerciseID[exerciseID] = nil
            }
        }

        let changedExercises = sessionExercises.filter { changedExerciseIDs.contains($0.id) }
        for exercise in changedExercises {
            scheduleGuidanceRefresh(for: exercise.id)
        }

        syncExerciseCardState()

        loadedExerciseStateStamp = currentStamp
        await Task.yield()
        guard !Task.isCancelled, currentStamp == exerciseHydrationStamp else { return }
        scheduleDeferredHydration(
            for: currentStamp,
            draftsByExerciseID: setDraftsByExerciseID
        )
    }

    @MainActor
    private func resolvedPreviousPerformanceResolution(for exerciseID: UUID) -> WorkoutPreviousPerformanceResolution {
        if let resolution = previousResolutionByExerciseID[exerciseID] {
            return resolution
        }

        if let preparedResolution = activeWorkoutPresentationState.preparedPreviousPerformanceResolution(
            for: sessionID,
            exerciseID: exerciseID
        ) {
            return preparedResolution
        }

        return .loading
    }

    @MainActor
    private func applyPreparedFirstRenderSnapshot(
        _ snapshot: ActiveWorkoutPreparedFirstRenderSnapshot,
        exerciseIDs: Set<UUID>
    ) {
        guard !exerciseIDs.isEmpty else { return }

        setDraftsByExerciseID.merge(snapshot.draftsByExerciseID.filter { exerciseIDs.contains($0.key) }) { _, new in new }
        restByExerciseID.merge(snapshot.restsByExerciseID.filter { exerciseIDs.contains($0.key) }) { _, new in new }
        notesByExerciseID.merge(snapshot.notesByExerciseID.filter { exerciseIDs.contains($0.key) }) { _, new in new }
        refreshRenderProjection()
        previousResolutionByExerciseID.merge(
            snapshot.previousResolutionByExerciseID.filter { exerciseIDs.contains($0.key) }
        ) { _, new in new }
        guidanceByExerciseID.merge(
            snapshot.guidanceByExerciseID.filter { exerciseIDs.contains($0.key) }
        ) { _, new in new }
        catalogMatchesByUUID.merge(snapshot.catalogMatchesByUUID) { _, new in new }
    }

    @MainActor
    private func scheduleDeferredHydration(
        for stamp: ActiveWorkoutExerciseInteractionStamp,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) {
        guard canRunNonCriticalInteractionWork else {
            deferredHydrationTask?.cancel()
            deferredHydrationTask = nil
            return
        }

        let allExerciseIDs = Set(sessionExercises.map(\.id))
        let expandedExerciseIDs = allExerciseIDs.filter { cardStateController.isExpanded(for: $0) }
        let previousExerciseIDs = allExerciseIDs.filter { exerciseID in
            guard let resolution = previousResolutionByExerciseID[exerciseID] else { return true }
            return resolution.isLoading
        }
        let componentExerciseIDs = expandedExerciseIDs.filter { componentResolutionByExerciseID[$0] == nil }
        let hydrationExerciseIDs = previousExerciseIDs.union(componentExerciseIDs)
        guard let hydrationSession = currentRuntimeSnapshot() else { return }

        guard !hydrationExerciseIDs.isEmpty else {
            deferredHydrationTask?.cancel()
            deferredHydrationTask = nil
            return
        }

        deferredHydrationTask?.cancel()
        deferredHydrationTask = Task { @MainActor in
            try? await Task.sleep(for: previousPerformanceHydrationDelay)
            guard !Task.isCancelled,
                  loadedExerciseStateStamp == stamp,
                  canRunNonCriticalInteractionWork
            else { return }

            let loadedHydration: ActiveWorkoutDeferredHydrationResult
            do {
                if let appBackgroundStore {
                    loadedHydration = try await appBackgroundStore.perform("active-workout.hydrate.deferred") { backgroundContext in
                        try Self.loadDeferredHydrationResult(
                            modelContext: backgroundContext,
                            session: hydrationSession,
                            exerciseIDs: hydrationExerciseIDs,
                            draftsByExerciseID: draftsByExerciseID
                        )
                    }
                } else {
                    loadedHydration = try Self.loadDeferredHydrationResult(
                        modelContext: modelContext,
                        session: hydrationSession,
                        exerciseIDs: hydrationExerciseIDs,
                        draftsByExerciseID: draftsByExerciseID
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                showError(error)
                deferredHydrationTask = nil
                return
            }
            guard !Task.isCancelled,
                  loadedExerciseStateStamp == stamp,
                  canRunNonCriticalInteractionWork
            else { return }
            previousResolutionByExerciseID.merge(
                loadedHydration.previousResolutionByExerciseID.filter { previousExerciseIDs.contains($0.key) }
            ) { _, new in new }
            componentResolutionByExerciseID.merge(
                loadedHydration.componentResolutionByExerciseID.filter { componentExerciseIDs.contains($0.key) }
            ) { _, new in new }
            deferredHydrationTask = nil
        }
    }

    @MainActor
    private func reconcileSessionLifecycleIfNeeded() async {
        guard hasBootstrapped else { return }
        guard !isBootstrapping else { return }

        guard session != nil else {
            guard completedSessionID == nil, !isEndingSession else {
                return
            }
            activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
            dismiss()
            return
        }
    }

    private func handleCompletedSessionTransition(_ result: ActiveWorkoutFinishResult) {
        dismissKeyboard()
        showingFinishConfirmation = false
        isCancelArmed = false
        isEndingSession = true
        completedSessionID = result.completedSessionID
        restTimerState.clearRestTimer()

        guard !pendingCompletionAfterSaveTemplateSheet else { return }
        guard !showingSaveTemplateSheet, pendingTemplateUpdatePreview == nil else { return }

        if result.completedTemplateID == nil {
            guard canCreateTemplateFromCompletedWorkout() else {
                subscriptionState.presentPaywall()
                presentWorkoutCompletionSummary()
                return
            }

            if templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                templateNameDraft = result.completedSessionName == "Empty Workout" ? "New Template" : result.completedSessionName
            }
            saveTemplateFolders = result.saveTemplateFolders
            showingSaveTemplateSheet = true
            return
        }

        if let preview = result.templateUpdatePreview {
            pendingTemplateUpdatePreview = preview
        } else {
            presentWorkoutCompletionSummary()
        }
    }

    nonisolated private static func resolvedPreviousMap(
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
    private func scheduleExpandedExerciseHydrationIfNeeded() {
        guard let loadedExerciseStateStamp else { return }
        scheduleDeferredHydration(
            for: loadedExerciseStateStamp,
            draftsByExerciseID: setDraftsByExerciseID
        )
    }

    private func handlePickedExercise(_ item: ExerciseCatalogItem, target: ActiveWorkoutPickerTarget) {
        switch target {
        case .exercise:
            addExercise(item)
        case .replaceExercise(let exerciseID):
            replaceExercise(exerciseID: exerciseID, with: item)
        case .cardio(let phase):
            upsertCardioBlock(phase: phase, catalogItem: item)
        }
    }

    private func showCardioPicker(for phase: WorkoutCardioPhase) {
        dismissKeyboard()
        pickerTarget = .cardio(phase)
    }

    private func showExerciseReplacementPicker(for exerciseID: UUID) {
        dismissKeyboard()
        pickerTarget = .replaceExercise(exerciseID)
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            guard runtimeSession != nil else { return }
            guard !sessionExercises.contains(where: { $0.catalogExerciseUUID == item.remoteUUID }) else { return }
            let nextIndex = (sessionExercises.map(\.sortOrder).max() ?? -1) + 1
            let exercise = ActiveWorkoutSessionFactory(modelContext: modelContext)
                .createExercise(from: item, sortOrder: nextIndex)
            updateRuntimeSession { session in
                session.exercises.append(exercise)
            }
            setDraftsByExerciseID[exercise.id] = exercise.setDrafts
            restByExerciseID[exercise.id] = exercise.restSeconds
            notesByExerciseID[exercise.id] = exercise.notes
            refreshRenderProjection()
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        persistCommittedUserEditSnapshot()
    }

    private func replaceExercise(exerciseID: UUID, with item: ExerciseCatalogItem) {
        guard let existingExercise = sessionExercises.first(where: { $0.id == exerciseID }) else { return }
        guard !sessionExercises.contains(where: { $0.id != exerciseID && $0.catalogExerciseUUID == item.remoteUUID }) else {
            return
        }

        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? existingExercise.setDrafts).map(\.id))
        let replacement = existingExercise.replacingExercise(
            with: item,
            preferredLoadUnit: preferredLoadUnit
        )

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            updateRuntimeSession { session in
                guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                session.exercises[index] = replacement
            }
            setDraftsByExerciseID[exerciseID] = replacement.setDrafts
            restByExerciseID[exerciseID] = replacement.restSeconds
            notesByExerciseID[exerciseID] = replacement.notes
            previousResolutionByExerciseID[exerciseID] = nil
            componentResolutionByExerciseID[exerciseID] = nil
            guidanceByExerciseID[exerciseID] = nil
            rowFlushCoordinator.setDirty(false, for: exerciseID)

            if let restTimerSourceSetID = restTimerState.restTimerSourceSetID,
               removedSetIDs.contains(restTimerSourceSetID) {
                clearRestTimerAndPersist(sourceSetID: restTimerSourceSetID)
            }

            refreshRenderProjection()
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        scheduleGuidanceRefresh(for: exerciseID)
        persistCommittedUserEditSnapshot()
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
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            updateRuntimeSession { session in
                session.exercises.move(fromOffsets: fromOffsets, toOffset: toOffset)
            }
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        persistCommittedUserEditSnapshot()
    }

    private func presentExerciseReorder(for exercise: ActiveWorkoutRuntimeExercise) {
        exerciseReorderRequest = ExerciseReorderRequest(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot
        )
    }

    private func removeExercise(exerciseID: UUID) {
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            updateRuntimeSession { session in
                session.exercises.removeAll { $0.id == exerciseID }
            }
            discardExerciseState(for: exerciseID)
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        persistCommittedUserEditSnapshot()
    }

    private func upsertCardioBlock(phase: WorkoutCardioPhase, catalogItem: ExerciseCatalogItem) {
        let existing = cardioBlock(for: phase)
        let updated = ActiveWorkoutRuntimeCardioBlock(
            id: existing?.id ?? UUID(),
            phase: phase,
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            targetDurationSeconds: existing?.targetDurationSeconds ?? phase.defaultDurationSeconds,
            isCompleted: false,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        updateRuntimeSession { session in
            session.cardioBlocks.removeAll { $0.phase == phase }
            session.cardioBlocks.append(updated)
        }
        persistCommittedUserEditSnapshot()
    }

    private func removeCardioBlock(phase: WorkoutCardioPhase) {
        updateRuntimeSession { session in
            session.cardioBlocks.removeAll { $0.phase == phase }
        }
        pendingCardioCompletionsByPhase[phase] = nil
        refreshRenderProjection()
        persistCommittedUserEditSnapshot()
    }

    private func saveCardioDuration(phase: WorkoutCardioPhase, targetDurationSeconds: Int) {
        updateRuntimeSession { session in
            guard let index = session.cardioBlocks.firstIndex(where: { $0.phase == phase }) else { return }
            session.cardioBlocks[index].targetDurationSeconds = targetDurationSeconds
            session.cardioBlocks[index].isCompleted = resolvedCardioCompletion(for: session.cardioBlocks[index])
            session.cardioBlocks[index].updatedAt = .now
        }
        persistCommittedUserEditSnapshot()
    }

    @MainActor
    private func toggleCardioCompletion(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) {
        let currentCompletion = resolvedCardioCompletion(for: cardioBlock)
        guard canToggleCompletion(for: cardioBlock) || currentCompletion else {
            return
        }

        let updatedCompletion = !currentCompletion
        pendingCardioCompletionsByPhase[cardioBlock.phase] = updatedCompletion
        refreshRenderProjection()

        if updatedCompletion {
            WorkoutFeedbackCenter.shared.exerciseCompleted()
        }
        persistCommittedUserEditSnapshot()
    }

    @MainActor
    private func handleDraftsChanged(
        _ drafts: [WorkoutSessionSetDraft],
        for exercise: ActiveWorkoutRuntimeExercise,
        scrollProxy: ScrollViewProxy
    ) {
        let previousDrafts = resolvedDrafts(for: exercise)
        let changeSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previousDrafts,
            current: drafts
        )
        updateDraftsValue(drafts, for: exercise.id)
        let isCompleted = isExerciseCompleted(drafts)
        let previouslyCompleted = cardStateController.didCompleteCurrentCycle(for: exercise.id)
        if previouslyCompleted != isCompleted {
            cardStateController.updateCompletion(
                for: exercise.id,
                isCompleted: isCompleted
            )
            if isCompleted {
                WorkoutFeedbackCenter.shared.exerciseCompleted()
            }
            reanchorCompletedExerciseIfNeeded(
                exerciseID: exercise.id,
                didTransitionToCompleted: isCompleted,
                using: scrollProxy
            )
        }
        persistCommittedUserEditSnapshot(
            writeDurableSnapshot: ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(
                for: changeSummary
            )
        )
    }

    @MainActor
    private func reanchorCompletedExerciseIfNeeded(
        exerciseID: UUID,
        didTransitionToCompleted: Bool,
        using scrollProxy: ScrollViewProxy
    ) {
        guard let target = ActiveWorkoutCompletionScrollPolicy.targetAfterAutoCollapse(
            exerciseID: exerciseID,
            didTransitionToCompleted: didTransitionToCompleted
        ) else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollProxy.scrollTo(target, anchor: .top)
            }
        }
    }

    @MainActor
    private func handleSetCompletionChange(
        sourceID: UUID,
        setLabel: String?,
        restSeconds: Int,
        exercise: ActiveWorkoutRuntimeExercise
    ) {
        let drafts = resolvedDrafts(for: exercise)
        guard let source = completionSourceContext(sourceID: sourceID, drafts: drafts) else {
            startRestTimer(
                seconds: restSeconds,
                exerciseName: exercise.exerciseNameSnapshot,
                setLabel: setLabel,
                sourceSetID: sourceID
            )
            return
        }

        guard source.completesSetCycle else {
            clearRestTimerAndPersist(sourceSetID: sourceID)
            return
        }

        let resolvedRestSeconds: Int
        if let supersetContext = supersetContextByExerciseID[exercise.id],
           supersetContext.position == .second {
            resolvedRestSeconds = supersetContext.roundRestSeconds
        } else {
            resolvedRestSeconds = restSeconds
        }

        startRestTimer(
            seconds: resolvedRestSeconds,
            exerciseName: exercise.exerciseNameSnapshot,
            setLabel: setLabel,
            sourceSetID: sourceID
        )
    }

    @MainActor
    private func completionSourceContext(
        sourceID: UUID,
        drafts: [WorkoutSessionSetDraft]
    ) -> ActiveWorkoutCompletionSourceContext? {
        for (setIndex, draft) in drafts.enumerated() {
            if draft.id == sourceID {
                return ActiveWorkoutCompletionSourceContext(
                    setIndex: setIndex,
                    completesSetCycle: !draft.hasDropset
                )
            }

            if let dropStageIndex = draft.dropStages.firstIndex(where: { $0.id == sourceID }) {
                return ActiveWorkoutCompletionSourceContext(
                    setIndex: setIndex,
                    completesSetCycle: dropStageIndex == draft.dropStages.count - 1
                )
            }
        }

        return nil
    }

    @MainActor
    private func setCycleCompletionStates(for exerciseID: UUID) -> [Bool] {
        guard let exercise = sessionExercises.first(where: { $0.id == exerciseID }) else {
            return []
        }

        return resolvedDrafts(for: exercise).map(\.isCycleCompleted)
    }

    private func startRestTimer(
        seconds: Int,
        exerciseName: String,
        setLabel: String?,
        sourceSetID: UUID
    ) {
        if seconds > 0 {
            restTimerState.startRestTimer(
                seconds: seconds,
                exerciseName: exerciseName,
                setLabel: setLabel,
                sourceSetID: sourceSetID
            )
            persistCommittedUserEditSnapshot()
        } else {
            restTimerState.clearRestTimer(sourceSetID: sourceSetID)
            persistCommittedUserEditSnapshot()
        }
    }

    private func clearRestTimerAndPersist(
        sourceSetID: UUID? = nil,
        cancelNotification: Bool = true
    ) {
        guard restTimerState.clearRestTimer(
            sourceSetID: sourceSetID,
            cancelNotification: cancelNotification
        ) else {
            return
        }
        persistCommittedUserEditSnapshot()
    }

    private func isExerciseCompleted(_ drafts: [WorkoutSessionSetDraft]) -> Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isCycleCompleted)
    }

    private var isTrainingGuidanceEnabled: Bool {
        profilePreferences.isTrainingGuidanceEnabled
    }

    private var canRunNonCriticalInteractionWork: Bool {
        ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(
            scenePhase: scenePhase,
            isMetricInputFocused: isMetricInputFocused
        )
    }

    @MainActor
    private func refreshGuidanceCache() {
        guidanceByExerciseID = buildGuidanceCache(
            draftsByExerciseID: setDraftsByExerciseID,
            catalogMatchesByUUID: catalogMatchesByUUID
        )
    }

    @MainActor
    private func scheduleGuidanceRefresh(for exerciseID: UUID) {
        guard isTrainingGuidanceEnabled else {
            guidanceByExerciseID[exerciseID] = nil
            return
        }

        guard canRunNonCriticalInteractionWork else {
            pendingGuidanceRefreshExerciseIDs.insert(exerciseID)
            pendingGuidanceRefreshTask?.cancel()
            pendingGuidanceRefreshTask = nil
            return
        }

        pendingGuidanceRefreshExerciseIDs.insert(exerciseID)
        pendingGuidanceRefreshTask?.cancel()
        pendingGuidanceRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: guidanceRefreshDelay)
            guard !Task.isCancelled,
                  canRunNonCriticalInteractionWork
            else { return }
            flushScheduledGuidanceRefresh()
            pendingGuidanceRefreshTask = nil
        }
    }

    @MainActor
    private func scheduleGuidanceRefreshForAll() {
        guard canRunNonCriticalInteractionWork else {
            shouldRefreshAllGuidance = true
            pendingGuidanceRefreshExerciseIDs = []
            pendingGuidanceRefreshTask?.cancel()
            pendingGuidanceRefreshTask = nil
            return
        }

        shouldRefreshAllGuidance = true
        pendingGuidanceRefreshExerciseIDs = []
        pendingGuidanceRefreshTask?.cancel()
        pendingGuidanceRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: guidanceRefreshDelay)
            guard !Task.isCancelled,
                  canRunNonCriticalInteractionWork
            else { return }
            flushScheduledGuidanceRefresh()
            pendingGuidanceRefreshTask = nil
        }
    }

    @MainActor
    private func flushScheduledGuidanceRefresh() {
        if shouldRefreshAllGuidance {
            shouldRefreshAllGuidance = false
            pendingGuidanceRefreshExerciseIDs = []
            refreshGuidanceCache()
            return
        }

        let exerciseIDs = pendingGuidanceRefreshExerciseIDs
        pendingGuidanceRefreshExerciseIDs = []
        for exerciseID in exerciseIDs {
            refreshGuidance(for: exerciseID)
        }
    }

    @MainActor
    private func refreshGuidance(for exerciseID: UUID) {
        guard let exercise = sessionExercises.first(where: { $0.id == exerciseID }) else {
            guidanceByExerciseID[exerciseID] = nil
            return
        }

        guidanceByExerciseID[exerciseID] = guidancePresentation(
            for: exercise,
            drafts: resolvedDrafts(for: exercise)
        )
    }

    @MainActor
    private func buildGuidanceCache(
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]],
        catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot]
    ) -> [UUID: ActiveWorkoutExerciseGuidancePresentation?] {
        guard isTrainingGuidanceEnabled else {
            return Dictionary(
                sessionExercises.map { ($0.id, nil as ActiveWorkoutExerciseGuidancePresentation?) },
                uniquingKeysWith: { existing, _ in existing }
            )
        }

        return Dictionary(sessionExercises.map { exercise in
            let drafts = draftsByExerciseID[exercise.id] ?? []
            let guidance: ActiveWorkoutExerciseGuidancePresentation?
            if let catalogExercise = catalogMatchesByUUID[exercise.catalogExerciseUUID] {
                guidance = WGJPerformance.measure("active-workout.guidance") {
                    guidanceService.activeWorkoutGuidance(
                        for: catalogExercise,
                        targetRepMin: exercise.targetRepMin,
                        targetRepMax: exercise.targetRepMax,
                        setDrafts: drafts
                    )
                }
            } else {
                guidance = WGJPerformance.measure("active-workout.guidance") {
                    guidanceService.activeWorkoutGuidance(
                        for: TrainingGuidanceCatalogSnapshot(
                            exerciseName: exercise.exerciseNameSnapshot,
                            categoryName: exercise.categorySnapshot,
                            equipmentSummary: "",
                            primaryMuscleNames: exercise.muscleSummarySnapshot
                        ),
                        targetRepMin: exercise.targetRepMin,
                        targetRepMax: exercise.targetRepMax,
                        setDrafts: drafts
                    )
                }
            }
            return (exercise.id, guidance)
        }, uniquingKeysWith: { existing, _ in existing })
    }

    @MainActor
    private func guidancePresentation(
        for exercise: ActiveWorkoutRuntimeExercise,
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
    private func firstIncompleteExerciseID(
        from exercises: [ActiveWorkoutRuntimeExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> UUID? {
        for exercise in exercises {
            let drafts = draftsByExerciseID[exercise.id] ?? []
            if !isExerciseCompleted(drafts) {
                return exercise.id
            }
        }
        return nil
    }

    @MainActor
    private func allExercisesCompleted(
        from exercises: [ActiveWorkoutRuntimeExercise],
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) -> Bool {
        exercises.allSatisfy { exercise in
            let drafts = draftsByExerciseID[exercise.id] ?? []
            return isExerciseCompleted(drafts)
        }
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var previousPerformanceHydrationDelay: Duration {
        ActiveWorkoutInteractionWorkPolicy.previousPerformanceHydrationDelay()
    }

    private var guidanceRefreshDelay: Duration {
        ActiveWorkoutInteractionWorkPolicy.defaultGuidanceRefreshDelay
    }

    private func showExerciseSettings(for exercise: ActiveWorkoutRuntimeExercise) {
        dismissKeyboard()
        exerciseSettingsDraft = ActiveWorkoutExerciseSettingsDraft(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot,
            minRepsText: exercise.targetRepMin.map(String.init) ?? "",
            maxRepsText: exercise.targetRepMax.map(String.init) ?? "",
            restSeconds: restByExerciseID[exercise.id] ?? exercise.restSeconds
        )
    }

    private func showExerciseComponentPicker(for exercise: ActiveWorkoutRuntimeExercise) {
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
        guard sessionExercises.contains(where: { $0.id == draft.exerciseID }) else {
            showError(WorkoutSessionRepositoryError.sessionExerciseNotFound)
            return
        }

        let minReps = parsedRepValue(from: draft.minRepsText)
        let maxReps = parsedRepValue(from: draft.maxRepsText)
        let normalizedRest = max(0, min(3600, draft.restSeconds))

        updateRuntimeSession { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == draft.exerciseID }) else { return }
            session.exercises[index].targetRepMin = minReps
            session.exercises[index].targetRepMax = maxReps
            session.exercises[index].restSeconds = normalizedRest
            session.exercises[index].updatedAt = .now
        }
        restByExerciseID[draft.exerciseID] = normalizedRest
        applyPersistedRestChange(
            sessionExerciseID: draft.exerciseID,
            updatedRest: normalizedRest
        )
        refreshRenderProjection()
        exerciseSettingsDraft = nil
        scheduleGuidanceRefresh(for: draft.exerciseID)
        persistCommittedUserEditSnapshot()
    }

    private func saveExerciseComponentSelection(exerciseID: UUID, componentID: UUID) {
        guard let component = componentResolutionByExerciseID[exerciseID]?.availableComponents.first(where: { $0.id == componentID }) else {
            return
        }
        updateRuntimeSession { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            session.exercises[index].catalogExerciseUUID = component.catalogExerciseUUID
            session.exercises[index].exerciseNameSnapshot = component.exerciseNameSnapshot
            session.exercises[index].categorySnapshot = component.categorySnapshot
            session.exercises[index].muscleSummarySnapshot = component.muscleSummarySnapshot
            session.exercises[index].updatedAt = .now
        }
        exerciseComponentPickerDraft = nil
        loadedExerciseStateStamp = nil
        exerciseHydrationInvalidation += 1
        persistCommittedUserEditSnapshot()
    }

    private func finishWorkout() {
        Task { @MainActor in
            dismissKeyboard()
            pendingFinishAfterConfirmation = false
            isCancelArmed = false
            guard !isEndingSession else { return }
            isEndingSession = true
            rowFlushCoordinator.flushAll()
            await pendingUserEditSnapshotTask?.value
            pendingUserEditSnapshotTask = nil
            guard let finishingSession = currentRuntimeSnapshot() else {
                isEndingSession = false
                showError(WorkoutSessionRepositoryError.sessionNotFound)
                return
            }
            restTimerState.clearRestTimer()
            let finalNotes = notesDraft

            do {
                let result = try await performFinishCommand(session: finishingSession, notes: finalNotes)
                do {
                    try await ActiveWorkoutSnapshotStore.shared.delete()
                } catch {
                    NSLog("WGJ active workout snapshot cleanup failed after completion: \(error.localizedDescription)")
                }
                handleCompletedSessionTransition(result)
            } catch {
                isEndingSession = false
                showError(error)
            }
        }
    }

    private func saveSessionAsTemplate() {
        Task { @MainActor in
            dismissKeyboard()
            guard canCreateTemplateFromCompletedWorkout() else {
                showingSaveTemplateSheet = false
                subscriptionState.presentPaywall()
                presentWorkoutCompletionSummary()
                return
            }

            let templateName = templateNameDraft
            let selectedFolderID = templateFolderID
            do {
                if let appBackgroundStore {
                    _ = try await appBackgroundStore.performWrite("active-workout.template.create-from-session") { backgroundContext in
                        let repository = TemplateRepository(modelContext: backgroundContext, autoSaveChanges: false)
                        let template = try repository.createTemplate(
                            fromSessionID: sessionID,
                            name: templateName,
                            folderID: selectedFolderID
                        )
                        try repository.finalizeDeferredUserDataChangesIfNeeded()
                        return template.id
                    }
                } else {
                    let repository = TemplateRepository(modelContext: modelContext, autoSaveChanges: false)
                    _ = try repository.createTemplate(
                        fromSessionID: sessionID,
                        name: templateName,
                        folderID: selectedFolderID
                    )
                    try repository.finalizeDeferredUserDataChangesIfNeeded()
                }
                requestCompletionAfterSaveTemplateSheetDismissal()
            } catch {
                showError(error)
            }
        }
    }

    private func canCreateTemplateFromCompletedWorkout() -> Bool {
        do {
            return ProAccessPolicy.canCreateTemplate(
                currentTemplateCount: try templateRepository.templates().count,
                isPro: subscriptionState.isPro
            )
        } catch {
            showError(error)
            return false
        }
    }

    private func skipSavingSessionAsTemplate() {
        dismissKeyboard()
        requestCompletionAfterSaveTemplateSheetDismissal()
    }

    private func handleSaveTemplateSheetDismissed() {
        guard pendingCompletionAfterSaveTemplateSheet else { return }
        presentWorkoutCompletionSummary()
    }

    private func handleTemplateReviewSheetDismissed() {
        if let preview = pendingTemplateUpdateAfterReviewSheetDismissal {
            pendingTemplateUpdateAfterReviewSheetDismissal = nil
            applyTemplateUpdate(preview)
            return
        }

        guard pendingCompletionAfterTemplateReviewSheet else { return }
        presentWorkoutCompletionSummary()
    }

    private func requestCompletionAfterSaveTemplateSheetDismissal() {
        pendingCompletionAfterSaveTemplateSheet = true
        showingSaveTemplateSheet = false
    }

    private func requestCompletionAfterTemplateReviewSheetDismissal() {
        pendingCompletionAfterTemplateReviewSheet = true
        pendingTemplateUpdateAfterReviewSheetDismissal = nil
        pendingTemplateUpdatePreview = nil
    }

    private func requestTemplateUpdateAfterReviewSheetDismissal(_ preview: WorkoutTemplateSyncPreview) {
        pendingCompletionAfterTemplateReviewSheet = false
        pendingTemplateUpdateAfterReviewSheetDismissal = preview
        pendingTemplateUpdatePreview = nil
    }

    private func presentWorkoutCompletionSummary() {
        dismissKeyboard()
        isCancelArmed = false
        showingSaveTemplateSheet = false
        pendingCompletionAfterSaveTemplateSheet = false
        pendingCompletionAfterTemplateReviewSheet = false
        pendingTemplateUpdateAfterReviewSheetDismissal = nil
        exerciseSettingsDraft = nil
        exerciseComponentPickerDraft = nil
        pendingTemplateUpdatePreview = nil
        let completionSessionID = completedSessionID ?? sessionID
        workoutCompletionPresentationState.queueAfterActiveWorkoutDismiss(sessionID: completionSessionID)
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
    }

    private func minimizeWorkout() {
        dismissKeyboard()
        isCancelArmed = false
        stageMinimizedRuntimeState()
        collapseActiveWorkout()
        dismiss()
    }

    @MainActor
    private func stageMinimizedRuntimeState() {
        rowFlushCoordinator.flushAll()
        guard let snapshot = currentRuntimeSnapshot() else { return }
        runtimeSession = snapshot
        pendingCardioCompletionsByPhase = [:]
        refreshRenderProjection()
        activeWorkoutPresentationState.stageRuntimeSession(snapshot, for: sessionID)
        activeWorkoutPresentationState.stagePreparedFirstRenderSnapshot(
            currentPreparedFirstRenderSnapshot(),
            for: sessionID
        )
        activeWorkoutPresentationState.stageExpandedExerciseIDs(
            cardStateController.expandedExerciseIDs(),
            for: sessionID
        )
        activeWorkoutPresentationState.stageScrollTarget(minimizedScrollRestoreTarget(), for: sessionID)
    }

    @MainActor
    private func minimizedScrollRestoreTarget() -> ActiveWorkoutScrollTarget? {
        ActiveWorkoutMinimizeScrollRestorePolicy.target(
            currentScrollTarget: currentScrollTarget,
            expandedExerciseIDs: cardStateController.expandedExerciseIDs(),
            orderedExerciseIDs: sessionExercises.map(\.id),
            hasPreWorkoutCardio: preWorkoutCardio != nil,
            hasPostWorkoutCardio: postWorkoutCardio != nil
        )
    }

    private func presentActiveWorkout() {
        activeWorkoutPresentationState.present(sessionID: sessionID)
    }

    private func collapseActiveWorkout() {
        activeWorkoutPresentationState.collapseActiveWorkout()
    }

    private func cancelWorkout() {
        Task { @MainActor in
            dismissKeyboard()
            isCancelArmed = false
            guard !isEndingSession else { return }
            isEndingSession = true
            rowFlushCoordinator.flushAll()
            await pendingUserEditSnapshotTask?.value
            pendingUserEditSnapshotTask = nil
            restTimerState.clearRestTimer()

            do {
                try await ActiveWorkoutSnapshotStore.shared.delete()
                activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
                dismiss()
            } catch {
                isEndingSession = false
                showError(error)
            }
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
        Task { @MainActor in
            do {
                if let appBackgroundStore {
                    try await appBackgroundStore.performWrite("active-workout.template.apply-sync") { backgroundContext in
                        try WorkoutTemplateSyncService(modelContext: backgroundContext).applyTemplateUpdate(preview)
                    }
                } else {
                    try templateSyncService.applyTemplateUpdate(preview)
                }
                presentWorkoutCompletionSummary()
            } catch {
                showError(error)
            }
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
            .union(previousResolutionByExerciseID.keys)
            .union(componentResolutionByExerciseID.keys)
            .union(guidanceByExerciseID.keys)

        for exerciseID in knownIDs where !currentIDs.contains(exerciseID) {
            discardExerciseState(for: exerciseID)
        }
    }

    @MainActor
    private func discardExerciseState(for exerciseID: UUID) {
        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? []).map(\.id))

        setDraftsByExerciseID[exerciseID] = nil
        restByExerciseID[exerciseID] = nil
        notesByExerciseID[exerciseID] = nil
        previousResolutionByExerciseID[exerciseID] = nil
        componentResolutionByExerciseID[exerciseID] = nil
        guidanceByExerciseID[exerciseID] = nil

        if let restTimerSourceSetID = restTimerState.restTimerSourceSetID,
           removedSetIDs.contains(restTimerSourceSetID) {
            clearRestTimerAndPersist(sourceSetID: restTimerSourceSetID)
        }
        refreshRenderProjection()
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
                setDraftsByExerciseID[exercise.id] ?? []
            },
            cardioBlocks: orderedCardioBlocks.map(resolvedCardioDraft)
        )
    }

    nonisolated private static func loadHydrationResult(
        modelContext: ModelContext,
        exercises: [ActiveWorkoutRuntimeExercise]
    ) throws -> ActiveWorkoutHydrationResult {
        guard !exercises.isEmpty else {
            return ActiveWorkoutHydrationResult(
                draftsByExerciseID: [:],
                restsByExerciseID: [:],
                notesByExerciseID: [:],
                catalogMatchesByUUID: [:]
            )
        }

        let catalogByUUID = try loadCatalogSnapshots(
            modelContext: modelContext,
            remoteUUIDs: Array(Set(exercises.map(\.catalogExerciseUUID)))
        )

        var loadedDrafts: [UUID: [WorkoutSessionSetDraft]] = [:]
        var loadedRests: [UUID: Int] = [:]
        var loadedNotes: [UUID: String] = [:]

        for exercise in exercises {
            let normalizedDrafts = Self.normalizedDraftsForActiveLogging(
                exercise.setDrafts,
                catalogExercise: catalogByUUID[exercise.catalogExerciseUUID]
            )
            loadedDrafts[exercise.id] = normalizedDrafts
            loadedRests[exercise.id] = exercise.restSeconds
            loadedNotes[exercise.id] = exercise.notes
        }

        return ActiveWorkoutHydrationResult(
            draftsByExerciseID: loadedDrafts,
            restsByExerciseID: loadedRests,
            notesByExerciseID: loadedNotes,
            catalogMatchesByUUID: catalogByUUID
        )
    }

    nonisolated private static func loadDeferredHydrationResult(
        modelContext: ModelContext,
        session: ActiveWorkoutRuntimeSession,
        exerciseIDs: Set<UUID>,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) throws -> ActiveWorkoutDeferredHydrationResult {
        guard !exerciseIDs.isEmpty else {
            return ActiveWorkoutDeferredHydrationResult(
                previousResolutionByExerciseID: [:],
                componentResolutionByExerciseID: [:]
            )
        }

        let targetExercises = session.exercises.filter { exerciseIDs.contains($0.id) }
        let previousMaps = try WorkoutSessionRepository(modelContext: modelContext).previousSetMaps(
            forExercises: Array(Set(targetExercises.map(\.catalogExerciseUUID))),
            before: session.startedAt,
            excludingSessionID: session.id
        )

        var previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution] = [:]
        var componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
        let componentResolver = TemplateExerciseComponentRotationResolver(modelContext: modelContext)

        for exercise in targetExercises {
            let drafts = draftsByExerciseID[exercise.id] ?? orderedSessionSetDrafts(for: exercise)
            previousResolutionByExerciseID[exercise.id] = .resolved(
                Self.resolvedPreviousMap(
                    baseMap: previousMaps[exercise.catalogExerciseUUID] ?? [:],
                    maxSetCount: drafts.count
                )
            )

            if let templateID = session.templateID,
               let templateExerciseID = exercise.templateExerciseID,
               let resolution = try? componentResolver.resolution(
                    templateID: templateID,
                    templateExerciseID: templateExerciseID,
                    components: exercise.components.map(ExerciseComponentSnapshot.init(model:)),
                    before: session.startedAt,
                    selectedCatalogExerciseUUID: exercise.catalogExerciseUUID,
                    excludingSessionID: session.id
               ) {
                componentResolutionByExerciseID[exercise.id] = resolution
            }
        }

        return ActiveWorkoutDeferredHydrationResult(
            previousResolutionByExerciseID: previousResolutionByExerciseID,
            componentResolutionByExerciseID: componentResolutionByExerciseID
        )
    }

    nonisolated private static func loadCatalogSnapshots(
        modelContext: ModelContext,
        remoteUUIDs: [String]
    ) throws -> [String: TrainingGuidanceCatalogSnapshot] {
        let requestedUUIDs = Set(
            remoteUUIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !requestedUUIDs.isEmpty else { return [:] }

        let requestedList = Array(requestedUUIDs)
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                requestedList.contains(exercise.remoteUUID)
            }
        )
        let matches = try modelContext.fetch(descriptor)
        return Dictionary(
            matches.map { ($0.remoteUUID, TrainingGuidanceCatalogSnapshot(exercise: $0)) },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    nonisolated private static func orderedSessionSetDrafts(for exercise: ActiveWorkoutRuntimeExercise) -> [WorkoutSessionSetDraft] {
        exercise.setDrafts
    }

    nonisolated private static func normalizedDraftsForActiveLogging(
        _ drafts: [WorkoutSessionSetDraft],
        catalogExercise: TrainingGuidanceCatalogSnapshot?
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
    private func flushDirtyWritesNow(checkpoint: ActiveWorkoutLifecycleCheckpoint) async -> Bool {
        if checkpoint == .sceneTransition,
           !rowFlushCoordinator.hasDirtyRows,
           pendingUserEditSnapshotTask == nil {
            return true
        }

        let shouldBatchProjectionRefresh = checkpoint == .sceneTransition
        if shouldBatchProjectionRefresh {
            isBatchingRenderProjectionRefresh = true
            needsBatchedRenderProjectionRefresh = false
        }

        switch checkpoint {
        case .sceneTransition:
            rowFlushCoordinator.flushDirty()
        case .finish, .cancel, .minimize, .userEdit:
            rowFlushCoordinator.flushAll()
        }

        if shouldBatchProjectionRefresh {
            isBatchingRenderProjectionRefresh = false
            flushBatchedRenderProjectionIfNeeded()
        }

        let pendingSnapshotTask = pendingUserEditSnapshotTask
        pendingUserEditSnapshotTask = nil

        if checkpoint == .sceneTransition {
            pendingSnapshotTask?.cancel()
            await pendingSnapshotTask?.value

            guard let snapshot = currentRuntimeSnapshot() else {
                pendingCardioCompletionsByPhase = [:]
                return true
            }

            runtimeSession = snapshot
            pendingCardioCompletionsByPhase = [:]
            refreshRenderProjection()

            do {
                try await ActiveWorkoutSnapshotStore.shared.save(
                    snapshot,
                    restTimer: restTimerState.restTimerSnapshot(),
                    preservesExistingRestTimer: false
                )
                return true
            } catch {
                showError(error)
                return false
            }
        }

        pendingSnapshotTask?.cancel()
        await pendingSnapshotTask?.value

        switch checkpoint {
        case .finish, .cancel:
            return true
        case .minimize, .sceneTransition, .userEdit:
            break
        }

        guard let snapshot = currentRuntimeSnapshot() else {
            pendingCardioCompletionsByPhase = [:]
            return true
        }

        runtimeSession = snapshot
        pendingCardioCompletionsByPhase = [:]
        refreshRenderProjection()
        guard ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: checkpoint) else {
            return true
        }

        do {
            try await ActiveWorkoutSnapshotStore.shared.save(
                snapshot,
                restTimer: restTimerState.restTimerSnapshot(),
                preservesExistingRestTimer: false
            )
            return true
        } catch {
            showError(error)
            return false
        }
    }

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: newPhase) {
            dismissKeyboard()
        }

        // Foreground return must stay memory-only; non-critical work resumes from explicit user interactions.
        if ActiveWorkoutInteractionWorkPolicy.shouldCancelNonCriticalInteractionWork(scenePhase: newPhase) {
            cancelNonCriticalInteractionWorkForSceneTransition()
        }

        guard ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: newPhase) else {
            return
        }

        Task { @MainActor in
            _ = await flushDirtyWritesNow(checkpoint: .sceneTransition)
        }
    }

    @MainActor
    private func cancelNonCriticalInteractionWorkForSceneTransition() {
        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil
        foregroundNonCriticalInteractionWorkTask?.cancel()
        foregroundNonCriticalInteractionWorkTask = nil
        pendingGuidanceRefreshTask?.cancel()
        pendingGuidanceRefreshTask = nil
    }

    @MainActor
    private func scheduleForegroundNonCriticalInteractionWorkResume() {
        guard loadedExerciseStateStamp != nil || shouldRefreshAllGuidance || !pendingGuidanceRefreshExerciseIDs.isEmpty else {
            return
        }

        foregroundNonCriticalInteractionWorkTask?.cancel()
        foregroundNonCriticalInteractionWorkTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    foregroundNonCriticalInteractionWorkTask = nil
                }
            }
            try? await Task.sleep(for: ActiveWorkoutInteractionWorkPolicy.foregroundResumeGraceDelay)
            guard !Task.isCancelled,
                  canRunNonCriticalInteractionWork
            else { return }

            scheduleExpandedExerciseHydrationIfNeeded()
            if shouldRefreshAllGuidance {
                scheduleGuidanceRefreshForAll()
            } else {
                let pendingExerciseIDs = pendingGuidanceRefreshExerciseIDs
                for exerciseID in pendingExerciseIDs {
                    scheduleGuidanceRefresh(for: exerciseID)
                }
            }
        }
    }

    @MainActor
    private func persistCommittedUserEditSnapshot(writeDurableSnapshot: Bool = true) {
        guard !isEndingSession else { return }
        guard let snapshot = currentRuntimeSnapshot() else {
            pendingCardioCompletionsByPhase = [:]
            return
        }

        runtimeSession = snapshot
        pendingCardioCompletionsByPhase = [:]
        refreshRenderProjection()
        activeWorkoutPresentationState.stageRuntimeSession(snapshot, for: sessionID)
        activeWorkoutPresentationState.stagePreparedFirstRenderSnapshot(
            currentPreparedFirstRenderSnapshot(),
            for: sessionID
        )

        guard writeDurableSnapshot,
              ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .userEdit)
        else {
            return
        }

        pendingUserEditSnapshotTask?.cancel()
        pendingUserEditSnapshotTask = Task { @MainActor in
            do {
                try await ActiveWorkoutSnapshotStore.shared.save(
                    snapshot,
                    restTimer: restTimerState.restTimerSnapshot(),
                    preservesExistingRestTimer: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                showError(error)
            }
        }
    }

    private func performFinishCommand(
        session: ActiveWorkoutRuntimeSession,
        notes: String
    ) async throws -> ActiveWorkoutFinishResult {
        try await WGJPerformance.measureAsync("active-workout.finish") {
            if let appBackgroundStore {
                return try await appBackgroundStore.performWrite("active-workout.finish") { backgroundContext in
                    try Self.finishSession(
                        session: session,
                        notes: notes,
                        modelContext: backgroundContext
                    )
                }
            }

            return try Self.finishSession(
                session: session,
                notes: notes,
                modelContext: modelContext
            )
        }
    }

    nonisolated private static func finishSession(
        session runtimeSession: ActiveWorkoutRuntimeSession,
        notes: String,
        modelContext: ModelContext
    ) throws -> ActiveWorkoutFinishResult {
        let finishedSessionID = try ActiveWorkoutCompletionWriter(modelContext: modelContext)
            .finish(session: runtimeSession, notes: notes)
        let completedSessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        guard let completedSession = try completedSessionRepository.session(id: finishedSessionID) else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let folderSnapshots: [ActiveWorkoutTemplateFolderSnapshot]
        let templateUpdatePreview: WorkoutTemplateSyncPreview?
        if completedSession.templateID == nil {
            folderSnapshots = try TemplateRepository(modelContext: modelContext)
                .folders()
                .map(ActiveWorkoutTemplateFolderSnapshot.init(folder:))
            templateUpdatePreview = nil
        } else {
            folderSnapshots = []
            templateUpdatePreview = try WorkoutTemplateSyncService(modelContext: modelContext)
                .previewTemplateUpdate(forSessionID: completedSession.id)
        }

        return ActiveWorkoutFinishResult(
            completedSessionID: completedSession.id,
            completedSessionName: completedSession.name,
            completedTemplateID: completedSession.templateID,
            saveTemplateFolders: folderSnapshots,
            templateUpdatePreview: templateUpdatePreview
        )
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
    private func scrollToTarget(
        _ target: ActiveWorkoutScrollTarget,
        using scrollProxy: ScrollViewProxy,
        anchor: UnitPoint = .top,
        animation: Animation? = nil
    ) {
        let resolvedAnimation = animation ?? WGJMotion.cardAnimation(reduceMotion: reduceMotion)
        withAnimation(resolvedAnimation) {
            scrollProxy.scrollTo(target, anchor: anchor)
        }
    }

    @MainActor
    private func restorePreparedScrollTargetIfNeeded(using scrollProxy: ScrollViewProxy) {
        guard hasWorkoutContent else { return }
        guard let target = activeWorkoutPresentationState.preparedScrollTarget(for: sessionID) else { return }
        guard restoredScrollTarget != target else { return }
        restoredScrollTarget = target

        var immediateTransaction = Transaction()
        immediateTransaction.disablesAnimations = true
        withTransaction(immediateTransaction) {
            scrollProxy.scrollTo(target, anchor: .top)
        }

        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollProxy.scrollTo(target, anchor: .top)
            }
        }
    }

    @MainActor
    private func canToggleCompletion(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        switch cardioBlock.phase {
        case .preWorkout:
            return true
        case .postWorkout:
            return isPostWorkoutCardioUnlocked
        }
    }

    @MainActor
    private func resolvedCardioCompletion(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        pendingCardioCompletionsByPhase[cardioBlock.phase] ?? cardioBlock.isCompleted
    }

    @MainActor
    private func resolvedCardioDraft(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> WorkoutCardioBlockDraft {
        WorkoutCardioBlockDraft(
            id: cardioBlock.id,
            phase: cardioBlock.phase,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            targetDurationSeconds: cardioBlock.targetDurationSeconds,
            isCompleted: resolvedCardioCompletion(for: cardioBlock)
        )
    }

    @MainActor
    private func cardioStatusText(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> String {
        if resolvedCardioCompletion(for: cardioBlock) {
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
    private func cardioStatusTint(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> Color {
        if resolvedCardioCompletion(for: cardioBlock) {
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
    private func cardioFootnote(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> String {
        switch cardioBlock.phase {
        case .preWorkout:
            return resolvedCardioCompletion(for: cardioBlock)
                ? "Warmup complete. Main exercise logging is unlocked."
                : "Finish this warmup block before logging or completing sets."
        case .postWorkout:
            if resolvedCardioCompletion(for: cardioBlock) {
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
    private func makeCardioSettingsDraft(from cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> WorkoutCardioSettingsDraft {
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

    let session: ActiveWorkoutRuntimeSession
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

            WGJResponsiveTextField(
                placeholder: "Workout name",
                text: $sessionNameDraft,
                capitalization: .words,
                accessibilityIdentifier: "active-workout-name-field",
                onSubmit: onSubmit
            )

            WGJResponsiveTextField(
                placeholder: "Notes",
                text: $notesDraft,
                axis: .vertical,
                lineLimit: 2...4,
                capitalization: .sentences,
                accessibilityIdentifier: "active-workout-notes-field",
                onSubmit: onSubmit
            )

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

private struct ActiveWorkoutExerciseLoadingCard: View, Equatable {
    let exerciseAccessibilityIdentifier: String
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String

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

                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(WGJTheme.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WGJTheme.field)
                    )
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

        return "Track the working sets below."
    }
}

private struct ActiveWorkoutBottomDock: View {
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutRuntimeSession?
    let reduceMotion: Bool
    let onDismissRestTimer: () -> Void

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
                ActiveWorkoutActivityTimerDock(
                    session: session,
                    onDismissRestTimer: onDismissRestTimer
                )
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
        .accessibilityIdentifier(
            restTimerState.restTimerEndsAt == nil
                ? "active-workout-elapsed-timer"
                : "active-workout-rest-timer"
        )
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

private struct ActiveWorkoutProfilePreferences: Equatable {
    let preferredLoadUnit: TemplateLoadUnit
    let isBozarModeEnabled: Bool
    let isTrainingGuidanceEnabled: Bool

    nonisolated static let `default` = ActiveWorkoutProfilePreferences(
        preferredLoadUnit: .kg,
        isBozarModeEnabled: false,
        isTrainingGuidanceEnabled: true
    )
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
                        .accessibilityIdentifier("active-workout-finish-confirmation-title")

                    Text(content.message)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("active-workout-finish-confirmation-message")
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
    }
}

struct ActiveWorkoutFinishConfirmationContent: Equatable {
    let incompleteExerciseCount: Int
    let incompleteSetCount: Int
    let incompleteCardioCount: Int
    let incompletePreWorkoutCardioCount: Int
    let incompletePostWorkoutCardioCount: Int

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
        self.incompletePreWorkoutCardioCount = cardioBlocks.filter {
            $0.phase == .preWorkout && !$0.isCompleted
        }.count
        self.incompletePostWorkoutCardioCount = cardioBlocks.filter {
            $0.phase == .postWorkout && !$0.isCompleted
        }.count
        self.incompleteCardioCount = incompletePreWorkoutCardioCount + incompletePostWorkoutCardioCount
    }

    var hasIncompleteWork: Bool {
        incompleteExerciseCount > 0 || incompleteSetCount > 0 || incompleteCardioCount > 0
    }

    var title: String {
        return hasIncompleteWork ? "Finish With Unfinished Work?" : "Finish Workout?"
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

    let session: ActiveWorkoutRuntimeSession
    let onDismissRestTimer: () -> Void

    var body: some View {
        let isRestTimerActive = restTimerState.restTimerEndsAt != nil
        let dockAccent = isRestTimerActive ? WGJTheme.success : WGJTheme.accentCyan
        let fillOpacity = isRestTimerActive ? 0.16 : 0.12
        let strokeOpacity = isRestTimerActive ? 0.28 : 0.22

        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = restTimerState.restTimerRemaining(at: timeline.date)
            let isResting = remaining != nil
            let accent = isResting ? WGJTheme.success : WGJTheme.accentCyan
            let secondaryText = isResting
                ? restTimerState.restTimerContextLabel() ?? "Recover before the next set"
                : "Workout in progress"
            let primaryValue = isResting
                ? formattedRest(remaining ?? 0)
                : WGJDurationFormatter.elapsedString(since: session.startedAt, now: timeline.date)

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
                    .accessibilityIdentifier(isResting ? "active-workout-rest-timer" : "active-workout-elapsed-timer")

                if isResting {
                    Button {
                        onDismissRestTimer()
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
            .accessibilityLabel(accessibilityLabel(isResting: isResting, primaryValue: primaryValue, secondaryText: secondaryText))
            .allowsHitTesting(isResting)
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
                                    dockAccent.opacity(fillOpacity),
                                    WGJTheme.cardStrong.opacity(0.80),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(dockAccent.opacity(strokeOpacity), lineWidth: 1)
                }
                .shadow(color: WGJTheme.shadowStrong.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(isResting: Bool, primaryValue: String, secondaryText: String) -> String {
        isResting
            ? "Rest timer \(primaryValue). \(secondaryText)"
            : "Elapsed time \(primaryValue)"
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

    let folders: [ActiveWorkoutTemplateFolderSnapshot]
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
                        .accessibilityIdentifier("active-workout-template-skip-button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("active-workout-template-save-button")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("active-workout-template-save-sheet")
    }
}

private enum ActiveWorkoutPickerTarget: Identifiable {
    case exercise
    case replaceExercise(UUID)
    case cardio(WorkoutCardioPhase)

    var id: String {
        switch self {
        case .exercise:
            return "exercise"
        case .replaceExercise(let exerciseID):
            return "replace-exercise-\(exerciseID.uuidString.lowercased())"
        case .cardio(let phase):
            return "cardio-\(phase.rawValue)"
        }
    }

    var pickerTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise:
            return "Add Exercise"
        case .cardio:
            return "Choose Cardio"
        }
    }

    var pickerActionTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise:
            return "Add Exercise"
        case .cardio:
            return "Choose Exercise"
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

private struct ActiveWorkoutHydrationResult: Sendable {
    let draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    let restsByExerciseID: [UUID: Int]
    let notesByExerciseID: [UUID: String]
    let catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot]
}

private struct ActiveWorkoutDeferredHydrationResult: Sendable {
    let previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]
    let componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution]
}

private struct ActiveWorkoutSessionMetaSnapshot: Equatable, Sendable {
    let name: String
    let notes: String
}

nonisolated private struct ActiveWorkoutTemplateFolderSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String

    nonisolated init(folder: TemplateFolder) {
        self.id = folder.id
        self.name = folder.name
    }
}

private struct ActiveWorkoutFinishResult: Sendable {
    let completedSessionID: UUID
    let completedSessionName: String
    let completedTemplateID: UUID?
    let saveTemplateFolders: [ActiveWorkoutTemplateFolderSnapshot]
    let templateUpdatePreview: WorkoutTemplateSyncPreview?
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

private struct ActiveWorkoutCompletionSourceContext {
    let setIndex: Int
    let completesSetCycle: Bool
}

private struct ActiveWorkoutKeyboardAwareBottomDock: View {
    @Environment(\.scenePhase) private var scenePhase

    let session: ActiveWorkoutRuntimeSession?
    let isEndingSession: Bool
    let restTimerPopupID: UUID?
    let reduceMotion: Bool
    let isMetricInputFocused: Bool
    let onDismissRestTimer: () -> Void

    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowDock, let session {
                ActiveWorkoutBottomDock(
                    session: session,
                    reduceMotion: reduceMotion,
                    onDismissRestTimer: onDismissRestTimer
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardState(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: newPhase) else { return }
            isKeyboardVisible = false
        }
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: restTimerPopupID)
    }

    private var shouldShowDock: Bool {
        ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: session != nil,
            isEndingSession: isEndingSession,
            isKeyboardVisible: isKeyboardVisible,
            isMetricInputFocused: isMetricInputFocused,
            scenePhase: scenePhase
        )
    }

    private func updateKeyboardState(from notification: Notification) {
        guard WGJKeyboard.isVisible(from: notification) else { return }
        isKeyboardVisible = true
    }
}

private struct ActiveWorkoutSupersetHeader: View {
    let roundRestSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                structureChip("Superset", tint: WGJTheme.accentBlue)
                structureChip(SupersetExercisePosition.first.label, tint: WGJTheme.accentCyan)
                structureChip(SupersetExercisePosition.second.label, tint: WGJTheme.accentCyan)
            }

            Text("Complete A1, move straight into A2, then rest \(formattedRest(roundRestSeconds)).")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func structureChip(_ title: String, tint: Color) -> some View {
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

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
