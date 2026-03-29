import Foundation
import SwiftUI

struct TemplateExercisePrescriptionEditor: View {
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let infoDestination: AnyView?
    let exerciseIndexTitle: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let recommendation: TemplateExerciseRecommendation?
    let preferredLoadUnit: TemplateLoadUnit

    @Binding var targetRepMin: Int?
    @Binding var targetRepMax: Int?
    @Binding var restSeconds: Int
    @Binding var setDrafts: [TemplateExerciseSetDraft]

    var onSetDraftsChanged: (([TemplateExerciseSetDraft]) -> Void)?
    var onRepRangeChanged: ((Int?, Int?) -> Void)?
    var onRestChanged: ((Int) -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onExerciseDelete: (() -> Void)?

    private let externalIsExpanded: Binding<Bool>?
    @State private var localIsExpanded: Bool
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]

    private let restPresets = [10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240]

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        infoDestination: AnyView? = nil,
        recommendation: TemplateExerciseRecommendation? = nil,
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        exerciseIndexTitle: String? = nil,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false,
        preferredLoadUnit: TemplateLoadUnit = .kg,
        targetRepMin: Binding<Int?>,
        targetRepMax: Binding<Int?>,
        restSeconds: Binding<Int>,
        setDrafts: Binding<[TemplateExerciseSetDraft]>,
        onSetDraftsChanged: (([TemplateExerciseSetDraft]) -> Void)? = nil,
        onRepRangeChanged: ((Int?, Int?) -> Void)? = nil,
        onRestChanged: ((Int) -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.infoDestination = infoDestination
        self.recommendation = recommendation
        self.exerciseIndexTitle = exerciseIndexTitle
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.preferredLoadUnit = preferredLoadUnit
        self._targetRepMin = targetRepMin
        self._targetRepMax = targetRepMax
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.externalIsExpanded = isExpanded
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRepRangeChanged = onRepRangeChanged
        self.onRestChanged = onRestChanged
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onExerciseDelete = onExerciseDelete
        self._localIsExpanded = State(initialValue: isExpanded?.wrappedValue ?? initiallyExpanded)
    }

    var body: some View {
        let presentation = setPresentation

        return VStack(alignment: .leading, spacing: 14) {
            header(presentation: presentation)

            if isExpanded {
                if let recommendation {
                    TrainingGuidanceBannerView(
                        title: recommendation.title,
                        message: recommendation.summary,
                        tone: recommendation.tone
                    )
                }

                controlsSection
                setsSection(presentation: presentation)
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private func header(presentation: SetPresentation) -> some View {
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

                headerSummaryChips(presentation: presentation)
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
                }
                .buttonStyle(.plain)
            } else {
                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .wgjSingleLineText(scale: 0.8)
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

    private var repRangeControl: some View {
        compactControlCard(
            title: "Rep Range",
            subtitle: "Default target for each working set.",
            tint: WGJTheme.accentGold
        ) {
            HStack(spacing: 10) {
                TextField("Min", text: repMinTextBinding)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .frame(maxWidth: .infinity)

                Text("to")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentGold)

                TextField("Max", text: repMaxTextBinding)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .wgjPillField()
                    .frame(maxWidth: .infinity)
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

    private func setsSection(presentation: SetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.rows) { row in
                    SwipeDeleteRow(
                        offset: setSwipeOffsetBinding(for: row.id),
                        isRemoving: setRemovingBinding(for: row.id)
                    ) {
                        removeSet(withID: row.id)
                    } content: {
                        TemplateExerciseSetCardView(
                            row: row,
                            set: setDrafts[row.index],
                            defaultRestSeconds: restSeconds,
                            restPresets: restPresets,
                            canMoveDown: row.index < presentation.rows.count - 1,
                            repsText: repsText(for: row.index),
                            weightText: weightText(for: row.index),
                            onRepsTextChanged: { updateRepsText($0, at: row.index) },
                            onWeightTextChanged: { updateWeightText($0, at: row.index) },
                            onLoadUnitChanged: { updateLoadUnit($0, at: row.index) },
                            onToggleWarmup: { toggleWarmup(at: row.index) },
                            onInsertBelow: { insertSet(after: row.index) },
                            onMoveUp: { moveSetUp(row.index) },
                            onMoveDown: { moveSetDown(row.index) },
                            onSetRestChanged: { updateSetRest($0, at: row.index) },
                            onToggleLock: { toggleLock(at: row.index) },
                            onDelete: { removeSet(at: row.index) }
                        )
                        .equatable()
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
        guard setDrafts.indices.contains(index), let reps = setDrafts[index].targetReps else {
            return ""
        }
        return "\(reps)"
    }

    private func weightText(for index: Int) -> String {
        guard setDrafts.indices.contains(index), let weight = setDrafts[index].targetWeight else {
            return ""
        }
        return formatWeight(weight)
    }

    private var headerMenu: some View {
        Menu {
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

            if let onExerciseDelete {
                if onMoveUp != nil || onMoveDown != nil {
                    Divider()
                }

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

    private var hasHeaderMenu: Bool {
        onMoveUp != nil || onMoveDown != nil || onExerciseDelete != nil
    }

    private func headerSummaryChips(presentation: SetPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(presentation.summary, tint: WGJTheme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(presentation.summary, tint: WGJTheme.accentBlue)
            }
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

    private func toggleExpanded() {
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

    private var repMinTextBinding: Binding<String> {
        Binding(
            get: {
                guard let targetRepMin else { return "" }
                return "\(targetRepMin)"
            },
            set: { newValue in
                let cleaned = newValue.filter(\.isNumber)
                let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
                guard targetRepMin != updatedValue else { return }
                targetRepMin = updatedValue
                onRepRangeChanged?(targetRepMin, targetRepMax)
            }
        )
    }

    private var repMaxTextBinding: Binding<String> {
        Binding(
            get: {
                guard let targetRepMax else { return "" }
                return "\(targetRepMax)"
            },
            set: { newValue in
                let cleaned = newValue.filter(\.isNumber)
                let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
                guard targetRepMax != updatedValue else { return }
                targetRepMax = updatedValue
                onRepRangeChanged?(targetRepMin, targetRepMax)
            }
        )
    }

    private func updateRepsText(_ newValue: String, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let cleaned = newValue.filter(\.isNumber)
        let updatedValue = cleaned.isEmpty ? nil : Int(cleaned)
        guard setDrafts[index].targetReps != updatedValue else { return }
        setDrafts[index].targetReps = updatedValue
        notifySetChanged()
    }

    private func updateWeightText(_ newValue: String, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let updatedValue: Double?
        if normalized.isEmpty {
            updatedValue = nil
        } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
            updatedValue = max(0, parsed)
        } else {
            return
        }

        guard setDrafts[index].targetWeight != updatedValue else { return }
        setDrafts[index].targetWeight = updatedValue
        notifySetChanged()
    }

    private func updateLoadUnit(_ loadUnit: TemplateLoadUnit, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        guard setDrafts[index].loadUnit != loadUnit else { return }
        setDrafts[index].loadUnit = loadUnit
        notifySetChanged()
    }

    private func addSet() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.04)) {
            setDrafts.append(makeSetDraft(copying: setDrafts.last))
        }
        notifySetChanged()
    }

    private func insertSet(after index: Int) {
        guard setDrafts.indices.contains(index) else { return }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            setDrafts.insert(makeSetDraft(copying: setDrafts[index]), at: index + 1)
        }
        notifySetChanged()
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let removedID = setDrafts[index].id

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            _ = setDrafts.remove(at: index)
        }

        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        notifySetChanged()
    }

    private func removeSet(withID setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        removeSet(at: index)
    }

    private func toggleWarmup(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isWarmup.toggle()
        notifySetChanged()
    }

    private func toggleLock(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isLocked.toggle()
        notifySetChanged()
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index - 1)
        }
        notifySetChanged()
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index + 1)
        }
        notifySetChanged()
    }

    private func previousText(for set: TemplateExerciseSetDraft) -> String {
        if let weight = set.previousTargetWeight, let reps = set.previousTargetReps {
            return "\(formatWeight(weight)) \(set.previousLoadUnit.shortLabel) x \(reps)"
        }

        if let reps = set.previousTargetReps {
            return "\(reps) reps"
        }

        return "-"
    }

    private func previousSummary(for set: TemplateExerciseSetDraft) -> String {
        let previous = previousText(for: set)
        return previous == "-" ? "No previous target saved." : "Last target \(previous)"
    }

    private func setMetadataLine(for set: TemplateExerciseSetDraft) -> String? {
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

    private func makeSetDraft(copying source: TemplateExerciseSetDraft?) -> TemplateExerciseSetDraft {
        let fallbackLoadUnit = source?.loadUnit ?? preferredLoadUnit
        return TemplateExerciseSetDraft(
            targetReps: source?.targetReps,
            targetWeight: source?.targetWeight,
            loadUnit: fallbackLoadUnit,
            restSeconds: source?.restSeconds ?? restSeconds,
            isWarmup: source?.isWarmup ?? false,
            isLocked: false,
            previousTargetReps: source?.previousTargetReps,
            previousTargetWeight: source?.previousTargetWeight,
            previousLoadUnit: source?.previousLoadUnit ?? fallbackLoadUnit
        )
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
            notifySetChanged()
        }

        if didChangeDefaultRest {
            onRestChanged?(normalized)
        }
    }

    private func updateSetRest(_ seconds: Int, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let normalized = max(0, min(3600, seconds))
        guard setDrafts[index].restSeconds != normalized else { return }
        setDrafts[index].restSeconds = normalized
        notifySetChanged()
    }

    private func restLabel(for seconds: Int) -> String {
        seconds <= 0 ? "No rest" : formattedRest(seconds)
    }

    private func notifySetChanged() {
        onSetDraftsChanged?(setDrafts)
    }

    private func formatWeight(_ value: Double) -> String {
        WGJFormatters.decimalString(value)
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
    var setPresentation: SetPresentation {
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
                    title: set.isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber)",
                    badgeTitle: set.isWarmup ? "W" : "\(workingSetNumber)",
                    previousSummary: previousSummary(for: set),
                    metadataLine: setMetadataLine(for: set),
                    isLocked: set.isLocked
                )
            )
        }

        let workingSets = max(0, setDrafts.count - warmupCount)
        let summary = warmupCount > 0
            ? "\(workingSets) working • \(warmupCount) warmup"
            : "\(workingSets) working sets"

        return SetPresentation(rows: rows, summary: summary)
    }
}

private struct SetPresentation: Equatable {
    let rows: [SetRowData]
    let summary: String
}

private struct SetRowData: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let title: String
    let badgeTitle: String
    let previousSummary: String
    let metadataLine: String?
    let isLocked: Bool
}

private struct TemplateExerciseSetCardView: View, Equatable {
    let row: SetRowData
    let set: TemplateExerciseSetDraft
    let defaultRestSeconds: Int
    let restPresets: [Int]
    let canMoveDown: Bool
    let repsText: String
    let weightText: String

    let onRepsTextChanged: (String) -> Void
    let onWeightTextChanged: (String) -> Void
    let onLoadUnitChanged: (TemplateLoadUnit) -> Void
    let onToggleWarmup: () -> Void
    let onInsertBelow: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSetRestChanged: (Int) -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void

    static func == (lhs: TemplateExerciseSetCardView, rhs: TemplateExerciseSetCardView) -> Bool {
        lhs.row == rhs.row
            && lhs.set == rhs.set
            && lhs.defaultRestSeconds == rhs.defaultRestSeconds
            && lhs.restPresets == rhs.restPresets
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

    private var repsField: some View {
        TextField(
            "0",
            text: Binding(
                get: { repsText },
                set: { onRepsTextChanged($0) }
            )
        )
        .keyboardType(.numberPad)
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
            .multilineTextAlignment(.center)
            .disabled(set.isLocked)

            Menu {
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

            Button {
                onToggleWarmup()
            } label: {
                Label(set.isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }

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

            Menu {
                ForEach(restPresets, id: \.self) { value in
                    Button(formattedRest(value)) {
                        onSetRestChanged(value)
                    }
                }

                Divider()

                Button("Use exercise default (\(formattedRest(defaultRestSeconds)))") {
                    onSetRestChanged(defaultRestSeconds)
                }

                Button("-15 sec") {
                    onSetRestChanged(set.restSeconds - 15)
                }

                Button("+15 sec") {
                    onSetRestChanged(set.restSeconds + 15)
                }

                Button("No rest") {
                    onSetRestChanged(0)
                }
            } label: {
                Label("Set rest", systemImage: "timer")
            }

            Button {
                onToggleLock()
            } label: {
                Label(set.isLocked ? "Unlock set" : "Lock set", systemImage: set.isLocked ? "lock.open" : "lock")
            }

            if set.restSeconds != defaultRestSeconds {
                Button {
                    onSetRestChanged(defaultRestSeconds)
                } label: {
                    Label("Reset rest", systemImage: "timer")
                }
            }

            Divider()

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
        .buttonStyle(.plain)
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

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
