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

    @State private var isExpanded: Bool
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        infoDestination: AnyView? = nil,
        initiallyExpanded: Bool = true,
        exerciseIndexTitle: String? = nil,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false,
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
        self.exerciseIndexTitle = exerciseIndexTitle
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self._targetRepMin = targetRepMin
        self._targetRepMax = targetRepMax
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRepRangeChanged = onRepRangeChanged
        self.onRestChanged = onRestChanged
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onExerciseDelete = onExerciseDelete
        self._isExpanded = State(initialValue: initiallyExpanded)
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
                    .wgjSingleLineText(scale: 0.8)

                HStack(spacing: 8) {
                    infoChip("\(setDrafts.count) planned", tint: WGJTheme.accentBlue)

                    if !category.isEmpty {
                        infoChip(category, tint: WGJTheme.accentCyan)
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if hasHeaderMenu {
                    headerMenu
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
            HStack(alignment: .top, spacing: 12) {
                repRangeControl
                restControl
            }

            VStack(alignment: .leading, spacing: 12) {
                repRangeControl
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

            Text("This becomes the default rep target for each set.")
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

    private var restControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercise Rest")
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

                Text("Applies to every planned set.")
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
                Text("Set Plan")
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

                    Text(previousSummary(for: set))
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
                    metricField(title: "Weight") {
                        loadField(at: index)
                    }

                    metricField(title: "Reps") {
                        repsField(at: index)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    metricField(title: "Weight") {
                        loadField(at: index)
                    }

                    metricField(title: "Reps") {
                        repsField(at: index)
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

    private func setTitle(for index: Int) -> String {
        setDrafts[index].isWarmup ? "Warmup Set" : "Working Set \(workingSetNumber(at: index))"
    }

    private func workingSetNumber(at index: Int) -> Int {
        let priorWorking = setDrafts.prefix(index).filter { !$0.isWarmup }
        return priorWorking.count + 1
    }

    private func makeSetDraft(copying source: TemplateExerciseSetDraft?) -> TemplateExerciseSetDraft {
        TemplateExerciseSetDraft(
            targetReps: source?.targetReps,
            targetWeight: source?.targetWeight,
            loadUnit: source?.loadUnit ?? .kg,
            restSeconds: source?.restSeconds ?? restSeconds,
            isWarmup: source?.isWarmup ?? false,
            isLocked: false,
            previousTargetReps: source?.previousTargetReps,
            previousTargetWeight: source?.previousTargetWeight,
            previousLoadUnit: source?.previousLoadUnit ?? source?.loadUnit ?? .kg
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
