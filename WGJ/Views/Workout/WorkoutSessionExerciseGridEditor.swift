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
    let personalRecordSummaryKinds: [WorkoutPersonalRecordKind]
    let personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]]
    let guidance: ActiveWorkoutExerciseGuidancePresentation?
    let preferredLoadUnit: TemplateLoadUnit

    @Binding var restSeconds: Int
    @Binding var setDrafts: [WorkoutSessionSetDraft]

    var showsInlineExerciseControls: Bool
    var showsSetProgressChip: Bool
    var manualCompletionMode: Bool
    var enablesHeaderSwipeDelete: Bool
    var emphasizesExerciseCompletion: Bool
    var onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)?
    var onRestChanged: ((Int) -> Void)?
    var onSetCompletionChange: ((UUID, String, Int, Bool) -> Void)?
    var onExerciseSettings: (() -> Void)?
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
    @State private var pendingDraftChangeNotificationTask: Task<Void, Never>?
    @FocusState private var focusedInput: SetInputFocus?

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
    private let inputChangeNotificationDebounce = Duration.milliseconds(180)

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
        personalRecordSummaryKinds: [WorkoutPersonalRecordKind] = [],
        personalRecordKindsBySetID: [UUID: [WorkoutPersonalRecordKind]] = [:],
        guidance: ActiveWorkoutExerciseGuidancePresentation? = nil,
        preferredLoadUnit: TemplateLoadUnit = .kg,
        restSeconds: Binding<Int>,
        setDrafts: Binding<[WorkoutSessionSetDraft]>,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        showsInlineExerciseControls: Bool = true,
        showsSetProgressChip: Bool = true,
        manualCompletionMode: Bool = false,
        enablesHeaderSwipeDelete: Bool = false,
        emphasizesExerciseCompletion: Bool = false,
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
        self.personalRecordSummaryKinds = personalRecordSummaryKinds
        self.personalRecordKindsBySetID = personalRecordKindsBySetID
        self.guidance = guidance
        self.preferredLoadUnit = preferredLoadUnit
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.externalIsExpanded = isExpanded
        self.showsInlineExerciseControls = showsInlineExerciseControls
        self.showsSetProgressChip = showsSetProgressChip
        self.manualCompletionMode = manualCompletionMode
        self.enablesHeaderSwipeDelete = enablesHeaderSwipeDelete
        self.emphasizesExerciseCompletion = emphasizesExerciseCompletion
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRestChanged = onRestChanged
        self.onSetCompletionChange = onSetCompletionChange
        self.onExerciseSettings = onExerciseSettings
        self.onExerciseDelete = onExerciseDelete
        self._localIsExpanded = State(initialValue: isExpanded?.wrappedValue ?? initiallyExpanded)
        let initialRows = Self.makeDisplayRows(
            setDrafts: setDrafts.wrappedValue,
            previousBySetIndex: previousBySetIndex,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds.wrappedValue,
            formatWeight: { WGJFormatters.decimalString($0) }
        )
        self._rowSnapshots = State(initialValue: initialRows)
        self._cachedCompletedSetCount = State(
            initialValue: initialRows.reduce(0) { partialResult, row in
                partialResult + (row.set.isCompleted ? 1 : 0)
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
                setsSection
            }
        }
        .padding(16)
        .background {
            if shouldEmphasizeCompletedExercise {
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .fill(completedExerciseCardFill)
            }
        }
        .wgjCardContainer(strong: true)
        .overlay {
            if isExerciseCompleted {
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .stroke(
                        WGJTheme.success.opacity(shouldEmphasizeCompletedExercise ? 0.60 : 0.34),
                        lineWidth: shouldEmphasizeCompletedExercise ? 2 : 1.2
                    )
            }
        }
        .shadow(
            color: shouldEmphasizeCompletedExercise ? WGJTheme.success.opacity(0.12) : .clear,
            radius: 16,
            x: 0,
            y: 8
        )
        .onAppear(perform: refreshDisplayRows)
        .onDisappear(perform: flushPendingDraftChangeNotification)
        .onChange(of: _setDrafts.wrappedValue) { _, _ in
            refreshDisplayRows()
            pruneInputDrafts()
        }
        .onChange(of: previousBySetIndex) { _, _ in
            refreshDisplayRows()
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
            guard previousFocus != newFocus else { return }
            if let previousFocus {
                flushPendingDraftChangeNotification()
                clearInputDraft(for: previousFocus)
            }
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

                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(shouldEmphasizeCompletedExercise ? WGJTheme.success : WGJTheme.accentBlue)
                    .wgjSingleLineText(scale: 0.8)

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)

                if shouldEmphasizeCompletedExercise {
                    completedExerciseBadge
                }

                if let guidance {
                    TrainingGuidanceBannerView(
                        title: guidance.title,
                        message: guidance.summary,
                        tone: guidance.tone,
                        compact: true
                    )
                }

                if !personalRecordSummaryKinds.isEmpty {
                    personalRecordChipGroup(personalRecordSummaryKinds)
                }

                headerSummaryChips
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                if onExerciseSettings != nil || onExerciseDelete != nil {
                    WGJActionMenuButton("Exercise Actions") {
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
                    isEnabled: !row.set.isLocked,
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
        }
    }

    private func setCard(_ row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let set = row.set
        let progressReference = row.progressReference
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

                    if !manualCompletionMode || progressReference == nil {
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

            if manualCompletionMode, let progressReference {
                progressReferenceStrip(progressReference, at: row.index)
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

    private func progressReferenceStrip(_ reference: WorkoutSetProgressReference, at index: Int) -> some View {
        let canApplyPrevious = reference.canReusePrevious && !setDrafts[index].isLocked
        let showsSecondaryRow = canApplyPrevious || reference.statusText != nil

        return VStack(alignment: .leading, spacing: 10) {
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
                }

                VStack(alignment: .leading, spacing: 10) {
                    progressReferenceMetric(
                        title: "Last",
                        value: reference.lastValue,
                        tint: WGJTheme.textPrimary
                    )

                    progressReferenceMetric(
                        title: "Aim",
                        value: reference.aimValue,
                        tint: WGJTheme.accentBlue
                    )
                }
            }

            if showsSecondaryRow {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        if let statusText = reference.statusText {
                            progressStatusChip(text: statusText, tone: reference.statusTone)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if canApplyPrevious {
                            applyPreviousButton(at: index)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        if let statusText = reference.statusText {
                            progressStatusChip(text: statusText, tone: reference.statusTone)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if canApplyPrevious {
                            applyPreviousButton(at: index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
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
        TextField("0", text: repsTextBinding(for: index))
            .keyboardType(.numberPad)
            .submitLabel(.done)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .focused($focusedInput, equals: inputFocus(for: index, metric: .reps))
            .multilineTextAlignment(.center)
            .disabled(setDrafts[index].isLocked)
            .accessibilityIdentifier("workout-set-\(index)-reps-field")
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
                .accessibilityIdentifier("workout-set-\(index)-weight-field")

            WGJActionMenuButton("Load Unit", titleVisibility: .hidden) {
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
        .disabled(set.isLocked)
    }

    private func setMenu(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked
        let currentRest = setDrafts[index].restSeconds

        return WGJActionMenuButton("Set Actions") {
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

            ForEach(restPresets, id: \.self) { value in
                Button("Set rest to \(Self.formattedRest(value))") {
                    updateSetRest(value, at: index)
                }
                .disabled(isLocked)
            }

            Button("Use exercise default (\(Self.formattedRest(restSeconds)))") {
                updateSetRest(restSeconds, at: index)
            }
            .disabled(isLocked)

            Button("Reduce rest by 15 sec") {
                updateSetRest(currentRest - 15, at: index)
            }
            .disabled(isLocked)

            Button("Increase rest by 15 sec") {
                updateSetRest(currentRest + 15, at: index)
            }
            .disabled(isLocked)

            Button("No rest") {
                updateSetRest(0, at: index)
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
                var didChange = false

                if setDrafts[index].actualReps != updatedReps {
                    setDrafts[index].actualReps = updatedReps
                    didChange = true
                }

                if !manualCompletionMode {
                    let isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                    if setDrafts[index].isCompleted != isCompleted {
                        setDrafts[index].isCompleted = isCompleted
                        didChange = true
                    }
                }

                if didChange {
                    scheduleDraftChangeNotification()
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
                var didChange = false

                if normalized.isEmpty {
                    updatedWeight = nil
                } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
                    updatedWeight = max(0, parsed)
                } else {
                    updatedWeight = setDrafts[index].actualWeight
                }

                if setDrafts[index].actualWeight != updatedWeight {
                    setDrafts[index].actualWeight = updatedWeight
                    didChange = true
                }

                if !manualCompletionMode {
                    let isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                    if setDrafts[index].isCompleted != isCompleted {
                        setDrafts[index].isCompleted = isCompleted
                        didChange = true
                    }
                }

                if didChange {
                    scheduleDraftChangeNotification()
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
        setDrafts[index].isCompleted = false
        notifyChanged()
        if set.isCompleted {
            onSetCompletionChange?(set.id, setTitle(for: index), set.restSeconds, false)
        }
    }

    private func refreshDisplayRows() {
        let snapshot = Self.makeDisplayRows(
            setDrafts: _setDrafts.wrappedValue,
            previousBySetIndex: previousBySetIndex,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            formatWeight: formatWeight
        )
        rowSnapshots = snapshot
        cachedCompletedSetCount = snapshot.reduce(0) { partialResult, row in
            partialResult + (row.set.isCompleted ? 1 : 0)
        }
    }

    private static func makeDisplayRows(
        setDrafts: [WorkoutSessionSetDraft],
        previousBySetIndex: [Int: WorkoutPreviousSetSnapshot],
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
                    previousSummary: previousSummaryText(for: previousBySetIndex[index], formatWeight: formatWeight),
                    metadataLine: metadataLine(for: draft, restSeconds: restSeconds),
                    targetWeightText: targetWeightText(for: draft, formatWeight: formatWeight),
                    targetRepsText: targetRepsText(for: draft),
                    progressReference: WorkoutSetProgressReference.make(
                        draft: draft,
                        previous: previousBySetIndex[index],
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
        for snapshot: WorkoutPreviousSetSnapshot?,
        formatWeight: (Double) -> String
    ) -> String {
        guard let snapshot else {
            return "No previous log for this slot."
        }

        let previousText: String
        if let weight = snapshot.weight, let reps = snapshot.reps {
            previousText = "\(formatWeight(weight)) \(snapshot.unit.shortLabel) x \(reps)"
        } else if let reps = snapshot.reps {
            previousText = "\(reps) reps"
        } else {
            return "No previous log for this slot."
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

        onRestChanged?(normalized)
        notifyChanged()
    }

    private func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : Self.formattedRest(seconds)
    }

    private func completionRow(for row: WorkoutSessionExerciseSetRowDisplaySnapshot) -> some View {
        let index = row.index
        let set = row.set

        return Group {
            if set.isCompleted {
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
                    .disabled(set.isLocked)
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
                    Label(row.completionButtonTitle, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .wgjSingleLineText(scale: 0.82)
                }
                .buttonStyle(WGJCompactPrimaryButtonStyle())
                .disabled(set.isLocked)
            }
        }
    }

    private func toggleCompletion(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setCompletion(!setDrafts[index].isCompleted, at: index)
    }

    private func setCompletion(_ isCompleted: Bool, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isLocked else { return }
        if focusedInput?.setID == setDrafts[index].id {
            dismissInputFocus()
        }

        guard setDrafts[index].isCompleted != isCompleted else { return }
        let setID = setDrafts[index].id
        let setTitle = setTitle(for: index)
        let setRestSeconds = setDrafts[index].restSeconds
        setDrafts[index].isCompleted = isCompleted
        notifyChanged()
        onSetCompletionChange?(setID, setTitle, setRestSeconds, isCompleted)
    }

    private func notifyChanged() {
        pendingDraftChangeNotificationTask?.cancel()
        pendingDraftChangeNotificationTask = nil
        onSetDraftsChanged?(setDrafts)
    }

    private func scheduleDraftChangeNotification() {
        pendingDraftChangeNotificationTask?.cancel()
        pendingDraftChangeNotificationTask = Task { @MainActor in
            try? await Task.sleep(for: inputChangeNotificationDebounce)
            guard !Task.isCancelled else { return }
            pendingDraftChangeNotificationTask = nil
            onSetDraftsChanged?(setDrafts)
        }
    }

    private func flushPendingDraftChangeNotification() {
        guard pendingDraftChangeNotificationTask != nil else { return }
        pendingDraftChangeNotificationTask?.cancel()
        pendingDraftChangeNotificationTask = nil
        onSetDraftsChanged?(setDrafts)
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

    private func clearInputDraft(for focus: SetInputFocus) {
        switch focus.metric {
        case .weight:
            weightInputTextBySetID[focus.setID] = nil
        case .reps:
            repsInputTextBySetID[focus.setID] = nil
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
    let progressReference: WorkoutSetProgressReference?
    let completionButtonTitle: String
}
