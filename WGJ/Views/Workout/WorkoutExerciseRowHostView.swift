import SwiftUI

struct WorkoutExerciseRowHostView: View, Equatable {
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
    let guidance: ActiveWorkoutExerciseGuidancePresentation?
    let preferredLoadUnit: TemplateLoadUnit
    let componentSummaryResolution: ExerciseComponentRotationResolution?
    let componentSummaryAccessibilityIdentifierPrefix: String?
    let exerciseNotes: String
    let restSeconds: Int
    let setDrafts: [WorkoutSessionSetDraft]
    let isExpanded: Bool
    let showsInlineExerciseControls: Bool
    let showsSetProgressChip: Bool
    let manualCompletionMode: Bool
    let isSetEditingEnabled: Bool
    let isSetCompletionEnabled: Bool
    let setCompletionGatePresentation: WorkoutSetCompletionGatePresentation?
    let enablesHeaderSwipeDelete: Bool
    let emphasizesExerciseCompletion: Bool
    let canMoveExerciseUp: Bool
    let canMoveExerciseDown: Bool
    let onExerciseNotesCommitted: (String) -> Void
    let onSetDraftsCommitted: ([WorkoutSessionSetDraft]) -> Void
    let onRestCommitted: (Int) -> Void
    let onExpandedChanged: (Bool) -> Void
    let onSetCompletionChange: (UUID, String?, Int, Bool) -> Void
    let onExerciseSettings: (() -> Void)?
    let onExerciseComponentPicker: (() -> Void)?
    let onExerciseMoveUp: (() -> Void)?
    let onExerciseMoveDown: (() -> Void)?
    let onExerciseMoveToPosition: (() -> Void)?
    let onExerciseReplace: (() -> Void)?
    let onExerciseDelete: (() -> Void)?
    let flushCoordinator: WorkoutExerciseRowFlushCoordinator?
    let keyboardDismissToken: ActiveWorkoutKeyboardDismissToken
    let onInputFocusChange: (Bool) -> Void

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
        personalRecordSummaryKinds: [WorkoutPersonalRecordKind] = [],
        personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]] = [:],
        guidance: ActiveWorkoutExerciseGuidancePresentation? = nil,
        preferredLoadUnit: TemplateLoadUnit,
        componentSummaryResolution: ExerciseComponentRotationResolution? = nil,
        componentSummaryAccessibilityIdentifierPrefix: String? = nil,
        exerciseNotes: String = "",
        restSeconds: Int,
        setDrafts: [WorkoutSessionSetDraft],
        isExpanded: Bool,
        showsInlineExerciseControls: Bool = false,
        showsSetProgressChip: Bool = false,
        manualCompletionMode: Bool = true,
        isSetEditingEnabled: Bool = true,
        isSetCompletionEnabled: Bool = true,
        setCompletionGatePresentation: WorkoutSetCompletionGatePresentation? = nil,
        enablesHeaderSwipeDelete: Bool = true,
        emphasizesExerciseCompletion: Bool = true,
        canMoveExerciseUp: Bool = false,
        canMoveExerciseDown: Bool = false,
        onExerciseNotesCommitted: @escaping (String) -> Void = { _ in },
        onSetDraftsCommitted: @escaping ([WorkoutSessionSetDraft]) -> Void,
        onRestCommitted: @escaping (Int) -> Void,
        onExpandedChanged: @escaping (Bool) -> Void,
        onSetCompletionChange: @escaping (UUID, String?, Int, Bool) -> Void = { _, _, _, _ in },
        onExerciseSettings: (() -> Void)? = nil,
        onExerciseComponentPicker: (() -> Void)? = nil,
        onExerciseMoveUp: (() -> Void)? = nil,
        onExerciseMoveDown: (() -> Void)? = nil,
        onExerciseMoveToPosition: (() -> Void)? = nil,
        onExerciseReplace: (() -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil,
        flushCoordinator: WorkoutExerciseRowFlushCoordinator? = nil,
        keyboardDismissToken: ActiveWorkoutKeyboardDismissToken = ActiveWorkoutKeyboardDismissToken(),
        onInputFocusChange: @escaping (Bool) -> Void = { _ in }
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
        self.guidance = guidance
        self.preferredLoadUnit = preferredLoadUnit
        self.componentSummaryResolution = componentSummaryResolution
        self.componentSummaryAccessibilityIdentifierPrefix = componentSummaryAccessibilityIdentifierPrefix
        self.exerciseNotes = exerciseNotes
        self.restSeconds = restSeconds
        self.setDrafts = setDrafts
        self.isExpanded = isExpanded
        self.showsInlineExerciseControls = showsInlineExerciseControls
        self.showsSetProgressChip = showsSetProgressChip
        self.manualCompletionMode = manualCompletionMode
        self.isSetEditingEnabled = isSetEditingEnabled
        self.isSetCompletionEnabled = isSetCompletionEnabled
        self.setCompletionGatePresentation = setCompletionGatePresentation
        self.enablesHeaderSwipeDelete = enablesHeaderSwipeDelete
        self.emphasizesExerciseCompletion = emphasizesExerciseCompletion
        self.canMoveExerciseUp = canMoveExerciseUp
        self.canMoveExerciseDown = canMoveExerciseDown
        self.onExerciseNotesCommitted = onExerciseNotesCommitted
        self.onSetDraftsCommitted = onSetDraftsCommitted
        self.onRestCommitted = onRestCommitted
        self.onExpandedChanged = onExpandedChanged
        self.onSetCompletionChange = onSetCompletionChange
        self.onExerciseSettings = onExerciseSettings
        self.onExerciseComponentPicker = onExerciseComponentPicker
        self.onExerciseMoveUp = onExerciseMoveUp
        self.onExerciseMoveDown = onExerciseMoveDown
        self.onExerciseMoveToPosition = onExerciseMoveToPosition
        self.onExerciseReplace = onExerciseReplace
        self.onExerciseDelete = onExerciseDelete
        self.flushCoordinator = flushCoordinator
        self.keyboardDismissToken = keyboardDismissToken
        self.onInputFocusChange = onInputFocusChange
        self._localRestSeconds = State(initialValue: restSeconds)
        self._localSetDrafts = State(initialValue: setDrafts)
        self._localExerciseNotes = State(initialValue: exerciseNotes)
        self._editingCoordinator = State(
            initialValue: WorkoutExerciseEditingCoordinator(
                setDrafts: setDrafts,
                restSeconds: restSeconds,
                notes: exerciseNotes,
                onDraftsCommitted: onSetDraftsCommitted,
                onRestCommitted: onRestCommitted,
                onNotesCommitted: onExerciseNotesCommitted,
                onCompletionChanged: onSetCompletionChange
            )
        )
    }

    var body: some View {
        WorkoutSessionExerciseGridEditor(
            exerciseName: exerciseName,
            muscleSummary: muscleSummary,
            category: category,
            exerciseIndexTitle: exerciseIndexTitle,
            exerciseAccessibilityIdentifier: exerciseAccessibilityIdentifier,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            previousPerformanceResolution: previousPerformanceResolution,
            personalRecordSummaryKinds: personalRecordSummaryKinds,
            personalRecordKindsBySetID: personalRecordKindsBySetID,
            guidance: guidance,
            preferredLoadUnit: preferredLoadUnit,
            componentSummaryResolution: componentSummaryResolution,
            componentSummaryAccessibilityIdentifierPrefix: componentSummaryAccessibilityIdentifierPrefix,
            exerciseNotes: Binding(
                get: { localExerciseNotes },
                set: { updated in
                    localExerciseNotes = updated
                    editingCoordinator.stageNotesCommit(updated)
                }
            ),
            restSeconds: Binding(
                get: { localRestSeconds },
                set: { updated in
                    localRestSeconds = updated
                    editingCoordinator.stageRestCommit(updated)
                }
            ),
            setDrafts: Binding(
                get: { localSetDrafts },
                set: { updated in
                    localSetDrafts = updated
                    editingCoordinator.stageDrafts(updated)
                }
            ),
            isExpanded: Binding(
                get: { isExpanded },
                set: { onExpandedChanged($0) }
            ),
            showsInlineExerciseControls: showsInlineExerciseControls,
            showsSetProgressChip: showsSetProgressChip,
            manualCompletionMode: manualCompletionMode,
            isSetEditingEnabled: isSetEditingEnabled,
            isSetCompletionEnabled: isSetCompletionEnabled,
            setCompletionGatePresentation: setCompletionGatePresentation,
            enablesHeaderSwipeDelete: enablesHeaderSwipeDelete,
            emphasizesExerciseCompletion: emphasizesExerciseCompletion,
            onCommitRequest: { drafts, restSeconds in
                editingCoordinator.requestImmediateCommit(
                    setDrafts: drafts,
                    restSeconds: restSeconds,
                    notes: localExerciseNotes
                )
            },
            onSetCompletionChange: { setID, setLabel, restSeconds, isCompleted in
                editingCoordinator.relayCompletionChange(
                    setID: setID,
                    setLabel: setLabel,
                    restSeconds: restSeconds,
                    isCompleted: isCompleted
                )
            },
            onExerciseSettings: onExerciseSettings,
            onExerciseComponentPicker: onExerciseComponentPicker,
            canMoveExerciseUp: canMoveExerciseUp,
            canMoveExerciseDown: canMoveExerciseDown,
            onExerciseMoveUp: onExerciseMoveUp,
            onExerciseMoveDown: onExerciseMoveDown,
            onExerciseMoveToPosition: onExerciseMoveToPosition,
            onExerciseReplace: onExerciseReplace,
            onExerciseDelete: onExerciseDelete,
            flushCoordinator: flushCoordinator,
            flushIdentifier: exerciseID,
            keyboardDismissToken: keyboardDismissToken,
            onInputFocusChange: onInputFocusChange,
            onDirtyStateChange: { isDirty in
                flushCoordinator?.setDirty(isDirty, for: exerciseID)
            }
        )
        .onChange(of: restSeconds) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: newValue,
                notes: exerciseNotes
            )
            guard localRestSeconds != newValue else { return }
            localRestSeconds = newValue
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
        .onChange(of: exerciseNotes) { _, newValue in
            editingCoordinator.syncCommittedState(
                setDrafts: setDrafts,
                restSeconds: restSeconds,
                notes: newValue
            )
            guard localExerciseNotes != newValue else { return }
            localExerciseNotes = newValue
        }
        .onDisappear {
            flushPendingEditsIfNeeded()
        }
    }

    private func flushPendingEditsIfNeeded() {
        guard editingCoordinator.hasPendingChanges else { return }
        editingCoordinator.flushCommits()
    }

    static func == (lhs: WorkoutExerciseRowHostView, rhs: WorkoutExerciseRowHostView) -> Bool {
        lhs.exerciseID == rhs.exerciseID
            && lhs.exerciseAccessibilityIdentifier == rhs.exerciseAccessibilityIdentifier
            && lhs.exerciseName == rhs.exerciseName
            && lhs.muscleSummary == rhs.muscleSummary
            && lhs.category == rhs.category
            && lhs.exerciseIndexTitle == rhs.exerciseIndexTitle
            && lhs.targetRepMin == rhs.targetRepMin
            && lhs.targetRepMax == rhs.targetRepMax
            && lhs.previousPerformanceResolution == rhs.previousPerformanceResolution
            && lhs.personalRecordSummaryKinds == rhs.personalRecordSummaryKinds
            && lhs.personalRecordKindsBySetID == rhs.personalRecordKindsBySetID
            && lhs.guidance == rhs.guidance
            && lhs.preferredLoadUnit == rhs.preferredLoadUnit
            && lhs.componentSummaryResolution == rhs.componentSummaryResolution
            && lhs.componentSummaryAccessibilityIdentifierPrefix == rhs.componentSummaryAccessibilityIdentifierPrefix
            && lhs.exerciseNotes == rhs.exerciseNotes
            && lhs.restSeconds == rhs.restSeconds
            && lhs.setDrafts == rhs.setDrafts
            && lhs.isExpanded == rhs.isExpanded
            && lhs.showsInlineExerciseControls == rhs.showsInlineExerciseControls
            && lhs.showsSetProgressChip == rhs.showsSetProgressChip
            && lhs.manualCompletionMode == rhs.manualCompletionMode
            && lhs.isSetEditingEnabled == rhs.isSetEditingEnabled
            && lhs.isSetCompletionEnabled == rhs.isSetCompletionEnabled
            && lhs.setCompletionGatePresentation == rhs.setCompletionGatePresentation
            && lhs.enablesHeaderSwipeDelete == rhs.enablesHeaderSwipeDelete
            && lhs.emphasizesExerciseCompletion == rhs.emphasizesExerciseCompletion
            && lhs.canMoveExerciseUp == rhs.canMoveExerciseUp
            && lhs.canMoveExerciseDown == rhs.canMoveExerciseDown
            && (lhs.onExerciseSettings != nil) == (rhs.onExerciseSettings != nil)
            && (lhs.onExerciseComponentPicker != nil) == (rhs.onExerciseComponentPicker != nil)
            && (lhs.onExerciseMoveUp != nil) == (rhs.onExerciseMoveUp != nil)
            && (lhs.onExerciseMoveDown != nil) == (rhs.onExerciseMoveDown != nil)
            && (lhs.onExerciseMoveToPosition != nil) == (rhs.onExerciseMoveToPosition != nil)
            && (lhs.onExerciseReplace != nil) == (rhs.onExerciseReplace != nil)
            && (lhs.onExerciseDelete != nil) == (rhs.onExerciseDelete != nil)
            && lhs.keyboardDismissToken == rhs.keyboardDismissToken
    }
}
