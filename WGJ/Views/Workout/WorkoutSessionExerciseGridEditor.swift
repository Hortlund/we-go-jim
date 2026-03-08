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

    @Binding var restSeconds: Int
    @Binding var setDrafts: [WorkoutSessionSetDraft]

    var manualCompletionMode: Bool
    var onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)?
    var onRestChanged: ((Int) -> Void)?
    var onSetCompletionChange: ((UUID, String, Int, Bool) -> Void)?
    var onExerciseDelete: (() -> Void)?

    @State private var isExpanded = true
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        exerciseIndexTitle: String? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        previousBySetIndex: [Int: WorkoutPreviousSetSnapshot],
        restSeconds: Binding<Int>,
        setDrafts: Binding<[WorkoutSessionSetDraft]>,
        manualCompletionMode: Bool = false,
        onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)? = nil,
        onRestChanged: ((Int) -> Void)? = nil,
        onSetCompletionChange: ((UUID, String, Int, Bool) -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.exerciseIndexTitle = exerciseIndexTitle
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.previousBySetIndex = previousBySetIndex
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.manualCompletionMode = manualCompletionMode
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRestChanged = onRestChanged
        self.onSetCompletionChange = onSetCompletionChange
        self.onExerciseDelete = onExerciseDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isExpanded {
                controlsSection
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
    }

    private var header: some View {
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
                    .wgjSingleLineText(scale: 0.8)

                HStack(spacing: 8) {
                    infoChip(
                        "\(completedSetCount)/\(setDrafts.count) done",
                        tint: completedSetCount == setDrafts.count && !setDrafts.isEmpty
                            ? WGJTheme.success
                            : WGJTheme.accentBlue
                    )

                    if isExerciseCompleted {
                        infoChip("Exercise done", tint: WGJTheme.success)
                    }

                    if !category.isEmpty {
                        infoChip(category, tint: WGJTheme.accentGold)
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if let onExerciseDelete {
                    Menu {
                        Button(role: .destructive) {
                            onExerciseDelete()
                        } label: {
                            Label("Delete exercise", systemImage: "trash")
                        }
                    } label: {
                        headerIcon(symbol: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerIcon(symbol: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controlsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                if shouldShowRepRange {
                    repRangeControl
                }

                restControl
            }

            VStack(alignment: .leading, spacing: 12) {
                if shouldShowRepRange {
                    repRangeControl
                }

                restControl
            }
        }
    }

    private var repRangeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Range")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 10) {
                rangeValuePill(displayRepRange.min.map(String.init) ?? "Min")

                Text("to")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentGold)

                rangeValuePill(displayRepRange.max.map(String.init) ?? "Max")
            }

            Text("Template guide for the set entries below.")
                .font(.caption2)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.accentGold.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.accentGold.opacity(0.32), lineWidth: 1)
                )
        )
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Default Rest")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

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

                Text("Use this when you reset a set timer.")
                    .font(.caption2)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.field.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.accentBlue.opacity(0.22), lineWidth: 1)
                )
        )
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
                    isRemoving: setRemovingBinding(for: draft.id)
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

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                setBadge(for: index)

                VStack(alignment: .leading, spacing: 4) {
                    Text(setTitle(for: index))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.84)

                    Text(previousSummary(for: index))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                setRestMenu(at: index)
                lockButton(at: index)
                setMenu(at: index)
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
        .wgjPillField()
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
    }

    private func setRestMenu(at index: Int) -> some View {
        let currentRest = setDrafts[index].restSeconds
        let isDefaultRest = currentRest == restSeconds

        return Menu {
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
            Label(restLabel(for: currentRest), systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDefaultRest ? WGJTheme.textSecondary : WGJTheme.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(WGJTheme.field)
                        .overlay(
                            Capsule()
                                .stroke(
                                    (isDefaultRest ? WGJTheme.textSecondary : WGJTheme.accentBlue).opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func lockButton(at index: Int) -> some View {
        Button {
            toggleLock(at: index)
        } label: {
            Image(systemName: setDrafts[index].isLocked ? "lock.fill" : "lock.open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(setDrafts[index].isLocked ? WGJTheme.accentGold : WGJTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WGJTheme.field)
                )
        }
        .buttonStyle(.plain)
    }

    private func setMenu(at index: Int) -> some View {
        Menu {
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

            if setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil {
                Button {
                    clearLoggedValues(at: index)
                } label: {
                    Label("Clear logged values", systemImage: "eraser")
                }
            }

            if setDrafts[index].restSeconds != restSeconds {
                Button {
                    updateSetRest(restSeconds, at: index)
                } label: {
                    Label("Reset rest", systemImage: "timer")
                }
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

        return "Log the set values separately from the template target."
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
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.04)) {
            setDrafts.append(makeSetDraft(copying: setDrafts.last))
        }
        notifyChanged()
    }

    private func insertSet(after index: Int) {
        guard setDrafts.indices.contains(index) else { return }

        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            setDrafts.insert(makeSetDraft(copying: setDrafts[index]), at: index + 1)
        }
        notifyChanged()
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let removedID = setDrafts[index].id
        let removedTitle = setTitle(for: index)

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            _ = setDrafts.remove(at: index)
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
        setDrafts[index].isWarmup.toggle()
        notifyChanged()
    }

    private func toggleLock(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isLocked.toggle()
        notifyChanged()
    }

    private func updateSetRest(_ seconds: Int, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].restSeconds = max(0, min(3600, seconds))
        notifyChanged()
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index - 1)
        }
        notifyChanged()
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
            setDrafts.swapAt(index, index + 1)
        }
        notifyChanged()
    }

    private func clearLoggedValues(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].actualReps = nil
        setDrafts[index].actualWeight = nil
        setDrafts[index].isCompleted = false
        notifyChanged()
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
        WorkoutSessionSetDraft(
            isWarmup: source?.isWarmup ?? false,
            restSeconds: source?.restSeconds ?? restSeconds,
            targetReps: source?.targetReps,
            targetWeight: source?.targetWeight,
            targetLoadUnit: source?.targetLoadUnit ?? .kg,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: source?.actualLoadUnit ?? source?.targetLoadUnit ?? .kg,
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
        let normalized = max(0, min(3600, seconds))
        restSeconds = normalized

        for index in setDrafts.indices {
            setDrafts[index].restSeconds = normalized
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
                        toggleCompletion(at: index)
                    }
                    .buttonStyle(WGJGhostButtonStyle())
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
                    toggleCompletion(at: index)
                } label: {
                    Label(completionButtonTitle(for: index), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .wgjSingleLineText(scale: 0.82)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }
    }

    private func completionButtonTitle(for index: Int) -> String {
        let restLabel = setDrafts[index].restSeconds > 0 ? " + Rest \(formattedRest(setDrafts[index].restSeconds))" : ""
        return "Complete Set\(restLabel)"
    }

    private func toggleCompletion(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].isCompleted.toggle()
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
}
