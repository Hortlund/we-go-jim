import Foundation
import SwiftUI

struct WorkoutSessionExerciseGridEditor: View {
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let previousBySetIndex: [Int: WorkoutPreviousSetSnapshot]

    @Binding var restSeconds: Int
    @Binding var setDrafts: [WorkoutSessionSetDraft]

    var onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)?
    var onRestChanged: ((Int) -> Void)?

    @State private var isExpanded = true
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
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        previousBySetIndex: [Int: WorkoutPreviousSetSnapshot],
        restSeconds: Binding<Int>,
        setDrafts: Binding<[WorkoutSessionSetDraft]>,
        onSetDraftsChanged: (([WorkoutSessionSetDraft]) -> Void)? = nil,
        onRestChanged: ((Int) -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.muscleSummary = muscleSummary
        self.category = category
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.previousBySetIndex = previousBySetIndex
        self._restSeconds = restSeconds
        self._setDrafts = setDrafts
        self.onSetDraftsChanged = onSetDraftsChanged
        self.onRestChanged = onRestChanged
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
        headerContent
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WoKTheme.accentBlue)

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
        HStack(spacing: 10) {
            if shouldShowRepRange {
                repRangeControl
                Spacer()
            }
            restControl
        }
    }

    private var repRangeControl: some View {
        let range = displayRepRange

        return HStack(spacing: 8) {
            rangeValuePill(range.min.map(String.init) ?? "Min")

            Text("-")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WoKTheme.accentGold)

            rangeValuePill(range.max.map(String.init) ?? "Max")

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

    private func rangeValuePill(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(WoKTheme.textPrimary)
            .frame(minWidth: 56)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WoKTheme.field)
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

            previousCell(for: index)

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

            Button(role: .destructive) {
                removeSet(at: index)
            } label: {
                Label("Remove", systemImage: "trash")
            }

            Button {
                updateSetRest(restSeconds, setID: set.id)
            } label: {
                Label("Restore rest timer", systemImage: "timer")
            }
            .disabled(set.restSeconds > 0)
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
                        setDrafts[index].actualLoadUnit = unit
                        notifyChanged()
                    }
                }
            } label: {
                Text(effectiveUnit(for: setDrafts[index]).shortLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WoKTheme.accentCyan)
            }
            .disabled(isLocked)
        }
        .wokPillField()
    }

    private var summaryLine: String {
        var parts: [String] = ["\(setDrafts.count) sets"]

        if !category.isEmpty {
            parts.append(category)
        } else if !muscleSummary.isEmpty {
            parts.append(muscleSummary)
        }

        return parts.joined(separator: " · ")
    }

    private var shouldShowRepRange: Bool {
        targetRepMin != nil || targetRepMax != nil
    }

    private var displayRepRange: (min: Int?, max: Int?) {
        (targetRepMin, targetRepMax)
    }

    private func repsTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index) else { return "" }
                if let value = setDrafts[index].actualReps {
                    return "\(value)"
                }
                if let value = setDrafts[index].targetReps {
                    return "\(value)"
                }
                return ""
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let cleaned = newValue.filter(\.isNumber)
                if cleaned.isEmpty {
                    setDrafts[index].actualReps = nil
                } else {
                    setDrafts[index].actualReps = Int(cleaned)
                }
                setDrafts[index].isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                notifyChanged()
            }
        )
    }

    private func weightTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard setDrafts.indices.contains(index) else { return "" }
                if let value = setDrafts[index].actualWeight {
                    return formatWeight(value)
                }
                if let value = setDrafts[index].targetWeight {
                    return formatWeight(value)
                }
                return ""
            },
            set: { newValue in
                guard setDrafts.indices.contains(index) else { return }
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if normalized.isEmpty {
                    setDrafts[index].actualWeight = nil
                } else if let parsed = WoKFormatters.parseLocalizedDecimal(normalized) {
                    setDrafts[index].actualWeight = max(0, parsed)
                }

                setDrafts[index].isCompleted = (setDrafts[index].actualReps != nil || setDrafts[index].actualWeight != nil)
                notifyChanged()
            }
        )
    }

    private func addSet() {
        let last = setDrafts.last
        let newDraft = WorkoutSessionSetDraft(
            restSeconds: last?.restSeconds ?? restSeconds,
            targetReps: last?.targetReps,
            targetWeight: last?.targetWeight,
            targetLoadUnit: last?.targetLoadUnit ?? .kg,
            actualReps: nil,
            actualWeight: nil,
            actualLoadUnit: effectiveUnit(for: last ?? WorkoutSessionSetDraft()),
            isCompleted: false,
            isLocked: false
        )
        setDrafts.append(newDraft)
        notifyChanged()
    }

    private func removeSet(at index: Int) {
        guard setDrafts.indices.contains(index) else { return }
        let removedID = setDrafts[index].id
        setDrafts.remove(at: index)
        setSwipeOffsets[removedID] = nil
        setSwipeRemoving[removedID] = nil
        restSwipeOffsets[removedID] = nil
        restSwipeRemoving[removedID] = nil
        notifyChanged()
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

    private func updateSetRest(_ seconds: Int, setID: UUID) {
        guard let index = setDrafts.firstIndex(where: { $0.id == setID }) else { return }
        updateSetRest(seconds, at: index)
    }

    private func moveSetUp(_ index: Int) {
        guard index > 0 else { return }
        setDrafts.swapAt(index, index - 1)
        notifyChanged()
    }

    private func moveSetDown(_ index: Int) {
        guard index < setDrafts.count - 1 else { return }
        setDrafts.swapAt(index, index + 1)
        notifyChanged()
    }

    private func effectiveUnit(for set: WorkoutSessionSetDraft) -> TemplateLoadUnit {
        if set.actualWeight != nil {
            return set.actualLoadUnit
        }
        return set.targetLoadUnit
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

    private func previousCell(for index: Int) -> some View {
        let value = previousText(for: index)

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
        onRestChanged?(normalized)
        notifyChanged()
    }

    private func restLabel(for seconds: Int) -> String {
        if seconds <= 0 {
            return "No rest"
        }
        return formattedRest(seconds)
    }

    private func notifyChanged() {
        onSetDraftsChanged?(setDrafts)
    }

    private func formatWeight(_ value: Double) -> String {
        WoKFormatters.decimalString(value)
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
