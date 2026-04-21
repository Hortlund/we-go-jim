import Foundation
import SwiftUI

struct WorkoutSessionExerciseGridEditor: View {
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
    var isBozarModeEnabled: Bool
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
    var onExerciseDelete: (() -> Void)?

    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool
    @State private var rowSnapshots: [WorkoutSessionExerciseSetRowDisplaySnapshot]
    @State private var cachedCompletedSetCount: Int
    @State private var exerciseSwipeOffset: CGFloat = 0
    @State private var exerciseSwipeRemoving = false
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]
    @State private var repsInputTextBySetID: [UUID: String] = [:]
    @State private var weightInputTextBySetID: [UUID: String] = [:]
    @State private var pendingBozarCompletionSetIDs: Set<UUID> = []
    @State private var revealedCompletionGateSetIDs: Set<UUID> = []
    @State private var pendingDisplayRefreshTask: Task<Void, Never>?
    @State private var suppressNextSetDraftsDisplayRefresh = false
    @State private var suppressNextFocusLossCommit = false
    @FocusState private var focusedInput: SetInputFocus?

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
    private let displayRefreshDebounce = Duration.milliseconds(90)

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
        isBozarModeEnabled: Bool = false,
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
        onExerciseDelete: (() -> Void)? = nil
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
        self.isBozarModeEnabled = isBozarModeEnabled
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
        self.onExerciseDelete = onExerciseDelete
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
                partialResult + (draft.isCompleted ? 1 : 0)
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
        .background { cardBackgroundLayer }
        .wgjCardContainer(strong: true)
        .overlay { cardOverlayLayer }
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
        }
        .onDisappear {
            flushPendingEditorState()
        }
        .onChange(of: setDrafts) { previousValue, newValue in
            handleSetDraftsChange(previousValue: previousValue, currentValue: newValue)
        }
        .onChange(of: previousPerformanceResolution) { _, _ in
            handlePreviousPerformanceResolutionChange()
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
            handleFocusedInputChange(previousFocus, newFocus)
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

    @ViewBuilder
    private var cardBackgroundLayer: some View {
        if shouldEmphasizeCompletedExercise {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .fill(completedExerciseCardFill)
        }
    }

    @ViewBuilder
    private var cardOverlayLayer: some View {
        if isExerciseCompleted {
            RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                .stroke(
                    WGJTheme.success.opacity(shouldEmphasizeCompletedExercise ? 0.60 : 0.34),
                    lineWidth: shouldEmphasizeCompletedExercise ? 2 : 1.2
                )
        }
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

                if shouldEmphasizeCompletedExercise {
                    completedExerciseBadge
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

    private func setCard(_ row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let set = row.set
        let inlineHintPresentation = row.inlineHintPresentation
        let personalRecordKinds = personalRecordKindsBySetID[row.id] ?? []
        let hasPersonalRecord = !personalRecordKinds.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
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

                setMenu(at: row.index)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    metricField(title: "Weight", supporting: row.targetWeightText) {
                        loadField(at: row.index)
                    }

                    metricField(title: "Reps", supporting: row.targetRepsText) {
                        repsField(at: row.index)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricField(title: "Weight", supporting: row.targetWeightText) {
                        loadField(at: row.index)
                    }

                    metricField(title: "Reps", supporting: row.targetRepsText) {
                        repsField(at: row.index)
                    }
                }
            }

            if manualCompletionMode, let inlineHintPresentation {
                inlineHintRow(inlineHintPresentation, at: row.index)
            }

            if manualCompletionMode {
                completionRow(for: row)
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

    private func inlineHintRow(_ presentation: WorkoutSetInlineHintPresentation, at index: Int) -> some View {
        let canApplyPrevious = isSetEditingEnabled && presentation.canApplyPrevious && !setDrafts[index].isLocked

        return ViewThatFits(in: .horizontal) {
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

    private func repsField(at index: Int) -> some View {
        let overlayState = repsFieldDisplayState(at: index)

        return ZStack {
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
                .disabled(!isSetEditingEnabled || setDrafts[index].isLocked)
                .accessibilityIdentifier("workout-set-\(index)-reps-field")
        }
        .metricInputShell(isFocused: isInputFocused(.reps, at: index))
    }

    private func loadField(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked
        let overlayState = weightFieldDisplayState(at: index)

        return HStack(spacing: 6) {
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
                    .disabled(!isSetEditingEnabled || isLocked)
                    .accessibilityIdentifier("workout-set-\(index)-weight-field")
            }

            WGJActionMenuButton("Load Unit", titleVisibility: .hidden) {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        let setID = setDrafts[index].id
                        let hadWeight = setDrafts[index].actualWeight != nil
                        setDrafts[index].actualLoadUnit = unit
                        if unit == .bodyweight {
                            setDrafts[index].actualWeight = nil
                            weightInputTextBySetID[setID] = ""
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

    private func setMenu(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked

        return Menu {
            Button {
                insertSet(after: index)
            } label: {
                Label("Insert below", systemImage: "plus")
            }
            .disabled(!isSetEditingEnabled || isLocked)

            Menu {
                Button {
                    moveSetUp(index)
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                .disabled(!isSetEditingEnabled || isLocked || index == 0 || setDrafts[index - 1].isLocked)

                Button {
                    moveSetDown(index)
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                .disabled(!isSetEditingEnabled || isLocked || index == setDrafts.count - 1 || setDrafts[index + 1].isLocked)
            } label: {
                Label("Reorder", systemImage: "arrow.up.arrow.down")
            }

            Menu {
                Button("Use exercise default (\(Self.formattedRest(restSeconds)))") {
                    updateSetRest(restSeconds, at: index)
                }
                .disabled(!isSetEditingEnabled || isLocked)

                Button("Reduce rest by 15 sec") {
                    updateSetRest(setDrafts[index].restSeconds - 15, at: index)
                }
                .disabled(!isSetEditingEnabled || isLocked)

                Button("Increase rest by 15 sec") {
                    updateSetRest(setDrafts[index].restSeconds + 15, at: index)
                }
                .disabled(!isSetEditingEnabled || isLocked)

                Button("No rest") {
                    updateSetRest(0, at: index)
                }
                .disabled(!isSetEditingEnabled || isLocked)

                Divider()

                Menu("Presets") {
                    ForEach(restPresets, id: \.self) { value in
                        Button(Self.formattedRest(value)) {
                            updateSetRest(value, at: index)
                        }
                        .disabled(!isSetEditingEnabled || isLocked)
                    }
                }
            } label: {
                Label("Rest", systemImage: "timer")
            }

            Button {
                toggleWarmup(at: index)
            } label: {
                Label(setDrafts[index].isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }
            .disabled(!isSetEditingEnabled || isLocked)

            Button {
                toggleLock(at: index)
            } label: {
                Label(setDrafts[index].isLocked ? "Unlock set" : "Lock set", systemImage: setDrafts[index].isLocked ? "lock.open" : "lock")
            }
            .disabled(!isSetEditingEnabled)

            if setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil {
                Button {
                    clearLoggedValues(at: index)
                } label: {
                    Label("Clear logged values", systemImage: "eraser")
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            if manualCompletionMode {
                Button {
                    toggleCompletion(at: index)
                } label: {
                    Label(
                        setDrafts[index].isCompleted ? "Mark incomplete" : "Complete set",
                        systemImage: setDrafts[index].isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }
                .disabled(!isSetEditingEnabled || isLocked)
            }

            Button(role: .destructive) {
                removeSet(at: index)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
            .disabled(!isSetEditingEnabled || isLocked)
        } label: {
            headerIcon(symbol: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("workout-set-actions-button-\(index)")
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

    private var completedExerciseBadge: some View {
        Label("Exercise complete", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(WGJTheme.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(WGJTheme.success.opacity(0.14))
                    .overlay(
                        Capsule()
                            .stroke(WGJTheme.success.opacity(0.28), lineWidth: 1)
                    )
            )
    }

    private func toggleExpanded() {
        if isExpanded {
            dismissInputFocus()
        }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            expansionBinding.wrappedValue.toggle()
        }
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
        rowSnapshots
    }

    private var completedSetCount: Int {
        cachedCompletedSetCount
    }

    private var isExerciseCompleted: Bool {
        !setDrafts.isEmpty && completedSetCount == setDrafts.count
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
        if let valueText = weightActualDisplayText(at: index) {
            return MetricFieldDisplayState(
                text: valueText,
                tone: .actual,
                accessibilityIdentifier: "workout-set-\(index)-weight-actual"
            )
        }

        guard let ghostText = weightGhostText(at: index) else { return nil }
        return MetricFieldDisplayState(
            text: ghostText,
            tone: .ghost,
            accessibilityIdentifier: "workout-set-\(index)-weight-ghost"
        )
    }

    private func repsFieldDisplayState(at index: Int) -> MetricFieldDisplayState? {
        guard setDrafts.indices.contains(index), !isInputFocused(.reps, at: index) else { return nil }
        if let valueText = repsActualDisplayText(at: index) {
            return MetricFieldDisplayState(
                text: valueText,
                tone: .actual,
                accessibilityIdentifier: "workout-set-\(index)-reps-actual"
            )
        }

        guard let ghostText = repsGhostText(at: index) else { return nil }
        return MetricFieldDisplayState(
            text: ghostText,
            tone: .ghost,
            accessibilityIdentifier: "workout-set-\(index)-reps-ghost"
        )
    }

    private func weightActualDisplayText(at index: Int) -> String? {
        guard setDrafts.indices.contains(index) else { return nil }
        let draft = setDrafts[index]

        if let actualWeight = draft.actualWeight {
            return formatWeight(actualWeight)
        }

        let showsBodyweightAsLoggedValue =
            draft.actualLoadUnit == .bodyweight
            && (draft.actualReps != nil || draft.isCompleted)

        return showsBodyweightAsLoggedValue ? TemplateLoadUnit.bodyweight.shortLabel : nil
    }

    private func repsActualDisplayText(at index: Int) -> String? {
        guard setDrafts.indices.contains(index), let actualReps = setDrafts[index].actualReps else {
            return nil
        }
        return "\(actualReps)"
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
        if suppressCommit, focusedInput != nil {
            suppressNextFocusLossCommit = true
        }
        focusedInput = nil
    }

    private func repsTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index) else {
                    return ""
                }
                let setID = setDrafts[index].id
                if isInputFocused(.reps, at: index), let draft = repsInputTextBySetID[setID] {
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
                repsInputTextBySetID[setID] = newValue
                let cleaned = newValue.filter(\.isNumber)
                let updatedReps = cleaned.isEmpty ? nil : Int(cleaned)
                suppressNextSetDraftsDisplayRefresh = true

                if setDrafts[index].actualReps != updatedReps {
                    setDrafts[index].actualReps = updatedReps
                }

                if !manualCompletionMode {
                    let isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                    if setDrafts[index].isCompleted != isCompleted {
                        setDrafts[index].isCompleted = isCompleted
                    }
                }
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
                if isInputFocused(.weight, at: index), let draft = weightInputTextBySetID[setID] {
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
                weightInputTextBySetID[setID] = newValue
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedWeight: Double?
                suppressNextSetDraftsDisplayRefresh = true

                if normalized.isEmpty {
                    updatedWeight = nil
                } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
                    updatedWeight = max(0, parsed)
                } else {
                    updatedWeight = setDrafts[index].actualWeight
                }

                if setDrafts[index].actualWeight != updatedWeight {
                    setDrafts[index].actualWeight = updatedWeight
                }

                let fallbackWeightedUnit = resolvedWeightedLoadUnit(for: setDrafts[index])
                if let updatedWeight, updatedWeight > 0 {
                    if setDrafts[index].actualLoadUnit == .bodyweight {
                        setDrafts[index].actualLoadUnit = fallbackWeightedUnit
                    }
                } else if updatedWeight == nil,
                          setDrafts[index].targetLoadUnit == .bodyweight,
                          setDrafts[index].actualLoadUnit != .bodyweight
                {
                    setDrafts[index].actualLoadUnit = .bodyweight
                }

                if !manualCompletionMode {
                    let isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                    if setDrafts[index].isCompleted != isCompleted {
                        setDrafts[index].isCompleted = isCompleted
                    }
                }
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
        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        notifyChanged()
        onSetCompletionChange?(removedID, removedTitle, 0, false)
    }

    private func removeSet(withID setID: UUID) {
        guard let index = setDrafts.firstIndex(where: { $0.id == setID }) else { return }
        removeSet(at: index)
    }

    private func toggleWarmup(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        setDrafts[index].isWarmup.toggle()
        notifyChanged()
    }

    private func toggleLock(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isLocked.toggle()
        if setDrafts[index].isLocked, focusedInput?.setID == setDrafts[index].id {
            dismissInputFocus()
        }
        notifyChanged()
    }

    private func updateSetRest(_ seconds: Int, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        setDrafts[index].restSeconds = max(0, min(3600, seconds))
        notifyChanged()
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }
        guard !setDrafts[index].isLocked, !setDrafts[index - 1].isLocked else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index - 1)
        }
        notifyChanged()
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }
        guard !setDrafts[index].isLocked, !setDrafts[index + 1].isLocked else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index + 1)
        }
        notifyChanged()
    }

    private func clearLoggedValues(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        let set = setDrafts[index]
        setDrafts[index].actualReps = nil
        setDrafts[index].actualWeight = nil
        if setDrafts[index].targetLoadUnit == .bodyweight {
            setDrafts[index].actualLoadUnit = .bodyweight
        }
        setDrafts[index].isCompleted = false
        notifyChanged()
        if set.isCompleted {
            onSetCompletionChange?(set.id, setTitle(for: index), set.restSeconds, false)
        }
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
            partialResult + (row.set.isCompleted ? 1 : 0)
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
        pendingDisplayRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: displayRefreshDebounce)
            guard !Task.isCancelled else { return }
            pendingDisplayRefreshTask = nil
            refreshDisplayRows()
        }
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
        pendingBozarCompletionSetIDs.removeAll()
        flushPendingDisplayRefresh()
    }

    private func handlePreviousPerformanceResolutionChange() {
        prunePendingBozarCompletions()
        resolvePendingBozarCompletionsIfNeeded()
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
            let label: WorkoutSessionExerciseSetRowLabel
            if draft.isWarmup {
                label = WorkoutSessionExerciseSetRowLabel(
                    badgeTitle: "W",
                    title: "Warmup Set"
                )
            } else {
                workingSetNumber += 1
                label = WorkoutSessionExerciseSetRowLabel(
                    badgeTitle: "\(workingSetNumber)",
                    title: "Working Set \(workingSetNumber)"
                )
            }

            rows.append(
                WorkoutSessionExerciseSetRowDisplaySnapshot(
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
                    metadataLine: metadataLine(for: draft, restSeconds: restSeconds),
                    targetWeightText: targetWeightText(for: draft, formatWeight: formatWeight),
                    targetRepsText: targetRepsText(for: draft),
                    inlineHintPresentation: WorkoutSetInlineHintPresentation.make(
                        draft: draft,
                        previous: previousPerformanceResolution.previous(at: index),
                        targetRepMin: targetRepMin,
                        targetRepMax: targetRepMax,
                        formatWeight: formatWeight
                    ),
                    completionButtonTitle: completionButtonTitle(restSeconds: draft.restSeconds)
                )
            )
        }

        return rows
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

    private static func metadataLine(for set: WorkoutSessionSetDraft, restSeconds: Int) -> String? {
        var parts: [String] = []

        if set.isLocked {
            parts.append("Locked")
        }

        if set.restSeconds != restSeconds {
            parts.append("Rest \(restLabel(for: set.restSeconds))")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private static func targetWeightText(for set: WorkoutSessionSetDraft, formatWeight: (Double) -> String) -> String? {
        guard let targetWeight = set.targetWeight else {
            return nil
        }

        return "Target \(formatWeight(targetWeight)) \(set.targetLoadUnit.shortLabel)"
    }

    private static func targetRepsText(for set: WorkoutSessionSetDraft) -> String? {
        guard let targetReps = set.targetReps else {
            return nil
        }

        return "Target \(targetReps)"
    }

    private static func completionButtonTitle(restSeconds: Int) -> String {
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
        guard let updatedDrafts = WorkoutSetBozarCompletionController.applyPreviousPerformance(
            to: setDrafts,
            at: index,
            previousResolution: previousPerformanceResolution
        ) else {
            return
        }
        let focusedSetInput = focusedInput?.setID == setDrafts[index].id ? focusedInput : nil
        if let focusedSetInput {
            syncInputDraft(for: focusedSetInput, using: updatedDrafts[index])
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

    private func resolvedWeightedLoadUnit(for set: WorkoutSessionSetDraft) -> TemplateLoadUnit {
        switch set.targetLoadUnit {
        case .kg, .lb:
            return set.targetLoadUnit
        case .bodyweight:
            return preferredLoadUnit
        }
    }

    private func setCardFill(for set: WorkoutSessionSetDraft, hasPersonalRecord: Bool) -> Color {
        if hasPersonalRecord {
            if set.isCompleted {
                return WGJTheme.accentGold.opacity(0.12)
            }
            if set.isWarmup {
                return WGJTheme.accentGold.opacity(0.14)
            }
            return WGJTheme.accentGold.opacity(0.08)
        }

        if set.isCompleted {
            return WGJTheme.accentBlue.opacity(0.12)
        }

        if set.isWarmup {
            return WGJTheme.accentGold.opacity(0.12)
        }

        return WGJTheme.field.opacity(0.54)
    }

    private func setCardStroke(for set: WorkoutSessionSetDraft, hasPersonalRecord: Bool) -> Color {
        if hasPersonalRecord {
            return WGJTheme.accentGold.opacity(0.50)
        }

        if set.isCompleted {
            return WGJTheme.accentBlue.opacity(0.34)
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

    private func completionRow(for row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let index = row.index
        let set = row.set
        let completionGatePresentation = isSetCompletionEnabled ? nil : setCompletionGatePresentation
        let isCompletionGateRevealed = revealedCompletionGateSetIDs.contains(set.id)

        return Group {
            if pendingBozarCompletionSetIDs.contains(set.id) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading previous set...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.9)

                    Spacer(minLength: 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.field.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WGJTheme.outline.opacity(0.72), lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("workout-set-\(index)-bozar-pending")
            } else if set.isCompleted {
                HStack(spacing: 10) {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.success)
                        .wgjSingleLineText(scale: 0.9)

                    Spacer(minLength: 8)

                Button("Undo") {
                    requestCompletionChange(at: index, isCompleted: false)
                }
                .buttonStyle(WGJGhostButtonStyle())
                .disabled(!isSetEditingEnabled || set.isLocked)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.success.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WGJTheme.success.opacity(0.22), lineWidth: 1)
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let completionGatePresentation {
                        completionGateNotice(
                            completionGatePresentation,
                            at: index,
                            isRevealed: isCompletionGateRevealed
                        )
                        Button {
                            requestCompletionChange(at: index, isCompleted: true)
                        } label: {
                            Label(row.completionButtonTitle, systemImage: "lock.fill")
                                .frame(maxWidth: .infinity)
                                .wgjSingleLineText(scale: 0.82)
                                .foregroundStyle(WGJTheme.accentGold)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(WGJTheme.accentGold.opacity(isCompletionGateRevealed ? 0.16 : 0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(WGJTheme.accentGold.opacity(isCompletionGateRevealed ? 0.40 : 0.24), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSetEditingEnabled || set.isLocked)
                        .accessibilityIdentifier("workout-set-\(index)-completion-button")
                    } else {
                        Button {
                            requestCompletionChange(at: index, isCompleted: true)
                        } label: {
                            Label(row.completionButtonTitle, systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .wgjSingleLineText(scale: 0.82)
                        }
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                        .disabled(!isSetEditingEnabled || set.isLocked)
                        .accessibilityIdentifier("workout-set-\(index)-completion-button")
                    }
                }
            }
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

    private func toggleCompletion(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        requestCompletionChange(at: index, isCompleted: !setDrafts[index].isCompleted)
    }

    private func requestCompletionChange(at index: Int, isCompleted: Bool) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        if isCompleted, !isSetCompletionEnabled {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                revealedCompletionGateSetIDs.insert(setDrafts[index].id)
            }
            return
        }

        revealedCompletionGateSetIDs.remove(setDrafts[index].id)
        let focusedSetInput = focusedInput?.setID == setDrafts[index].id ? focusedInput : nil

        guard isCompleted else {
            if focusedSetInput != nil {
                dismissInputFocus(suppressCommit: true)
            }
            pendingBozarCompletionSetIDs.remove(setDrafts[index].id)
            setCompletion(false, at: index)
            return
        }

        guard manualCompletionMode, isBozarModeEnabled else {
            if focusedSetInput != nil {
                dismissInputFocus(suppressCommit: true)
            }
            pendingBozarCompletionSetIDs.remove(setDrafts[index].id)
            setCompletion(true, at: index)
            return
        }

        guard let decision = WorkoutSetBozarCompletionController.decision(
            drafts: setDrafts,
            at: index,
            previousResolution: previousPerformanceResolution
        ) else {
            return
        }

        switch decision {
        case .waitForPreviousPerformance(let setID):
            if focusedSetInput != nil {
                dismissInputFocus(suppressCommit: true)
            }
            pendingBozarCompletionSetIDs.insert(setID)
        case .completeImmediately(let updatedDrafts):
            pendingBozarCompletionSetIDs.remove(setDrafts[index].id)
            completeSetUsingBozar(at: index, draftOverride: updatedDrafts)
        }
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
        pendingBozarCompletionSetIDs.remove(setID)
        guard updatedDrafts[index].isCompleted != isCompleted else { return }
        let setRestSeconds = updatedDrafts[index].restSeconds
        updatedDrafts[index].isCompleted = isCompleted
        setDrafts = updatedDrafts
        let restTimerSetLabel: String?
        if isCompleted {
            restTimerSetLabel = WorkoutRestTimerContextBuilder.nextSetLabel(
                afterCompletingSetAt: index,
                in: updatedDrafts
            )
        } else {
            restTimerSetLabel = setTitle(for: index, in: updatedDrafts)
        }
        notifyChanged(drafts: updatedDrafts)
        onSetCompletionChange?(setID, restTimerSetLabel, setRestSeconds, isCompleted)
    }

    private func notifyChanged(drafts: [WorkoutSessionSetDraft]? = nil) {
        pendingDisplayRefreshTask?.cancel()
        pendingDisplayRefreshTask = nil
        let currentDrafts = drafts ?? setDrafts
        suppressNextSetDraftsDisplayRefresh = true
        syncCompletedSetCount(using: currentDrafts)
        if isExpanded {
            rebuildDisplayRows(using: currentDrafts, restSeconds: restSeconds)
        }
        requestCommitForCurrentState(drafts: currentDrafts)
    }

    private func handleFocusedInputChange(_ previousFocus: SetInputFocus?, _ newFocus: SetInputFocus?) {
        guard previousFocus != newFocus else { return }
        if let previousFocus {
            if suppressNextFocusLossCommit {
                suppressNextFocusLossCommit = false
            } else {
                clearInputDraft(for: previousFocus)
                requestCommitForCurrentState()
            }
        } else {
            suppressNextFocusLossCommit = false
        }
        if newFocus == nil {
            pendingDisplayRefreshTask?.cancel()
            pendingDisplayRefreshTask = nil
            if isExpanded {
                refreshDisplayRows()
            }
        }
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

        if changeSummary.hasMeaningfulChange {
            prunePendingBozarCompletions()
        }
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
        let currentDrafts = drafts ?? setDrafts
        let currentRestSeconds = overrideRestSeconds ?? restSeconds
        onCommitRequest?(currentDrafts, currentRestSeconds)
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
    }

    private func pruneInputDrafts() {
        let validSetIDs = Set(setDrafts.map(\.id))
        repsInputTextBySetID = repsInputTextBySetID.filter { validSetIDs.contains($0.key) }
        weightInputTextBySetID = weightInputTextBySetID.filter { validSetIDs.contains($0.key) }

        if let focusedInput, !validSetIDs.contains(focusedInput.setID) {
            self.focusedInput = nil
        }
    }

    private func syncCompletedSetCount(using drafts: [WorkoutSessionSetDraft]? = nil) {
        let currentDrafts = drafts ?? setDrafts
        cachedCompletedSetCount = currentDrafts.reduce(0) { partialResult, draft in
            partialResult + (draft.isCompleted ? 1 : 0)
        }
    }

    private func prunePendingBozarCompletions() {
        let validSetIDs = Set(
            setDrafts
                .filter { !$0.isCompleted }
                .map(\.id)
        )
        pendingBozarCompletionSetIDs = pendingBozarCompletionSetIDs.filter { validSetIDs.contains($0) }
    }

    private func resolvePendingBozarCompletionsIfNeeded() {
        guard !previousPerformanceResolution.isLoading, !pendingBozarCompletionSetIDs.isEmpty else {
            return
        }

        let pendingSetIDs = pendingBozarCompletionSetIDs
        for setID in pendingSetIDs {
            guard let index = setDrafts.firstIndex(where: { $0.id == setID }) else {
                pendingBozarCompletionSetIDs.remove(setID)
                continue
            }

            guard let decision = WorkoutSetBozarCompletionController.decision(
                drafts: setDrafts,
                at: index,
                previousResolution: previousPerformanceResolution
            ) else {
                pendingBozarCompletionSetIDs.remove(setID)
                continue
            }

            switch decision {
            case .waitForPreviousPerformance:
                break
            case .completeImmediately(let updatedDrafts):
                completeSetUsingBozar(at: index, draftOverride: updatedDrafts)
            }
        }
    }

    private func completeSetUsingBozar(
        at index: Int,
        draftOverride: [WorkoutSessionSetDraft]? = nil
    ) {
        guard setDrafts.indices.contains(index) else { return }

        let updatedDrafts =
            draftOverride
            ?? WorkoutSetBozarCompletionController.applyPreviousPerformance(
                to: setDrafts,
                at: index,
                previousResolution: previousPerformanceResolution,
                mode: .fillMissing
            )
            ?? setDrafts
        guard updatedDrafts.indices.contains(index) else { return }

        if let focusedSetInput = focusedInput, focusedSetInput.setID == updatedDrafts[index].id {
            syncInputDraft(for: focusedSetInput, using: updatedDrafts[index])
            dismissInputFocus(suppressCommit: true)
        }

        setCompletion(true, at: index, draftOverride: updatedDrafts)
    }

    private func clearInputDraft(for focus: SetInputFocus) {
        switch focus.metric {
        case .weight:
            weightInputTextBySetID[focus.setID] = nil
        case .reps:
            repsInputTextBySetID[focus.setID] = nil
        }
    }

    private func syncInputDraft(for focus: SetInputFocus, using draft: WorkoutSessionSetDraft) {
        guard focus.setID == draft.id else { return }

        switch focus.metric {
        case .weight:
            weightInputTextBySetID[draft.id] = draft.actualWeight.map(formatWeight) ?? ""
        case .reps:
            repsInputTextBySetID[draft.id] = draft.actualReps.map(String.init) ?? ""
        }
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

private extension View {
    func metricInputShell(isFocused: Bool) -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
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
    let targetWeightText: String?
    let targetRepsText: String?
    let inlineHintPresentation: WorkoutSetInlineHintPresentation?
    let completionButtonTitle: String
}

struct WorkoutSetCompletionGatePresentation: Equatable {
    let title: String
    let detail: String
    let iconSystemName: String

    static let preWorkoutCardioRequired = WorkoutSetCompletionGatePresentation(
        title: "Finish pre-workout cardio before completing sets",
        detail: "Complete the warmup block above before you mark any main-work sets done.",
        iconSystemName: "lock.fill"
    )
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

enum WorkoutSetBozarCompletionResolver {
    static func resolve(
        draft: WorkoutSessionSetDraft,
        previous: WorkoutPreviousSetSnapshot?,
        mode: WorkoutPreviousPerformanceApplicationMode = .fillMissing
    ) -> WorkoutSessionSetDraft {
        draft.applyingPreviousPerformance(previous, mode: mode)
    }
}

private extension WorkoutSessionSetDraft {
    var showsLoggedPerformance: Bool {
        if actualWeight != nil || actualReps != nil {
            return true
        }

        return actualLoadUnit == .bodyweight && isCompleted
    }

    func applyingPreviousPerformance(
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
