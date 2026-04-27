import Foundation
import SwiftUI

nonisolated struct TemplateEditorKeyboardDismissToken: Equatable, Sendable {
    private(set) var value: Int = 0

    mutating func requestDismiss() {
        value &+= 1
    }
}

private enum TemplateEditorInputMetric: Hashable {
    case weight
    case reps
}

private enum TemplateEditorInputFocus: Hashable {
    case repMin
    case repMax
    case set(setID: UUID, metric: TemplateEditorInputMetric)
}

@MainActor
private final class TemplateExerciseInputDraftStore {
    private var repMinText: String?
    private var repMaxText: String?
    private var repsTextBySetID: [UUID: String] = [:]
    private var weightTextBySetID: [UUID: String] = [:]

    func text(for focus: TemplateEditorInputFocus) -> String? {
        switch focus {
        case .repMin:
            return repMinText
        case .repMax:
            return repMaxText
        case let .set(setID, metric):
            switch metric {
            case .reps:
                return repsTextBySetID[setID]
            case .weight:
                return weightTextBySetID[setID]
            }
        }
    }

    func stage(_ text: String, for focus: TemplateEditorInputFocus) {
        switch focus {
        case .repMin:
            repMinText = text
        case .repMax:
            repMaxText = text
        case let .set(setID, metric):
            switch metric {
            case .reps:
                repsTextBySetID[setID] = text
            case .weight:
                weightTextBySetID[setID] = text
            }
        }
    }

    func clear(for focus: TemplateEditorInputFocus) {
        switch focus {
        case .repMin:
            repMinText = nil
        case .repMax:
            repMaxText = nil
        case let .set(setID, metric):
            switch metric {
            case .reps:
                repsTextBySetID[setID] = nil
            case .weight:
                weightTextBySetID[setID] = nil
            }
        }
    }

    func prune(keeping validSetIDs: Set<UUID>) {
        repsTextBySetID = repsTextBySetID.filter { validSetIDs.contains($0.key) }
        weightTextBySetID = weightTextBySetID.filter { validSetIDs.contains($0.key) }
    }
}

struct TemplateExercisePrescriptionEditor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseAccessibilityIdentifier: String?
    let infoDestination: AnyView?
    let exerciseIndexTitle: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let recommendation: TemplateExerciseRecommendation?
    let structureSummaries: [String]
    let preferredLoadUnit: TemplateLoadUnit
    let supplementaryContent: AnyView?
    let keyboardDismissToken: TemplateEditorKeyboardDismissToken

    @Binding var targetRepMin: Int?
    @Binding var targetRepMax: Int?
    @Binding var restSeconds: Int
    @Binding var setDrafts: [TemplateExerciseSetDraft]

    var onCommitRequest: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onMoveToPosition: (() -> Void)?
    var onExerciseDelete: (() -> Void)?

    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]
    @State private var inputDraftStore = TemplateExerciseInputDraftStore()
    @FocusState private var focusedInput: TemplateEditorInputFocus?

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]
    private let shouldCommitOnDisappear: (() -> Bool)?

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        exerciseAccessibilityIdentifier: String? = nil,
        infoDestination: AnyView? = nil,
        recommendation: TemplateExerciseRecommendation? = nil,
        structureSummaries: [String] = [],
        supplementaryContent: AnyView? = nil,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        exerciseIndexTitle: String? = nil,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false,
        preferredLoadUnit: TemplateLoadUnit = .kg,
        keyboardDismissToken: TemplateEditorKeyboardDismissToken = TemplateEditorKeyboardDismissToken(),
        targetRepMin: Binding<Int?>,
        targetRepMax: Binding<Int?>,
        restSeconds: Binding<Int>,
        setDrafts: Binding<[TemplateExerciseSetDraft]>,
        onCommitRequest: (() -> Void)? = nil,
        shouldCommitOnDisappear: (() -> Bool)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onMoveToPosition: (() -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.exerciseAccessibilityIdentifier = exerciseAccessibilityIdentifier
        self.infoDestination = infoDestination
        self.recommendation = recommendation
        self.structureSummaries = structureSummaries
        self.supplementaryContent = supplementaryContent
        self.exerciseIndexTitle = exerciseIndexTitle
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.preferredLoadUnit = preferredLoadUnit
        self.keyboardDismissToken = keyboardDismissToken
        self._targetRepMin = targetRepMin
        self._targetRepMax = targetRepMax
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.externalIsExpanded = isExpanded
        self.onCommitRequest = onCommitRequest
        self.shouldCommitOnDisappear = shouldCommitOnDisappear
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onMoveToPosition = onMoveToPosition
        self.onExerciseDelete = onExerciseDelete
        self._localIsExpanded = State(initialValue: isExpanded?.wrappedValue ?? initiallyExpanded)
    }

    var body: some View {
        let summaryPresentation = collapsedSetPresentation

        return VStack(alignment: .leading, spacing: 14) {
            header(summary: summaryPresentation.summary)

            if isExpanded {
                if let recommendation {
                    TrainingGuidanceBannerView(
                        title: recommendation.title,
                        message: recommendation.summary,
                        tone: recommendation.tone
                    )
                }

                controlsSection

                if let supplementaryContent {
                    supplementaryContent
                }

                if let recommendation {
                    setupTipsSection(recommendation: recommendation)
                }

                setsSection
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
        .onDisappear {
            if let focusedInput {
                commitInputDraft(for: focusedInput)
                clearInputDraft(for: focusedInput)
            }
            if shouldCommitOnDisappear?() ?? true {
                onCommitRequest?()
            }
        }
        .onChange(of: _setDrafts.wrappedValue) { _, _ in
            pruneInputDrafts()
        }
        .onChange(of: focusedInput) { previousFocus, newFocus in
            guard previousFocus != newFocus else { return }
            if let previousFocus {
                commitInputDraft(for: previousFocus)
                clearInputDraft(for: previousFocus)
                onCommitRequest?()
            }
        }
        .onChange(of: keyboardDismissToken) { _, _ in
            dismissFocusedInput()
        }
    }

    private func dismissFocusedInput() {
        guard let focusedInput else { return }
        commitInputDraft(for: focusedInput)
        clearInputDraft(for: focusedInput)
        self.focusedInput = nil
        onCommitRequest?()
    }

    private func header(summary: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let exerciseIndexTitle {
                    Text(exerciseIndexTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentCyan)
                }

                titleView

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(2)

                headerSummaryChips(summary: summary)
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                if hasHeaderMenu {
                    headerMenu
                }

                Button {
                    toggleExpanded()
                } label: {
                    headerIcon(symbol: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    exerciseAccessibilityIdentifier.map { "\($0)-expand-button" }
                        ?? "template-editor-exercise-expand-button"
                )
            }
        }
    }

    private var titleView: some View {
        Group {
            if let infoDestination {
                NavigationLink {
                    infoDestination
                } label: {
                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .wgjSingleLineText(scale: 0.8)
                        .accessibilityIdentifier(exerciseAccessibilityIdentifier ?? "")
                }
                .buttonStyle(.plain)
            } else {
                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .wgjSingleLineText(scale: 0.8)
                    .accessibilityIdentifier(exerciseAccessibilityIdentifier ?? "")
            }
        }
    }

    private var controlsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                repRangeControl
                restControl
            }

            VStack(alignment: .leading, spacing: 10) {
                repRangeControl
                restControl
            }
        }
    }

    private func setupTipsSection(recommendation: TemplateExerciseRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup Tips")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    setupTipCard(
                        title: "Rep Range",
                        value: recommendedRepRangeText(recommendation),
                        detail: repRangeTipDetail(recommendation),
                        tint: WGJTheme.accentGold
                    )

                    setupTipCard(
                        title: "Rest",
                        value: recommendedRestRangeText(recommendation),
                        detail: restTipDetail(recommendation),
                        tint: WGJTheme.accentBlue
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    setupTipCard(
                        title: "Rep Range",
                        value: recommendedRepRangeText(recommendation),
                        detail: repRangeTipDetail(recommendation),
                        tint: WGJTheme.accentGold
                    )

                    setupTipCard(
                        title: "Rest",
                        value: recommendedRestRangeText(recommendation),
                        detail: restTipDetail(recommendation),
                        tint: WGJTheme.accentBlue
                    )
                }
            }

            setupTipCard(
                title: "Set Structure",
                value: recommendedSetStructureText(recommendation),
                detail: setStructureTipDetail(recommendation),
                tint: WGJTheme.accentCyan
            )
        }
    }

    private func setupTipCard(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var repRangeControl: some View {
        compactControlCard(
            title: "Rep Range",
            subtitle: "Default target for each working set.",
            tint: WGJTheme.accentGold
        ) {
            HStack(spacing: 10) {
                TextField("Min", text: repMinTextBinding)
                    .keyboardType(.numberPad)
                    .focused($focusedInput, equals: .repMin)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(
                        exerciseAccessibilityIdentifier.map { "\($0)-rep-min-field" }
                            ?? "template-editor-rep-min-field"
                    )

                Text("to")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentGold)

                TextField("Max", text: repMaxTextBinding)
                    .keyboardType(.numberPad)
                    .focused($focusedInput, equals: .repMax)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(
                        exerciseAccessibilityIdentifier.map { "\($0)-rep-max-field" }
                            ?? "template-editor-rep-max-field"
                    )
            }
        }
    }

    private var restControl: some View {
        compactControlCard(
            title: "Default Rest",
            subtitle: "Applies to every planned set unless you override it.",
            tint: WGJTheme.accentBlue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                WGJActionMenuButton("Default Rest") {
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
        let presentation = currentSetPresentation

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set Plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer()

                Text("\(presentation.rows.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            Text(presentation.summary)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)

            if presentation.rows.isEmpty {
                Text("No sets yet.")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .padding(.vertical, 6)
            }

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(presentation.rows) { row in
                    SwipeDeleteRow(
                        offset: setSwipeOffsetBinding(for: row.id),
                        isRemoving: setRemovingBinding(for: row.id)
                    ) {
                        removeSet(withID: row.id)
                    } content: {
                        TemplateExerciseSetCardView(
                            row: row,
                            canMoveDown: row.index < presentation.rows.count - 1,
                            focusedInput: $focusedInput,
                            repsText: repsText(for: row.index),
                            weightText: weightText(for: row.index),
                            onRepsTextChanged: { updateRepsText($0, forSetID: row.id) },
                            onWeightTextChanged: { updateWeightText($0, forSetID: row.id) },
                            onLoadUnitChanged: { updateLoadUnit($0, forSetID: row.id) },
                            onToggleWarmup: { toggleWarmup(setID: row.id) },
                            onInsertBelow: { insertSet(afterSetID: row.id) },
                            onMoveUp: { moveSetUp(setID: row.id) },
                            onMoveDown: { moveSetDown(setID: row.id) },
                            onAddDropStage: { addDropStage(toSetID: row.id) },
                            onRemoveDropStage: { stageID in
                                removeDropStage(stageID, fromSetID: row.id)
                            },
                            onClearDropStages: { clearDropStages(fromSetID: row.id) },
                            onDropStageRepsChanged: { stageID, value in
                                updateDropStageRepsText(value, stageID: stageID, setID: row.id)
                            },
                            onDropStageWeightChanged: { stageID, value in
                                updateDropStageWeightText(value, stageID: stageID, setID: row.id)
                            },
                            onDropStageLoadUnitChanged: { stageID, unit in
                                updateDropStageLoadUnit(unit, stageID: stageID, setID: row.id)
                            },
                            onToggleLock: { toggleLock(setID: row.id) },
                            onDelete: { removeSet(withID: row.id) }
                        )
                        .equatable()
                        .fixedSize(horizontal: false, vertical: true)
                    }
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

    private func metricField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func repsText(for index: Int) -> String {
        guard setDrafts.indices.contains(index) else {
            return ""
        }
        let setID = setDrafts[index].id
        if isInputFocused(.reps, at: index),
           let draft = inputDraftStore.text(for: .set(setID: setID, metric: .reps)) {
            return draft
        }
        guard let reps = setDrafts[index].targetReps else { return "" }
        return "\(reps)"
    }

    private func weightText(for index: Int) -> String {
        guard setDrafts.indices.contains(index) else {
            return ""
        }
        let setID = setDrafts[index].id
        if isInputFocused(.weight, at: index),
           let draft = inputDraftStore.text(for: .set(setID: setID, metric: .weight)) {
            return draft
        }
        guard let weight = setDrafts[index].targetWeight else { return "" }
        return formatWeight(weight)
    }

    private var headerMenu: some View {
        WGJActionMenuButton("Exercise Actions") {
            if let onMoveUp {
                Button {
                    onMoveUp()
                } label: {
                    Label("Move exercise up", systemImage: "arrow.up")
                }
                .disabled(!canMoveUp)
            }

            if let onMoveDown {
                Button {
                    onMoveDown()
                } label: {
                    Label("Move exercise down", systemImage: "arrow.down")
                }
                .disabled(!canMoveDown)
            }

            if let onMoveToPosition {
                Button {
                    onMoveToPosition()
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
                ?? "template-editor-exercise-actions-button"
        )
    }

    private var hasHeaderMenu: Bool {
        onMoveUp != nil || onMoveDown != nil || onMoveToPosition != nil || onExerciseDelete != nil
    }

    private func headerSummaryChips(summary: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(summary, tint: WGJTheme.accentBlue)
                ForEach(structureSummaries, id: \.self) { structureSummary in
                    infoChip(structureSummary, tint: structureTint(for: structureSummary))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(summary, tint: WGJTheme.accentBlue)
                ForEach(structureSummaries, id: \.self) { structureSummary in
                    infoChip(structureSummary, tint: structureTint(for: structureSummary))
                }
            }
        }
    }

    private func structureTint(for summary: String) -> Color {
        summary.localizedCaseInsensitiveContains("drop") ? WGJTheme.accentCyan : WGJTheme.accentBlue
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

    private var summaryLine: String {
        if !muscleSummary.isEmpty {
            return muscleSummary
        }

        if !category.isEmpty {
            return category
        }

        return "Plan weight, reps, and rest for each set."
    }

    private var isExpanded: Bool {
        expansionBinding.wrappedValue
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $localIsExpanded
    }

    private func inputFocus(for index: Int, metric: TemplateEditorInputMetric) -> TemplateEditorInputFocus {
        .set(setID: setDrafts[index].id, metric: metric)
    }

    private func isInputFocused(_ metric: TemplateEditorInputMetric, at index: Int) -> Bool {
        guard setDrafts.indices.contains(index) else { return false }
        return focusedInput == inputFocus(for: index, metric: metric)
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
            return "No rep range"
        }
    }

    private func recommendedRepRangeText(_ recommendation: TemplateExerciseRecommendation) -> String {
        formattedRepRange(recommendation.suggestedRepRange) + " reps"
    }

    private func recommendedRestRangeText(_ recommendation: TemplateExerciseRecommendation) -> String {
        formattedRestRange(recommendation.suggestedRestSeconds)
    }

    private func recommendedSetStructureText(_ recommendation: TemplateExerciseRecommendation) -> String {
        let warmups = formattedCountRange(recommendation.suggestedWarmupSets, singular: "warmup", plural: "warmups")
        let workingSets = formattedCountRange(recommendation.suggestedWorkingSets, singular: "working set", plural: "working sets")
        return "\(warmups) · \(workingSets)"
    }

    private func repRangeTipDetail(_ recommendation: TemplateExerciseRecommendation) -> String {
        switch (targetRepMin, targetRepMax) {
        case let (min?, max?) where min >= recommendation.suggestedRepRange.lowerBound && max <= recommendation.suggestedRepRange.upperBound:
            return "Current target \(repRangeSummary) sits inside the usual sweet spot for this lift."
        case let (min?, max?):
            let current = min == max ? "\(min) reps" : "\(min)-\(max) reps"
            return "Current target is \(current). A cleaner starting window here is \(recommendedRepRangeText(recommendation))."
        case let (min?, nil):
            return "Current target is \(min)+ reps. A cleaner starting window here is \(recommendedRepRangeText(recommendation))."
        case let (nil, max?):
            return "Current target tops out at \(max). A cleaner starting window here is \(recommendedRepRangeText(recommendation))."
        case (nil, nil):
            return "Start here if you want the working sets and overload targets to track cleanly."
        }
    }

    private func restTipDetail(_ recommendation: TemplateExerciseRecommendation) -> String {
        let currentRestText = restLabel(for: restSeconds)
        let recommendedText = recommendedRestRangeText(recommendation)

        if recommendation.suggestedRestSeconds.contains(restSeconds) {
            return "Current default rest \(currentRestText) sits inside the suggested window."
        }

        return "Current default rest is \(currentRestText). Suggested window here is \(recommendedText)."
    }

    private func setStructureTipDetail(_ recommendation: TemplateExerciseRecommendation) -> String {
        let warmupCount = setDrafts.filter(\.isWarmup).count
        let workingCount = max(0, setDrafts.count - warmupCount)
        let currentPlan = "\(warmupCount) warmup\(warmupCount == 1 ? "" : "s") · \(workingCount) working"

        let warmupsOkay = recommendation.suggestedWarmupSets.contains(warmupCount)
        let workingOkay = recommendation.suggestedWorkingSets.contains(workingCount)
        if warmupsOkay && workingOkay {
            return "Current plan \(currentPlan) already lines up well with the usual setup for this lift."
        }

        return "Current plan is \(currentPlan). Use the warmup and working-set mix above as the default starting structure."
    }

    private func formattedRepRange(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)-\(range.upperBound)"
    }

    private func formattedRestRange(_ range: ClosedRange<Int>) -> String {
        "\(restLabel(for: range.lowerBound))-\(restLabel(for: range.upperBound))"
    }

    private func formattedCountRange(
        _ range: ClosedRange<Int>,
        singular: String,
        plural: String
    ) -> String {
        if range.lowerBound == range.upperBound {
            let count = range.lowerBound
            let label = count == 1 ? singular : plural
            return "\(count) \(label)"
        }

        return "\(range.lowerBound)-\(range.upperBound) \(plural)"
    }

    private func toggleExpanded() {
        withAnimation(WGJMotion.disclosureAnimation(reduceMotion: reduceMotion)) {
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
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var repMinTextBinding: Binding<String> {
        Binding(
            get: {
                if focusedInput == .repMin {
                    return inputDraftStore.text(for: .repMin) ?? targetRepMin.map(String.init) ?? ""
                }
                guard let targetRepMin else { return "" }
                return "\(targetRepMin)"
            },
            set: { newValue in
                inputDraftStore.stage(newValue, for: .repMin)
                let updatedValue = parsedOptionalInt(from: newValue)
                if targetRepMin != updatedValue {
                    targetRepMin = updatedValue
                }
            }
        )
    }

    private var repMaxTextBinding: Binding<String> {
        Binding(
            get: {
                if focusedInput == .repMax {
                    return inputDraftStore.text(for: .repMax) ?? targetRepMax.map(String.init) ?? ""
                }
                guard let targetRepMax else { return "" }
                return "\(targetRepMax)"
            },
            set: { newValue in
                inputDraftStore.stage(newValue, for: .repMax)
                let updatedValue = parsedOptionalInt(from: newValue)
                if targetRepMax != updatedValue {
                    targetRepMax = updatedValue
                }
            }
        )
    }

    private func parsedOptionalInt(from text: String) -> Int? {
        let cleaned = text.filter(\.isNumber)
        return cleaned.isEmpty ? nil : Int(cleaned)
    }

    private func updateRepsText(_ newValue: String, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let setID = setDrafts[index].id
        inputDraftStore.stage(newValue, for: .set(setID: setID, metric: .reps))
    }

    private func updateRepsText(_ newValue: String, forSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateRepsText(newValue, at: index)
    }

    private func updateWeightText(_ newValue: String, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let setID = setDrafts[index].id
        inputDraftStore.stage(newValue, for: .set(setID: setID, metric: .weight))
    }

    private func updateWeightText(_ newValue: String, forSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateWeightText(newValue, at: index)
    }

    private func updateLoadUnit(_ loadUnit: TemplateLoadUnit, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard setDrafts[index].loadUnit != loadUnit else { return }
        setDrafts[index].loadUnit = loadUnit
        requestImmediateCommit()
    }

    private func updateLoadUnit(_ loadUnit: TemplateLoadUnit, forSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateLoadUnit(loadUnit, at: index)
    }

    private func addSet() {
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            setDrafts.append(makeSetDraft(copying: setDrafts.last))
        }
        requestImmediateCommit()
    }

    private func insertSet(after index: Int) {
        guard setDrafts.indices.contains(index) else { return }

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            setDrafts.insert(makeSetDraft(copying: setDrafts[index]), at: index + 1)
        }
        requestImmediateCommit()
    }

    private func insertSet(afterSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        insertSet(after: index)
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let removedID = setDrafts[index].id

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            _ = setDrafts.remove(at: index)
        }

        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        requestImmediateCommit()
    }

    private func removeSet(withID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        removeSet(at: index)
    }

    private func toggleWarmup(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isWarmup.toggle()
        requestImmediateCommit()
    }

    private func toggleWarmup(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        toggleWarmup(at: index)
    }

    private func toggleLock(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isLocked.toggle()
        requestImmediateCommit()
    }

    private func toggleLock(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        toggleLock(at: index)
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            setDrafts.swapAt(index, index - 1)
        }
        requestImmediateCommit()
    }

    private func moveSetUp(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        moveSetUp(index)
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            setDrafts.swapAt(index, index + 1)
        }
        requestImmediateCommit()
    }

    private func moveSetDown(setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        moveSetDown(index)
    }

    private func makeSetDraft(copying source: TemplateExerciseSetDraft?) -> TemplateExerciseSetDraft {
        let fallbackLoadUnit = source?.loadUnit ?? preferredLoadUnit
        return TemplateExerciseSetDraft(
            targetReps: source?.targetReps,
            targetWeight: source?.targetWeight,
            loadUnit: fallbackLoadUnit,
            restSeconds: restSeconds,
            isWarmup: source?.isWarmup ?? false,
            isLocked: false,
            previousTargetReps: source?.previousTargetReps,
            previousTargetWeight: source?.previousTargetWeight,
            previousLoadUnit: source?.previousLoadUnit ?? fallbackLoadUnit
        )
    }

    private func addDropStage(to index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard !setDrafts[index].isWarmup else { return }
        let sourceStage = setDrafts[index].dropStages.last
        let sourceReps = sourceStage?.targetReps ?? setDrafts[index].targetReps
        let sourceWeight = sourceStage?.targetWeight ?? setDrafts[index].targetWeight
        let sourceLoadUnit = sourceStage?.loadUnit ?? setDrafts[index].loadUnit
        setDrafts[index].dropStages.append(
            TemplateExerciseDropStageDraft(
                targetReps: sourceReps,
                targetWeight: sourceWeight,
                loadUnit: sourceLoadUnit
            )
        )
        requestImmediateCommit()
    }

    private func addDropStage(toSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        addDropStage(to: index)
    }

    private func removeDropStage(_ stageID: UUID, from setIndex: Int) {
        guard setDrafts.indices.contains(setIndex) else { return }
        setDrafts[setIndex].dropStages.removeAll { $0.id == stageID }
        requestImmediateCommit()
    }

    private func removeDropStage(_ stageID: UUID, fromSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        removeDropStage(stageID, from: index)
    }

    private func clearDropStages(from index: Int) {
        guard setDrafts.indices.contains(index), !setDrafts[index].dropStages.isEmpty else { return }
        setDrafts[index].dropStages = []
        requestImmediateCommit()
    }

    private func clearDropStages(fromSetID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        clearDropStages(from: index)
    }

    private func updateDropStageRepsText(_ newValue: String, stageID: UUID, setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }
        let cleaned = newValue.filter(\.isNumber)
        let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
        guard setDrafts[setIndex].dropStages[stageIndex].targetReps != updatedValue else { return }
        setDrafts[setIndex].dropStages[stageIndex].targetReps = updatedValue
        requestImmediateCommit()
    }

    private func updateDropStageRepsText(_ newValue: String, stageID: UUID, setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateDropStageRepsText(newValue, stageID: stageID, setIndex: index)
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
            updatedValue = setDrafts[setIndex].dropStages[stageIndex].targetWeight
        }

        guard setDrafts[setIndex].dropStages[stageIndex].targetWeight != updatedValue else { return }
        setDrafts[setIndex].dropStages[stageIndex].targetWeight = updatedValue
        requestImmediateCommit()
    }

    private func updateDropStageWeightText(_ newValue: String, stageID: UUID, setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateDropStageWeightText(newValue, stageID: stageID, setIndex: index)
    }

    private func updateDropStageLoadUnit(_ loadUnit: TemplateLoadUnit, stageID: UUID, setIndex: Int) {
        guard setDrafts.indices.contains(setIndex),
              let stageIndex = setDrafts[setIndex].dropStages.firstIndex(where: { $0.id == stageID }) else {
            return
        }
        guard setDrafts[setIndex].dropStages[stageIndex].loadUnit != loadUnit else { return }
        setDrafts[setIndex].dropStages[stageIndex].loadUnit = loadUnit
        requestImmediateCommit()
    }

    private func updateDropStageLoadUnit(_ loadUnit: TemplateLoadUnit, stageID: UUID, setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateDropStageLoadUnit(loadUnit, stageID: stageID, setIndex: index)
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func updateRest(_ seconds: Int) {
        let normalized = max(0, min(3600, seconds))
        let didChangeDefaultRest = restSeconds != normalized
        let didChangeSetRest = setDrafts.contains(where: { $0.restSeconds != normalized })
        guard didChangeDefaultRest || didChangeSetRest else { return }

        if didChangeDefaultRest {
            restSeconds = normalized
        }

        if didChangeSetRest {
            for index in setDrafts.indices where setDrafts[index].restSeconds != normalized {
                setDrafts[index].restSeconds = normalized
            }
        }
        requestImmediateCommit()
    }

    private func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : formattedRest(seconds)
    }

    private func requestImmediateCommit() {
        if let focusedInput {
            commitInputDraft(for: focusedInput)
        }
        normalizeSetRestToDefault()
        onCommitRequest?()
    }

    private func normalizeSetRestToDefault() {
        let normalized = max(0, min(3600, restSeconds))
        for index in setDrafts.indices where setDrafts[index].restSeconds != normalized {
            setDrafts[index].restSeconds = normalized
        }
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
    }

    private func pruneInputDrafts() {
        let validSetIDs = Set(setDrafts.map(\.id))
        inputDraftStore.prune(keeping: validSetIDs)

        if case let .set(setID, _)? = focusedInput, !validSetIDs.contains(setID) {
            focusedInput = nil
        }
    }

    private func commitInputDraft(for focus: TemplateEditorInputFocus) {
        guard let text = inputDraftStore.text(for: focus) else { return }

        switch focus {
        case .repMin:
            let cleaned = text.filter(\.isNumber)
            let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
            guard targetRepMin != updatedValue else { return }
            targetRepMin = updatedValue
        case .repMax:
            let cleaned = text.filter(\.isNumber)
            let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
            guard targetRepMax != updatedValue else { return }
            targetRepMax = updatedValue
        case let .set(setID, metric):
            guard let index = indexForSetID(setID) else { return }
            switch metric {
            case .reps:
                let cleaned = text.filter(\.isNumber)
                let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
                guard setDrafts[index].targetReps != updatedValue else { return }
                setDrafts[index].targetReps = updatedValue
            case .weight:
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedValue: Double?
                if normalized.isEmpty {
                    updatedValue = nil
                } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
                    updatedValue = max(0, parsed)
                } else {
                    updatedValue = setDrafts[index].targetWeight
                }
                guard setDrafts[index].targetWeight != updatedValue else { return }
                setDrafts[index].targetWeight = updatedValue
            }
        }
    }

    private func clearInputDraft(for focus: TemplateEditorInputFocus) {
        inputDraftStore.clear(for: focus)
    }

    private func indexForSetID(_ setID: UUID) -> Int? {
        setDrafts.firstIndex(where: { $0.id == setID })
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
}

private extension TemplateExercisePrescriptionEditor {
    var collapsedSetPresentation: TemplateExerciseCollapsedSetPresentation {
        Self.makeCollapsedSetPresentation(setDrafts: setDrafts)
    }

    var currentSetPresentation: SetPresentation {
        WGJPerformance.measure("template-editor.set-presentation") {
            Self.makeSetPresentation(
                setDrafts: setDrafts,
                formatWeight: formatWeight
            )
        }
    }

    static func makeCollapsedSetPresentation(
        setDrafts: [TemplateExerciseSetDraft]
    ) -> TemplateExerciseCollapsedSetPresentation {
        let warmupCount = setDrafts.filter(\.isWarmup).count
        let workingSetCount = max(0, setDrafts.count - warmupCount)
        let summary = warmupCount > 0
            ? "\(workingSetCount) working • \(warmupCount) warmup"
            : "\(workingSetCount) working sets"

        return TemplateExerciseCollapsedSetPresentation(
            totalSetCount: setDrafts.count,
            warmupCount: warmupCount,
            workingSetCount: workingSetCount,
            summary: summary
        )
    }

    static func makeSetPresentation(
        setDrafts: [TemplateExerciseSetDraft],
        formatWeight: (Double) -> String
    ) -> SetPresentation {
        var rows: [SetRowData] = []
        rows.reserveCapacity(setDrafts.count)

        var workingSetNumber = 0
        var warmupCount = 0

        for (index, set) in setDrafts.enumerated() {
            if set.isWarmup {
                warmupCount += 1
            } else {
                workingSetNumber += 1
            }

            rows.append(
                SetRowData(
                    id: set.id,
                    index: index,
                    set: set,
                    title: set.isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber)",
                    badgeTitle: set.isWarmup ? "W" : "\(workingSetNumber)",
                    previousSummary: previousSummary(for: set, formatWeight: formatWeight),
                    metadataLine: setMetadataLine(for: set),
                    isLocked: set.isLocked
                )
            )
        }

        let collapsed = makeCollapsedSetPresentation(setDrafts: setDrafts)

        return SetPresentation(rows: rows, summary: collapsed.summary)
    }

    static func previousSummary(
        for set: TemplateExerciseSetDraft,
        formatWeight: (Double) -> String
    ) -> String {
        let previous = previousText(for: set, formatWeight: formatWeight)
        return previous == "-" ? "No previous target saved." : "Last target \(previous)"
    }

    static func previousText(
        for set: TemplateExerciseSetDraft,
        formatWeight: (Double) -> String
    ) -> String {
        if let weight = set.previousTargetWeight, let reps = set.previousTargetReps {
            return "\(formatWeight(weight)) \(set.previousLoadUnit.shortLabel) x \(reps)"
        }

        if let reps = set.previousTargetReps {
            return "\(reps) reps"
        }

        return "-"
    }

    static func setMetadataLine(for set: TemplateExerciseSetDraft) -> String? {
        var parts: [String] = []

        if set.isLocked {
            parts.append("Locked")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }
}

private struct TemplateExerciseCollapsedSetPresentation: Equatable {
    let totalSetCount: Int
    let warmupCount: Int
    let workingSetCount: Int
    let summary: String
}

private struct SetPresentation: Equatable {
    let rows: [SetRowData]
    let summary: String
}

private struct SetRowData: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let set: TemplateExerciseSetDraft
    let title: String
    let badgeTitle: String
    let previousSummary: String
    let metadataLine: String?
    let isLocked: Bool
}

private struct TemplateExerciseSetCardView: View, Equatable {
    let row: SetRowData
    let canMoveDown: Bool
    let focusedInput: FocusState<TemplateEditorInputFocus?>.Binding
    let repsText: String
    let weightText: String

    let onRepsTextChanged: (String) -> Void
    let onWeightTextChanged: (String) -> Void
    let onLoadUnitChanged: (TemplateLoadUnit) -> Void
    let onToggleWarmup: () -> Void
    let onInsertBelow: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAddDropStage: () -> Void
    let onRemoveDropStage: (UUID) -> Void
    let onClearDropStages: () -> Void
    let onDropStageRepsChanged: (UUID, String) -> Void
    let onDropStageWeightChanged: (UUID, String) -> Void
    let onDropStageLoadUnitChanged: (UUID, TemplateLoadUnit) -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void

    static func == (lhs: TemplateExerciseSetCardView, rhs: TemplateExerciseSetCardView) -> Bool {
        lhs.row == rhs.row
            && lhs.canMoveDown == rhs.canMoveDown
            && lhs.repsText == rhs.repsText
            && lhs.weightText == rhs.weightText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                setBadge

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .wgjSingleLineText(scale: 0.84)

                        if row.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WGJTheme.accentGold)
                        }
                    }

                    Text(row.previousSummary)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)
                        .monospacedDigit()

                    if let metadata = row.metadataLine {
                        Text(metadata)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                setMenu
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    metricField(title: "Weight") {
                        loadField
                    }

                    metricField(title: "Reps") {
                        repsField
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricField(title: "Weight") {
                        loadField
                    }

                    metricField(title: "Reps") {
                        repsField
                    }
                }
            }

            if !set.dropStages.isEmpty {
                dropStagesSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(set.isWarmup ? WGJTheme.accentGold.opacity(0.12) : WGJTheme.field.opacity(0.54))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            set.isWarmup ? WGJTheme.accentGold.opacity(0.34) : WGJTheme.accentBlue.opacity(0.18),
                            lineWidth: 1
                        )
                )
        )
    }

    private var set: TemplateExerciseSetDraft {
        row.set
    }

    private var repsField: some View {
        TextField(
            "0",
            text: Binding(
                get: { repsText },
                set: { onRepsTextChanged($0) }
            )
        )
        .keyboardType(.numberPad)
        .focused(focusedInput, equals: .set(setID: row.id, metric: .reps))
        .multilineTextAlignment(.center)
        .disabled(set.isLocked)
        .wgjPillField()
    }

    private var loadField: some View {
        HStack(spacing: 6) {
            TextField(
                "0",
                text: Binding(
                    get: { weightText },
                    set: { onWeightTextChanged($0) }
                )
            )
            .keyboardType(.decimalPad)
            .focused(focusedInput, equals: .set(setID: row.id, metric: .weight))
            .multilineTextAlignment(.center)
            .disabled(set.isLocked)

            WGJActionMenuButton("Load Unit", titleVisibility: .hidden) {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        onLoadUnitChanged(unit)
                    }
                }
            } label: {
                Text(set.loadUnit.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
            .disabled(set.isLocked)
        }
        .wgjPillField()
    }

    private var setBadge: some View {
        Button {
            onToggleWarmup()
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
    }

    private var setMenu: some View {
        Menu {
            Button {
                onInsertBelow()
            } label: {
                Label("Insert below", systemImage: "plus")
            }

            Menu {
                Button {
                    onMoveUp()
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                .disabled(row.index == 0)

                Button {
                    onMoveDown()
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                .disabled(!canMoveDown)
            } label: {
                Label("Reorder", systemImage: "arrow.up.arrow.down")
            }

            Button {
                onToggleWarmup()
            } label: {
                Label(set.isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }

            Button {
                onToggleLock()
            } label: {
                Label(set.isLocked ? "Unlock set" : "Lock set", systemImage: set.isLocked ? "lock.open" : "lock")
            }

            if !set.isWarmup {
                if set.dropStages.isEmpty {
                    Button {
                        onAddDropStage()
                    } label: {
                        Label("Make dropset", systemImage: "arrow.down.to.line")
                    }
                } else {
                    Button {
                        onAddDropStage()
                    } label: {
                        Label("Add drop stage", systemImage: "plus")
                    }

                    Button(role: .destructive) {
                        onClearDropStages()
                    } label: {
                        Label("Remove dropset", systemImage: "trash")
                    }
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete set", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(WGJTheme.accentBlue)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WGJTheme.field)
                )
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier("template-set-actions-button-\(row.index)")
    }

    private func metricField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dropStagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dropset")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentCyan)

                Spacer()

                Button {
                    onAddDropStage()
                } label: {
                    Label("Add Drop", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WGJTheme.accentBlue)
            }

            ForEach(Array(set.dropStages.enumerated()), id: \.element.id) { stageIndex, stage in
                TemplateExerciseDropStageCardView(
                    index: stageIndex,
                    stage: stage,
                    onRepsChanged: { onDropStageRepsChanged(stage.id, $0) },
                    onWeightChanged: { onDropStageWeightChanged(stage.id, $0) },
                    onLoadUnitChanged: { onDropStageLoadUnitChanged(stage.id, $0) },
                    onDelete: { onRemoveDropStage(stage.id) }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WGJTheme.accentCyan.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WGJTheme.accentCyan.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct TemplateExerciseDropStageCardView: View, Equatable {
    let index: Int
    let stage: TemplateExerciseDropStageDraft
    let onRepsChanged: (String) -> Void
    let onWeightChanged: (String) -> Void
    let onLoadUnitChanged: (TemplateLoadUnit) -> Void
    let onDelete: () -> Void

    @State private var repsText: String
    @State private var weightText: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case reps
    }

    init(
        index: Int,
        stage: TemplateExerciseDropStageDraft,
        onRepsChanged: @escaping (String) -> Void,
        onWeightChanged: @escaping (String) -> Void,
        onLoadUnitChanged: @escaping (TemplateLoadUnit) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.index = index
        self.stage = stage
        self.onRepsChanged = onRepsChanged
        self.onWeightChanged = onWeightChanged
        self.onLoadUnitChanged = onLoadUnitChanged
        self.onDelete = onDelete
        _repsText = State(initialValue: stage.targetReps.map(String.init) ?? "")
        _weightText = State(initialValue: stage.targetWeight.map(WGJFormatters.decimalString) ?? "")
    }

    static func == (lhs: TemplateExerciseDropStageCardView, rhs: TemplateExerciseDropStageCardView) -> Bool {
        lhs.index == rhs.index && lhs.stage == rhs.stage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drop \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(WGJTheme.textSecondary)
            }

            HStack(spacing: 10) {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .focused($focusedField, equals: .weight)

                WGJActionMenuButton("Drop Load Unit", titleVisibility: .hidden) {
                    ForEach(TemplateLoadUnit.allCases) { unit in
                        Button(unit.shortLabel) {
                            commitLocalText()
                            onLoadUnitChanged(unit)
                        }
                    }
                } label: {
                    Text(stage.loadUnit.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentCyan)
                }

                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .focused($focusedField, equals: .reps)
            }
        }
        .onChange(of: stage.targetReps) { _, newValue in
            let resolved = newValue.map(String.init) ?? ""
            guard repsText != resolved else { return }
            repsText = resolved
        }
        .onChange(of: stage.targetWeight) { _, newValue in
            let resolved = newValue.map(WGJFormatters.decimalString) ?? ""
            guard weightText != resolved else { return }
            weightText = resolved
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            commitLocalText()
        }
        .onDisappear {
            commitLocalText()
        }
    }

    private func commitLocalText() {
        let resolvedWeightText = stage.targetWeight.map(WGJFormatters.decimalString) ?? ""
        if weightText != resolvedWeightText {
            onWeightChanged(weightText)
        }

        let resolvedRepsText = stage.targetReps.map(String.init) ?? ""
        if repsText != resolvedRepsText {
            onRepsChanged(repsText)
        }
    }
}
