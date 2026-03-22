import Foundation
import SwiftUI

struct WorkoutSessionExerciseGridEditor: View {
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseIndexTitle: String?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let previousBySetIndex: [Int: WorkoutPreviousSetSnapshot]
    let overloadFeedback: ActiveWorkoutProgressiveOverloadPresentation?
    let preferredLoadUnit: TemplateLoadUnit

    @Binding var restSeconds: Int
    @Binding var setDrafts: [WorkoutSessionSetDraft]

    var showsInlineExerciseControls: Bool
    var showsSetProgressChip: Bool
    var manualCompletionMode: Bool
    var enablesHeaderSwipeDelete: Bool
    var onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)?
    var onRestChanged: ((Int) -> Void)?
    var onSetCompletionChange: ((UUID, String, Int, Bool) -> Void)?
    var onExerciseSettings: (() -> Void)?
    var onExerciseDelete: (() -> Void)?

    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool
    @State private var exerciseSwipeOffset: CGFloat = 0
    @State private var exerciseSwipeRemoving = false
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]
    @FocusState private var focusedInput: SetInputFocus?

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]

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
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        previousBySetIndex: [Int: WorkoutPreviousSetSnapshot],
        overloadFeedback: ActiveWorkoutProgressiveOverloadPresentation? = nil,
        preferredLoadUnit: TemplateLoadUnit = .kg,
        restSeconds: Binding<Int>,
        setDrafts: Binding<[WorkoutSessionSetDraft]>,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        showsInlineExerciseControls: Bool = true,
        showsSetProgressChip: Bool = true,
        manualCompletionMode: Bool = false,
        enablesHeaderSwipeDelete: Bool = false,
        onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)? = nil,
        onRestChanged: ((Int) -> Void)? = nil,
        onSetCompletionChange: ((UUID, String, Int, Bool) -> Void)? = nil,
        onExerciseSettings: (() -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.exerciseIndexTitle = exerciseIndexTitle
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.previousBySetIndex = previousBySetIndex
        self.overloadFeedback = overloadFeedback
        self.preferredLoadUnit = preferredLoadUnit
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.externalIsExpanded = isExpanded
        self.showsInlineExerciseControls = showsInlineExerciseControls
        self.showsSetProgressChip = showsSetProgressChip
        self.manualCompletionMode = manualCompletionMode
        self.enablesHeaderSwipeDelete = enablesHeaderSwipeDelete
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRestChanged = onRestChanged
        self.onSetCompletionChange = onSetCompletionChange
        self.onExerciseSettings = onExerciseSettings
        self.onExerciseDelete = onExerciseDelete
        self._localIsExpanded = State(initialValue: isExpanded?.wrappedValue ?? initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if isExpanded {
                if showsInlineExerciseControls {
                    controlsSection
                }
                setsSection
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
        .overlay {
            if isExerciseCompleted {
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .stroke(WGJTheme.success.opacity(0.34), lineWidth: 1.2)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                keyboardToolbar
            }
        }
        .onChange(of: setDrafts.map(\.id)) { _, updatedSetIDs in
            guard let focusedInput, !updatedSetIDs.contains(focusedInput.setID) else { return }
            dismissInputFocus()
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
                        .foregroundStyle(WGJTheme.accentCyan)
                }

                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .wgjSingleLineText(scale: 0.8)

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)

                if let overloadFeedback {
                    Text(overloadFeedback.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(feedbackTint(for: overloadFeedback.tone))
                        .lineLimit(2)
                }

                headerSummaryChips
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                if onExerciseSettings != nil || onExerciseDelete != nil {
                    Menu {
                        if let onExerciseSettings {
                            Button {
                                onExerciseSettings()
                            } label: {
                                Label("Exercise Settings", systemImage: "slider.horizontal.3")
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
                    .buttonStyle(.plain)
                }

                Button {
                    toggleExpanded()
                } label: {
                    headerIcon(symbol: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
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
            subtitle: "Template guide for the set entries below.",
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
                Menu {
                    ForEach(restPresets, id: \.self) { value in
                        Button(formattedRest(value)) {
                            updateRest(value)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(formattedRest(restSeconds), systemImage: "timer")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logged Sets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer()

                Text("\(setDrafts.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            if setDrafts.isEmpty {
                Text("No sets yet.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(.vertical, 6)
            }

            ForEach(Array(setDrafts.enumerated()), id: \.element.id) { index, draft in
                SwipeDeleteRow(
                    offset: setSwipeOffsetBinding(for: draft.id),
                    isRemoving: setRemovingBinding(for: draft.id),
                    isEnabled: !draft.isLocked,
                    gestureStrategy: .simultaneous
                ) {
                    removeSet(withID: draft.id)
                } content: {
                    setCard(at: index)
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
        }
    }

    private func setCard(at index: Int) -> some View {
        let set = setDrafts[index]
        let progressReference = progressReference(for: index)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                setBadge(for: index)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(setTitle(for: index))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .wgjSingleLineText(scale: 0.84)

                        if set.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WGJTheme.accentGold)
                        }
                    }

                    if !manualCompletionMode || progressReference == nil {
                        Text(previousSummary(for: index))
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                            .monospacedDigit()
                    }

                    if let metadata = setMetadataLine(for: index) {
                        Text(metadata)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                setMenu(at: index)
            }

            if manualCompletionMode, let progressReference {
                progressReferenceStrip(progressReference, at: index)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    metricField(title: "Weight", supporting: targetWeightText(for: index)) {
                        loadField(at: index)
                    }

                    metricField(title: "Reps", supporting: targetRepsText(for: index)) {
                        repsField(at: index)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricField(title: "Weight", supporting: targetWeightText(for: index)) {
                        loadField(at: index)
                    }

                    metricField(title: "Reps", supporting: targetRepsText(for: index)) {
                        repsField(at: index)
                    }
                }
            }

            if manualCompletionMode {
                completionRow(at: index)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(setCardFill(for: set))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(setCardStroke(for: set), lineWidth: 1)
                )
        )
    }

    private func progressReferenceStrip(_ reference: WorkoutSetProgressReference, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    progressReferenceMetric(
                        title: "Last",
                        value: reference.lastValue,
                        tint: WGJTheme.textPrimary
                    )

                    Rectangle()
                        .fill(WGJTheme.rowDivider)
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    progressReferenceMetric(
                        title: "Aim",
                        value: reference.aimValue,
                        tint: WGJTheme.accentBlue
                    )

                    if reference.canReusePrevious && !setDrafts[index].isLocked {
                        Spacer(minLength: 8)
                        applyPreviousButton(at: index)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        progressReferenceMetric(
                            title: "Last",
                            value: reference.lastValue,
                            tint: WGJTheme.textPrimary
                        )

                        Spacer(minLength: 8)

                        if reference.canReusePrevious && !setDrafts[index].isLocked {
                            applyPreviousButton(at: index)
                        }
                    }

                    progressReferenceMetric(
                        title: "Aim",
                        value: reference.aimValue,
                        tint: WGJTheme.accentBlue
                    )
                }
            }

            if let statusText = reference.statusText {
                progressStatusChip(text: statusText, tone: reference.statusTone)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.cardElevated.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WGJTheme.accentBlue.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func progressReferenceMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(WGJTheme.textTertiary)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressStatusChip(text: String, tone: WorkoutSetProgressTone) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(progressToneColor(for: tone))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(progressToneColor(for: tone).opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(progressToneColor(for: tone).opacity(0.22), lineWidth: 1)
                    )
            )
    }

    private func applyPreviousButton(at index: Int) -> some View {
        Button {
            applyPreviousPerformance(at: index)
        } label: {
            Label("Use Last", systemImage: "arrow.down.left.circle.fill")
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

    private var keyboardToolbar: some View {
        Group {
            if let index = focusedSetIndex, setDrafts.indices.contains(index) {
                Button("Weight") {
                    focusMetric(.weight, at: index)
                }
                .disabled(isInputFocused(.weight, at: index))

                Button("Reps") {
                    focusMetric(.reps, at: index)
                }
                .disabled(isInputFocused(.reps, at: index))

                Spacer()

                if manualCompletionMode {
                    Button(setDrafts[index].isCompleted ? "Logged" : "Complete") {
                        completeFocusedSet()
                    }
                    .fontWeight(.semibold)
                    .disabled(setDrafts[index].isLocked)
                }

                Button("Done") {
                    dismissInputFocus()
                }
                .fontWeight(.semibold)
            } else {
                Spacer()

                Button("Done") {
                    dismissInputFocus()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func repsField(at index: Int) -> some View {
        TextField("0", text: repsTextBinding(for: index))
            .keyboardType(.numberPad)
            .submitLabel(.done)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .focused($focusedInput, equals: inputFocus(for: index, metric: .reps))
            .multilineTextAlignment(.center)
            .disabled(setDrafts[index].isLocked)
            .metricInputShell(isFocused: isInputFocused(.reps, at: index))
    }

    private func loadField(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked

        return HStack(spacing: 6) {
            TextField("0", text: weightTextBinding(for: index))
                .keyboardType(.decimalPad)
                .submitLabel(.next)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .focused($focusedInput, equals: inputFocus(for: index, metric: .weight))
                .multilineTextAlignment(.center)
                .disabled(isLocked)

            Menu {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        setDrafts[index].actualLoadUnit = unit
                        notifyChanged()
                    }
                }
            } label: {
                Text(setDrafts[index].actualLoadUnit.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
            .disabled(isLocked)
        }
        .metricInputShell(isFocused: isInputFocused(.weight, at: index))
    }

    private func setBadge(for index: Int) -> some View {
        let set = setDrafts[index]
        let title = set.isWarmup ? "W" : "\(workingSetNumber(at: index))"

        return Button {
            toggleWarmup(at: index)
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

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.isWarmup ? WGJTheme.accentGold : WGJTheme.textPrimary)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(set.isLocked)
    }

    private func setMenu(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked
        let currentRest = setDrafts[index].restSeconds

        return Menu {
            Button {
                insertSet(after: index)
            } label: {
                Label("Insert below", systemImage: "plus")
            }
            .disabled(isLocked)

            Button {
                toggleWarmup(at: index)
            } label: {
                Label(setDrafts[index].isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }
            .disabled(isLocked)

            Button {
                moveSetUp(index)
            } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            .disabled(isLocked || index == 0 || setDrafts[index - 1].isLocked)

            Button {
                moveSetDown(index)
            } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            .disabled(isLocked || index == setDrafts.count - 1 || setDrafts[index + 1].isLocked)

            Menu {
                ForEach(restPresets, id: \.self) { value in
                    Button(formattedRest(value)) {
                        updateSetRest(value, at: index)
                    }
                }

                Divider()

                Button("Use exercise default (\(formattedRest(restSeconds)))") {
                    updateSetRest(restSeconds, at: index)
                }

                Button("-15 sec") {
                    updateSetRest(currentRest - 15, at: index)
                }

                Button("+15 sec") {
                    updateSetRest(currentRest + 15, at: index)
                }

                Button("No rest") {
                    updateSetRest(0, at: index)
                }
            } label: {
                Label("Set rest", systemImage: "timer")
            }
            .disabled(isLocked)

            Button {
                toggleLock(at: index)
            } label: {
                Label(setDrafts[index].isLocked ? "Unlock set" : "Lock set", systemImage: setDrafts[index].isLocked ? "lock.open" : "lock")
            }

            if setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil {
                Button {
                    clearLoggedValues(at: index)
                } label: {
                    Label("Clear logged values", systemImage: "eraser")
                }
                .disabled(isLocked)
            }

            if setDrafts[index].restSeconds != restSeconds {
                Button {
                    updateSetRest(restSeconds, at: index)
                } label: {
                    Label("Reset rest", systemImage: "timer")
                }
                .disabled(isLocked)
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
                .disabled(isLocked)
            }

            Divider()

            Button(role: .destructive) {
                removeSet(at: index)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
            .disabled(isLocked)
        } label: {
            headerIcon(symbol: "ellipsis.circle")
        }
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

    private func headerIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(WGJTheme.accentBlue)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WGJTheme.field)
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

    private func feedbackTint(for tone: TrainingGuidanceTone) -> Color {
        switch tone {
        case .accent:
            return WGJTheme.accentBlue
        case .success:
            return WGJTheme.success
        case .caution:
            return WGJTheme.accentGold
        }
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

        return "Log the set values separately from the template target."
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

    private var completedSetCount: Int {
        setDrafts.filter(\.isCompleted).count
    }

    private var isExerciseCompleted: Bool {
        !setDrafts.isEmpty && completedSetCount == setDrafts.count
    }

    private var focusedSetIndex: Int? {
        guard let focusedInput else { return nil }
        return setDrafts.firstIndex { $0.id == focusedInput.setID }
    }

    private func inputFocus(for index: Int, metric: SetInputFocus.Metric) -> SetInputFocus {
        SetInputFocus(setID: setDrafts[index].id, metric: metric)
    }

    private func isInputFocused(_ metric: SetInputFocus.Metric, at index: Int) -> Bool {
        guard setDrafts.indices.contains(index) else { return false }
        return focusedInput == inputFocus(for: index, metric: metric)
    }

    private func focusMetric(_ metric: SetInputFocus.Metric, at index: Int) {
        guard setDrafts.indices.contains(index), !setDrafts[index].isLocked else { return }
        focusedInput = inputFocus(for: index, metric: metric)
    }

    private func dismissInputFocus() {
        focusedInput = nil
    }

    private func repsTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index), let value = setDrafts[index].actualReps else {
                    return ""
                }
                return "\(value)"
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let cleaned = newValue.filter(\.isNumber)

                if cleaned.isEmpty {
                    setDrafts[index].actualReps = nil
                } else {
                    setDrafts[index].actualReps = Int(cleaned)
                }

                if !manualCompletionMode {
                    setDrafts[index].isCompleted =
                        (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                }
                notifyChanged()
            }
        )
    }

    private func weightTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index), let value = setDrafts[index].actualWeight else {
                    return ""
                }
                return formatWeight(value)
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if normalized.isEmpty {
                    setDrafts[index].actualWeight = nil
                } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
                    setDrafts[index].actualWeight = max(0, parsed)
                }

                if !manualCompletionMode {
                    setDrafts[index].isCompleted =
                        (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                }
                notifyChanged()
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
        setDrafts[index].isCompleted = false
        notifyChanged()
        if set.isCompleted {
            onSetCompletionChange?(set.id, setTitle(for: index), set.restSeconds, false)
        }
    }

    private func progressReference(for index: Int) -> WorkoutSetProgressReference? {
        guard setDrafts.indices.contains(index) else { return nil }
        return WorkoutSetProgressReference.make(
            draft: setDrafts[index],
            previous: previousBySetIndex[index],
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            formatWeight: formatWeight
        )
    }

    private func previousText(for index: Int) -> String {
        guard let snapshot = previousBySetIndex[index] else {
            return "-"
        }

        if let weight = snapshot.weight, let reps = snapshot.reps {
            return "\(formatWeight(weight)) \(snapshot.unit.shortLabel) x \(reps)"
        }

        if let reps = snapshot.reps {
            return "\(reps) reps"
        }

        return "-"
    }

    private func previousSummary(for index: Int) -> String {
        let previous = previousText(for: index)
        return previous == "-" ? "No previous log for this slot." : "Previous \(previous)"
    }

    private func applyPreviousPerformance(at index: Int) {
        guard setDrafts.indices.contains(index), let previous = previousBySetIndex[index] else { return }
        guard !setDrafts[index].isLocked else { return }

        setDrafts[index].actualWeight = previous.weight
        setDrafts[index].actualReps = previous.reps
        setDrafts[index].actualLoadUnit = previous.unit

        if !manualCompletionMode {
            setDrafts[index].isCompleted = previous.weight != nil || previous.reps != nil
        }

        notifyChanged()
    }

    private func setMetadataLine(for index: Int) -> String? {
        guard setDrafts.indices.contains(index) else { return nil }
        let set = setDrafts[index]
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

    private func targetWeightText(for index: Int) -> String? {
        guard setDrafts.indices.contains(index), let targetWeight = setDrafts[index].targetWeight else {
            return nil
        }

        return "Target \(formatWeight(targetWeight)) \(setDrafts[index].targetLoadUnit.shortLabel)"
    }

    private func targetRepsText(for index: Int) -> String? {
        guard setDrafts.indices.contains(index), let targetReps = setDrafts[index].targetReps else {
            return nil
        }

        return "Target \(targetReps)"
    }

    private func setTitle(for index: Int) -> String {
        setDrafts[index].isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber(at: index))"
    }

    private func workingSetNumber(at index: Int) -> Int {
        let priorWorking = setDrafts.prefix(index).filter { !$0.isWarmup }
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

    private func setCardFill(for set: WorkoutSessionSetDraft) -> Color {
        if set.isCompleted {
            return WGJTheme.accentBlue.opacity(0.12)
        }

        if set.isWarmup {
            return WGJTheme.accentGold.opacity(0.12)
        }

        return WGJTheme.field.opacity(0.54)
    }

    private func setCardStroke(for set: WorkoutSessionSetDraft) -> Color {
        if set.isCompleted {
            return WGJTheme.accentBlue.opacity(0.34)
        }

        if set.isWarmup {
            return WGJTheme.accentGold.opacity(0.34)
        }

        return WGJTheme.accentBlue.opacity(0.18)
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func updateRest(_ seconds: Int) {
        let previousDefaultRest = restSeconds
        let normalized = max(0, min(3600, seconds))
        restSeconds = normalized

        for index in setDrafts.indices {
            if !setDrafts[index].isLocked && setDrafts[index].restSeconds == previousDefaultRest {
                setDrafts[index].restSeconds = normalized
            }
        }

        onRestChanged?(normalized)
        notifyChanged()
    }

    private func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : formattedRest(seconds)
    }

    private func completionRow(at index: Int) -> some View {
        Group {
            if setDrafts[index].isCompleted {
                HStack(spacing: 10) {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.success)
                        .wgjSingleLineText(scale: 0.9)

                    Spacer(minLength: 8)

                    Button("Undo") {
                        setCompletion(false, at: index)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .disabled(setDrafts[index].isLocked)
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
                Button {
                    setCompletion(true, at: index)
                } label: {
                    Label(completionButtonTitle(for: index), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .wgjSingleLineText(scale: 0.82)
                }
                .buttonStyle(WGJCompactPrimaryButtonStyle())
                .disabled(setDrafts[index].isLocked)
            }
        }
    }

    private func completionButtonTitle(for index: Int) -> String {
        let restLabel = setDrafts[index].restSeconds > 0 ? " + Rest \(formattedRest(setDrafts[index].restSeconds))" : ""
        return "Complete Set\(restLabel)"
    }

    private func completeFocusedSet() {
        guard let index = focusedSetIndex else {
            dismissInputFocus()
            return
        }

        setCompletion(true, at: index, dismissingKeyboard: true)
    }

    private func toggleCompletion(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setCompletion(!setDrafts[index].isCompleted, at: index)
    }

    private func setCompletion(_ isCompleted: Bool, at index: Int, dismissingKeyboard: Bool = false) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        if dismissingKeyboard || focusedInput?.setID == setDrafts[index].id {
            dismissInputFocus()
        }

        guard setDrafts[index].isCompleted != isCompleted else { return }
        setDrafts[index].isCompleted = isCompleted
        let set = setDrafts[index]
        notifyChanged()
        onSetCompletionChange?(set.id, setTitle(for: index), set.restSeconds, set.isCompleted)
    }

    private func notifyChanged() {
        onSetDraftsChanged?(setDrafts)
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
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
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .fill(WGJTheme.field.opacity(isFocused ? 0.86 : 0.74))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(
                                isFocused ? WGJTheme.accentBlue.opacity(0.56) : WGJTheme.outline.opacity(0.84),
                                lineWidth: isFocused ? 1.4 : 1
                            )
                    }
                    .shadow(
                        color: isFocused ? WGJTheme.accentBlue.opacity(0.16) : WGJTheme.shadowSoft.opacity(0.9),
                        radius: isFocused ? 12 : 10,
                        x: 0,
                        y: isFocused ? 4 : 6
                    )
            }
    }
}
