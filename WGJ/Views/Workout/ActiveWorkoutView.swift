import Combine
import Foundation
import OSLog
import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(ActiveWorkoutCoordinator.self) private var activeWorkoutCoordinator
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let sessionID: UUID
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "ActiveWorkout"
    )

    @State private var runtimeSession: ActiveWorkoutRuntimeSession?
    @State private var hasBootstrapped = false
    @State private var isBootstrapping = false
    @State private var draftStateStore = WorkoutExerciseDraftStateStore()
    @State private var pendingCardioCompletionsByID: [UUID: Bool] = [:]
    @State private var rowFlushCoordinator = WorkoutExerciseRowFlushCoordinator()

    @State private var previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution] = [:]
    @State private var componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
    @State private var catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot] = [:]
    @State private var loadedExerciseStateStamp: ActiveWorkoutExerciseInteractionStamp?
    @State private var exerciseHydrationInvalidation = 0
    @State private var deferredHydrationTask: Task<Void, Never>?
    @State private var foregroundNonCriticalInteractionWorkTask: Task<Void, Never>?
    @State private var pendingTemplateUpdatePreviewTask: Task<Void, Never>?
    @State private var cardStateController = ActiveWorkoutExerciseCardStateController()
    @State private var renderProjection = ActiveWorkoutRenderProjection.empty
    @State private var scrollPositionTracker = ActiveWorkoutScrollPositionTracker()
    @State private var scrollPosition = ScrollPosition(idType: ActiveWorkoutScrollTarget.self)
    @State private var didRestoreInitialScrollTarget = false
    @State private var isBatchingRenderProjectionRefresh = false
    @State private var needsBatchedRenderProjectionRefresh = false
    @State private var profilePreferences = ActiveWorkoutProfilePreferences.default

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var pickerTarget: ActiveWorkoutPickerTarget?
    @State private var showingFinishConfirmation = false
    @State private var finishSummaryModel = ActiveWorkoutFinishSummaryModel()
    @State private var pendingFinishAfterConfirmation = false
    @State private var isCancelArmed = false
    @State private var isEndingSession = false
    @State private var completedSessionID: UUID?
    @State private var showingSaveTemplateSheet = false
    @State private var pendingCompletionAfterSaveTemplateSheet = false
    @State private var pendingCompletionAfterTemplateReviewSheet = false
    @State private var exerciseSettingsDraft: ActiveWorkoutExerciseSettingsDraft?
    @State private var exerciseComponentPickerDraft: ActiveWorkoutExerciseComponentPickerDraft?
    @State private var cardioPickerRequest: ActiveWorkoutCardioPickerRequest?
    @State private var pendingCardioSelection: ActiveWorkoutCardioPendingSelection?
    @State private var cardioSetupRequest: ActiveWorkoutCardioSetupRequest?
    @State private var cardioConfirmation: ActiveWorkoutCardioConfirmation?
    @State private var pendingFinishedCardioID: UUID?
    @State private var pendingFinishedCardioResult: ActiveWorkoutPendingCardioResult?
    @State private var exerciseReorderRequest: ExerciseReorderRequest?
    @State private var pendingTemplateUpdatePreview: WorkoutTemplateSyncPreview?
    @State private var pendingTemplateUpdateAfterReviewSheetDismissal: WorkoutTemplateSyncPreview?
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?
    @State private var saveTemplateFolders: [ActiveWorkoutTemplateFolderSnapshot] = []
    @State private var canSaveCompletedWorkoutAsTemplate = true
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var keyboardDismissToken = ActiveWorkoutKeyboardDismissToken()
    @State private var isKeyboardVisible = false
    @State private var keyboardContainerFrame = CGRect.zero
    @State private var isMetricInputFocused = false
    @State private var focusedMetricInputExerciseID: UUID?
    @State private var keyboardDismissTargetExerciseID: UUID?

    private let cancelSectionFocusSpacerHeight: CGFloat = 160
    private let cancelSectionDockClearanceHeight: CGFloat = 96
    private let cancelSectionScrollTarget = ActiveWorkoutScrollTarget.cancelSection

    private var persistenceBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        Group {
            ScrollView {
                // Exercise cards can change height aggressively as set rows update, and a
                // non-lazy stack keeps the scroll position stable during active logging.
                activeWorkoutScrollContent
                .scrollTargetLayout()
                .padding(16)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.visibleRect.minY)
            } action: { _, offsetY in
                scrollPositionTracker.record(
                    offsetY: offsetY,
                    isSuspended: isMetricInputFocused || isKeyboardVisible
                )
            }
            .onChange(of: scrollPosition.viewID(type: ActiveWorkoutScrollTarget.self)) { _, target in
                scrollPositionTracker.record(
                    target: target,
                    isSuspended: isMetricInputFocused || isKeyboardVisible
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
                if ActiveWorkoutBottomDockPlacementPolicy.shouldReserveBottomSafeAreaInset(
                    hasSession: session != nil,
                    isEndingSession: isEndingSession,
                    isCancelArmed: isCancelArmed
                ) {
                    ActiveWorkoutKeyboardAwareBottomDock(
                        session: session,
                        isEndingSession: isEndingSession,
                        reduceMotion: reduceMotion,
                        isKeyboardVisible: isKeyboardVisible,
                        isMetricInputFocused: isMetricInputFocused,
                        onDismissRestTimer: {
                            clearRestTimerAndPersist()
                        }
                    )
                }
            }
            .sheet(item: $pickerTarget, onDismiss: {
                dismissKeyboard()
            }) { target in
                ExercisePickerView(
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
            .sheet(item: $cardioPickerRequest, onDismiss: presentPendingCardioSetup) { request in
                CardioActivityQuickPicker { selection in
                    pendingCardioSelection = ActiveWorkoutCardioPendingSelection(
                        pickerRequest: request,
                        selection: selection
                    )
                }
            }
            .sheet(item: $cardioSetupRequest) { request in
                WorkoutCardioSetupSheet(
                    activityName: request.selection.displayName,
                    draft: request.setupDraft
                ) { validatedSetup in
                    applyCardioSetup(request: request, validatedSetup: validatedSetup)
                }
            }
            .sheet(item: $pendingFinishedCardioResult, onDismiss: {
                pendingFinishedCardioID = nil
            }) { result in
                let trackingProfile = WorkoutCardioTrackingProfileResolver.resolved(
                    storedProfile: result.trackingProfile,
                    identity: result.activityName,
                    hasDistance: result.actualDistanceMeters != nil
                )
                let distanceUnit = result.preferredDistanceUnit ?? preferredDistanceUnit
                WorkoutCardioResultEditor(
                    activityName: result.activityName,
                    draft: WorkoutCardioResultDraft(
                        actualDurationSeconds: result.actualDurationSeconds,
                        actualDistanceMeters: result.actualDistanceMeters,
                        distanceUnit: distanceUnit,
                        inclinePercent: result.inclinePercent,
                        resistanceLevel: result.resistanceLevel,
                        notes: result.notes,
                        trackingProfile: trackingProfile
                    )
                ) { validatedResult in
                    try saveCardioResult(
                        activityID: result.id,
                        result: validatedResult
                    )
                }
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
                guard !isFocused else { return }
                flushBatchedRenderProjectionIfNeeded()
                guard canRunNonCriticalInteractionWork else { return }
                scheduleForegroundNonCriticalInteractionWorkResume()
            }
            .wgjTrackContainerFrame($keyboardContainerFrame)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardFrameState(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                updateKeyboardFrameState(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isKeyboardVisible = false
                isMetricInputFocused = false
                focusedMetricInputExerciseID = nil
            }
            .onDisappear {
                isCancelArmed = false
                pendingFinishAfterConfirmation = false
                pendingCompletionAfterSaveTemplateSheet = false
                pendingCompletionAfterTemplateReviewSheet = false
                pendingTemplateUpdateAfterReviewSheetDismissal = nil
                pendingCardioSelection = nil
                cardioConfirmation = nil
                pendingFinishedCardioID = nil
                pendingFinishedCardioResult = nil
                deferredHydrationTask?.cancel()
                deferredHydrationTask = nil
                foregroundNonCriticalInteractionWorkTask?.cancel()
                foregroundNonCriticalInteractionWorkTask = nil
                pendingTemplateUpdatePreviewTask?.cancel()
                pendingTemplateUpdatePreviewTask = nil
            }
            .alert("Workout Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                workoutErrorAlertMessage
            }
            .confirmationDialog(
                cardioConfirmation?.title ?? String(localized: "Cardio"),
                isPresented: cardioConfirmationBinding,
                titleVisibility: .visible,
                presenting: cardioConfirmation
            ) { confirmation in
                cardioConfirmationActions(confirmation)
            } message: { confirmation in
                Text(confirmation.message)
            }
        }
    }

    @MainActor
    private var activeWorkoutScrollContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            activeWorkoutHeaderContent
            cardioRoleSection(for: .warmUp)
            cardioRoleSection(for: .main)
            if session != nil {
                exercisesSectionHeader
            }
            emptyWorkoutContent

            ForEach(exerciseDisplayGroups) { group in
                exerciseSection(for: group)
            }

            if session != nil && !sessionExercises.isEmpty {
                addExerciseButton(title: "Add another exercise")
                    .disabled(session == nil)
            }

            cardioRoleSection(for: .finisher)

            activeWorkoutCancelContent
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
                onSubmit: {
                    persistCommittedUserEditSnapshot()
                },
                onAddCardio: showCardioPicker
            )
            .id(ActiveWorkoutScrollTarget.header)
        } else if isEndingSession || completedSessionID != nil {
            WGJEmptyStateCard(
                title: "Wrapping up workout",
                message: "Saving your workout.",
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
    private var activeWorkoutCancelContent: some View {
        if session != nil && !isEndingSession {
            ActiveWorkoutCancelSection(
                isCancelArmed: isCancelArmed,
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

    private var cardioConfirmationBinding: Binding<Bool> {
        Binding(
            get: { cardioConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    cardioConfirmation = nil
                }
            }
        )
    }

    @ViewBuilder
    private func cardioConfirmationActions(
        _ confirmation: ActiveWorkoutCardioConfirmation
    ) -> some View {
        switch confirmation {
        case .timerConflict(let conflict):
            Button(conflict.requestedTransition.conflictConfirmationActionTitle) {
                cardioConfirmation = nil
                do {
                    try ActiveWorkoutCardioConflictTransitionOrchestrator.perform(
                        conflict: conflict
                    ) { boundary in
                        switch boundary {
                        case .finishCurrent(let activityID):
                            try performCardioTimerTransition(activityID: activityID) { activityID, blocks, date in
                                try WorkoutCardioTimerCoordinator.finish(
                                    activityID: activityID,
                                    blocks: &blocks,
                                    at: date
                                )
                            }
                            WorkoutFeedbackCenter.shared.exerciseCompleted()
                        case .requested(let transition):
                            try performCardioTimerTransition(activityID: transition.activityID) { _, blocks, date in
                                try transition.apply(to: &blocks, at: date)
                            }
                        }
                    }
                } catch {
                    showError(error)
                }
            }

            Button("Keep current running", role: .cancel) {
                cardioConfirmation = nil
            }

        case .replace(let activityID, _):
            Button("Clear data and change exercise", role: .destructive) {
                cardioConfirmation = nil
                guard let activity = cardioBlock(activityID: activityID) else { return }
                showCardioReplacementPicker(for: activity)
            }

            Button("Cancel", role: .cancel) {
                cardioConfirmation = nil
            }

        case .remove(let activityID, _):
            Button("Remove", role: .destructive) {
                cardioConfirmation = nil
                removeCardioActivity(activityID: activityID)
            }

            Button("Cancel", role: .cancel) {
                cardioConfirmation = nil
            }
        }
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

    private var preferredDistanceUnit: WorkoutDistanceUnit {
        profilePreferences.preferredDistanceUnit
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
    private var hasWorkoutContent: Bool {
        renderProjection.hasWorkoutContent
    }

    @MainActor
    private func cardioBlocks(for role: WorkoutCardioRole) -> [ActiveWorkoutRuntimeCardioBlock] {
        renderProjection.cardioByRole[role, default: []]
    }

    @MainActor
    private var orderedCardioActivityIDsByRole: [WorkoutCardioRole: [UUID]] {
        Dictionary(
            uniqueKeysWithValues: WorkoutCardioRole.allCases.map { role in
                (role, cardioBlocks(for: role).map(\.id))
            }
        )
    }

    @MainActor
    private var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>] {
        renderProjection.exerciseDisplayGroups
    }

    @MainActor
    private var supersetContextByExerciseID: [UUID: ActiveWorkoutSupersetContext] {
        renderProjection.supersetContextByExerciseID
    }

    private var shouldShowBottomDock: Bool {
        ActiveWorkoutBottomDockPlacementPolicy.shouldReserveScrollClearance(
            hasSession: session != nil,
            isEndingSession: isEndingSession,
            isCancelArmed: isCancelArmed
        )
    }

    private var cancelSectionBottomSpacerHeight: CGFloat {
        if isCancelArmed {
            return cancelSectionFocusSpacerHeight
        }

        return shouldShowBottomDock ? cancelSectionDockClearanceHeight : 24
    }

    private var exerciseHydrationStamp: ActiveWorkoutExerciseInteractionStamp {
        renderProjection.exerciseHydrationStamp.withInvalidation(exerciseHydrationInvalidation)
    }

    private var exercisesSectionHeader: some View {
        Group {
            if sessionExercises.isEmpty {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Add exercises and log sets as you train."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Add, reorder, or remove exercises during this workout."
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
        Button("Finish") {
            presentFinishConfirmation()
        }
        .disabled(isEndingSession || session == nil || !hasWorkoutContent)
        .accessibilityIdentifier("active-workout-finish-button")
        .popover(isPresented: $showingFinishConfirmation, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            if let content = finishSummaryModel.content {
                ActiveWorkoutFinishPopover(
                    content: content,
                    onFinish: confirmFinishWorkout,
                    onCancel: { showingFinishConfirmation = false }
                )
                .presentationCompactAdaptation(.popover)
            }
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
    private func cardioRoleSection(for role: WorkoutCardioRole) -> some View {
        let activities = cardioBlocks(for: role)
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(role.title, subtitle: cardioSectionSubtitle(for: role)) {
                    Button {
                        showCardioPicker(for: role)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .accessibilityLabel("Add \(role.title) cardio")
                }

                ForEach(activities) { activity in
                    if ActiveWorkoutCardioInteractionPolicy.usesQuickCompletion(for: activity.role) {
                        quickCompletionCard(for: activity)
                            .id(cardioScrollTarget(for: activity))
                    } else {
                        ActiveWorkoutCardioActivityCard(
                            presentation: .make(activity: activity),
                            onStart: { startCardioTimer(activityID: activity.id) },
                            onPause: { pauseCardioTimer(activityID: activity.id) },
                            onResume: { resumeCardioTimer(activityID: activity.id) },
                            onFinish: { finishCardioTimer(activityID: activity.id) },
                            onEditResult: { presentCardioResult(activityID: activity.id) },
                            onEditPlan: { presentCardioSetup(for: activity) },
                            onChangeExercise: { requestCardioReplacement(for: activity) },
                            onRemove: { requestCardioRemoval(for: activity) }
                        )
                        .id(cardioScrollTarget(for: activity))
                    }
                }
            }
        }
    }

    @MainActor
    private func quickCompletionCard(
        for activity: ActiveWorkoutRuntimeCardioBlock
    ) -> some View {
        let presentation = ActiveWorkoutCardioPresentation.make(activity: activity)
        return ActiveWorkoutCardioPhaseCard(
            phase: activity.phase,
            exerciseName: activity.exerciseNameSnapshot,
            descriptor: presentation.descriptor,
            goalText: presentation.goalText,
            statusText: activity.isCompleted ? CardioLocalizedCopy.stateTitle(.complete) : nil,
            statusTint: WGJTheme.success,
            isCompleted: activity.isCompleted,
            canComplete: true,
            completionTitle: "Complete",
            completionAccessibilityLabel: "Complete \(activity.exerciseNameSnapshot)",
            undoAccessibilityLabel: "Mark \(activity.exerciseNameSnapshot) incomplete",
            completionAccessibilityIdentifier: "active-workout-cardio-\(activity.id)-quick-completion-button",
            accessibilityIdentifier: "active-workout-cardio-\(activity.id)-card",
            onToggleCompletion: { toggleQuickCardioCompletion(activityID: activity.id) }
        ) {
            Menu {
                Button("Edit Plan") { presentCardioSetup(for: activity) }
                Button("Change Exercise") { requestCardioReplacement(for: activity) }
                Button("Remove", role: .destructive) { requestCardioRemoval(for: activity) }
            } label: {
                ActiveWorkoutCardioHeaderActionIcon(
                    tint: activity.isCompleted ? WGJTheme.success : quickCardioTint(for: activity.role)
                )
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Cardio Actions")
            .accessibilityIdentifier("active-workout-cardio-\(activity.id)-actions-button")
        }
    }

    private func quickCardioTint(for role: WorkoutCardioRole) -> Color {
        role == .warmUp ? WGJTheme.accentBlue : WGJTheme.accentGold
    }

    @MainActor
    @ViewBuilder
    private func exerciseRow(
        for exercise: ActiveWorkoutRuntimeExercise,
        index: Int,
        displayTitle: String? = nil
    ) -> some View {
        let exerciseID = exercise.id
        let exerciseName = exercise.exerciseNameSnapshot

        Group {
            if let drafts = renderableDrafts(for: exerciseID) {
                WorkoutExerciseRowHostView(
                    exerciseID: exerciseID,
                    catalogExerciseUUID: exercise.catalogExerciseUUID,
                    exerciseAccessibilityIdentifier: "active-workout-exercise-\(exercise.catalogExerciseUUID)",
                    exerciseName: exerciseName,
                    muscleSummary: exercise.muscleSummarySnapshot,
                    category: exercise.categorySnapshot,
                    exerciseIndexTitle: displayTitle ?? "Exercise \(index + 1)",
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    previousPerformanceResolution: resolvedPreviousPerformanceResolution(for: exerciseID),
                    guidance: nil,
                    preferredLoadUnit: preferredLoadUnit,
                    componentSummaryResolution: componentResolutionByExerciseID[exerciseID],
                    componentSummaryAccessibilityIdentifierPrefix: "active-workout-exercise-\(exercise.catalogExerciseUUID)-component-summary",
                    exerciseNotes: resolvedNotes(for: exercise),
                    restSeconds: resolvedRest(for: exercise),
                    setDrafts: drafts,
                    isExpanded: cardStateController.isExpanded(for: exerciseID),
                    manualCompletionMode: true,
                    isSetEditingEnabled: true,
                    isSetCompletionEnabled: true,
                    setCompletionGatePresentation: nil,
                    canMoveExerciseUp: index > 0,
                    canMoveExerciseDown: index < sessionExercises.count - 1,
                    onExerciseNotesCommitted: { notes in
                        updateNotesValue(notes, for: exerciseID)
                        persistCommittedUserEditSnapshot()
                    },
                    onSetDraftsCommitted: { drafts in
                        handleDraftsChanged(drafts, for: exercise)
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
                    keyboardDismissToken: keyboardDismissToken,
                    onInputFocusChange: { isFocused in
                        handleMetricInputFocusChange(isFocused, exerciseID: exerciseID)
                    }
                )
                .equatable()
                .id(WorkoutExerciseRowContentIdentity(exercise: exercise))
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
        for group: WorkoutExerciseDisplayGroup<ActiveWorkoutRuntimeExercise>
    ) -> some View {
        switch group {
        case .single(let exercise, let index):
            exerciseRow(
                for: exercise,
                index: index
            )
        case .superset(let superset):
            VStack(alignment: .leading, spacing: 12) {
                ActiveWorkoutSupersetHeader(
                    roundRestSeconds: superset.roundRestSeconds
                )

                exerciseRow(
                    for: superset.first,
                    index: superset.firstIndex,
                    displayTitle: SupersetExercisePosition.first.label
                )

                exerciseRow(
                    for: superset.second,
                    index: superset.secondIndex,
                    displayTitle: SupersetExercisePosition.second.label
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
            .id(ActiveWorkoutScrollTarget.superset(superset.groupID))
            .transition(exerciseCardTransition)
        }
    }

    @MainActor
    private func renderableDrafts(for exerciseID: UUID) -> [WorkoutSessionSetDraft]? {
        if let drafts = draftStateStore.drafts(for: exerciseID) {
            return drafts
        }

        return activeWorkoutPresentationState
            .preparedFirstRenderSnapshot(for: sessionID)?
            .draftsByExerciseID[exerciseID]
    }

    @MainActor
    private func resolvedDrafts(for exercise: ActiveWorkoutRuntimeExercise) -> [WorkoutSessionSetDraft] {
        renderableDrafts(for: exercise.id) ?? exercise.setDrafts
    }

    @MainActor
    private func resolvedRest(for exercise: ActiveWorkoutRuntimeExercise) -> Int {
        draftStateStore.restSeconds(for: exercise.id)
            ?? activeWorkoutPresentationState
                .preparedFirstRenderSnapshot(for: sessionID)?
                .restsByExerciseID[exercise.id]
            ?? exercise.restSeconds
    }

    @MainActor
    private func resolvedNotes(for exercise: ActiveWorkoutRuntimeExercise) -> String {
        draftStateStore.notes(for: exercise.id)
            ?? activeWorkoutPresentationState
                .preparedFirstRenderSnapshot(for: sessionID)?
                .notesByExerciseID[exercise.id]
            ?? exercise.notes
    }

    @MainActor
    private func updateDraftsValue(
        _ updated: [WorkoutSessionSetDraft],
        for exerciseID: UUID,
        refreshProjectionImmediately: Bool = true
    ) {
        guard draftStateStore.setDrafts(updated, for: exerciseID) else { return }
        if refreshProjectionImmediately {
            refreshRenderProjection()
        } else {
            needsBatchedRenderProjectionRefresh = true
        }
    }

    @MainActor
    private func updateRestValue(_ updated: Int, for exerciseID: UUID) {
        guard draftStateStore.setRestSeconds(updated, for: exerciseID) else { return }
        refreshRenderProjection()
    }

    @MainActor
    private func updateNotesValue(_ updated: String, for exerciseID: UUID) {
        _ = draftStateStore.setNotes(updated, for: exerciseID)
    }

    @MainActor
    private func refreshRenderProjection() {
        guard !isBatchingRenderProjectionRefresh else {
            needsBatchedRenderProjectionRefresh = true
            return
        }

        let draftState = draftStateStore.snapshot()
        renderProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: runtimeSession,
            setDraftsByExerciseID: draftState.draftsByExerciseID,
            pendingCardioCompletionsByID: pendingCardioCompletionsByID
        )
    }

    @MainActor
    private func flushBatchedRenderProjectionIfNeeded() {
        guard needsBatchedRenderProjectionRefresh else { return }
        needsBatchedRenderProjectionRefresh = false
        let draftState = draftStateStore.snapshot()
        renderProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: runtimeSession,
            setDraftsByExerciseID: draftState.draftsByExerciseID,
            pendingCardioCompletionsByID: pendingCardioCompletionsByID
        )
    }

    @MainActor
    private var areAllMainExercisesCompleted: Bool {
        renderProjection.areAllMainExercisesCompleted
    }

    @MainActor
    private func cardioBlock(activityID: UUID) -> ActiveWorkoutRuntimeCardioBlock? {
        orderedCardioBlocks.first { $0.id == activityID }
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

        draftStateStore.replace(
            with: WorkoutExerciseDraftStateSnapshot(
                draftsByExerciseID: Dictionary(
                    session.exercises.map { ($0.id, $0.setDrafts) },
                    uniquingKeysWith: { first, _ in first }
                ),
                restsByExerciseID: Dictionary(
                    session.exercises.map { ($0.id, $0.restSeconds) },
                    uniquingKeysWith: { first, _ in first }
                ),
                notesByExerciseID: Dictionary(
                    session.exercises.map { ($0.id, $0.notes) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        )
        pendingCardioCompletionsByID = [:]
        refreshRenderProjection()
        syncExerciseCardState()
    }

    @MainActor
    private func syncExerciseCardState() {
        let draftState = draftStateStore.snapshot()
        let completedExerciseIDs = Set(
            sessionExercises.compactMap { exercise in
                let drafts = draftState.draftsByExerciseID[exercise.id] ?? []
                return isExerciseCompleted(drafts) ? exercise.id : nil
            }
        )
        cardStateController.sync(
            exerciseIDs: sessionExercises.map(\.id),
            completedExerciseIDs: completedExerciseIDs,
            firstIncompleteExerciseID: firstIncompleteExerciseID(
                from: sessionExercises,
                draftsByExerciseID: draftState.draftsByExerciseID
            )
        )

        let preparedExpandedExerciseIDs = activeWorkoutPresentationState.preparedExpandedExerciseIDs(for: sessionID)
        guard !preparedExpandedExerciseIDs.isEmpty else { return }
        cardStateController.restoreExpandedExerciseIDs(preparedExpandedExerciseIDs)
        activeWorkoutPresentationState.clearPreparedExpandedExerciseIDs(for: sessionID)
    }

    @MainActor
    private func currentRuntimeSnapshot() -> ActiveWorkoutRuntimeSession? {
        let draftState = draftStateStore.snapshot()
        return runtimeSession?.snapshotForActiveWorkoutPersistence(
            sessionNameDraft: sessionNameDraft,
            notesDraft: notesDraft,
            pendingCardioCompletionsByID: pendingCardioCompletionsByID,
            setDraftsByExerciseID: draftState.draftsByExerciseID,
            restByExerciseID: draftState.restsByExerciseID,
            notesByExerciseID: draftState.notesByExerciseID
        )
    }

    @MainActor
    private func currentPreparedFirstRenderSnapshot() -> ActiveWorkoutPreparedFirstRenderSnapshot {
        let currentExerciseIDs = Set(sessionExercises.map(\.id))
        let draftState = draftStateStore.snapshot(keeping: currentExerciseIDs)
        return ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: draftState.draftsByExerciseID,
            restsByExerciseID: draftState.restsByExerciseID,
            notesByExerciseID: draftState.notesByExerciseID,
            catalogMatchesByUUID: catalogMatchesByUUID,
            previousResolutionByExerciseID: previousResolutionByExerciseID.filter { currentExerciseIDs.contains($0.key) }
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
            guard let storedSession = activeWorkoutCoordinator.storedSnapshot?.session,
                  storedSession.id == sessionID else {
                throw WorkoutSessionRepositoryError.sessionNotFound
            }
            applyRuntimeSessionState(storedSession)
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
        restoreInitialScrollPositionIfNeeded()
    }

    @MainActor
    private func restoreInitialScrollPositionIfNeeded() {
        guard !didRestoreInitialScrollTarget else { return }
        if let preparedOffsetY = activeWorkoutPresentationState.preparedScrollOffsetY(for: sessionID) {
            didRestoreInitialScrollTarget = true
            activeWorkoutPresentationState.stageScrollOffsetY(nil, for: sessionID)
            activeWorkoutPresentationState.stageScrollTarget(nil, for: sessionID)
            Task { @MainActor in
                await Task.yield()
                guard hasBootstrapped, !Task.isCancelled else { return }
                scrollPosition.scrollTo(y: max(0, CGFloat(preparedOffsetY)))
            }
            return
        }
        guard let preparedTarget = activeWorkoutPresentationState.preparedScrollTarget(for: sessionID) else { return }
        guard let target = ActiveWorkoutScrollRestorePolicy.resolvedRestorableTarget(
            preparedTarget,
            orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
            isRestorable: isRestorableScrollTarget
        ) else {
            activeWorkoutPresentationState.stageScrollTarget(nil, for: sessionID)
            didRestoreInitialScrollTarget = true
            return
        }

        didRestoreInitialScrollTarget = true
        scrollPositionTracker.currentTarget = target
        activeWorkoutPresentationState.stageScrollTarget(nil, for: sessionID)
        Task { @MainActor in
            await Task.yield()
            guard hasBootstrapped, !Task.isCancelled else { return }
            scrollToTarget(target, animation: nil)
        }
    }

    @MainActor
    private func loadActiveWorkoutProfilePreferences() async {
        let backgroundStore = persistenceBackgroundStore
        let loadedPreferences = try? await backgroundStore.perform("active-workout.profile-preferences") { backgroundContext in
            Self.profilePreferences(modelContext: backgroundContext)
        }

        let resolvedPreferences = loadedPreferences ?? .default
        guard profilePreferences != resolvedPreferences else {
            preferredLoadUnit = resolvedPreferences.preferredLoadUnit
            return
        }

        profilePreferences = resolvedPreferences
        preferredLoadUnit = resolvedPreferences.preferredLoadUnit
    }

    nonisolated private static func profilePreferences(modelContext: ModelContext) -> ActiveWorkoutProfilePreferences {
        guard let profile = try? ProfileRepository(modelContext: modelContext).currentProfile() else {
            return .default
        }

        return ActiveWorkoutProfilePreferences(
            preferredLoadUnit: profile.preferredLoadUnit,
            preferredDistanceUnit: profile.preferredDistanceUnit,
            automaticallyClosesCompletedExercises: profile.automaticallyClosesCompletedExercises
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
                let backgroundStore = persistenceBackgroundStore
                result = try await backgroundStore.perform("active-workout.hydrate.local") { backgroundContext in
                    try Self.loadHydrationResult(
                        modelContext: backgroundContext,
                        exercises: loadingExercises
                    )
                }
            } catch {
                showError(error)
                return
            }

            draftStateStore.merge(
                WorkoutExerciseDraftStateSnapshot(
                    draftsByExerciseID: result.draftsByExerciseID,
                    restsByExerciseID: result.restsByExerciseID,
                    notesByExerciseID: result.notesByExerciseID
                )
            )
            catalogMatchesByUUID.merge(result.catalogMatchesByUUID) { _, new in new }
            refreshRenderProjection()

            for exerciseID in loadingExerciseIDs {
                if previousResolutionByExerciseID[exerciseID] == nil {
                    previousResolutionByExerciseID[exerciseID] = .loading
                }
                componentResolutionByExerciseID[exerciseID] = nil
            }
        }

        syncExerciseCardState()

        loadedExerciseStateStamp = currentStamp
        await Task.yield()
        guard !Task.isCancelled, currentStamp == exerciseHydrationStamp else { return }
        let draftState = draftStateStore.snapshot()
        scheduleDeferredHydration(
            for: currentStamp,
            draftsByExerciseID: draftState.draftsByExerciseID
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

        draftStateStore.merge(
            WorkoutExerciseDraftStateSnapshot(
                draftsByExerciseID: snapshot.draftsByExerciseID.filter { exerciseIDs.contains($0.key) },
                restsByExerciseID: snapshot.restsByExerciseID.filter { exerciseIDs.contains($0.key) },
                notesByExerciseID: snapshot.notesByExerciseID.filter { exerciseIDs.contains($0.key) }
            )
        )
        refreshRenderProjection()
        previousResolutionByExerciseID.merge(
            snapshot.previousResolutionByExerciseID.filter { exerciseIDs.contains($0.key) }
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
        let hydrationDelay = previousPerformanceHydrationDelay
        let backgroundStore = persistenceBackgroundStore
        let hydrationWorker = ActiveWorkoutDeferredHydrationWorker()
        deferredHydrationTask = Task.detached(priority: .userInitiated) {
            guard await runDeferredHydrationIfStillAllowed(stamp: stamp) else { return }

            let loadedHydration: ActiveWorkoutDeferredHydrationResult
            do {
                loadedHydration = try await hydrationWorker.loadAfterDelay(
                    hydrationDelay,
                    backgroundStore: backgroundStore,
                    session: hydrationSession,
                    exerciseIDs: hydrationExerciseIDs,
                    draftsByExerciseID: draftsByExerciseID
                )
            } catch {
                guard !Task.isCancelled else { return }
                await applyDeferredHydrationFailureIfStillAllowed(error, stamp: stamp)
                return
            }

            guard !Task.isCancelled else { return }
            await applyDeferredHydrationIfStillAllowed(
                loadedHydration,
                stamp: stamp,
                previousExerciseIDs: previousExerciseIDs,
                componentExerciseIDs: componentExerciseIDs
            )
        }
    }

    @MainActor
    private func runDeferredHydrationIfStillAllowed(stamp: ActiveWorkoutExerciseInteractionStamp) -> Bool {
        loadedExerciseStateStamp == stamp && canRunNonCriticalInteractionWork
    }

    @MainActor
    private func applyDeferredHydrationFailureIfStillAllowed(
        _ error: Error,
        stamp: ActiveWorkoutExerciseInteractionStamp
    ) {
        guard loadedExerciseStateStamp == stamp else { return }
        showError(error)
        deferredHydrationTask = nil
    }

    @MainActor
    private func applyDeferredHydrationIfStillAllowed(
        _ loadedHydration: ActiveWorkoutDeferredHydrationResult,
        stamp: ActiveWorkoutExerciseInteractionStamp,
        previousExerciseIDs: Set<UUID>,
        componentExerciseIDs: Set<UUID>
    ) {
        guard loadedExerciseStateStamp == stamp,
              canRunNonCriticalInteractionWork
        else { return }

        previousResolutionByExerciseID.merge(
            loadedHydration.previousResolutionByExerciseID.filter { previousExerciseIDs.contains($0.key) }
        ) { _, new in new }
        let previousSetSnapshotsByExerciseID = loadedHydration.previousResolutionByExerciseID
            .filter { previousExerciseIDs.contains($0.key) }
            .mapValues(\.previousBySetIndex)
        if !previousSetSnapshotsByExerciseID.isEmpty {
            _ = activeWorkoutCoordinator.send(.cachePreviousPerformance(previousSetSnapshotsByExerciseID))
        }
        componentResolutionByExerciseID.merge(
            loadedHydration.componentResolutionByExerciseID.filter { componentExerciseIDs.contains($0.key) }
        ) { _, new in new }
        deferredHydrationTask = nil
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
            canSaveCompletedWorkoutAsTemplate = result.canCreateTemplateFromCompletedWorkout

            if templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                templateNameDraft = result.completedSessionName == "Empty Workout" ? "New Template" : result.completedSessionName
            }
            saveTemplateFolders = result.saveTemplateFolders
            showingSaveTemplateSheet = true
            return
        }

        if let preview = result.templateUpdatePreview {
            pendingTemplateUpdatePreview = preview
        } else if result.completedTemplateID != nil {
            loadTemplateUpdatePreviewAfterFinish(sessionID: result.completedSessionID)
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
        let draftState = draftStateStore.snapshot()
        scheduleDeferredHydration(
            for: loadedExerciseStateStamp,
            draftsByExerciseID: draftState.draftsByExerciseID
        )
    }

    private func handlePickedExercise(_ item: ExerciseCatalogSelection, target: ActiveWorkoutPickerTarget) -> ExercisePickerSelectionResult {
        switch target {
        case .exercise:
            return addExercise(item)
        case .replaceExercise(let exerciseID):
            return replaceExercise(exerciseID: exerciseID, with: item)
        }
    }

    private func showCardioPicker() {
        showCardioPicker(
            for: ActiveWorkoutCardioQuickAddPolicy.defaultRole(
                hasStrengthExercises: !sessionExercises.isEmpty
            )
        )
    }

    private func showCardioPicker(for role: WorkoutCardioRole) {
        dismissKeyboard()
        cardioPickerRequest = ActiveWorkoutCardioPickerRequest(
            activityID: nil,
            role: role,
            resetsResult: false
        )
    }

    private func showCardioReplacementPicker(for activity: ActiveWorkoutRuntimeCardioBlock) {
        dismissKeyboard()
        cardioPickerRequest = ActiveWorkoutCardioPickerRequest(
            activityID: activity.id,
            role: activity.role,
            resetsResult: true
        )
    }

    private func requestCardioReplacement(for activity: ActiveWorkoutRuntimeCardioBlock) {
        switch ActiveWorkoutCardioReplacementPolicy.decision(activity: activity) {
        case .replaceDirectly:
            showCardioReplacementPicker(for: activity)
        case .confirmClearingRecordedData:
            cardioConfirmation = .replace(
                activityID: activity.id,
                activityName: activity.exerciseNameSnapshot
            )
        }
    }

    private func presentPendingCardioSetup() {
        guard let pendingCardioSelection else { return }
        self.pendingCardioSelection = nil
        cardioSetupRequest = makeCardioSetupRequest(
            activityID: pendingCardioSelection.pickerRequest.activityID,
            role: pendingCardioSelection.pickerRequest.role,
            selection: pendingCardioSelection.selection,
            resetsResult: pendingCardioSelection.pickerRequest.resetsResult
        )
    }

    private func presentCardioSetup(for activity: ActiveWorkoutRuntimeCardioBlock) {
        cardioSetupRequest = makeCardioSetupRequest(
            activityID: activity.id,
            role: activity.role,
            selection: ExerciseCatalogSelection(
                remoteUUID: activity.catalogExerciseUUID,
                displayName: activity.exerciseNameSnapshot,
                categoryName: activity.categorySnapshot,
                equipmentSummary: "",
                primaryMuscleNames: activity.muscleSummarySnapshot,
                cardioTrackingProfileRaw: activity.trackingProfile?.rawValue
            ),
            resetsResult: false
        )
    }

    private func showExerciseReplacementPicker(for exerciseID: UUID) {
        dismissKeyboard()
        pickerTarget = .replaceExercise(exerciseID)
    }

    private func addExercise(_ item: ExerciseCatalogSelection) -> ExercisePickerSelectionResult {
        guard runtimeSession != nil else { return .accepted }
        guard !sessionExercises.contains(where: { $0.catalogExerciseUUID == item.remoteUUID }) else {
            return duplicateExerciseRejectedResult(for: item)
        }

        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            let nextIndex = (sessionExercises.map(\.sortOrder).max() ?? -1) + 1
            let exercise = ActiveWorkoutRuntimeExercise.catalogExercise(
                from: item,
                sortOrder: nextIndex,
                preferredLoadUnit: preferredLoadUnit
            )
            updateRuntimeSession { session in
                session.exercises.append(exercise)
            }
            draftStateStore.merge(
                WorkoutExerciseDraftStateSnapshot(
                    draftsByExerciseID: [exercise.id: exercise.setDrafts],
                    restsByExerciseID: [exercise.id: exercise.restSeconds],
                    notesByExerciseID: [exercise.id: exercise.notes]
                )
            )
            refreshRenderProjection()
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        persistCommittedUserEditSnapshot()
        return .accepted
    }

    private func replaceExercise(exerciseID: UUID, with item: ExerciseCatalogSelection) -> ExercisePickerSelectionResult {
        dismissKeyboard()
        rowFlushCoordinator.flush(for: exerciseID)
        guard let existingExercise = sessionExercises.first(where: { $0.id == exerciseID }) else { return .accepted }
        let duplicateResult = ExerciseReplacementSelectionPolicy.result(
            catalogExerciseUUID: item.remoteUUID,
            exerciseName: item.displayName,
            existingCatalogExerciseUUIDs: sessionExercises.map(\.catalogExerciseUUID),
            destination: .activeWorkout
        )
        guard duplicateResult == .accepted else {
            return duplicateResult
        }

        let removedSetIDs = Set((draftStateStore.drafts(for: exerciseID) ?? existingExercise.setDrafts).map(\.id))
        let replacement = existingExercise.replacingExercise(
            with: item,
            preferredLoadUnit: preferredLoadUnit
        )

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            updateRuntimeSession { session in
                guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                session.exercises[index] = replacement
            }
            draftStateStore.merge(
                WorkoutExerciseDraftStateSnapshot(
                    draftsByExerciseID: [exerciseID: replacement.setDrafts],
                    restsByExerciseID: [exerciseID: replacement.restSeconds],
                    notesByExerciseID: [exerciseID: replacement.notes]
                )
            )
            previousResolutionByExerciseID[exerciseID] = nil
            componentResolutionByExerciseID[exerciseID] = nil
            rowFlushCoordinator.setDirty(false, for: exerciseID)

            if let restTimerSourceSetID = restTimerState.restTimerSourceSetID,
               removedSetIDs.contains(restTimerSourceSetID) {
                clearRestTimerAndPersist(sourceSetID: restTimerSourceSetID)
            }

            refreshRenderProjection()
            loadedExerciseStateStamp = nil
            exerciseHydrationInvalidation += 1
        }
        persistCommittedUserEditSnapshot()
        return .accepted
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

    private func makeCardioSetupRequest(
        activityID: UUID?,
        role: WorkoutCardioRole,
        selection: ExerciseCatalogSelection,
        resetsResult: Bool
    ) -> ActiveWorkoutCardioSetupRequest {
        let existing = activityID.flatMap(cardioBlock(activityID:))
        let distanceUnit = existing?.preferredDistanceUnit ?? preferredDistanceUnit

        return ActiveWorkoutCardioSetupRequest(
            activityID: activityID ?? UUID(),
            isNewActivity: activityID == nil,
            selection: selection,
            setupDraft: existing.map {
                WorkoutCardioSetupDraft(
                    activeCardio: $0,
                    replacementSelection: resetsResult ? selection : nil,
                    fallbackDistanceUnit: distanceUnit
                )
            } ?? WorkoutCardioSetupDraft(
                role: role,
                goalKind: .time,
                durationMinutesText: "10",
                distanceText: "",
                distanceUnit: distanceUnit,
                trackingProfile: WorkoutCardioTrackingProfileResolver.resolved(
                    storedProfile: selection.cardioTrackingProfile,
                    catalogExerciseUUID: selection.remoteUUID,
                    exerciseName: selection.displayName,
                    hasDistance: false
                )
            ),
            resetsResult: resetsResult
        )
    }

    private func applyCardioSetup(
        request: ActiveWorkoutCardioSetupRequest,
        validatedSetup: ValidatedWorkoutCardioSetup
    ) {
        let now = Date()
        let existing = cardioBlock(activityID: request.activityID)
        var updated = existing ?? ActiveWorkoutRuntimeCardioBlock(
            id: request.activityID,
            phase: TemplateCardioDraftReducer.legacyPhase(for: validatedSetup.role),
            role: validatedSetup.role,
            catalogExerciseUUID: request.selection.remoteUUID,
            exerciseNameSnapshot: request.selection.displayName,
            categorySnapshot: request.selection.categoryName,
            muscleSummarySnapshot: request.selection.primaryMuscleNames,
            trackingProfile: validatedSetup.trackingProfile,
            goalKind: validatedSetup.goalKind,
            targetDurationSeconds: validatedSetup.targetDurationSeconds,
            targetDistanceMeters: validatedSetup.targetDistanceMeters,
            preferredDistanceUnit: validatedSetup.preferredDistanceUnit,
            createdAt: now,
            updatedAt: now
        )

        updated.phase = TemplateCardioDraftReducer.legacyPhase(for: validatedSetup.role)
        updated.role = validatedSetup.role
        updated.catalogExerciseUUID = request.selection.remoteUUID
        updated.exerciseNameSnapshot = request.selection.displayName
        updated.categorySnapshot = request.selection.categoryName
        updated.muscleSummarySnapshot = request.selection.primaryMuscleNames
        updated.trackingProfile = validatedSetup.trackingProfile
        updated.goalKind = validatedSetup.goalKind
        updated.targetDurationSeconds = validatedSetup.targetDurationSeconds
        updated.targetDistanceMeters = validatedSetup.targetDistanceMeters
        updated.preferredDistanceUnit = validatedSetup.preferredDistanceUnit
        updated.updatedAt = now

        if request.resetsResult {
            updated.sourceTemplateCardioID = nil
            updated.actualDurationSeconds = nil
            updated.actualDistanceMeters = nil
            updated.inclinePercent = nil
            updated.resistanceLevel = nil
            updated.cardioNotes = ""
            updated.timerState = .idle
            updated.timerSegmentStartedAt = nil
            updated.timerAccumulatedSeconds = 0
            updated.isCompleted = false
        }

        updateRuntimeSession { session in
            session.cardioBlocks = request.isNewActivity
                ? ActiveWorkoutRuntimeCardioPlanReducer.appending(updated, to: session.cardioBlocks)
                : ActiveWorkoutRuntimeCardioPlanReducer.updating(updated, in: session.cardioBlocks)
        }
        persistCommittedUserEditSnapshot()
    }

    private func requestCardioRemoval(for activity: ActiveWorkoutRuntimeCardioBlock) {
        if ActiveWorkoutCardioRemovalPolicy.requiresConfirmation(activity: activity) {
            cardioConfirmation = .remove(activityID: activity.id, activityName: activity.exerciseNameSnapshot)
        } else {
            removeCardioActivity(activityID: activity.id)
        }
    }

    private func removeCardioActivity(activityID: UUID) {
        updateRuntimeSession { session in
            session.cardioBlocks = ActiveWorkoutRuntimeCardioPlanReducer.removing(
                activityID: activityID,
                from: session.cardioBlocks
            )
        }
        pendingCardioCompletionsByID[activityID] = nil
        if pendingFinishedCardioID == activityID {
            pendingFinishedCardioID = nil
            pendingFinishedCardioResult = nil
        }
        persistCommittedUserEditSnapshot()
    }

    private func startCardioTimer(activityID: UUID) {
        requestCardioTimerTransition(.start(activityID: activityID))
    }

    private func requestCardioTimerTransition(
        _ requestedTransition: ActiveWorkoutCardioRequestedTimerTransition
    ) {
        do {
            try performCardioTimerTransition(
                activityID: requestedTransition.activityID
            ) { _, blocks, date in
                try requestedTransition.apply(to: &blocks, at: date)
            }
        } catch WorkoutCardioTimerError.anotherActivityRunning(let runningActivityID) {
            cardioConfirmation = .timerConflict(
                ActiveWorkoutCardioTimerConflict(
                    runningActivityID: runningActivityID,
                    requestedTransition: requestedTransition
                )
            )
        } catch {
            showError(error)
        }
    }

    private func pauseCardioTimer(activityID: UUID) {
        do {
            try performCardioTimerTransition(activityID: activityID) { activityID, blocks, date in
                try WorkoutCardioTimerCoordinator.pause(activityID: activityID, blocks: &blocks, at: date)
            }
        } catch {
            showError(error)
        }
    }

    private func resumeCardioTimer(activityID: UUID) {
        requestCardioTimerTransition(.resume(activityID: activityID))
    }

    private func toggleQuickCardioCompletion(activityID: UUID) {
        guard let activity = cardioBlock(activityID: activityID) else { return }

        if activity.isCompleted {
            pendingCardioCompletionsByID[activityID] = false
            refreshRenderProjection()
            persistCommittedUserEditSnapshot()
            return
        }

        if activity.timerState != .idle {
            _ = finishCardioTimer(activityID: activityID, presentsResult: false)
            return
        }

        pendingCardioCompletionsByID[activityID] = true
        refreshRenderProjection()
        WorkoutFeedbackCenter.shared.exerciseCompleted()
        persistCommittedUserEditSnapshot()
    }

    @discardableResult
    private func finishCardioTimer(
        activityID: UUID,
        presentsResult: Bool = true
    ) -> Bool {
        do {
            try performCardioTimerTransition(activityID: activityID) { activityID, blocks, date in
                try WorkoutCardioTimerCoordinator.finish(activityID: activityID, blocks: &blocks, at: date)
            }
            WorkoutFeedbackCenter.shared.exerciseCompleted()
            if presentsResult {
                presentCardioResult(activityID: activityID)
            }
            return true
        } catch {
            showError(error)
            return false
        }
    }

    private func performCardioTimerTransition(
        activityID: UUID,
        at date: Date = .now,
        transition: (
            UUID,
            inout [ActiveWorkoutRuntimeCardioBlock],
            Date
        ) throws -> Void
    ) throws {
        guard var updatedSession = runtimeSession else {
            throw WorkoutCardioTimerError.activityNotFound
        }

        try transition(activityID, &updatedSession.cardioBlocks, date)
        guard let index = updatedSession.cardioBlocks.firstIndex(where: { $0.id == activityID }) else {
            throw WorkoutCardioTimerError.activityNotFound
        }
        updatedSession.cardioBlocks[index].updatedAt = date
        updatedSession.touch(date: date)
        runtimeSession = updatedSession

        // This existing committed boundary performs the one projection refresh and snapshot write.
#if DEBUG
        ActiveWorkoutCardioRuntimeDiagnostics.recordPersistenceBoundary(
            activityID: activityID,
            kind: .timerTransition
        )
#endif
        persistCommittedUserEditSnapshot()
    }

    private func presentCardioResult(activityID: UUID) {
        guard let activity = cardioBlock(activityID: activityID) else { return }
        pendingFinishedCardioID = activityID
        pendingFinishedCardioResult = .make(activity: activity)
    }

    private func saveCardioResult(
        activityID: UUID,
        result: ValidatedWorkoutCardioResult,
        at date: Date = .now
    ) throws {
        guard let runtimeSession else {
            throw WorkoutCardioTimerError.activityNotFound
        }
        let plan = try ActiveWorkoutCardioResultSavePlan.make(
            session: runtimeSession,
            activityID: activityID,
            result: result,
            at: date
        )
        self.runtimeSession = plan.session

        switch plan.disposition {
        case .noOp:
            break
        case .committedSnapshot:
            // Result Save is one explicit local-first active-workout snapshot boundary.
            persistCommittedUserEditSnapshot()
        }
    }

    @MainActor
    private func handleDraftsChanged(
        _ drafts: [WorkoutSessionSetDraft],
        for exercise: ActiveWorkoutRuntimeExercise
    ) {
        let previousDrafts = resolvedDrafts(for: exercise)
        let changeSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previousDrafts,
            current: drafts
        )
        let isCompleted = isExerciseCompleted(drafts)
        let previouslyCompleted = cardStateController.didCompleteCurrentCycle(for: exercise.id)
        let refreshesProjectionImmediately = ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: changeSummary,
            isMetricInputFocused: isMetricInputFocused
        )
        updateDraftsValue(
            drafts,
            for: exercise.id,
            refreshProjectionImmediately: refreshesProjectionImmediately
        )
        persistCommittedUserEditSnapshot(
            writeDurableSnapshot: ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(
                for: changeSummary
            )
        )

        guard previouslyCompleted != isCompleted else { return }
        cardStateController.updateCompletion(
            for: exercise.id,
            isCompleted: isCompleted
        )
        if isCompleted {
            WorkoutFeedbackCenter.shared.exerciseCompleted()
            collapseCompletedExerciseCard(exercise.id)
        }
    }

    @MainActor
    private func collapseCompletedExerciseCard(_ exerciseID: UUID) {
        let wasExpanded = cardStateController.isExpanded(for: exerciseID)
        switch ActiveWorkoutCompletedExercisePresentationPolicy.effect(
            wasExpanded: wasExpanded,
            automaticallyClosesCompletedExercises: profilePreferences.automaticallyClosesCompletedExercises
        ) {
        case .none:
            return
        case .collapseCardKeepingVisible:
            let destination = completedExerciseScrollDestination(for: exerciseID)
            let target = destination.target
            scrollPositionTracker.currentTarget = target
            withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
                cardStateController.setExpanded(false, for: exerciseID)
                // Collapsing a tall card can clamp the previous offset to the bottom of
                // the shorter scroll content. Anchor the card in the same transaction so
                // the completed exercise remains visible after it closes.
                scrollPosition.scrollTo(id: target, anchor: destination.anchor)
            }
        }
    }

    @MainActor
    private func completedExerciseScrollDestination(
        for exerciseID: UUID
    ) -> (target: ActiveWorkoutScrollTarget, anchor: UnitPoint) {
        guard let supersetContext = supersetContextByExerciseID[exerciseID] else {
            return (.exercise(exerciseID), .center)
        }

        let anchor: UnitPoint = supersetContext.position == .first ? .top : .bottom
        return (.superset(supersetContext.groupID), anchor)
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

    private var canRunNonCriticalInteractionWork: Bool {
        ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(
            scenePhase: scenePhase,
            isMetricInputFocused: isMetricInputFocused
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

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var previousPerformanceHydrationDelay: Duration {
        ActiveWorkoutInteractionWorkPolicy.previousPerformanceHydrationDelay()
    }

    private func showExerciseSettings(for exercise: ActiveWorkoutRuntimeExercise) {
        dismissKeyboard()
        exerciseSettingsDraft = ActiveWorkoutExerciseSettingsDraft(
            exerciseID: exercise.id,
            exerciseName: exercise.exerciseNameSnapshot,
            minRepsText: exercise.targetRepMin.map(String.init) ?? "",
            maxRepsText: exercise.targetRepMax.map(String.init) ?? "",
            restSeconds: draftStateStore.restSeconds(for: exercise.id) ?? exercise.restSeconds
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
        _ = draftStateStore.setRestSeconds(normalizedRest, for: draft.exerciseID)
        applyPersistedRestChange(
            sessionExerciseID: draft.exerciseID,
            updatedRest: normalizedRest
        )
        refreshRenderProjection()
        exerciseSettingsDraft = nil
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
            pendingFinishAfterConfirmation = false
            isCancelArmed = false
            guard !isEndingSession else { return }
            isEndingSession = true
            rowFlushCoordinator.flushAll()
            dismissKeyboard()
            guard let finishingSession = currentRuntimeSnapshot() else {
                isEndingSession = false
                showError(WorkoutSessionRepositoryError.sessionNotFound)
                return
            }
            restTimerState.clearRestTimer()
            let finalNotes = notesDraft

            do {
                let result = try await performFinishCommand(session: finishingSession, notes: finalNotes)
                handleCompletedSessionTransition(result)
            } catch {
                isEndingSession = false
                showError(error)
            }
        }
    }

    private func saveSessionAsTemplate() {
        dismissKeyboard()

        let templateName = templateNameDraft
        let selectedFolderID = templateFolderID
        let backgroundStore = persistenceBackgroundStore
        let sessionID = sessionID
        Task.detached(priority: .utility) {
            do {
                _ = try await backgroundStore.performWrite("active-workout.template.create-from-session") { backgroundContext in
                    let repository = TemplateRepository(
                        modelContext: backgroundContext,
                        autoSaveChanges: false,
                        userDataChangeBackupReason: .workoutCompletionTemplateSaved
                    )
                    let template = try repository.createTemplate(
                        fromSessionID: sessionID,
                        name: templateName,
                        folderID: selectedFolderID
                    )
                    try repository.finalizeDeferredUserDataChangesIfNeeded()
                    return template.id
                }
                await MainActor.run {
                    TemplateLibraryChangeBroadcaster.post()
                    requestCompletionAfterSaveTemplateSheetDismissal()
                }
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
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

    private func loadTemplateUpdatePreviewAfterFinish(sessionID: UUID) {
        pendingTemplateUpdatePreviewTask?.cancel()
        let backgroundStore = persistenceBackgroundStore

        pendingTemplateUpdatePreviewTask = Task(priority: .utility) {
            do {
                let preview = try await backgroundStore.perform("active-workout.template.preview-sync") { backgroundContext in
                    try WorkoutTemplateSyncService(modelContext: backgroundContext)
                        .previewTemplateUpdate(forSessionID: sessionID)
                }
                guard !Task.isCancelled else { return }
                pendingTemplateUpdatePreviewTask = nil

                if let preview {
                    pendingTemplateUpdatePreview = preview
                } else {
                    presentWorkoutCompletionSummary()
                }
            } catch {
                guard !Task.isCancelled else { return }
                pendingTemplateUpdatePreviewTask = nil
                isEndingSession = false
                showError(error)
            }
        }
    }

    private func presentWorkoutCompletionSummary() {
        dismissKeyboard()
        isCancelArmed = false
        showingSaveTemplateSheet = false
        pendingCompletionAfterSaveTemplateSheet = false
        pendingCompletionAfterTemplateReviewSheet = false
        pendingTemplateUpdateAfterReviewSheetDismissal = nil
        pendingTemplateUpdatePreviewTask?.cancel()
        pendingTemplateUpdatePreviewTask = nil
        exerciseSettingsDraft = nil
        exerciseComponentPickerDraft = nil
        pendingTemplateUpdatePreview = nil
        let completionSessionID = completedSessionID ?? sessionID
        workoutCompletionPresentationState.queueAfterActiveWorkoutDismiss(sessionID: completionSessionID)
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
    }

    private func minimizeWorkout() {
        isCancelArmed = false
        stageMinimizedRuntimeState()
        dismissKeyboard()
        collapseActiveWorkout()
        dismiss()
    }

    @MainActor
    private func stageMinimizedRuntimeState() {
        rowFlushCoordinator.flushAll()
        guard let snapshot = currentRuntimeSnapshot() else { return }
        runtimeSession = snapshot
        pendingCardioCompletionsByID = [:]
        refreshRenderProjection()
        activeWorkoutPresentationState.stagePreparedFirstRenderSnapshot(
            currentPreparedFirstRenderSnapshot(),
            for: sessionID
        )
        activeWorkoutPresentationState.stageExpandedExerciseIDs(
            cardStateController.expandedExerciseIDs(),
            for: sessionID
        )
        activeWorkoutPresentationState.stageScrollTarget(minimizedScrollRestoreTarget(), for: sessionID)
        activeWorkoutPresentationState.stageScrollOffsetY(currentScrollOffsetY(), for: sessionID)
        scheduleMinimizedDurableSnapshotSave(snapshot)
    }

    @MainActor
    private func scheduleMinimizedDurableSnapshotSave(_ snapshot: ActiveWorkoutRuntimeSession) {
        guard ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .minimize) else {
            return
        }

        let restTimerSnapshot = restTimerState.restTimerSnapshot()
        let scrollTarget = minimizedScrollRestoreTarget()
        let scrollOffsetY = currentScrollOffsetY()
        let expandedExerciseIDs = cardStateController.expandedExerciseIDs()
        _ = activeWorkoutCoordinator.send(.updateScrollOffsetY(scrollOffsetY), persist: false)
        _ = activeWorkoutCoordinator.send(.synchronize(
            session: snapshot,
            restTimer: restTimerSnapshot,
            presentationMode: .collapsed,
            scrollTarget: scrollTarget,
            expandedExerciseIDs: expandedExerciseIDs
        ))
    }

    @MainActor
    private func minimizedScrollRestoreTarget() -> ActiveWorkoutScrollTarget? {
        let validExerciseIDs = Set(sessionExercises.map(\.id))
        return ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: focusedMetricInputExerciseID.flatMap { validExerciseIDs.contains($0) ? $0 : nil },
            keyboardExerciseID: keyboardDismissTargetExerciseID.flatMap { validExerciseIDs.contains($0) ? $0 : nil },
            trackedTarget: scrollPositionTracker.currentTarget,
            expandedExerciseIDs: cardStateController.expandedExerciseIDs(),
            orderedExerciseIDs: sessionExercises.map(\.id),
            orderedCardioActivityIDsByRole: orderedCardioActivityIDsByRole,
            isRestorable: isRestorableScrollTarget,
            hasSession: session != nil
        )
    }

    @MainActor
    private func currentScrollOffsetY() -> Double? {
        scrollPositionTracker.currentOffsetY.map(Double.init)
    }

    @MainActor
    private func isRestorableScrollTarget(_ target: ActiveWorkoutScrollTarget) -> Bool {
        switch target {
        case .header:
            return session != nil
        case .cardio(let role, let activityID):
            guard let activityID else { return false }
            return cardioBlocks(for: role).contains { $0.id == activityID }
        case .exercise(let exerciseID):
            return sessionExercises.contains { $0.id == exerciseID }
        case .superset(let groupID):
            return exerciseDisplayGroups.contains { group in
                guard case .superset(let superset) = group else { return false }
                return superset.groupID == groupID
            }
        case .cancelSection:
            return session != nil && !isEndingSession
        }
    }

    private func presentActiveWorkout() {
        withAnimation(WGJMotion.activeWorkoutPresentationAnimation(reduceMotion: reduceMotion)) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }

    private func collapseActiveWorkout() {
        withAnimation(WGJMotion.activeWorkoutPresentationAnimation(reduceMotion: reduceMotion)) {
            activeWorkoutPresentationState.collapseActiveWorkout()
        }
    }

    private func cancelWorkout() {
        Task { @MainActor in
            dismissKeyboard()
            isCancelArmed = false
            guard !isEndingSession else { return }
            isEndingSession = true
            rowFlushCoordinator.flushAll()
            restTimerState.clearRestTimer()
            activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
            dismiss()

            await activeWorkoutCoordinator.discard()
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
        let backgroundStore = persistenceBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("active-workout.template.apply-sync") { backgroundContext in
                    try WorkoutTemplateSyncService(modelContext: backgroundContext).applyTemplateUpdate(
                        preview,
                        backupReason: .workoutCompletionTemplateSaved
                    )
                }
                await MainActor.run {
                    TemplateLibraryChangeBroadcaster.post()
                    presentWorkoutCompletionSummary()
                }
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
        }
    }

    private func dismissKeyboard() {
        if let focusedMetricInputExerciseID {
            keyboardDismissTargetExerciseID = focusedMetricInputExerciseID
        }

        keyboardDismissToken.requestDismiss()
        Task { @MainActor in
            await Task.yield()
            WGJKeyboard.dismiss()
        }
    }

    private func handleMetricInputFocusChange(_ isFocused: Bool, exerciseID: UUID) {
        if isFocused {
            // Drop the stale pre-keyboard anchor before suspending tracking so it
            // cannot snap the scroll view back when the keyboard later dismisses.
            scrollPositionTracker.currentTarget = nil
            isMetricInputFocused = true
            focusedMetricInputExerciseID = exerciseID
            keyboardDismissTargetExerciseID = nil
            return
        }

        if focusedMetricInputExerciseID == exerciseID {
            focusedMetricInputExerciseID = nil
        }
        if keyboardDismissTargetExerciseID == exerciseID {
            keyboardDismissTargetExerciseID = nil
        }
        isMetricInputFocused = focusedMetricInputExerciseID != nil
    }

    private var exerciseReorderItems: [ExerciseReorderListItem] {
        sessionExercises.map { exercise in
            ExerciseReorderListItem(id: exercise.id, name: exercise.exerciseNameSnapshot)
        }
    }

    @MainActor
    private func discardRemovedExerciseState(keeping currentIDs: Set<UUID>) {
        let draftState = draftStateStore.snapshot()
        let knownIDs =
            Set(draftState.draftsByExerciseID.keys)
            .union(draftState.restsByExerciseID.keys)
            .union(draftState.notesByExerciseID.keys)
            .union(previousResolutionByExerciseID.keys)
            .union(componentResolutionByExerciseID.keys)

        for exerciseID in knownIDs where !currentIDs.contains(exerciseID) {
            discardExerciseState(for: exerciseID)
        }
    }

    @MainActor
    private func discardExerciseState(for exerciseID: UUID) {
        let removedSetIDs = Set((draftStateStore.drafts(for: exerciseID) ?? []).map(\.id))

        draftStateStore.remove(exerciseID: exerciseID)
        previousResolutionByExerciseID[exerciseID] = nil
        componentResolutionByExerciseID[exerciseID] = nil

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
        finishSummaryModel.present(makeFinishSummaryInput())
        showingFinishConfirmation = true
    }

    private func confirmFinishWorkout() {
        guard !isEndingSession else { return }
        pendingFinishAfterConfirmation = true
        showingFinishConfirmation = false
    }

    @MainActor
    private func handleFinishConfirmationChange(from oldValue: Bool, to newValue: Bool) {
        if oldValue, !newValue {
            finishSummaryModel.dismiss()
        }
        guard oldValue, !newValue, pendingFinishAfterConfirmation else { return }
        pendingFinishAfterConfirmation = false

        Task { @MainActor in
            await Task.yield()
            guard !showingFinishConfirmation else { return }
            finishWorkout()
        }
    }

    @MainActor
    private func makeFinishSummaryInput(
        revision: UInt64? = nil
    ) -> ActiveWorkoutFinishSummaryInput {
        ActiveWorkoutFinishSummaryInput(
            revision: revision ?? activeWorkoutCoordinator.storedSnapshot?.revision ?? 0,
            exerciseDrafts: sessionExercises.map { exercise in
                draftStateStore.drafts(for: exercise.id) ?? []
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

    nonisolated fileprivate static func loadDeferredHydrationResult(
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

        if checkpoint == .sceneTransition {
            guard let snapshot = currentRuntimeSnapshot() else {
                pendingCardioCompletionsByID = [:]
                return true
            }

            runtimeSession = snapshot
            pendingCardioCompletionsByID = [:]
            refreshRenderProjection()
            let scrollTarget = minimizedScrollRestoreTarget()
            let scrollOffsetY = currentScrollOffsetY()
            let expandedExerciseIDs = cardStateController.expandedExerciseIDs()
            activeWorkoutPresentationState.stageScrollTarget(scrollTarget, for: sessionID)
            activeWorkoutPresentationState.stageScrollOffsetY(scrollOffsetY, for: sessionID)
            activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: sessionID)

            return await flushCoordinatorSnapshot(
                snapshot,
                presentationMode: .presented,
                scrollTarget: scrollTarget,
                scrollOffsetY: scrollOffsetY,
                expandedExerciseIDs: expandedExerciseIDs
            )
        }

        switch checkpoint {
        case .finish, .cancel:
            return true
        case .minimize, .sceneTransition, .userEdit:
            break
        }

        guard let snapshot = currentRuntimeSnapshot() else {
            pendingCardioCompletionsByID = [:]
            return true
        }

        runtimeSession = snapshot
        pendingCardioCompletionsByID = [:]
        refreshRenderProjection()
        let scrollTarget = minimizedScrollRestoreTarget()
        let scrollOffsetY = currentScrollOffsetY()
        let expandedExerciseIDs = cardStateController.expandedExerciseIDs()
        activeWorkoutPresentationState.stageScrollTarget(scrollTarget, for: sessionID)
        activeWorkoutPresentationState.stageScrollOffsetY(scrollOffsetY, for: sessionID)
        activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: sessionID)
        guard ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: checkpoint) else {
            return true
        }

        return await flushCoordinatorSnapshot(
            snapshot,
            presentationMode: .presented,
            scrollTarget: scrollTarget,
            scrollOffsetY: scrollOffsetY,
            expandedExerciseIDs: expandedExerciseIDs
        )
    }

    @MainActor
    private func flushCoordinatorSnapshot(
        _ snapshot: ActiveWorkoutRuntimeSession,
        presentationMode: ActiveWorkoutStoredPresentationMode,
        scrollTarget: ActiveWorkoutScrollTarget?,
        scrollOffsetY: Double?,
        expandedExerciseIDs: Set<UUID>
    ) async -> Bool {
        _ = activeWorkoutCoordinator.send(.updateScrollOffsetY(scrollOffsetY), persist: false)
        _ = activeWorkoutCoordinator.send(.synchronize(
            session: snapshot,
            restTimer: restTimerState.restTimerSnapshot(),
            presentationMode: presentationMode,
            scrollTarget: scrollTarget,
            expandedExerciseIDs: expandedExerciseIDs
        ))
        await activeWorkoutCoordinator.flushSnapshot()
        guard activeWorkoutCoordinator.persistenceWarning == nil else {
            return false
        }
        return true
    }

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: newPhase) {
            dismissKeyboard()
            isKeyboardVisible = false
            isMetricInputFocused = false
            focusedMetricInputExerciseID = nil
        }

        if ActiveWorkoutInteractionWorkPolicy.shouldCancelNonCriticalInteractionWork(scenePhase: newPhase) {
            cancelNonCriticalInteractionWorkForSceneTransition()
        } else {
            scheduleForegroundNonCriticalInteractionWorkResume()
        }

        guard ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: newPhase) else {
            return
        }

        Task.detached(priority: .userInitiated) {
            await flushDirtyWritesForSceneTransitionIfStillCurrent()
        }
    }

    @MainActor
    private func flushDirtyWritesForSceneTransitionIfStillCurrent() async {
        guard ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: scenePhase) else { return }
        _ = await flushDirtyWritesNow(checkpoint: .sceneTransition)
    }

    @MainActor
    private func updateKeyboardFrameState(from notification: Notification) {
        let keyboardIsVisible = WGJKeyboard.isVisible(
            from: notification,
            containerFrame: keyboardContainerFrame
        )
        scrollPositionTracker.prepareForKeyboardVisibilityChange(
            wasVisible: isKeyboardVisible,
            isVisible: keyboardIsVisible
        )
        isKeyboardVisible = keyboardIsVisible
    }

    @MainActor
    private func cancelNonCriticalInteractionWorkForSceneTransition() {
        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil
        foregroundNonCriticalInteractionWorkTask?.cancel()
        foregroundNonCriticalInteractionWorkTask = nil
    }

    @MainActor
    private func scheduleForegroundNonCriticalInteractionWorkResume() {
        guard loadedExerciseStateStamp != nil else {
            return
        }

        foregroundNonCriticalInteractionWorkTask?.cancel()
        foregroundNonCriticalInteractionWorkTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: ActiveWorkoutInteractionWorkPolicy.foregroundResumeGraceDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                foregroundNonCriticalInteractionWorkTask = nil
                guard canRunNonCriticalInteractionWork else { return }
                scheduleExpandedExerciseHydrationIfNeeded()
            }
        }
    }

    @MainActor
    private func persistCommittedUserEditSnapshot(writeDurableSnapshot: Bool = true) {
        guard !isEndingSession else { return }
        guard let snapshot = currentRuntimeSnapshot() else {
            pendingCardioCompletionsByID = [:]
            return
        }

#if DEBUG
        ActiveWorkoutCardioRuntimeDiagnostics.recordPersistenceBoundary(
            activityID: nil,
            kind: .activeWorkoutSnapshot
        )
#endif

        runtimeSession = snapshot
        pendingCardioCompletionsByID = [:]
        refreshRenderProjection()
        let scrollTarget = minimizedScrollRestoreTarget()
        let scrollOffsetY = currentScrollOffsetY()
        let expandedExerciseIDs = cardStateController.expandedExerciseIDs()
        activeWorkoutPresentationState.stageScrollTarget(scrollTarget, for: sessionID)
        activeWorkoutPresentationState.stageScrollOffsetY(scrollOffsetY, for: sessionID)
        activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: sessionID)

        _ = activeWorkoutCoordinator.send(.updateScrollOffsetY(scrollOffsetY), persist: false)
        let receipt = activeWorkoutCoordinator.send(.synchronize(
            session: snapshot,
            restTimer: restTimerState.restTimerSnapshot(),
            presentationMode: .presented,
            scrollTarget: scrollTarget,
            expandedExerciseIDs: expandedExerciseIDs
        ), persist: writeDurableSnapshot)
        finishSummaryModel.refreshIfPresented(
            makeFinishSummaryInput(revision: receipt.revision)
        )
    }

    @MainActor
    private func performFinishCommand(
        session: ActiveWorkoutRuntimeSession,
        notes: String
    ) async throws -> ActiveWorkoutFinishResult {
        return try await WGJPerformance.measureAsync("active-workout.finish") {
            _ = activeWorkoutCoordinator.send(.updateScrollOffsetY(currentScrollOffsetY()), persist: false)
            _ = activeWorkoutCoordinator.send(.synchronize(
                session: session,
                restTimer: restTimerState.restTimerSnapshot(),
                presentationMode: .presented,
                scrollTarget: minimizedScrollRestoreTarget(),
                expandedExerciseIDs: cardStateController.expandedExerciseIDs()
            ))
            let completion = try await activeWorkoutCoordinator.complete(notes: notes)
            let backgroundStore = persistenceBackgroundStore
            return try await backgroundStore.perform("active-workout.finish-presentation") { backgroundContext in
                try Self.finishSessionPresentation(
                    completedSessionID: completion.sessionID,
                    modelContext: backgroundContext
                )
            }
        }
    }

    nonisolated private static func finishSessionPresentation(
        completedSessionID: UUID,
        modelContext: ModelContext
    ) throws -> ActiveWorkoutFinishResult {
        return try WGJPerformance.measure("workout-completion.presentation-fetch") {
            let completedSessionRepository = WorkoutSessionRepository(modelContext: modelContext)
            guard let completedSession = try completedSessionRepository.session(id: completedSessionID) else {
                throw WorkoutSessionRepositoryError.sessionNotFound
            }
            let folderSnapshots: [ActiveWorkoutTemplateFolderSnapshot]
            let templateUpdatePreview: WorkoutTemplateSyncPreview?
            let canCreateTemplateFromCompletedWorkout: Bool
            if completedSession.templateID == nil {
                let templateRepository = TemplateRepository(modelContext: modelContext)
                canCreateTemplateFromCompletedWorkout = true
                folderSnapshots = try templateRepository.folders()
                    .map(ActiveWorkoutTemplateFolderSnapshot.init(folder:))
                templateUpdatePreview = nil
            } else {
                canCreateTemplateFromCompletedWorkout = true
                folderSnapshots = []
                templateUpdatePreview = nil
            }

            return ActiveWorkoutFinishResult(
                completedSessionID: completedSession.id,
                completedSessionName: completedSession.name,
                completedTemplateID: completedSession.templateID,
                saveTemplateFolders: folderSnapshots,
                templateUpdatePreview: templateUpdatePreview,
                canCreateTemplateFromCompletedWorkout: canCreateTemplateFromCompletedWorkout
            )
        }
    }

    @MainActor
    private func applyPersistedRestChange(
        sessionExerciseID: UUID,
        updatedRest: Int
    ) {
        guard var drafts = draftStateStore.drafts(for: sessionExerciseID) else { return }

        var changed = false
        for index in drafts.indices where !drafts[index].isLocked {
            drafts[index].restSeconds = updatedRest
            changed = true
        }

        guard changed else { return }
        _ = draftStateStore.setDrafts(drafts, for: sessionExerciseID)
        let isCompleted = isExerciseCompleted(drafts)
        if cardStateController.didCompleteCurrentCycle(for: sessionExerciseID) != isCompleted {
            cardStateController.updateCompletion(
                for: sessionExerciseID,
                isCompleted: isCompleted
            )
        }
    }

    private func cardioScrollTarget(
        for activity: ActiveWorkoutRuntimeCardioBlock
    ) -> ActiveWorkoutScrollTarget {
        .cardio(role: activity.role, activityID: activity.id)
    }

    @MainActor
    private func scrollToTarget(
        _ target: ActiveWorkoutScrollTarget,
        anchor: UnitPoint = .top,
        animation: Animation? = nil
    ) {
        if let animation {
            withAnimation(animation) {
                scrollPosition.scrollTo(id: target, anchor: anchor)
            }
        } else {
            scrollPosition.scrollTo(id: target, anchor: anchor)
        }
    }

    @MainActor
    private func resolvedCardioCompletion(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> Bool {
        pendingCardioCompletionsByID[cardioBlock.id] ?? cardioBlock.isCompleted
    }

    @MainActor
    private func resolvedCardioDraft(for cardioBlock: ActiveWorkoutRuntimeCardioBlock) -> WorkoutCardioBlockDraft {
        WorkoutCardioBlockDraft(
            id: cardioBlock.id,
            sourceTemplateCardioID: cardioBlock.sourceTemplateCardioID,
            phase: cardioBlock.phase,
            role: cardioBlock.role,
            sortOrder: cardioBlock.sortOrder,
            catalogExerciseUUID: cardioBlock.catalogExerciseUUID,
            exerciseNameSnapshot: cardioBlock.exerciseNameSnapshot,
            categorySnapshot: cardioBlock.categorySnapshot,
            muscleSummarySnapshot: cardioBlock.muscleSummarySnapshot,
            trackingProfile: cardioBlock.trackingProfile,
            goalKind: cardioBlock.goalKind,
            targetDurationSeconds: cardioBlock.targetDurationSeconds,
            targetDistanceMeters: cardioBlock.targetDistanceMeters,
            actualDurationSeconds: cardioBlock.actualDurationSeconds,
            actualDistanceMeters: cardioBlock.actualDistanceMeters,
            preferredDistanceUnit: cardioBlock.preferredDistanceUnit,
            inclinePercent: cardioBlock.inclinePercent,
            resistanceLevel: cardioBlock.resistanceLevel,
            cardioNotes: cardioBlock.cardioNotes,
            timerState: cardioBlock.timerState,
            timerSegmentStartedAt: cardioBlock.timerSegmentStartedAt,
            timerAccumulatedSeconds: cardioBlock.timerAccumulatedSeconds,
            isCompleted: resolvedCardioCompletion(for: cardioBlock)
        )
    }

    private func cardioSectionSubtitle(for role: WorkoutCardioRole) -> String {
        CardioLocalizedCopy.roleSubtitle(role)
    }

    private func duplicateExerciseRejectedResult(for item: ExerciseCatalogSelection) -> ExercisePickerSelectionResult {
        .rejected(
            ExerciseSelectionDuplicateNotice(
                exerciseName: item.displayName,
                destination: .activeWorkout
            )
        )
    }

}

private struct ActiveWorkoutHeaderCard: View {
    @Binding var sessionNameDraft: String
    @Binding var notesDraft: String

    let session: ActiveWorkoutRuntimeSession
    let exerciseCount: Int
    let cardioCount: Int
    let onSubmit: () -> Void
    let onAddCardio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Session") {
                addCardioButton
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
        Button(action: onAddCardio) {
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
        .buttonStyle(.plain)
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
        .allowsHitTesting(restTimerState.restTimerEndsAt != nil)
    }
}

private struct ActiveWorkoutCancelSection: View {
    let isCancelArmed: Bool
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
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
    let preferredDistanceUnit: WorkoutDistanceUnit
    let automaticallyClosesCompletedExercises: Bool

    nonisolated static let `default` = ActiveWorkoutProfilePreferences(
        preferredLoadUnit: .kg,
        preferredDistanceUnit: .kilometers,
        automaticallyClosesCompletedExercises: true
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

nonisolated struct ActiveWorkoutFinishConfirmationContent: Equatable, Sendable {
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(isResting ? "active-workout-rest-timer" : "active-workout-elapsed-timer")
                    .accessibilityLabel(Text(primaryValue))
                    .accessibilityValue(Text(primaryValue))

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
            .frame(minHeight: 44)
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
                    WGJSectionHeader("Save as Template", subtitle: "Save this workout as a template.")

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

    var id: String {
        switch self {
        case .exercise:
            return "exercise"
        case .replaceExercise(let exerciseID):
            return "replace-exercise-\(exerciseID.uuidString.lowercased())"
        }
    }

    var pickerTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise:
            return "Add Exercise"
        }
    }

    var pickerActionTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise:
            return "Add Exercise"
        }
    }
}

private struct ActiveWorkoutCardioPickerRequest: Identifiable {
    let id = UUID()
    let activityID: UUID?
    let role: WorkoutCardioRole
    let resetsResult: Bool
}

private struct ActiveWorkoutCardioPendingSelection {
    let pickerRequest: ActiveWorkoutCardioPickerRequest
    let selection: ExerciseCatalogSelection
}

private struct ActiveWorkoutCardioSetupRequest: Identifiable {
    var id: UUID { activityID }

    let activityID: UUID
    let isNewActivity: Bool
    let selection: ExerciseCatalogSelection
    let setupDraft: WorkoutCardioSetupDraft
    let resetsResult: Bool
}

private enum ActiveWorkoutCardioConfirmation: Identifiable {
    case timerConflict(ActiveWorkoutCardioTimerConflict)
    case replace(activityID: UUID, activityName: String)
    case remove(activityID: UUID, activityName: String)

    var id: String {
        switch self {
        case .timerConflict(let conflict):
            return conflict.identifier
        case .replace(let activityID, _):
            return "replace-\(activityID)"
        case .remove(let activityID, _):
            return "remove-\(activityID)"
        }
    }

    var title: String {
        switch self {
        case .timerConflict:
            return ActiveWorkoutCardioConfirmationCopy.timerConflictTitle
        case .replace(_, let activityName):
            return ActiveWorkoutCardioConfirmationCopy.replacementTitle(activityName: activityName)
        case .remove(_, let activityName):
            return ActiveWorkoutCardioConfirmationCopy.removalTitle(activityName: activityName)
        }
    }

    var message: String {
        switch self {
        case .timerConflict:
            return ActiveWorkoutCardioConfirmationCopy.timerConflictMessage
        case .replace:
            return ActiveWorkoutCardioConfirmationCopy.replacementMessage
        case .remove:
            return ActiveWorkoutCardioConfirmationCopy.removalMessage
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

private actor ActiveWorkoutDeferredHydrationWorker {
    func loadAfterDelay(
        _ delay: Duration,
        backgroundStore: AppBackgroundStore,
        session: ActiveWorkoutRuntimeSession,
        exerciseIDs: Set<UUID>,
        draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    ) async throws -> ActiveWorkoutDeferredHydrationResult {
        try await Task.sleep(for: delay)
        return try await backgroundStore.perform("active-workout.hydrate.deferred") { backgroundContext in
            try ActiveWorkoutView.loadDeferredHydrationResult(
                modelContext: backgroundContext,
                session: session,
                exerciseIDs: exerciseIDs,
                draftsByExerciseID: draftsByExerciseID
            )
        }
    }
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
    let canCreateTemplateFromCompletedWorkout: Bool
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
    @Environment(RestTimerState.self) private var restTimerState

    let session: ActiveWorkoutRuntimeSession?
    let isEndingSession: Bool
    let reduceMotion: Bool
    let isKeyboardVisible: Bool
    let isMetricInputFocused: Bool
    let onDismissRestTimer: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowDock, let session {
                ActiveWorkoutBottomDock(
                    session: session,
                    reduceMotion: reduceMotion,
                    onDismissRestTimer: onDismissRestTimer
                )
                .transition(WGJMotion.cardTransition(reduceMotion: reduceMotion))
            } else if shouldReserveMetricInputClearance {
                Color.clear
                    .frame(height: ActiveWorkoutKeyboardChromePolicy.metricInputClearanceHeight)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: restTimerState.restTimerPopup?.id)
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: shouldShowDock)
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

    private var shouldReserveMetricInputClearance: Bool {
        ActiveWorkoutKeyboardChromePolicy.shouldReserveMetricInputClearance(
            isMetricInputFocused: isMetricInputFocused
        )
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
    let session = ActiveWorkoutRuntimeSession(name: "Preview Workout")
    NavigationStack {
        ActiveWorkoutView(sessionID: session.id)
    }
    .environment(WorkoutCompletionPresentationState())
    .environment(ActiveWorkoutPresentationState())
    .environment(ActiveWorkoutCoordinator.preview(session: session))
    .environment(RestTimerState())
    .wgjPreviewModelContainer()
}
