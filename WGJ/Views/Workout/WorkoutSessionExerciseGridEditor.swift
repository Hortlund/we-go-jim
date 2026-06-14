import Foundation
import SwiftUI

nonisolated struct ActiveWorkoutKeyboardDismissToken: Equatable, Sendable {
    private(set) var value: Int = 0

    mutating func requestDismiss() {
        value &+= 1
    }
}

struct WorkoutSessionExerciseGridEditor: View {
    @Environment(\.scenePhase) private var scenePhase

    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String?
    let exerciseAccessibilityIdentifier: String?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let previousPerformanceResolution: WorkoutPreviousPerformanceResolution
    let personalRecordSummaryKinds: [WorkoutPersonalRecordKind]
    let personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]]
    let guidance: ActiveWorkoutExerciseGuidancePresentation?
    let preferredLoadUnit: TemplateLoadUnit
    let componentSummaryResolution: ExerciseComponentRotationResolution?
    let componentSummaryAccessibilityIdentifierPrefix: String?

    @Binding var exerciseNotes: String
    @Binding var restSeconds: Int
    @Binding var setDrafts: [WorkoutSessionSetDraft]

    var showsInlineExerciseControls: Bool
    var showsSetProgressChip: Bool
    var manualCompletionMode: Bool
    var isSetEditingEnabled: Bool
    var isSetCompletionEnabled: Bool
    var setCompletionGatePresentation: WorkoutSetCompletionGatePresentation?
    var enablesHeaderSwipeDelete: Bool
    var emphasizesExerciseCompletion: Bool
    var onCommitRequest: (([WorkoutSessionSetDraft], Int) -> Void)?
    var onSetCompletionChange: ((UUID, String?, Int, Bool) -> Void)?
    var onExerciseSettings: (() -> Void)?
    var onExerciseComponentPicker: (() -> Void)?
    var canMoveExerciseUp: Bool
    var canMoveExerciseDown: Bool
    var onExerciseMoveUp: (() -> Void)?
    var onExerciseMoveDown: (() -> Void)?
    var onExerciseMoveToPosition: (() -> Void)?
    var onExerciseReplace: (() -> Void)?
    var onExerciseDelete: (() -> Void)?
    var flushCoordinator: WorkoutExerciseRowFlushCoordinator?
    var flushIdentifier: UUID?
    var keyboardDismissToken: ActiveWorkoutKeyboardDismissToken
    var onInputFocusChange: (Bool) -> Void
    var onDirtyStateChange: (Bool) -> Void

    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool
    @State private var rowSnapshots: [WorkoutSessionExerciseSetRowDisplaySnapshot]
    @State private var cachedCompletedSetCount: Int
    @State private var exerciseSwipeOffset: CGFloat = 0
    @State private var exerciseSwipeRemoving = false
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]
    @State private var metricInputDraftBuffer = WorkoutMetricInputDraftStore()
    @State private var revealedCompletionGateSetIDs: Set<UUID> = []
    @State private var pendingDisplayRefreshTask: Task<Void, Never>?
    @State private var pendingCommitTask: Task<Void, Never>?
    @State private var suppressNextSetDraftsDisplayRefresh = false
    @State private var suppressNextFocusLossCommit = false
    @FocusState private var focusedInput: SetInputFocus?

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
    private let displayRefreshDebounce = Duration.milliseconds(90)
    private let commitDebounce = Duration.milliseconds(150)

    private struct SetInputFocus: Hashable {
        let setID: UUID
        let metric: Metric

        enum Metric: Hashable {
            case weight
            case reps
        }
    }

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        exerciseIndexTitle: String? = nil,
        exerciseAccessibilityIdentifier: String? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        previousPerformanceResolution: WorkoutPreviousPerformanceResolution,
        personalRecordSummaryKinds: [WorkoutPersonalRecordKind] = [],
        personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]] = [:],
        guidance: ActiveWorkoutExerciseGuidancePresentation? = nil,
        preferredLoadUnit: TemplateLoadUnit = .kg,
        componentSummaryResolution: ExerciseComponentRotationResolution? = nil,
        componentSummaryAccessibilityIdentifierPrefix: String? = nil,
        exerciseNotes: Binding<String> = .constant(""),
        restSeconds: Binding<Int>,
        setDrafts: Binding<[WorkoutSessionSetDraft]>,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        showsInlineExerciseControls: Bool = true,
        showsSetProgressChip: Bool = true,
        manualCompletionMode: Bool = false,
        isSetEditingEnabled: Bool = true,
        isSetCompletionEnabled: Bool = true,
        setCompletionGatePresentation: WorkoutSetCompletionGatePresentation? = nil,
        enablesHeaderSwipeDelete: Bool = false,
        emphasizesExerciseCompletion: Bool = false,
        onCommitRequest: (([WorkoutSessionSetDraft], Int) -> Void)? = nil,
        onSetCompletionChange: ((UUID, String?, Int, Bool) -> Void)? = nil,
        onExerciseSettings: (() -> Void)? = nil,
        onExerciseComponentPicker: (() -> Void)? = nil,
        canMoveExerciseUp: Bool = false,
        canMoveExerciseDown: Bool = false,
        onExerciseMoveUp: (() -> Void)? = nil,
        onExerciseMoveDown: (() -> Void)? = nil,
        onExerciseMoveToPosition: (() -> Void)? = nil,
        onExerciseReplace: (() -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil,
        flushCoordinator: WorkoutExerciseRowFlushCoordinator? = nil,
        flushIdentifier: UUID? = nil,
        keyboardDismissToken: ActiveWorkoutKeyboardDismissToken = ActiveWorkoutKeyboardDismissToken(),
        onInputFocusChange: @escaping (Bool) -> Void = { _ in },
        onDirtyStateChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.exerciseIndexTitle = exerciseIndexTitle
        self.exerciseAccessibilityIdentifier = exerciseAccessibilityIdentifier
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.previousPerformanceResolution = previousPerformanceResolution
        self.personalRecordSummaryKinds = personalRecordSummaryKinds
        self.personalRecordKindsBySetID = personalRecordKindsBySetID
        self.guidance = guidance
        self.preferredLoadUnit = preferredLoadUnit
        self.componentSummaryResolution = componentSummaryResolution
        self.componentSummaryAccessibilityIdentifierPrefix = componentSummaryAccessibilityIdentifierPrefix
        self._exerciseNotes = exerciseNotes
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.externalIsExpanded = isExpanded
        self.showsInlineExerciseControls = showsInlineExerciseControls
        self.showsSetProgressChip = showsSetProgressChip
        self.manualCompletionMode = manualCompletionMode
        self.isSetEditingEnabled = isSetEditingEnabled
        self.isSetCompletionEnabled = isSetCompletionEnabled
        self.setCompletionGatePresentation = setCompletionGatePresentation
        self.enablesHeaderSwipeDelete = enablesHeaderSwipeDelete
        self.emphasizesExerciseCompletion = emphasizesExerciseCompletion
        self.onCommitRequest = onCommitRequest
        self.onSetCompletionChange = onSetCompletionChange
        self.onExerciseSettings = onExerciseSettings
        self.onExerciseComponentPicker = onExerciseComponentPicker
        self.canMoveExerciseUp = canMoveExerciseUp
        self.canMoveExerciseDown = canMoveExerciseDown
        self.onExerciseMoveUp = onExerciseMoveUp
        self.onExerciseMoveDown = onExerciseMoveDown
        self.onExerciseMoveToPosition = onExerciseMoveToPosition
        self.onExerciseReplace = onExerciseReplace
        self.onExerciseDelete = onExerciseDelete
        self.flushCoordinator = flushCoordinator
        self.flushIdentifier = flushIdentifier
        self.keyboardDismissToken = keyboardDismissToken
        self.onInputFocusChange = onInputFocusChange
        self.onDirtyStateChange = onDirtyStateChange
        self._localIsExpanded = State(initialValue: isExpanded?.wrappedValue ?? initiallyExpanded)
        let startsExpanded = isExpanded?.wrappedValue ?? initiallyExpanded
        let initialRows = startsExpanded
            ? Self.makeDisplayRows(
                setDrafts: setDrafts.wrappedValue,
                previousPerformanceResolution: previousPerformanceResolution,
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                restSeconds: restSeconds.wrappedValue,
                formatWeight: { WGJFormatters.decimalString($0) }
            )
            : []
        self._rowSnapshots = State(initialValue: initialRows)
        self._cachedCompletedSetCount = State(
            initialValue: setDrafts.wrappedValue.reduce(0) { partialResult, draft in
                partialResult + (draft.isCycleCompleted ? 1 : 0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if isExpanded {
                if showsInlineExerciseControls {
                    controlsSection
                }
                exerciseNotesSection
                setsSection
            }
        }
        .padding(16)
        .background {
            cardBackgroundLayer
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .wgjCardContainer(strong: true)
        .overlay {
            cardOverlayLayer
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .shadow(
            color: shouldEmphasizeCompletedExercise ? WGJTheme.success.opacity(0.12) : .clear,
            radius: 16,
            x: 0,
            y: 8
        )
        .onAppear {
            syncCompletedSetCount()
            if isExpanded {
                refreshDisplayRows()
            }
            if let flushIdentifier {
                flushCoordinator?.register(exerciseID: flushIdentifier) {
                    flushPendingEditorState()
                }
            }
        }
        .onDisappear {
            onInputFocusChange(false)
            flushPendingEditorState()
            if let flushIdentifier {
                flushCoordinator?.unregister(exerciseID: flushIdentifier)
            }
        }
        .onChange(of: setDrafts) { previousValue, newValue in
            handleSetDraftsChange(previousValue: previousValue, currentValue: newValue)
        }
        .onChange(of: previousPerformanceResolution) { _, _ in
            handlePreviousPerformanceResolutionChange()
        }
        .onChange(of: exerciseNotes) { previousValue, currentValue in
            scheduleCommitRequest(
                ActiveWorkoutEditorCommitDisposition.fieldChange(
                    previous: previousValue,
                    current: currentValue
                )
            )
        }
        .onChange(of: restSeconds) { _, _ in
            refreshDisplayRows()
        }
        .onChange(of: targetRepMin) { _, _ in
            refreshDisplayRows()
        }
        .onChange(of: targetRepMax) { _, _ in
            refreshDisplayRows()
        }
        .onChange(of: focusedInput) { previousFocus, newFocus in
            onInputFocusChange(newFocus != nil)
            handleFocusedInputChange(previousFocus, newFocus)
        }
        .onChange(of: keyboardDismissToken) { _, _ in
            dismissInputFocus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            guard focusedInput != nil else { return }
            dismissInputFocus()
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                refreshDisplayRows()
            } else {
                pendingDisplayRefreshTask?.cancel()
                pendingDisplayRefreshTask = nil
                rowSnapshots = []
            }
        }
        .onChange(of: isSetCompletionEnabled) { _, isEnabled in
            if isEnabled {
                revealedCompletionGateSetIDs.removeAll()
            }
        }
    }

    private var previousBySetIndex: [Int: WorkoutPreviousSetSnapshot] {
        previousPerformanceResolution.previousBySetIndex
    }

    private var cardBackgroundLayer: some View {
        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
            .fill(completedExerciseBackgroundStyle)
    }

    private var cardOverlayLayer: some View {
        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
            .stroke(
                isExerciseCompleted
                    ? WGJTheme.success.opacity(shouldEmphasizeCompletedExercise ? 0.60 : 0.34)
                    : Color.clear,
                lineWidth: shouldEmphasizeCompletedExercise ? 2 : 1.2
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var headerSection: some View {
        if enablesHeaderSwipeDelete, let onExerciseDelete {
            SwipeDeleteRow(
                offset: $exerciseSwipeOffset,
                isRemoving: $exerciseSwipeRemoving,
                gestureStrategy: .simultaneous
            ) {
                onExerciseDelete()
            } content: {
                headerContent
            }
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let exerciseIndexTitle {
                    Text(exerciseIndexTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(shouldEmphasizeCompletedExercise ? WGJTheme.success : WGJTheme.accentCyan)
                }

                exerciseNameText

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)

                if let componentSummaryResolution,
                   componentSummaryResolution.availableComponents.count > 1 {
                    ActiveWorkoutExerciseComponentSummaryView(
                        resolution: componentSummaryResolution,
                        accessibilityIdentifierPrefix: componentSummaryAccessibilityIdentifierPrefix
                    )
                }

                if let guidance {
                    ActiveWorkoutGuidanceDisclosureView(
                        guidance: guidance,
                        accessibilityIdentifier: exerciseAccessibilityIdentifier
                    )
                }

                if !personalRecordSummaryKinds.isEmpty {
                    personalRecordChipGroup(personalRecordSummaryKinds)
                }

                headerSummaryChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                if onExerciseSettings != nil
                    || onExerciseComponentPicker != nil
                    || onExerciseMoveUp != nil
                    || onExerciseMoveDown != nil
                    || onExerciseMoveToPosition != nil
                    || onExerciseReplace != nil
                    || onExerciseDelete != nil {
                    WGJActionMenuButton("Exercise Actions") {
                        if let onExerciseComponentPicker {
                            Button {
                                onExerciseComponentPicker()
                            } label: {
                                Label("Choose exercise", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .accessibilityIdentifier("workout-exercise-choose-component-button")
                        }

                        if let onExerciseSettings {
                            Button {
                                onExerciseSettings()
                            } label: {
                                Label("Exercise Settings", systemImage: "slider.horizontal.3")
                            }
                        }

                        if let onExerciseReplace {
                            Button {
                                onExerciseReplace()
                            } label: {
                                Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .accessibilityIdentifier("active-workout-replace-exercise-button")
                        }

                        if let onExerciseMoveUp {
                            Button {
                                onExerciseMoveUp()
                            } label: {
                                Label("Move up", systemImage: "arrow.up")
                            }
                            .disabled(!canMoveExerciseUp)
                        }

                        if let onExerciseMoveDown {
                            Button {
                                onExerciseMoveDown()
                            } label: {
                                Label("Move down", systemImage: "arrow.down")
                            }
                            .disabled(!canMoveExerciseDown)
                        }

                        if let onExerciseMoveToPosition {
                            Button {
                                onExerciseMoveToPosition()
                            } label: {
                                Label("Move to position", systemImage: "list.number")
                            }
                        }

                        if let onExerciseDelete {
                            Button(role: .destructive) {
                                onExerciseDelete()
                            } label: {
                                Label("Delete exercise", systemImage: "trash")
                            }
                        }
                    } label: {
                        headerIcon(symbol: "ellipsis.circle")
                    }
                    .accessibilityIdentifier(
                        exerciseAccessibilityIdentifier.map { "\($0)-actions-button" }
                            ?? "workout-exercise-actions-button"
                    )
                }

                Button {
                    toggleExpanded()
                } label: {
                    headerIcon(symbol: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(exerciseName)" : "Expand \(exerciseName)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier(
                    exerciseAccessibilityIdentifier.map { "\($0)-expand-button" }
                        ?? "workout-exercise-expand-button"
                )
            }
        }
    }

    private var exerciseNameText: some View {
        Text(exerciseName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(shouldEmphasizeCompletedExercise ? WGJTheme.success : WGJTheme.accentBlue)
            .wgjSingleLineText(scale: 0.8)
            .accessibilityIdentifier(exerciseAccessibilityIdentifier ?? "")
    }

    private var controlsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                if shouldShowRepRange {
                    repRangeControl
                }

                restControl
            }

            VStack(alignment: .leading, spacing: 10) {
                if shouldShowRepRange {
                    repRangeControl
                }

                restControl
            }
        }
    }

    private var repRangeControl: some View {
        compactControlCard(
            title: "Rep Range",
            subtitle: "Target range for the set entries below.",
            tint: WGJTheme.accentGold
        ) {
            HStack(spacing: 10) {
                rangeValuePill(displayRepRange.min.map(String.init) ?? "Min")

                Text("to")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentGold)

                rangeValuePill(displayRepRange.max.map(String.init) ?? "Max")
            }
        }
    }

    private func rangeValuePill(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WGJTheme.field)
            )
    }

    private var restControl: some View {
        compactControlCard(
            title: "Default Rest",
            subtitle: "Used when you reset a set timer.",
            tint: WGJTheme.accentBlue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                WGJActionMenuButton("Default Rest") {
                    ForEach(restPresets, id: \.self) { value in
                        Button(Self.formattedRest(value)) {
                            updateRest(value)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(Self.formattedRest(restSeconds), systemImage: "timer")
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
                    restAdjustButton(symbol: "minus.circle", action: {
                        updateRest(restSeconds - 15)
                    })

                    restAdjustButton(symbol: "plus.circle.fill", action: {
                        updateRest(restSeconds + 15)
                    })

                    Spacer(minLength: 8)
                }
            }
        }
    }

    private var setsSection: some View {
        let rows = displayRows

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logged Sets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer()

                Text("\(rows.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            if rows.isEmpty {
                Text("No sets yet.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(.vertical, 6)
            }

            ForEach(rows) { row in
                SwipeDeleteRow(
                    offset: setSwipeOffsetBinding(for: row.id),
                    isRemoving: setRemovingBinding(for: row.id),
                    isEnabled: isSetEditingEnabled && !row.set.isLocked,
                    gestureStrategy: .simultaneous
                ) {
                    removeSet(withID: row.id)
                } content: {
                    setCard(row)
                }
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(WGJTheme.accentBlue.opacity(0.28), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(WGJTheme.textPrimary)
            .disabled(!isSetEditingEnabled)
            .opacity(isSetEditingEnabled ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var exerciseNotesSection: some View {
        WGJExerciseNotesEditor(
            placeholder: "Add notes for this exercise",
            accessibilityIdentifier: exerciseAccessibilityIdentifier.map { "\($0)-notes-field" },
            notes: $exerciseNotes
        )
    }

    private func currentDisplayRow(
        for row: WorkoutSessionExerciseSetRowDisplaySnapshot
    ) -> WorkoutSessionExerciseSetRowDisplaySnapshot? {
        guard let currentIndex = indexForSetID(row.id),
              setDrafts.indices.contains(currentIndex)
        else {
            return nil
        }

        let currentSet = setDrafts[currentIndex]
        guard row.index != currentIndex || row.set != currentSet else {
            return row
        }

        let workingSetNumber = setDrafts
            .prefix(currentIndex + 1)
            .filter { !$0.isWarmup }
            .count
        let row = Self.makeDisplayRow(
            draft: currentSet,
            index: currentIndex,
            workingSetNumber: workingSetNumber,
            previousPerformanceResolution: previousPerformanceResolution,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            formatWeight: formatWeight
        )
        guard row.id == currentSet.id else { return nil }

        return row
    }

    @ViewBuilder
    private func setCard(_ row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        if let row = currentDisplayRow(for: row) {
            let set = row.set
            let inlineHintPresentation = row.inlineHintPresentation
            let personalRecordKinds = personalRecordKindsBySetID[row.id] ?? []
            let hasPersonalRecord = !personalRecordKinds.isEmpty
            let completionPresentation = completionControlPresentation(for: row)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    setBadge(for: row)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)
                                .wgjSingleLineText(scale: 0.84)

                            if set.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(WGJTheme.accentGold)
                            }

                            if hasPersonalRecord {
                                Image(systemName: "trophy.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WGJTheme.accentGold)
                            }
                        }

                        if (!manualCompletionMode || inlineHintPresentation == nil),
                           !row.previousSummary.isEmpty {
                            Text(row.previousSummary)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(2)
                                .monospacedDigit()
                        }

                        if let metadata = row.metadataLine {
                            Text(metadata)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(1)
                        }

                        if hasPersonalRecord {
                            personalRecordChipGroup(personalRecordKinds, compact: true)
                        }
                    }

                    Spacer(minLength: 8)

                    setMenu(for: row)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        metricField(title: "Weight", supporting: nil) {
                            loadField(at: row.index)
                        }

                        metricField(title: "Reps", supporting: nil) {
                            repsFieldWithCompletionControl(for: row, presentation: completionPresentation)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        metricField(title: "Weight", supporting: nil) {
                            loadField(at: row.index)
                        }

                        metricField(title: "Reps", supporting: nil) {
                            repsFieldWithCompletionControl(for: row, presentation: completionPresentation)
                        }
                    }
                }

                if manualCompletionMode, let inlineHintPresentation {
                    inlineHintRow(inlineHintPresentation, at: row.index)
                }

                if !set.dropStages.isEmpty {
                    dropStagesSection(for: row.index)
                }

                if let supplementalRow = completionPresentation?.supplementalRow {
                    completionSupplementalRow(supplementalRow, for: row)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(setCardFill(for: set, hasPersonalRecord: hasPersonalRecord))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(setCardStroke(for: set, hasPersonalRecord: hasPersonalRecord), lineWidth: hasPersonalRecord ? 1.35 : 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func inlineHintRow(_ presentation: WorkoutSetInlineHintPresentation, at index: Int) -> some View {
        if setDrafts.indices.contains(index) {
            let canApplyPrevious = isSetEditingEnabled && presentation.canApplyPrevious && !setDrafts[index].isLocked

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        inlineHintAim(presentation.aimText)

                        if let statusText = presentation.statusText {
                            progressStatusChip(text: statusText, tone: presentation.statusTone)
                        }
                    }

                    Spacer(minLength: 8)

                    if canApplyPrevious {
                        applyPreviousButton(at: index)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    inlineHintAim(presentation.aimText)

                    if let statusText = presentation.statusText {
                        progressStatusChip(text: statusText, tone: presentation.statusTone)
                    }

                    if canApplyPrevious {
                        applyPreviousButton(at: index)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func inlineHintAim(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "target")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
        }
    }

    private func progressStatusChip(text: String, tone: WorkoutSetProgressTone) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(progressToneColor(for: tone))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(progressToneColor(for: tone).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(progressToneColor(for: tone).opacity(0.22), lineWidth: 1)
                    )
            )
            .layoutPriority(1)
    }

    private func applyPreviousButton(at index: Int) -> some View {
        Button {
            applyPreviousPerformance(at: index)
        } label: {
            Label("Fill Last", systemImage: "arrow.down.left.circle.fill")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(WGJTheme.accentBlue.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(WGJTheme.accentBlue.opacity(0.24), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(WGJTheme.accentBlue)
        .accessibilityIdentifier("workout-set-\(index)-use-last-button")
    }

    private func metricField<Content: View>(
        title: String,
        supporting: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Spacer(minLength: 8)

                if let supporting, !supporting.isEmpty {
                    Text(supporting)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func repsField(at index: Int) -> some View {
        if setDrafts.indices.contains(index) {
            let overlayState = isInputFocused(.reps, at: index) ? nil : repsFieldDisplayState(at: index)

            ZStack {
                if let overlayState {
                    metricDisplayText(overlayState)
                }

                TextField(metricPlaceholderText(for: overlayState), text: repsTextBinding(for: index))
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(overlayState == nil ? WGJTheme.textPrimary : Color.clear)
                    .focused($focusedInput, equals: inputFocus(for: index, metric: .reps))
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        focusMetric(.reps, at: index)
                    }
                    .disabled(!isSetEditingEnabled || setDrafts[index].isLocked)
                    .accessibilityIdentifier("workout-set-\(index)-reps-field")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusMetric(.reps, at: index)
            }
            .metricInputShell(isFocused: isInputFocused(.reps, at: index))
        }
    }

    private func repsFieldWithCompletionControl(
        for row: WorkoutSessionExerciseSetRowDisplaySnapshot,
        presentation: WorkoutSetCompletionControlPresentation?
    ) -> some View {
        HStack(spacing: 8) {
            repsField(at: row.index)

            if let inlineButton = presentation?.inlineButton {
                completionControlButton(inlineButton, for: row)
            }
        }
    }

    private func completionControlButton(
        _ presentation: WorkoutSetCompletionControlPresentation.InlineButton,
        for row: WorkoutSessionExerciseSetRowDisplaySnapshot
    ) -> some View {
        let set = row.set

        return Button {
            requestCompletionChange(at: row.index, isCompleted: presentation.targetIsCompleted)
        } label: {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 20, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(completionControlTint(for: presentation.tone))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(completionControlFill(for: presentation.tone))
                        .overlay(
                            Circle()
                                .stroke(completionControlStroke(for: presentation.tone), lineWidth: 1)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 54)
        .disabled(!isSetEditingEnabled || set.isLocked)
        .accessibilityLabel(presentation.label)
        .accessibilityIdentifier("workout-set-\(row.index)-completion-button")
    }

    private func completionControlTint(for tone: WorkoutSetCompletionControlPresentation.Tone) -> Color {
        tone.tintColor
    }

    private func completionControlFill(for tone: WorkoutSetCompletionControlPresentation.Tone) -> Color {
        tone.fillColor
    }

    private func completionControlStroke(for tone: WorkoutSetCompletionControlPresentation.Tone) -> Color {
        tone.strokeColor
    }

    @ViewBuilder
    private func loadField(at index: Int) -> some View {
        if setDrafts.indices.contains(index) {
            let isLocked = setDrafts[index].isLocked
            let overlayState = isInputFocused(.weight, at: index) ? nil : weightFieldDisplayState(at: index)

            HStack(spacing: 6) {
                ZStack {
                    if let overlayState {
                        metricDisplayText(overlayState)
                    }

                    TextField(metricPlaceholderText(for: overlayState), text: weightTextBinding(for: index))
                        .keyboardType(.decimalPad)
                        .submitLabel(.next)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(overlayState == nil ? WGJTheme.textPrimary : Color.clear)
                        .focused($focusedInput, equals: inputFocus(for: index, metric: .weight))
                        .multilineTextAlignment(.center)
                        .onTapGesture {
                            focusMetric(.weight, at: index)
                        }
                        .disabled(!isSetEditingEnabled || isLocked)
                        .accessibilityIdentifier("workout-set-\(index)-weight-field")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusMetric(.weight, at: index)
                }

                WGJActionMenuButton("Load Unit", titleVisibility: .hidden) {
                    ForEach(TemplateLoadUnit.allCases) { unit in
                        Button(unit.shortLabel) {
                            let setID = setDrafts[index].id
                            let hadWeight = setDrafts[index].actualWeight != nil
                            setDrafts[index].actualLoadUnit = unit
                            if unit == .bodyweight {
                                setDrafts[index].actualWeight = nil
                                metricInputDraftBuffer.stage("", for: setID, metric: .weight)
                            }
                            if unit != .bodyweight || hadWeight {
                                scheduleDisplayRefresh()
                            }
                            notifyChanged()
                        }
                    }
                } label: {
                    Text(setDrafts[index].actualLoadUnit.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentCyan)
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }
            .metricInputShell(isFocused: isInputFocused(.weight, at: index))
        }
    }

    private func metricPlaceholderText(for overlayState: MetricFieldDisplayState?) -> String {
        guard overlayState == nil else { return "" }
        return previousPerformanceResolution.isLoading ? "" : "0"
    }

    private func setBadge(for row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let set = row.set

        return Button {
            toggleWarmup(at: row.index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(set.isWarmup ? WGJTheme.accentGold.opacity(0.24) : WGJTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                set.isWarmup ? WGJTheme.accentGold.opacity(0.58) : WGJTheme.accentBlue.opacity(0.22),
                                lineWidth: 1
                            )
                    )

                Text(row.badgeTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.isWarmup ? WGJTheme.accentGold : WGJTheme.textPrimary)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!isSetEditingEnabled || set.isLocked)
    }

    private func setMenu(for row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let currentIndex = indexForSetID(row.id)
        let set = currentIndex.map { setDrafts[$0] } ?? row.set
        let isLocked = set.isLocked
        let canMoveUp = currentIndex.map { index in
            index > 0 && !isLocked && !setDrafts[index - 1].isLocked
        } ?? false
        let canMoveDown = currentIndex.map { index in
            index < setDrafts.count - 1 && !isLocked && !setDrafts[index + 1].isLocked
        } ?? false

        return Menu {
            Button {
                insertSet(afterSetID: row.id)
            } label: {
                Label("Insert below", systemImage: "plus")
            }
            .disabled(!isSetEditingEnabled || isLocked)

            Menu {
                Button {
                    moveSetUp(setID: row.id)
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                .disabled(!isSetEditingEnabled || !canMoveUp)

                Button {
                    moveSetDown(setID: row.id)
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                .disabled(!isSetEditingEnabled || !canMoveDown)
            } label: {
                Label("Reorder", systemImage: "arrow.up.arrow.down")
            }

            Button {
                toggleWarmup(setID: row.id)
            } label: {
                Label(set.isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }
            .disabled(!isSetEditingEnabled || isLocked)

            Button {
                toggleLock(setID: row.id)
            } label: {
                Label(set.isLocked ? "Unlock set" : "Lock set", systemImage: set.isLocked ? "lock.open" : "lock")
            }
            .disabled(!isSetEditingEnabled)

            if !set.isWarmup && set.dropStages.isEmpty {
                Button {
                    addDropStage(toSetID: row.id)
                } label: {
                    Label("Make dropset", systemImage: "arrow.down.to.line.compact")
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            if !set.dropStages.isEmpty {
                Button {
                    addDropStage(toSetID: row.id)
                } label: {
                    Label("Add drop stage", systemImage: "plus.circle")
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            if !set.dropStages.isEmpty {
                Button(role: .destructive) {
                    clearDropStages(fromSetID: row.id)
                } label: {
                    Label("Remove dropset", systemImage: "trash")
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            if set.actualReps != nil
                || set.actualWeight != nil
                || set.dropStages.contains(where: {
                    $0.actualReps != nil || $0.actualWeight != nil || $0.isCompleted
                })
            {
                Button {
                    clearLoggedValues(setID: row.id)
                } label: {
                    Label("Clear logged values", systemImage: "eraser")
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            if manualCompletionMode {
                Button {
                    toggleCompletion(setID: row.id)
                } label: {
                    Label(
                        set.isCompleted ? "Mark incomplete" : "Complete set",
                        systemImage: set.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            Button(role: .destructive) {
                removeSet(withID: row.id)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
            .disabled(!isSetEditingEnabled || isLocked)
        } label: {
            headerIcon(symbol: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("workout-set-actions-button-\(row.index)")
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

    @ViewBuilder
    private func personalRecordChipGroup(_ kinds: [WorkoutPersonalRecordKind], compact: Bool = false) -> some View {
        let orderedKinds = kinds.sorted()

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(orderedKinds) { kind in
                    personalRecordChip(kind, compact: compact)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(orderedKinds) { kind in
                    personalRecordChip(kind, compact: compact)
                }
            }
        }
    }

    private func personalRecordChip(_ kind: WorkoutPersonalRecordKind, compact: Bool) -> some View {
        let tint = personalRecordTint(for: kind)
        let font: Font = compact ? .caption : .caption.weight(.bold)

        return Label(kind.chipTitle, systemImage: kind.systemImage)
            .font(font.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .background(
                Capsule()
                    .fill(tint.opacity(compact ? 0.12 : 0.14))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.28), lineWidth: 1)
                    )
            )
    }

    private func personalRecordTint(for kind: WorkoutPersonalRecordKind) -> Color {
        switch kind {
        case .strength:
            return WGJTheme.accentGold
        case .weight:
            return WGJTheme.accentBlue
        case .reps:
            return WGJTheme.success
        case .volume:
            return WGJTheme.accentCyan
        }
    }

    private func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(shouldEmphasizeCompletedExercise ? WGJTheme.success : WGJTheme.accentBlue)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(shouldEmphasizeCompletedExercise ? WGJTheme.success.opacity(0.14) : WGJTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                shouldEmphasizeCompletedExercise
                                    ? WGJTheme.success.opacity(0.24)
                                    : WGJTheme.outline.opacity(0.36),
                                lineWidth: 1
                            )
                    )
            )
    }

    private func restAdjustButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(WGJTheme.textSecondary)
    }

    private func progressToneColor(for tone: WorkoutSetProgressTone) -> Color {
        switch tone {
        case .accent:
            return WGJTheme.accentBlue
        case .success:
            return WGJTheme.success
        case .caution:
            return WGJTheme.accentGold
        }
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

    private var headerSummaryChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                if showsSetProgressChip {
                    infoChip(setProgressSummary, tint: isExerciseCompleted ? WGJTheme.success : WGJTheme.accentBlue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                if showsSetProgressChip {
                    infoChip(setProgressSummary, tint: isExerciseCompleted ? WGJTheme.success : WGJTheme.accentBlue)
                }
            }
        }
    }

    private var isExpanded: Bool {
        expansionBinding.wrappedValue
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $localIsExpanded
    }

    private var repRangeSummary: String {
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

    private var setProgressSummary: String {
        "\(completedSetCount)/\(setDrafts.count) sets done"
    }

    private var completedExerciseCardFill: LinearGradient {
        LinearGradient(
            colors: [
                WGJTheme.success.opacity(0.18),
                WGJTheme.cardStrong.opacity(0.98),
                WGJTheme.success.opacity(0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var completedExerciseBackgroundStyle: AnyShapeStyle {
        shouldEmphasizeCompletedExercise
            ? AnyShapeStyle(completedExerciseCardFill)
            : AnyShapeStyle(Color.clear)
    }

    private func toggleExpanded() {
        if isExpanded {
            dismissInputFocus()
        }

        expansionBinding.wrappedValue.toggle()
    }

    private func compactControlCard<Content: View>(
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            content()

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var shouldShowRepRange: Bool {
        targetRepMin != nil || targetRepMax != nil
    }

    private var displayRepRange: (min: Int?, max: Int?) {
        (targetRepMin, targetRepMax)
    }

    private var displayRows: [WorkoutSessionExerciseSetRowDisplaySnapshot] {
        let currentIDs = setDrafts.map(\.id)
        guard rowSnapshots.map(\.id) == currentIDs else {
            return Self.makeDisplayRows(
                setDrafts: setDrafts,
                previousPerformanceResolution: previousPerformanceResolution,
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                restSeconds: restSeconds,
                formatWeight: formatWeight
            )
        }
        return rowSnapshots
    }

    private var completedSetCount: Int {
        cachedCompletedSetCount
    }

    private var isExerciseCompleted: Bool {
        !setDrafts.isEmpty && setDrafts.allSatisfy(\.isCycleCompleted)
    }

    private var shouldEmphasizeCompletedExercise: Bool {
        emphasizesExerciseCompletion && isExerciseCompleted
    }

    private func inputFocus(for index: Int, metric: SetInputFocus.Metric) -> SetInputFocus {
        SetInputFocus(setID: setDrafts[index].id, metric: metric)
    }

    private func inlineHintPresentation(at index: Int) -> WorkoutSetInlineHintPresentation? {
        guard setDrafts.indices.contains(index) else { return nil }
        return WorkoutSetInlineHintPresentation.make(
            draft: setDrafts[index],
            previous: previousBySetIndex[index],
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            formatWeight: formatWeight
        )
    }

    private func weightGhostText(at index: Int) -> String? {
        guard setDrafts.indices.contains(index) else { return nil }
        return WorkoutSetInlineHintPresentation.weightGhostText(
            from: previousBySetIndex[index],
            formatWeight: formatWeight
        )
    }

    private func repsGhostText(at index: Int) -> String? {
        guard setDrafts.indices.contains(index) else { return nil }
        return WorkoutSetInlineHintPresentation.repsGhostText(
            from: previousBySetIndex[index]
        )
    }

    private func weightFieldDisplayState(at index: Int) -> MetricFieldDisplayState? {
        guard setDrafts.indices.contains(index), !isInputFocused(.weight, at: index) else { return nil }
        guard setDrafts[index].actualWeight == nil else { return nil }
        guard let ghostText = weightGhostText(at: index) else { return nil }
        return MetricFieldDisplayState(
            text: ghostText,
            tone: .ghost,
            accessibilityIdentifier: "workout-set-\(index)-weight-ghost"
        )
    }

    private func repsFieldDisplayState(at index: Int) -> MetricFieldDisplayState? {
        guard setDrafts.indices.contains(index), !isInputFocused(.reps, at: index) else { return nil }
        guard setDrafts[index].actualReps == nil else { return nil }
        guard let ghostText = repsGhostText(at: index) else { return nil }
        return MetricFieldDisplayState(
            text: ghostText,
            tone: .ghost,
            accessibilityIdentifier: "workout-set-\(index)-reps-ghost"
        )
    }

    private func isInputFocused(_ metric: SetInputFocus.Metric, at index: Int) -> Bool {
        guard setDrafts.indices.contains(index) else { return false }
        return focusedInput == inputFocus(for: index, metric: metric)
    }

    private func focusMetric(_ metric: SetInputFocus.Metric, at index: Int) {
        guard setDrafts.indices.contains(index), isSetEditingEnabled, !setDrafts[index].isLocked else { return }
        focusedInput = inputFocus(for: index, metric: metric)
    }

    private func dismissInputFocus() {
        dismissInputFocus(suppressCommit: false)
    }

    private func dismissInputFocus(suppressCommit: Bool) {
        if let focusedInput {
            commitBufferedInput(for: focusedInput, clearsText: true)
        }
        if suppressCommit, focusedInput != nil {
            suppressNextFocusLossCommit = true
        }
        guard focusedInput != nil else { return }
        focusedInput = nil
        WGJKeyboard.dismiss()
    }

    private func repsTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index) else {
                    return ""
                }
                let setID = setDrafts[index].id
                if isInputFocused(.reps, at: index),
                   let draft = metricInputDraftBuffer.text(for: setID, metric: .reps) {
                    return draft
                }
                guard let value = setDrafts[index].actualReps else {
                    return ""
                }
                return "\(value)"
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let setID = setDrafts[index].id
                metricInputDraftBuffer.stage(newValue, for: setID, metric: .reps)
                scheduleBufferedInputCommit()
            }
        )
    }

    private func weightTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index) else {
                    return ""
                }
                let setID = setDrafts[index].id
                if isInputFocused(.weight, at: index),
                   let draft = metricInputDraftBuffer.text(for: setID, metric: .weight) {
                    return draft
                }
                guard let value = setDrafts[index].actualWeight else {
                    return ""
                }
                return formatWeight(value)
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let setID = setDrafts[index].id
                metricInputDraftBuffer.stage(newValue, for: setID, metric: .weight)
                scheduleBufferedInputCommit()
            }
        )
    }

    private func addSet() {
        let newDraft = makeSetDraft(copying: setDrafts.last)

        withAnimation(.snappy(duration: 0.24, extraBounce: 0.04)) {
            setDrafts.append(newDraft)
        }

        focusMetric(.weight, forSetID: newDraft.id)
        notifyChanged()
    }

    private func insertSet(after index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        let newDraft = makeSetDraft(copying: setDrafts[index])

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            setDrafts.insert(newDraft, at: index + 1)
        }

        focusMetric(.weight, forSetID: newDraft.id)
        notifyChanged()
    }

    private func insertSet(afterSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        insertSet(after: index)
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        let removedID = setDrafts[index].id
        let removedTitle = setTitle(for: index)

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            _ = setDrafts.remove(at: index)
        }

        if focusedInput?.setID == removedID {
            dismissInputFocus()
        }
        rebuildDisplayRows(using: setDrafts)
        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        notifyChanged()
        onSetCompletionChange?(removedID, removedTitle, 0, false)
    }

    private func removeSet(withID setID: UUID) {
        guard let index = setDrafts.firstIndex(where: { $0.id == setID }) else { return }
        removeSet(at: index)
    }

    private func indexForSetID(_ setID: UUID) -> Int? {
        WorkoutSetRowIdentityResolver.currentIndex(for: setID, in: setDrafts)
    }

    private func toggleWarmup(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        setDrafts[index].isWarmup.toggle()
        notifyChanged()
    }

    private func toggleWarmup(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        toggleWarmup(at: index)
    }

    private func toggleLock(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isLocked.toggle()
        if setDrafts[index].isLocked, focusedInput?.setID == setDrafts[index].id {
            dismissInputFocus()
        }
        notifyChanged()
    }

    private func toggleLock(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        toggleLock(at: index)
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }
        guard !setDrafts[index].isLocked, !setDrafts[index - 1].isLocked else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index - 1)
        }
        notifyChanged()
    }

    private func moveSetUp(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        moveSetUp(index)
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }
        guard !setDrafts[index].isLocked, !setDrafts[index + 1].isLocked else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index + 1)
        }
        notifyChanged()
    }

    private func moveSetDown(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        moveSetDown(index)
    }

    private func clearLoggedValues(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        let set = setDrafts[index]
        let completedDropStageIDs = set.dropStages.filter(\.isCompleted).map(\.id)
        setDrafts[index].actualReps = nil
        setDrafts[index].actualWeight = nil
        if setDrafts[index].targetLoadUnit == .bodyweight {
            setDrafts[index].actualLoadUnit = .bodyweight
        }
        setDrafts[index].isCompleted = false
        for stageIndex in setDrafts[index].dropStages.indices {
            setDrafts[index].dropStages[stageIndex].actualReps = nil
            setDrafts[index].dropStages[stageIndex].actualWeight = nil
            if setDrafts[index].dropStages[stageIndex].targetLoadUnit == .bodyweight {
                setDrafts[index].dropStages[stageIndex].actualLoadUnit = .bodyweight
            }
            setDrafts[index].dropStages[stageIndex].isCompleted = false
        }
        notifyChanged()
        if set.isCompleted {
            onSetCompletionChange?(set.id, setTitle(for: index), set.restSeconds, false)
        }
        for stageID in completedDropStageIDs {
            onSetCompletionChange?(stageID, nil, 0, false)
        }
    }

    private func clearLoggedValues(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        clearLoggedValues(at: index)
    }

    private func refreshDisplayRows() {
        guard isExpanded else { return }
        rebuildDisplayRows()
    }

    private func rebuildDisplayRows(
        using drafts: [WorkoutSessionSetDraft]? = nil,
        restSeconds overrideRestSeconds: Int? = nil
    ) {
        guard isExpanded else { return }
        let currentDrafts = drafts ?? _setDrafts.wrappedValue
        let currentRestSeconds = overrideRestSeconds ?? restSeconds
        let snapshot = WGJPerformance.measure("workout-grid.row-refresh") {
            Self.makeDisplayRows(
                setDrafts: currentDrafts,
                previousPerformanceResolution: previousPerformanceResolution,
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                restSeconds: currentRestSeconds,
                formatWeight: formatWeight
            )
        }
        rowSnapshots = snapshot
        cachedCompletedSetCount = snapshot.reduce(0) { partialResult, row in
            partialResult + (row.set.isCycleCompleted ? 1 : 0)
        }
    }

    private func scheduleDisplayRefresh() {
        guard isExpanded else { return }
        guard focusedInput != nil else {
            pendingDisplayRefreshTask?.cancel()
            pendingDisplayRefreshTask = nil
            refreshDisplayRows()
            return
        }

        pendingDisplayRefreshTask?.cancel()
        let delay = displayRefreshDebounce
        pendingDisplayRefreshTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await refreshDisplayRowsAfterDebounceIfStillNeeded()
        }
    }

    @MainActor
    private func refreshDisplayRowsAfterDebounceIfStillNeeded() {
        guard !Task.isCancelled else { return }
        pendingDisplayRefreshTask = nil
        refreshDisplayRows()
    }

    private func flushPendingDisplayRefresh() {
        guard pendingDisplayRefreshTask != nil else { return }
        pendingDisplayRefreshTask?.cancel()
        pendingDisplayRefreshTask = nil
        if isExpanded {
            refreshDisplayRows()
        }
    }

    private func flushPendingEditorState() {
        let hadPendingCommit = pendingCommitTask != nil
        if commitAllBufferedInput(clearsText: true) || hadPendingCommit {
            requestImmediateCommitForCurrentState()
        }
        if focusedInput != nil {
            dismissInputFocus(suppressCommit: true)
        }
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        flushPendingDisplayRefresh()
        markEditorClean()
    }

    private func handleDraftValueMutation(previousDrafts: [WorkoutSessionSetDraft]) {
        let changeSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previousDrafts,
            current: setDrafts
        )

        switch changeSummary.commitDisposition {
        case .none:
            return
        case .debounced:
            scheduleCommitRequest(.debounced)
        case .immediate:
            notifyChanged()
        }
    }

    private func handlePreviousPerformanceResolutionChange() {
        guard isExpanded else { return }
        refreshDisplayRows()
    }

    private static func makeDisplayRows(
        setDrafts: [WorkoutSessionSetDraft],
        previousPerformanceResolution: WorkoutPreviousPerformanceResolution,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        formatWeight: (Double) -> String
    ) -> [WorkoutSessionExerciseSetRowDisplaySnapshot] {
        var rows: [WorkoutSessionExerciseSetRowDisplaySnapshot] = []
        rows.reserveCapacity(setDrafts.count)
        var workingSetNumber = 0

        for (index, draft) in setDrafts.enumerated() {
            if !draft.isWarmup {
                workingSetNumber += 1
            }

            rows.append(
                makeDisplayRow(
                    draft: draft,
                    index: index,
                    workingSetNumber: workingSetNumber,
                    previousPerformanceResolution: previousPerformanceResolution,
                    targetRepMin: targetRepMin,
                    targetRepMax: targetRepMax,
                    restSeconds: restSeconds,
                    formatWeight: formatWeight
                )
            )
        }

        return rows
    }

    private static func makeDisplayRow(
        draft: WorkoutSessionSetDraft,
        index: Int,
        workingSetNumber: Int,
        previousPerformanceResolution: WorkoutPreviousPerformanceResolution,
        targetRepMin: Int?,
        targetRepMax: Int?,
        restSeconds: Int,
        formatWeight: (Double) -> String
    ) -> WorkoutSessionExerciseSetRowDisplaySnapshot {
        let label = draft.isWarmup
            ? WorkoutSessionExerciseSetRowLabel(
                badgeTitle: "W",
                title: "Warmup Set"
            )
            : WorkoutSessionExerciseSetRowLabel(
                badgeTitle: "\(workingSetNumber)",
                title: "Working Set \(workingSetNumber)"
            )

        return WorkoutSessionExerciseSetRowDisplaySnapshot(
            id: draft.id,
            index: index,
            set: draft,
            badgeTitle: label.badgeTitle,
            title: label.title,
            previousSummary: previousSummaryText(
                for: draft,
                for: previousPerformanceResolution,
                at: index,
                formatWeight: formatWeight
            ),
            metadataLine: metadataLine(for: draft),
            inlineHintPresentation: WorkoutSetInlineHintPresentation.make(
                draft: draft,
                previous: previousPerformanceResolution.previous(at: index),
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                formatWeight: formatWeight
            ),
            completionButtonTitle: completionButtonTitle(for: draft, restSeconds: restSeconds)
        )
    }

    private static func previousSummaryText(
        for draft: WorkoutSessionSetDraft,
        for previousPerformanceResolution: WorkoutPreviousPerformanceResolution,
        at index: Int,
        formatWeight: (Double) -> String
    ) -> String {
        guard !draft.showsLoggedPerformance else {
            return ""
        }

        if previousPerformanceResolution.isLoading {
            return ""
        }

        guard let snapshot = previousPerformanceResolution.previous(at: index) else {
            return ""
        }

        let previousText: String
        if let weight = snapshot.weight, let reps = snapshot.reps {
            previousText = "\(formatWeight(weight)) \(snapshot.unit.shortLabel) x \(reps)"
        } else if let reps = snapshot.reps {
            previousText = "\(reps) reps"
        } else {
            return ""
        }

        return "Previous \(previousText)"
    }

    private static func metadataLine(for set: WorkoutSessionSetDraft) -> String? {
        var parts: [String] = []

        if set.isLocked {
            parts.append("Locked")
        }

        if !set.dropStages.isEmpty {
            parts.append("\(set.dropStages.count) drop" + (set.dropStages.count == 1 ? "" : "s"))
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private static func completionButtonTitle(for draft: WorkoutSessionSetDraft, restSeconds: Int) -> String {
        if !draft.dropStages.isEmpty {
            return "Complete Main Set"
        }
        let restLabel = restSeconds > 0 ? " + Rest \(formattedRest(restSeconds))" : ""
        return "Complete Set\(restLabel)"
    }

    private static func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : formattedRest(seconds)
    }

    private func applyPreviousPerformance(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard isSetEditingEnabled, !setDrafts[index].isLocked else { return }
        let targetSetID = setDrafts[index].id
        guard let updatedDrafts = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: setDrafts,
            at: index,
            previousResolution: previousPerformanceResolution
        ) else {
            return
        }

        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        clearInputDrafts(for: targetSetID)
        if focusedInput?.setID == targetSetID {
            dismissInputFocus(suppressCommit: true)
        }

        if !manualCompletionMode {
            var autoCompletedDrafts = updatedDrafts
            autoCompletedDrafts[index].isCompleted = true
            setDrafts = autoCompletedDrafts
            notifyChanged(drafts: autoCompletedDrafts)
            return
        }

        setDrafts = updatedDrafts
        notifyChanged(drafts: updatedDrafts)
    }

    private func setTitle(for index: Int, in drafts: [WorkoutSessionSetDraft]? = nil) -> String {
        let drafts = drafts ?? setDrafts
        return drafts[index].isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber(at: index, in: drafts))"
    }

    private func workingSetNumber(at index: Int, in drafts: [WorkoutSessionSetDraft]? = nil) -> Int {
        let drafts = drafts ?? setDrafts
        let priorWorking = drafts.prefix(index).filter { !$0.isWarmup }
        return priorWorking.count + 1
    }

    private func makeSetDraft(copying source: WorkoutSessionSetDraft?) -> WorkoutSessionSetDraft {
        let fallbackLoadUnit = source?.targetLoadUnit ?? preferredLoadUnit
        return WorkoutSessionSetDraft(
            isWarmup: source?.isWarmup ?? false,
            restSeconds: source?.restSeconds ?? restSeconds,
            targetReps: source?.targetReps,
            targetWeight: source?.targetWeight,
            targetLoadUnit: fallbackLoadUnit,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: source?.actualLoadUnit ?? source?.targetLoadUnit ?? fallbackLoadUnit,
            isCompleted: false,
            isLocked: false
        )
    }

    private func addDropStage(to index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isWarmup, !setDrafts[index].isLocked else { return }
        let sourceStage = setDrafts[index].dropStages.last
        let sourceReps = sourceStage?.targetReps ?? setDrafts[index].targetReps
        let sourceWeight = sourceStage?.targetWeight ?? setDrafts[index].targetWeight
        let sourceLoadUnit = sourceStage?.targetLoadUnit ?? setDrafts[index].targetLoadUnit
        let sourceActualLoadUnit = sourceStage?.actualLoadUnit ?? setDrafts[index].actualLoadUnit
        setDrafts[index].dropStages.append(
            WorkoutSessionDropStageDraft(
                targetReps: sourceReps,
                targetWeight: sourceWeight,
                targetLoadUnit: sourceLoadUnit,
                actualReps: nil,
                actualWeight: nil,
                actualLoadUnit: sourceActualLoadUnit,
                isCompleted: false
            )
        )
        notifyChanged()
    }

    private func addDropStage(toSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        addDropStage(to: index)
    }

    private func removeDropStage(_ stageID: UUID, from setIndex: Int) {
        guard setDrafts.indices.contains(setIndex) else { return }
        setDrafts[setIndex].dropStages.removeAll { $0.id == stageID }
        notifyChanged()
    }

    private func clearDropStages(from index: Int) {
        guard setDrafts.indices.contains(index), !setDrafts[index].dropStages.isEmpty else { return }
        setDrafts[index].dropStages = []
        notifyChanged()
    }

    private func clearDropStages(fromSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        clearDropStages(from: index)
    }

    private func updateDropStageWeightText(_ newValue: String, stageID: UUID, setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }

        let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedValue: Double?
        if normalized.isEmpty {
            updatedValue = nil
        } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
            updatedValue = max(0, parsed)
        } else {
            updatedValue = setDrafts[setIndex].dropStages[stageIndex].actualWeight
        }

        guard setDrafts[setIndex].dropStages[stageIndex].actualWeight != updatedValue else { return }
        let previousDrafts = setDrafts
        setDrafts[setIndex].dropStages[stageIndex].actualWeight = updatedValue
        if let updatedValue, updatedValue > 0,
           setDrafts[setIndex].dropStages[stageIndex].actualLoadUnit == .bodyweight
        {
            let fallbackUnit = setDrafts[setIndex].dropStages[stageIndex].targetLoadUnit == .bodyweight
                ? preferredLoadUnit
                : setDrafts[setIndex].dropStages[stageIndex].targetLoadUnit
            setDrafts[setIndex].dropStages[stageIndex].actualLoadUnit = fallbackUnit
        } else if updatedValue == nil,
                  setDrafts[setIndex].dropStages[stageIndex].targetLoadUnit == .bodyweight
        {
            setDrafts[setIndex].dropStages[stageIndex].actualLoadUnit = .bodyweight
        }
        if !manualCompletionMode {
            let stage = setDrafts[setIndex].dropStages[stageIndex]
            setDrafts[setIndex].dropStages[stageIndex].isCompleted = stage.actualReps != nil || stage.actualWeight != nil
        }
        handleDraftValueMutation(previousDrafts: previousDrafts)
    }

    private func updateDropStageRepsText(_ newValue: String, stageID: UUID, setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }
        let cleaned = newValue.filter(\.isNumber)
        let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
        guard setDrafts[setIndex].dropStages[stageIndex].actualReps != updatedValue else { return }
        let previousDrafts = setDrafts
        setDrafts[setIndex].dropStages[stageIndex].actualReps = updatedValue
        if !manualCompletionMode {
            let stage = setDrafts[setIndex].dropStages[stageIndex]
            setDrafts[setIndex].dropStages[stageIndex].isCompleted = stage.actualReps != nil || stage.actualWeight != nil
        }
        handleDraftValueMutation(previousDrafts: previousDrafts)
    }

    private func updateDropStageLoadUnit(_ loadUnit: TemplateLoadUnit, stageID: UUID, setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }
        guard setDrafts[setIndex].dropStages[stageIndex].actualLoadUnit != loadUnit else { return }
        setDrafts[setIndex].dropStages[stageIndex].actualLoadUnit = loadUnit
        if loadUnit == .bodyweight {
            setDrafts[setIndex].dropStages[stageIndex].actualWeight = nil
        }
        notifyChanged()
    }

    private func toggleDropStageCompletion(_ stageID: UUID, in setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }
        guard !setDrafts[setIndex].isLocked, setDrafts[setIndex].isCompleted else { return }

        let isCompleted = !setDrafts[setIndex].dropStages[stageIndex].isCompleted
        setDrafts[setIndex].dropStages[stageIndex].isCompleted = isCompleted
        let restLabel: String?
        let restSeconds: Int
        if isCompleted {
            let nextStageIndex = stageIndex + 1
            if setDrafts[setIndex].dropStages.indices.contains(nextStageIndex),
               !setDrafts[setIndex].dropStages[nextStageIndex].isCompleted {
                restLabel = "Drop \(nextStageIndex + 1)"
                restSeconds = 0
            } else {
                restLabel = WorkoutRestTimerContextBuilder.nextSetLabel(
                    afterCompletingSetAt: setIndex,
                    in: setDrafts
                )
                restSeconds = self.restSeconds
            }
        } else {
            for trailingIndex in setDrafts[setIndex].dropStages.indices where trailingIndex > stageIndex {
                setDrafts[setIndex].dropStages[trailingIndex].isCompleted = false
            }
            restLabel = "Drop \(stageIndex + 1)"
            restSeconds = self.restSeconds
        }
        notifyChanged()
        onSetCompletionChange?(stageID, restLabel, restSeconds, isCompleted)
    }

    private func setCardFill(for set: WorkoutSessionSetDraft, hasPersonalRecord: Bool) -> Color {
        if set.isCompleted {
            return WGJTheme.success.opacity(0.16)
        }

        if hasPersonalRecord {
            if set.isWarmup {
                return WGJTheme.accentGold.opacity(0.14)
            }
            return WGJTheme.accentGold.opacity(0.08)
        }

        if set.isWarmup {
            return WGJTheme.accentGold.opacity(0.12)
        }

        return WGJTheme.field.opacity(0.54)
    }

    private func setCardStroke(for set: WorkoutSessionSetDraft, hasPersonalRecord: Bool) -> Color {
        if set.isCompleted {
            return WGJTheme.success.opacity(0.44)
        }

        if hasPersonalRecord {
            return WGJTheme.accentGold.opacity(0.50)
        }

        if set.isWarmup {
            return WGJTheme.accentGold.opacity(0.34)
        }

        return WGJTheme.accentBlue.opacity(0.18)
    }

    private func updateRest(_ seconds: Int) {
        let normalized = max(0, min(3600, seconds))
        restSeconds = normalized

        for index in setDrafts.indices where !setDrafts[index].isLocked {
            setDrafts[index].restSeconds = normalized
        }

        notifyChanged()
    }

    private func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : Self.formattedRest(seconds)
    }

    private func completionControlPresentation(
        for row: WorkoutSessionExerciseSetRowDisplaySnapshot
    ) -> WorkoutSetCompletionControlPresentation? {
        let canCompleteSet = row.set.isCompleted || canCompleteSet(row.set)
        return WorkoutSetCompletionControlPresentation.make(
            draft: row.set,
            manualCompletionMode: manualCompletionMode,
            isSetCompletionEnabled: canCompleteSet,
            gatePresentation: resolvedSetCompletionGatePresentation,
            isGateRevealed: revealedCompletionGateSetIDs.contains(row.id)
        )
    }

    @ViewBuilder
    private func completionSupplementalRow(
        _ supplementalRow: WorkoutSetCompletionControlPresentation.SupplementalRow,
        for row: WorkoutSessionExerciseSetRowDisplaySnapshot
    ) -> some View {
        switch supplementalRow {
        case .gateNotice(let presentation):
            completionGateNotice(
                presentation,
                at: row.index,
                isRevealed: true
            )
        }
    }

    private func completionGateNotice(
        _ presentation: WorkoutSetCompletionGatePresentation,
        at index: Int,
        isRevealed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.title, systemImage: presentation.iconSystemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentGold)
                .fixedSize(horizontal: false, vertical: true)

            if isRevealed {
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workout-set-\(index)-completion-gate-message")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.accentGold.opacity(isRevealed ? 0.14 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WGJTheme.accentGold.opacity(isRevealed ? 0.34 : 0.22), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func dropStagesSection(for setIndex: Int) -> some View {
        if setDrafts.indices.contains(setIndex) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dropset")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentCyan)

                    Spacer()

                    if isSetEditingEnabled, !setDrafts[setIndex].isLocked {
                        Button {
                            addDropStage(to: setIndex)
                        } label: {
                            Label("Add Drop", systemImage: "plus.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WGJTheme.accentBlue)
                        .accessibilityIdentifier("workout-set-\(setIndex)-add-drop-stage-button")
                    }
                }

                if !setDrafts[setIndex].isCompleted {
                    Text("Finish the main set before completing the drop stages.")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                ForEach(Array(setDrafts[setIndex].dropStages.enumerated()), id: \.element.id) { stageIndex, stage in
                    WorkoutExerciseDropStageCardView(
                        setIndex: setIndex,
                        stageIndex: stageIndex,
                        stage: stage,
                        isEditingEnabled: isSetEditingEnabled,
                        isCompletionEnabled: setDrafts[setIndex].isCompleted,
                        onToggleCompletion: { toggleDropStageCompletion(stage.id, in: setIndex) },
                        onRepsChanged: { updateDropStageRepsText($0, stageID: stage.id, setIndex: setIndex) },
                        onWeightChanged: { updateDropStageWeightText($0, stageID: stage.id, setIndex: setIndex) },
                        onLoadUnitChanged: { updateDropStageLoadUnit($0, stageID: stage.id, setIndex: setIndex) },
                        onDelete: { removeDropStage(stage.id, from: setIndex) },
                        keyboardDismissToken: keyboardDismissToken
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WGJTheme.accentCyan.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WGJTheme.accentCyan.opacity(0.18), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stages")
        }
    }

    private func toggleCompletion(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        requestCompletionChange(at: index, isCompleted: !setDrafts[index].isCompleted)
    }

    private func toggleCompletion(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        toggleCompletion(at: index)
    }

    private func requestCompletionChange(at index: Int, isCompleted: Bool) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        let targetSetID = setDrafts[index].id
        let focusedSetInput = focusedInput?.setID == targetSetID ? focusedInput : nil
        _ = commitBufferedInput(forSetID: targetSetID, clearsText: true)
        guard let resolvedIndex = indexForSetID(targetSetID) else { return }

        if isCompleted, !canCompleteSet(setDrafts[resolvedIndex]) {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                revealedCompletionGateSetIDs.insert(targetSetID)
            }
            return
        }

        revealedCompletionGateSetIDs.remove(targetSetID)

        guard isCompleted else {
            if focusedSetInput != nil {
                dismissInputFocus(suppressCommit: true)
            }
            setCompletion(false, at: resolvedIndex)
            return
        }

        setCompletion(true, at: resolvedIndex)
    }

    private func setCompletion(
        _ isCompleted: Bool,
        at index: Int,
        draftOverride: [WorkoutSessionSetDraft]? = nil
    ) {
        var updatedDrafts = draftOverride ?? setDrafts
        guard updatedDrafts.indices.contains(index) else { return }
        guard !updatedDrafts[index].isLocked else { return }
        if focusedInput?.setID == updatedDrafts[index].id {
            dismissInputFocus(suppressCommit: true)
        }

        let setID = updatedDrafts[index].id
        let dropStageIDs = updatedDrafts[index].dropStages.map(\.id)
        guard updatedDrafts[index].isCompleted != isCompleted else { return }
        let setRestSeconds = restSeconds
        updatedDrafts = canonicalizedSetDrafts(updatedDrafts)
        updatedDrafts[index].isCompleted = isCompleted
        if !isCompleted {
            for stageIndex in updatedDrafts[index].dropStages.indices {
                updatedDrafts[index].dropStages[stageIndex].isCompleted = false
            }
        }
        setDrafts = updatedDrafts
        let restTimerSetLabel: String?
        if isCompleted {
            restTimerSetLabel = updatedDrafts[index].hasDropset
                ? "Drop 1"
                : WorkoutRestTimerContextBuilder.nextSetLabel(
                    afterCompletingSetAt: index,
                    in: updatedDrafts
                )
        } else {
            restTimerSetLabel = setTitle(for: index, in: updatedDrafts)
        }
        notifyChanged(drafts: updatedDrafts)
        let resolvedRestSeconds = isCompleted && updatedDrafts[index].hasDropset ? 0 : setRestSeconds
        onSetCompletionChange?(setID, restTimerSetLabel, resolvedRestSeconds, isCompleted)
        if !isCompleted {
            for stageID in dropStageIDs {
                onSetCompletionChange?(stageID, nil, 0, false)
            }
        }
    }

    private var resolvedSetCompletionGatePresentation: WorkoutSetCompletionGatePresentation {
        setCompletionGatePresentation ?? WorkoutSetCompletionGatePresentation(
            title: "Enter this set first",
            detail: "Add the current weight and reps before completing the set. Previous values are only guidance until you tap Fill Last.",
            iconSystemName: "exclamationmark.triangle.fill"
        )
    }

    private func canCompleteSet(_ draft: WorkoutSessionSetDraft) -> Bool {
        guard isSetCompletionEnabled else { return false }
        guard draft.actualReps != nil else { return false }
        if draft.actualLoadUnit == .bodyweight || draft.targetLoadUnit == .bodyweight {
            return true
        }
        return draft.actualWeight != nil
    }

    private func notifyChanged(drafts: [WorkoutSessionSetDraft]? = nil) {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        pendingDisplayRefreshTask?.cancel()
        pendingDisplayRefreshTask = nil
        let currentDrafts = canonicalizedSetDrafts(drafts ?? setDrafts)
        suppressNextSetDraftsDisplayRefresh = true
        if setDrafts != currentDrafts {
            setDrafts = currentDrafts
        }
        syncCompletedSetCount(using: currentDrafts)
        if isExpanded {
            rebuildDisplayRows(using: currentDrafts, restSeconds: restSeconds)
        }
        requestImmediateCommitForCurrentState(drafts: currentDrafts)
    }

    private func handleFocusedInputChange(_ previousFocus: SetInputFocus?, _ newFocus: SetInputFocus?) {
        guard previousFocus != newFocus else { return }
        if let previousFocus {
            if newFocus != nil {
                if suppressNextFocusLossCommit {
                    suppressNextFocusLossCommit = false
                } else {
                    scheduleBufferedInputCommit()
                }
            } else {
                let committedBufferedValueChange = commitBufferedInput(for: previousFocus, clearsText: true)
                if suppressNextFocusLossCommit {
                    suppressNextFocusLossCommit = false
                } else {
                    scheduleCommitRequest(
                        ActiveWorkoutEditorFocusCommitPolicy.dispositionForMetricFocusChange(
                            previousHadFocus: true,
                            newHasFocus: false,
                            committedBufferedValueChange: committedBufferedValueChange
                        )
                    )
                }
            }
        } else {
            suppressNextFocusLossCommit = false
        }
        if let newFocus {
            stageCurrentInputDraftIfNeeded(for: newFocus)
        }
        if newFocus == nil {
            pendingDisplayRefreshTask?.cancel()
            pendingDisplayRefreshTask = nil
            if isExpanded {
                refreshDisplayRows()
            }
        }
    }

    private func stageCurrentInputDraftIfNeeded(for focus: SetInputFocus) {
        guard let index = indexForSetID(focus.setID) else { return }
        let metric = inputDraftMetric(for: focus.metric)
        guard metricInputDraftBuffer.text(for: focus.setID, metric: metric) == nil else { return }
        metricInputDraftBuffer.sync(setID: focus.setID, metric: metric, draft: setDrafts[index])
    }

    private func handleSetDraftsChange(
        previousValue: [WorkoutSessionSetDraft],
        currentValue: [WorkoutSessionSetDraft]
    ) {
        if suppressNextSetDraftsDisplayRefresh {
            suppressNextSetDraftsDisplayRefresh = false
            return
        }

        let changeSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previousValue,
            current: currentValue
        )

        if changeSummary.hasCompletionChange {
            syncCompletedSetCount(using: currentValue)
        }
        if changeSummary.hasStructuralChange {
            pruneInputDrafts()
        }
        if isExpanded {
            scheduleDisplayRefresh()
        }
    }

    private func requestCommitForCurrentState(
        drafts: [WorkoutSessionSetDraft]? = nil,
        restSeconds overrideRestSeconds: Int? = nil
    ) {
        let currentDrafts = canonicalizedSetDrafts(drafts ?? setDrafts)
        let currentRestSeconds = overrideRestSeconds ?? restSeconds
        onCommitRequest?(currentDrafts, currentRestSeconds)
    }

    private func canonicalizedSetDrafts(_ drafts: [WorkoutSessionSetDraft]) -> [WorkoutSessionSetDraft] {
        let normalizedRest = max(0, min(3600, restSeconds))
        return drafts.map { draft in
            var updated = draft
            updated.restSeconds = normalizedRest
            return updated
        }
    }

    @discardableResult
    private func commitBufferedInput(
        for focus: SetInputFocus,
        clearsText: Bool
    ) -> Bool {
        var updatedDrafts = setDrafts
        let metric = inputDraftMetric(for: focus.metric)
        let changed = metricInputDraftBuffer.commit(
            setID: focus.setID,
            metric: metric,
            drafts: &updatedDrafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
        guard changed else { return false }

        let previousDrafts = setDrafts
        suppressNextSetDraftsDisplayRefresh = true
        setDrafts = updatedDrafts
        if isExpanded {
            rebuildDisplayRows(using: updatedDrafts)
        }
        handleDraftValueMutation(previousDrafts: previousDrafts)
        return true
    }

    @discardableResult
    private func commitBufferedInput(
        forSetID setID: UUID,
        clearsText: Bool
    ) -> Bool {
        var changed = false
        changed = commitBufferedInput(
            for: SetInputFocus(setID: setID, metric: .weight),
            clearsText: clearsText
        ) || changed
        changed = commitBufferedInput(
            for: SetInputFocus(setID: setID, metric: .reps),
            clearsText: clearsText
        ) || changed
        return changed
    }

    @discardableResult
    private func commitAllBufferedInput(clearsText: Bool) -> Bool {
        guard !metricInputDraftBuffer.isEmpty else { return false }
        var updatedDrafts = setDrafts
        let changed = metricInputDraftBuffer.commitAll(
            drafts: &updatedDrafts,
            preferredLoadUnit: preferredLoadUnit,
            manualCompletionMode: manualCompletionMode,
            clearsText: clearsText
        )
        guard changed else { return false }

        let previousDrafts = setDrafts
        suppressNextSetDraftsDisplayRefresh = true
        setDrafts = updatedDrafts
        if isExpanded {
            rebuildDisplayRows(using: updatedDrafts)
        }
        handleDraftValueMutation(previousDrafts: previousDrafts)
        return true
    }

    private func inputDraftMetric(for metric: SetInputFocus.Metric) -> WorkoutMetricInputDraftBuffer.Metric {
        switch metric {
        case .weight:
            return .weight
        case .reps:
            return .reps
        }
    }

    private func requestImmediateCommitForCurrentState(
        drafts: [WorkoutSessionSetDraft]? = nil,
        restSeconds overrideRestSeconds: Int? = nil
    ) {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        requestCommitForCurrentState(drafts: drafts, restSeconds: overrideRestSeconds)
        markEditorClean()
    }

    private func scheduleCommitRequest(_ disposition: ActiveWorkoutEditorCommitDisposition) {
        switch disposition {
        case .none:
            return
        case .immediate:
            requestImmediateCommitForCurrentState()
        case .debounced:
            pendingCommitTask?.cancel()
            markEditorDirty()
            let delay = commitDebounce
            pendingCommitTask = Task.detached(priority: .utility) {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await commitCurrentStateAfterDebounceIfStillNeeded()
            }
        }
    }

    private func scheduleBufferedInputCommit() {
        pendingCommitTask?.cancel()
        markEditorDirty()
        let delay = commitDebounce
        pendingCommitTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await commitBufferedInputAfterDebounceIfStillNeeded()
        }
    }

    @MainActor
    private func commitCurrentStateAfterDebounceIfStillNeeded() {
        guard !Task.isCancelled else { return }
        pendingCommitTask = nil
        requestCommitForCurrentState()
        markEditorClean()
    }

    @MainActor
    private func commitBufferedInputAfterDebounceIfStillNeeded() {
        guard !Task.isCancelled else { return }
        pendingCommitTask = nil
        if commitAllBufferedInput(clearsText: false) {
            requestCommitForCurrentState()
        }
        markEditorClean()
    }

    private func markEditorDirty() {
        onDirtyStateChange(true)
    }

    private func markEditorClean() {
        guard pendingCommitTask == nil, metricInputDraftBuffer.isEmpty else { return }
        onDirtyStateChange(false)
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
    }

    private func pruneInputDrafts() {
        let validSetIDs = Set(setDrafts.map(\.id))
        metricInputDraftBuffer.prune(keeping: validSetIDs)

        if let focusedInput, !validSetIDs.contains(focusedInput.setID) {
            self.focusedInput = nil
        }
    }

    private func syncCompletedSetCount(using drafts: [WorkoutSessionSetDraft]? = nil) {
        let currentDrafts = drafts ?? setDrafts
        cachedCompletedSetCount = currentDrafts.reduce(0) { partialResult, draft in
            partialResult + (draft.isCycleCompleted ? 1 : 0)
        }
    }

    private func syncInputDraft(for focus: SetInputFocus, using draft: WorkoutSessionSetDraft) {
        guard focus.setID == draft.id else { return }

        switch focus.metric {
        case .weight:
            metricInputDraftBuffer.sync(setID: draft.id, metric: .weight, draft: draft)
        case .reps:
            metricInputDraftBuffer.sync(setID: draft.id, metric: .reps, draft: draft)
        }
    }

    private func clearInputDrafts(for setID: UUID) {
        metricInputDraftBuffer.clear(for: setID, metric: .weight)
        metricInputDraftBuffer.clear(for: setID, metric: .reps)
    }

    private func setSwipeOffsetBinding(for setID: UUID) -> Binding<CGFloat> {
        Binding(
            get: { setSwipeOffsets[setID] ?? 0 },
            set: { setSwipeOffsets[setID] = $0 }
        )
    }

    private func setRemovingBinding(for setID: UUID) -> Binding<Bool> {
        Binding(
            get: { setSwipeRemoving[setID] ?? false },
            set: { setSwipeRemoving[setID] = $0 }
        )
    }

    private func focusMetric(_ metric: SetInputFocus.Metric, forSetID setID: UUID) {
        guard let index = setDrafts.firstIndex(where: { $0.id == setID }) else { return }
        focusMetric(metric, at: index)
    }
}

private struct WorkoutExerciseDropStageCardView: View, Equatable {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let setIndex: Int
    let stageIndex: Int
    let stage: WorkoutSessionDropStageDraft
    let isEditingEnabled: Bool
    let isCompletionEnabled: Bool
    let onToggleCompletion: () -> Void
    let onRepsChanged: (String) -> Void
    let onWeightChanged: (String) -> Void
    let onLoadUnitChanged: (TemplateLoadUnit) -> Void
    let onDelete: () -> Void
    let keyboardDismissToken: ActiveWorkoutKeyboardDismissToken

    @State private var repsText: String
    @State private var weightText: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case reps
    }

    init(
        setIndex: Int,
        stageIndex: Int,
        stage: WorkoutSessionDropStageDraft,
        isEditingEnabled: Bool,
        isCompletionEnabled: Bool,
        onToggleCompletion: @escaping () -> Void,
        onRepsChanged: @escaping (String) -> Void,
        onWeightChanged: @escaping (String) -> Void,
        onLoadUnitChanged: @escaping (TemplateLoadUnit) -> Void,
        onDelete: @escaping () -> Void,
        keyboardDismissToken: ActiveWorkoutKeyboardDismissToken = ActiveWorkoutKeyboardDismissToken()
    ) {
        self.setIndex = setIndex
        self.stageIndex = stageIndex
        self.stage = stage
        self.isEditingEnabled = isEditingEnabled
        self.isCompletionEnabled = isCompletionEnabled
        self.onToggleCompletion = onToggleCompletion
        self.onRepsChanged = onRepsChanged
        self.onWeightChanged = onWeightChanged
        self.onLoadUnitChanged = onLoadUnitChanged
        self.onDelete = onDelete
        self.keyboardDismissToken = keyboardDismissToken
        _repsText = State(initialValue: stage.actualReps.map(String.init) ?? "")
        _weightText = State(initialValue: stage.actualWeight.map(WGJFormatters.decimalString) ?? "")
    }

    static func == (lhs: WorkoutExerciseDropStageCardView, rhs: WorkoutExerciseDropStageCardView) -> Bool {
        lhs.setIndex == rhs.setIndex
            && lhs.stageIndex == rhs.stageIndex
            && lhs.stage == rhs.stage
            && lhs.isEditingEnabled == rhs.isEditingEnabled
            && lhs.isCompletionEnabled == rhs.isCompletionEnabled
            && lhs.keyboardDismissToken == rhs.keyboardDismissToken
    }

    var body: some View {
        let completionButton = WorkoutSetCompletionControlPresentation.InlineButton.make(
            isCompleted: stage.isCompleted,
            completedLabel: "Undo drop \(stageIndex + 1)",
            incompleteLabel: "Complete drop \(stageIndex + 1)",
            isSetCompletionEnabled: isCompletionEnabled
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop \(stageIndex + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    if let targetSummary {
                        Text(targetSummary)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }

                Spacer()

                if stage.isCompleted {
                    Text("Done")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WGJTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(WGJTheme.success.opacity(0.12))
                        )
                }

                if isEditingEnabled {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-delete-button")
                }
            }

            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    weightField
                    repsFieldWithCompletionControl(completionButton)
                }
            } else {
                HStack(spacing: 10) {
                    weightField
                    repsFieldWithCompletionControl(completionButton)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            stage.isCompleted ? WGJTheme.success.opacity(0.24) : WGJTheme.outline.opacity(0.18),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)")
        .onChange(of: stage.actualReps) { _, newValue in
            let resolved = newValue.map(String.init) ?? ""
            guard repsText != resolved else { return }
            repsText = resolved
        }
        .onChange(of: stage.actualWeight) { _, newValue in
            let resolved = newValue.map(WGJFormatters.decimalString) ?? ""
            guard weightText != resolved else { return }
            weightText = resolved
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            commitLocalText()
        }
        .onChange(of: keyboardDismissToken) { _, _ in
            guard focusedField != nil else { return }
            commitLocalText()
            focusedField = nil
        }
        .onDisappear {
            commitLocalText()
        }
    }

    private var weightField: some View {
        HStack(spacing: 8) {
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .wgjPillField()
                .focused($focusedField, equals: .weight)
                .disabled(!isEditingEnabled)
                .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-weight-field")

            WGJActionMenuButton("Drop Load Unit", titleVisibility: .hidden) {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        commitLocalText()
                        onLoadUnitChanged(unit)
                    }
                }
            } label: {
                Text(stage.actualLoadUnit.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
            .disabled(!isEditingEnabled)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-load-unit-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repsField: some View {
        TextField("Reps", text: $repsText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .wgjPillField()
            .focused($focusedField, equals: .reps)
            .disabled(!isEditingEnabled)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-reps-field")
    }

    private func repsFieldWithCompletionControl(
        _ presentation: WorkoutSetCompletionControlPresentation.InlineButton
    ) -> some View {
        HStack(spacing: 8) {
            repsField

            Button {
                commitLocalText()
                onToggleCompletion()
            } label: {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(presentation.tone.tintColor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(presentation.tone.fillColor)
                            .overlay(
                                Circle()
                                    .stroke(presentation.tone.strokeColor, lineWidth: 1)
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 48, height: 44)
            .disabled(!isEditingEnabled || !isCompletionEnabled)
            .accessibilityLabel(presentation.label)
            .accessibilityIdentifier("workout-set-\(setIndex)-drop-stage-\(stageIndex)-completion-button")
        }
    }

    private func commitLocalText() {
        let resolvedWeightText = stage.actualWeight.map(WGJFormatters.decimalString) ?? ""
        if weightText != resolvedWeightText {
            onWeightChanged(weightText)
        }

        let resolvedRepsText = stage.actualReps.map(String.init) ?? ""
        if repsText != resolvedRepsText {
            onRepsChanged(repsText)
        }
    }

    private var targetSummary: String? {
        let repsText = stage.targetReps.map { "\($0) reps" }
        let weightText: String?
        if let targetWeight = stage.targetWeight {
            weightText = "\(WGJFormatters.decimalString(targetWeight)) \(stage.targetLoadUnit.shortLabel)"
        } else if stage.targetLoadUnit == .bodyweight {
            weightText = TemplateLoadUnit.bodyweight.shortLabel
        } else {
            weightText = nil
        }

        switch (weightText, repsText) {
        case let (weight?, reps?):
            return "Target \(weight) x \(reps)"
        case let (weight?, nil):
            return "Target \(weight)"
        case let (nil, reps?):
            return "Target \(reps)"
        case (nil, nil):
            return nil
        }
    }
}

private extension View {
    func metricInputShell(isFocused: Bool) -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(isFocused ? WGJTheme.fieldStrong : WGJTheme.field.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(
                                isFocused ? WGJTheme.accentBlue.opacity(0.42) : WGJTheme.outline.opacity(0.72),
                                lineWidth: isFocused ? 1.4 : 1
                            )
                    }
                    .shadow(
                        color: isFocused ? WGJTheme.accentBlue.opacity(0.10) : WGJTheme.shadowSoft.opacity(0.42),
                        radius: isFocused ? 8 : 6,
                        x: 0,
                        y: isFocused ? 2 : 3
                    )
            }
    }
}

private enum MetricFieldDisplayTone {
    case actual
    case ghost
}

private struct MetricFieldDisplayState {
    let text: String
    let tone: MetricFieldDisplayTone
    var accessibilityIdentifier: String?
}

private func metricDisplayText(_ state: MetricFieldDisplayState) -> some View {
    Text(state.text)
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .foregroundStyle(
            state.tone == .actual
                ? WGJTheme.textPrimary
                : WGJTheme.textTertiary.opacity(0.72)
        )
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .applyIfLet(state.accessibilityIdentifier) { view, identifier in
            view.accessibilityIdentifier(identifier)
        }
}

private extension View {
    @ViewBuilder
    func applyIfLet<Value, Content: View>(
        _ value: Value?,
        @ViewBuilder transform: (Self, Value) -> Content
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

private struct WorkoutSessionExerciseSetRowLabel {
    let badgeTitle: String
    let title: String
}

private struct WorkoutSessionExerciseSetRowDisplaySnapshot: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let set: WorkoutSessionSetDraft
    let badgeTitle: String
    let title: String
    let previousSummary: String
    let metadataLine: String?
    let inlineHintPresentation: WorkoutSetInlineHintPresentation?
    let completionButtonTitle: String
}

nonisolated struct WorkoutSetCompletionGatePresentation: Equatable {
    let title: String
    let detail: String
    let iconSystemName: String
}

nonisolated struct WorkoutSetCompletionControlPresentation: Equatable {
    let inlineButton: InlineButton
    let supplementalRow: SupplementalRow?

    struct InlineButton: Equatable {
        let label: String
        let systemImage: String
        let tone: Tone
        let targetIsCompleted: Bool

        static func make(
            isCompleted: Bool,
            completedLabel: String,
            incompleteLabel: String,
            isSetCompletionEnabled: Bool
        ) -> InlineButton {
            if isCompleted {
                return InlineButton(
                    label: completedLabel,
                    systemImage: "checkmark.circle.fill",
                    tone: .completed,
                    targetIsCompleted: false
                )
            }

            return InlineButton(
                label: incompleteLabel,
                systemImage: "checkmark.circle",
                tone: isSetCompletionEnabled ? .ready : .gated,
                targetIsCompleted: true
            )
        }
    }

    enum SupplementalRow: Equatable {
        case gateNotice(WorkoutSetCompletionGatePresentation)
    }

    enum Tone: Equatable {
        case ready
        case completed
        case gated
    }

    static func make(
        draft: WorkoutSessionSetDraft,
        manualCompletionMode: Bool,
        isSetCompletionEnabled: Bool,
        gatePresentation: WorkoutSetCompletionGatePresentation?,
        isGateRevealed: Bool
    ) -> WorkoutSetCompletionControlPresentation? {
        guard manualCompletionMode else {
            return nil
        }

        let inlineButton = InlineButton.make(
            isCompleted: draft.isCompleted,
            completedLabel: draft.isCycleCompleted ? "Mark set incomplete" : "Undo main set",
            incompleteLabel: "Complete set",
            isSetCompletionEnabled: isSetCompletionEnabled
        )

        let supplementalRow: SupplementalRow?
        if !isSetCompletionEnabled, isGateRevealed, let gatePresentation {
            supplementalRow = .gateNotice(gatePresentation)
        } else {
            supplementalRow = nil
        }

        return WorkoutSetCompletionControlPresentation(
            inlineButton: inlineButton,
            supplementalRow: supplementalRow
        )
    }
}

struct WorkoutSetInlineHintPresentation: Equatable {
    let weightGhostText: String?
    let repsGhostText: String?
    let aimText: String
    let statusText: String?
    let statusTone: WorkoutSetProgressTone
    let canApplyPrevious: Bool

    static func make(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        formatWeight: (Double) -> String = { WGJFormatters.decimalString($0) }
    ) -> WorkoutSetInlineHintPresentation? {
        guard previous != nil else {
            return nil
        }

        guard let reference = WorkoutSetProgressReference.make(
            draft: draft,
            previous: previous,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            formatWeight: formatWeight
        ) else {
            return nil
        }

        return WorkoutSetInlineHintPresentation(
            weightGhostText: weightGhostText(from: previous, formatWeight: formatWeight),
            repsGhostText: repsGhostText(from: previous),
            aimText: reference.aimValue,
            statusText: reference.statusText,
            statusTone: reference.statusTone,
            canApplyPrevious: reference.canReusePrevious
        )
    }

    static func weightGhostText(
        from previous: WorkoutPreviousSetSnapshot?,
        formatWeight: (Double) -> String
    ) -> String? {
        guard let previous else { return nil }

        if previous.unit == .bodyweight {
            return "BW"
        }

        guard let weight = previous.weight else { return nil }
        return formatWeight(weight)
    }

    static func repsGhostText(from previous: WorkoutPreviousSetSnapshot?) -> String? {
        previous?.reps.map(String.init)
    }
}

private extension WorkoutSetCompletionControlPresentation.Tone {
    var tintColor: Color {
        switch self {
        case .ready:
            return WGJTheme.accentBlue
        case .completed:
            return WGJTheme.success
        case .gated:
            return WGJTheme.accentGold
        }
    }

    var fillColor: Color {
        tintColor.opacity(self == .completed ? 0.18 : 0.12)
    }

    var strokeColor: Color {
        tintColor.opacity(self == .completed ? 0.36 : 0.24)
    }
}

nonisolated enum WorkoutSetPreviousPerformanceApplicationResolver {
    static func resolve(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        mode: WorkoutPreviousPerformanceApplicationMode = .fillMissing
    ) -> WorkoutSessionSetDraft {
        draft.applyingPreviousPerformance(previous, mode: mode)
    }
}

private extension WorkoutSessionSetDraft {
    nonisolated var showsLoggedPerformance: Bool {
        if actualWeight != nil || actualReps != nil {
            return true
        }

        return actualLoadUnit == .bodyweight && isCompleted
    }

    nonisolated func applyingPreviousPerformance(
        _ previous: WorkoutPreviousSetSnapshot?,
        mode: WorkoutPreviousPerformanceApplicationMode = .overwriteExisting
    ) -> WorkoutSessionSetDraft {
        guard let previous else { return self }

        var updatedDraft = self
        let shouldReplaceWeight = mode == .overwriteExisting || updatedDraft.actualWeight == nil
        let shouldReplaceReps = mode == .overwriteExisting || updatedDraft.actualReps == nil

        if shouldReplaceWeight {
            updatedDraft.actualWeight = previous.weight
            updatedDraft.actualLoadUnit = previous.unit
        }

        if shouldReplaceReps {
            updatedDraft.actualReps = previous.reps
        }
        return updatedDraft
    }
}
