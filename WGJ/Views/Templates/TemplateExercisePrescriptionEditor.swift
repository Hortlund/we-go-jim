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

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]

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
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                if let recommendation {
                    TrainingGuidanceBannerView(
                        title: recommendation.title,
                        message: recommendation.summary,
                        tone: recommendation.tone
                    )
                }

                controlsSection
                setsSection
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private var header: some View {
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

                headerSummaryChips
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

    private var setsSection: some View {
        let presentation = setPresentation

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

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.rows) { row in
                    SwipeDeleteRow(
                        offset: setSwipeOffsetBinding(for: row.id),
                        isRemoving: setRemovingBinding(for: row.id)
                    ) {
                        removeSet(withID: row.id)
                    } content: {
                        setCard(row: row)
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

    private func setCard(row: SetRowData) -> some View {
        let set = setDrafts[row.index]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                setBadge(for: row)

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

                setMenu(at: row.index)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    metricField(title: "Weight") {
                        loadField(at: row.index)
                    }

                    metricField(title: "Reps") {
                        repsField(at: row.index)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricField(title: "Weight") {
                        loadField(at: row.index)
                    }

                    metricField(title: "Reps") {
                        repsField(at: row.index)
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

    private func repsField(at index: Int) -> some View {
        TextField("0", text: repsTextBinding(for: index))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .disabled(setDrafts[index].isLocked)
            .wgjPillField()
    }

    private func loadField(at index: Int) -> some View {
        let isLocked = setDrafts[index].isLocked

        return HStack(spacing: 6) {
            TextField("0", text: weightTextBinding(for: index))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .disabled(isLocked)

            Menu {
                ForEach(TemplateLoadUnit.allCases) { unit in
                    Button(unit.shortLabel) {
                        setDrafts[index].loadUnit = unit
                        notifySetChanged()
                    }
                }
            } label: {
                Text(setDrafts[index].loadUnit.shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)
            }
            .disabled(isLocked)
        }
        .wgjPillField()
    }

    private func setBadge(for row: SetRowData) -> some View {
        let set = setDrafts[row.index]

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
    }

    private func setMenu(at index: Int) -> some View {
        let currentRest = setDrafts[index].restSeconds

        return Menu {
            Button {
                insertSet(after: index)
            } label: {
                Label("Insert below", systemImage: "plus")
            }

            Button {
                toggleWarmup(at: index)
            } label: {
                Label(setDrafts[index].isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
            }

            Button {
                moveSetUp(index)
            } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            .disabled(index == 0)

            Button {
                moveSetDown(index)
            } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            .disabled(index == setDrafts.count - 1)

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

            Button {
                toggleLock(at: index)
            } label: {
                Label(setDrafts[index].isLocked ? "Unlock set" : "Lock set", systemImage: setDrafts[index].isLocked ? "lock.open" : "lock")
            }

            if setDrafts[index].restSeconds != restSeconds {
                Button {
                    updateSetRest(restSeconds, at: index)
                } label: {
                    Label("Reset rest", systemImage: "timer")
                }
            }

            Divider()

            Button(role: .destructive) {
                removeSet(at: index)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
        } label: {
            headerIcon(symbol: "ellipsis.circle")
        }
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

    private var headerSummaryChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(setPresentation.summary, tint: WGJTheme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 8) {
                infoChip(repRangeSummary, tint: WGJTheme.accentGold)
                infoChip(setPresentation.summary, tint: WGJTheme.accentBlue)
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
                targetRepMin = cleaned.isEmpty ? nil : Int(cleaned)
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
                targetRepMax = cleaned.isEmpty ? nil : Int(cleaned)
                onRepRangeChanged?(targetRepMin, targetRepMax)
            }
        )
    }

    private func repsTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index), let reps = setDrafts[index].targetReps else {
                    return ""
                }
                return "\(reps)"
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let cleaned = newValue.filter(\.isNumber)
                setDrafts[index].targetReps = cleaned.isEmpty ? nil : Int(cleaned)
                notifySetChanged()
            }
        )
    }

    private func weightTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index), let weight = setDrafts[index].targetWeight else {
                    return ""
                }
                return formatWeight(weight)
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if normalized.isEmpty {
                    setDrafts[index].targetWeight = nil
                } else if let parsed = WGJFormatters.parseLocalizedDecimal(normalized) {
                    setDrafts[index].targetWeight = max(0, parsed)
                }

                notifySetChanged()
            }
        )
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
        restSeconds = normalized

        for index in setDrafts.indices {
            setDrafts[index].restSeconds = normalized
        }

        notifySetChanged()
        onRestChanged?(normalized)
    }

    private func updateSetRest(_ seconds: Int, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].restSeconds = max(0, min(3600, seconds))
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
