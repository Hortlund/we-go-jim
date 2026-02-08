import Foundation
import SwiftUI

struct TemplateExercisePrescriptionEditor: View {
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let infoDestination: AnyView?

    @Binding var targetRepMin: Int?
    @Binding var targetRepMax: Int?
    @Binding var restSeconds: Int
    @Binding var setDrafts: [TemplateExerciseSetDraft]

    var onSetDraftsChanged: (([TemplateExerciseSetDraft]) -> Void)?
    var onRepRangeChanged: ((Int?, Int?) -> Void)?
    var onRestChanged: ((Int) -> Void)?
    var onExerciseDelete: (() -> Void)?

    @Binding private var exerciseSwipeOffset: CGFloat
    @Binding private var exerciseSwipeRemoving: Bool

    @State private var isExpanded: Bool
    @State private var setSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var setSwipeRemoving: [UUID: Bool] = [:]
    @State private var restSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var restSwipeRemoving: [UUID: Bool] = [:]

    private let restPresets = [45, 60, 75, 90, 120, 150, 180, 210, 240]
    private let setColumnWidth: CGFloat = 42
    private let previousMinColumnWidth: CGFloat = 84
    private let loadColumnWidth: CGFloat = 104
    private let repsColumnWidth: CGFloat = 56
    private let lockColumnWidth: CGFloat = 30
    private let tableColumnSpacing: CGFloat = 6

    init(
        exerciseName: String,
        muscleSummary: String,
        category: String,
        infoDestination: AnyView? = nil,
        initiallyExpanded: Bool = true,
        targetRepMin: Binding<Int?>,
        targetRepMax: Binding<Int?>,
        restSeconds: Binding<Int>,
        setDrafts: Binding<[TemplateExerciseSetDraft]>,
        onSetDraftsChanged: (([TemplateExerciseSetDraft]) -> Void)? = nil,
        onRepRangeChanged: ((Int?, Int?) -> Void)? = nil,
        onRestChanged: ((Int) -> Void)? = nil,
        onExerciseDelete: (() -> Void)? = nil,
        exerciseSwipeOffset: Binding<CGFloat>? = nil,
        exerciseSwipeRemoving: Binding<Bool>? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.infoDestination = infoDestination
        self._targetRepMin = targetRepMin
        self._targetRepMax = targetRepMax
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRepRangeChanged = onRepRangeChanged
        self.onRestChanged = onRestChanged
        self.onExerciseDelete = onExerciseDelete
        self._exerciseSwipeOffset = exerciseSwipeOffset ?? .constant(0)
        self._exerciseSwipeRemoving = exerciseSwipeRemoving ?? .constant(false)
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                controlsRow
                setTable
            }
        }
        .padding(14)
        .wokCardContainer(strong: true)
    }

    private var header: some View {
        Group {
            if let onExerciseDelete {
                SwipeDeleteRow(
                    offset: $exerciseSwipeOffset,
                    isRemoving: $exerciseSwipeRemoving
                ) {
                    onExerciseDelete()
                } content: {
                    headerContent
                }
            } else {
                headerContent
            }
        }
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let infoDestination {
                    NavigationLink {
                        infoDestination
                    } label: {
                        Text(exerciseName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WoKTheme.accentBlue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(exerciseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WoKTheme.accentBlue)
                }

                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(WoKTheme.accentBlue)
            }
            .buttonStyle(.plain)
        }
    }

    private var controlsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                repRangeControl
                Spacer()
                restControl
            }
        }
    }

    private var repRangeControl: some View {
        HStack(spacing: 8) {
            TextField("Min", text: repMinTextBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .wokPillField()

            Text("-")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WoKTheme.accentGold)

            TextField("Max", text: repMaxTextBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .wokPillField()

            Text("reps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WoKTheme.accentGold)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WoKTheme.accentGold.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WoKTheme.accentGold.opacity(0.58), lineWidth: 1)
                )
        )
    }

    private var restControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Rest")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WoKTheme.textSecondary)

            Menu {
                ForEach(restPresets, id: \.self) { value in
                    Button(formattedRest(value)) {
                        updateRest(value)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(formattedRest(restSeconds))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WoKTheme.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WoKTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WoKTheme.accentBlue.opacity(0.22), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 6) {
                Button {
                    updateRest(restSeconds - 15)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)

                Button {
                    updateRest(restSeconds + 15)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(WoKTheme.textSecondary)
        }
    }

    private var setTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: tableColumnSpacing) {
                Text("Set")
                    .frame(width: setColumnWidth, alignment: .leading)
                Text("Prev")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: previousMinColumnWidth, maxWidth: .infinity, alignment: .leading)
                Text("Weight")
                    .frame(width: loadColumnWidth, alignment: .leading)
                Text("Reps")
                    .frame(width: repsColumnWidth, alignment: .leading)
                Image(systemName: "lock.fill")
                    .frame(width: lockColumnWidth, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WoKTheme.textSecondary)

            if setDrafts.isEmpty {
                Text("No sets yet.")
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)
            }

            ForEach(Array(setDrafts.enumerated()), id: \.element.id) { index, draft in
                VStack(spacing: 8) {
                    SwipeDeleteRow(
                        offset: setSwipeOffsetBinding(for: draft.id),
                        isRemoving: setRemovingBinding(for: draft.id)
                    ) {
                        removeSet(withID: draft.id)
                    } content: {
                        setRow(at: index)
                    }

                    if draft.restSeconds > 0 {
                        SwipeDeleteRow(
                            offset: restSwipeOffsetBinding(for: draft.id),
                            isRemoving: restRemovingBinding(for: draft.id)
                        ) {
                            updateSetRest(0, setID: draft.id)
                        } content: {
                            restDivider(after: index)
                        }
                    }
                }
            }

            Button {
                addSet()
            } label: {
                Text("+ Add Set")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WoKTheme.field)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(WoKTheme.accentBlue.opacity(0.28), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(WoKTheme.textPrimary)
        }
    }

    private func setRow(at index: Int) -> some View {
        let set = setDrafts[index]

        return HStack(spacing: tableColumnSpacing) {
            setBadge(for: index)
                .frame(width: setColumnWidth, alignment: .leading)

            previousCell(for: set)

            loadField(at: index)
                .frame(width: loadColumnWidth, alignment: .leading)

            TextField("0", text: repsTextBinding(for: index))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .wokPillField()
                .disabled(set.isLocked)
                .frame(width: repsColumnWidth, alignment: .leading)

            Button {
                toggleLock(at: index)
            } label: {
                Image(systemName: set.isLocked ? "lock.fill" : "lock.open")
                    .font(.headline)
                    .foregroundStyle(set.isLocked ? WoKTheme.accentGold : WoKTheme.textSecondary)
                    .frame(width: lockColumnWidth, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private func setBadge(for index: Int) -> some View {
        let set = setDrafts[index]
        let title = set.isWarmup ? "W" : "\(workingSetNumber(at: index))"

        return Button {
            toggleWarmup(at: index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(set.isWarmup ? WoKTheme.accentGold.opacity(0.24) : WoKTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(set.isWarmup ? WoKTheme.accentGold.opacity(0.65) : WoKTheme.accentBlue.opacity(0.22), lineWidth: 1)
                    )

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.isWarmup ? WoKTheme.accentGold : WoKTheme.textPrimary)
            }
            .frame(width: setColumnWidth, height: 36)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleWarmup(at: index)
            } label: {
                Label(set.isWarmup ? "Mark as working" : "Mark as warmup", systemImage: "flame")
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

            Button {
                updateSetRest(restSeconds, setID: set.id)
            } label: {
                Label("Restore rest timer", systemImage: "timer")
            }
            .disabled(set.restSeconds > 0)

            Button(role: .destructive) {
                removeSet(withID: set.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func restDivider(after index: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(WoKTheme.rowDivider)
                .frame(height: 3)

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
                    updateSetRest(setDrafts[index].restSeconds - 15, at: index)
                }

                Button("+15 sec") {
                    updateSetRest(setDrafts[index].restSeconds + 15, at: index)
                }

                Button("No rest") {
                    updateSetRest(0, at: index)
                }
            } label: {
                Text(restLabel(for: setDrafts[index].restSeconds))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(setDrafts[index].restSeconds == 0 ? WoKTheme.textSecondary : WoKTheme.accentBlue)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            Capsule()
                .fill(WoKTheme.rowDivider)
                .frame(height: 3)
        }
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
                    .foregroundStyle(WoKTheme.accentCyan)
            }
            .disabled(isLocked)
        }
        .wokPillField()
    }

    private var summaryLine: String {
        var parts: [String] = ["\(setDrafts.count) sets"]

        if let min = targetRepMin, let max = targetRepMax {
            parts.append("\(min)-\(max) reps")
        } else if let min = targetRepMin {
            parts.append("\(min)+ reps")
        }

        if !category.isEmpty {
            parts.append(category)
        } else if !muscleSummary.isEmpty {
            parts.append(muscleSummary)
        }

        return parts.joined(separator: " · ")
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
                } else if let parsed = WoKFormatters.parseLocalizedDecimal(normalized) {
                    setDrafts[index].targetWeight = max(0, parsed)
                }

                notifySetChanged()
            }
        )
    }

    private func addSet() {
        setDrafts.append(TemplateExerciseSetDraft(restSeconds: restSeconds))
        notifySetChanged()
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let removedID = setDrafts[index].id
        setDrafts.remove(at: index)
        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        restSwipeOffsets[removedID] = nil
        restSwipeRemoving[removedID] = nil
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
        setDrafts.swapAt(index, index - 1)
        notifySetChanged()
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }
        setDrafts.swapAt(index, index + 1)
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

    private func previousCell(for set: TemplateExerciseSetDraft) -> some View {
        let value = previousText(for: set)

        return Text(value)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WoKTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)
            .monospacedDigit()
            .frame(
                minWidth: previousMinColumnWidth,
                maxWidth: .infinity,
                alignment: .leading
            )
    }

    private func workingSetNumber(at index: Int) -> Int {
        let priorWorking = setDrafts.prefix(index).filter { !$0.isWarmup }
        return priorWorking.count + 1
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func updateRest(_ seconds: Int) {
        let normalized = max(0, min(3600, seconds))
        restSeconds = normalized
        for i in setDrafts.indices {
            setDrafts[i].restSeconds = normalized
        }
        notifySetChanged()
        onRestChanged?(normalized)
    }

    private func updateSetRest(_ seconds: Int, at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        setDrafts[index].restSeconds = max(0, min(3600, seconds))
        notifySetChanged()
    }

    private func updateSetRest(_ seconds: Int, setID: UUID) {
        guard let index = indexForSetID(setID) else { return }
        updateSetRest(seconds, at: index)
    }

    private func restLabel(for seconds: Int) -> String {
        if seconds <= 0 {
            return "No rest"
        }
        return formattedRest(seconds)
    }

    private func notifySetChanged() {
        onSetDraftsChanged?(setDrafts)
    }

    private func formatWeight(_ value: Double) -> String {
        WoKFormatters.decimalString(value)
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

    private func restSwipeOffsetBinding(for setID: UUID) -> Binding<CGFloat> {
        Binding(
            get: { restSwipeOffsets[setID] ?? 0 },
            set: { restSwipeOffsets[setID] = $0 }
        )
    }

    private func restRemovingBinding(for setID: UUID) -> Binding<Bool> {
        Binding(
            get: { restSwipeRemoving[setID] ?? false },
            set: { restSwipeRemoving[setID] = $0 }
        )
    }
}
