import SwiftUI

struct WorkoutPreviousWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let exerciseName: String
    let source: WorkoutPreviousWorkoutSource
    let drafts: [WorkoutSessionSetDraft]
    let usesAssistance: Bool
    let onUse: () -> Void

    private var visibleSetIndices: [Int] {
        source.sets.keys.sorted().filter { drafts.indices.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exerciseName)
                            .font(.title2.bold())
                            .foregroundStyle(WGJTheme.textPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From \(source.name)")
                            Text(source.date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                        }
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(visibleSetIndices, id: \.self) { index in
                            if let set = source.sets[index] {
                                setRow(index: index, set: set)
                                if index != visibleSetIndices.last {
                                    Divider().overlay(WGJTheme.rowDivider).padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .background(WGJTheme.field, in: RoundedRectangle(cornerRadius: 16))

                    Text("Copy these reps and weights into blank fields. Anything you’ve already logged stays unchanged.")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .wgjScreenBackground()
            .navigationTitle("Previous sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    onUse()
                    dismiss()
                } label: {
                    Text("Copy to workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(WGJTheme.bgBase)
                .accessibilityIdentifier("use-other-workout-values")
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize
            ? [.large]
            : [.height(CGFloat(340 + min(visibleSetIndices.count, 4) * 56)), .large])
        .presentationDragIndicator(.visible)
    }

    private func setRow(index: Int, set: WorkoutPreviousSetSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                setLabel(index: index)
                Spacer(minLength: 0)
                performanceLabel(set)
            }
            VStack(alignment: .leading, spacing: 8) {
                setLabel(index: index)
                performanceLabel(set)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func setLabel(index: Int) -> some View {
        let isWarmup = drafts[index].isWarmup
        let number = drafts.prefix(index).filter { $0.isWarmup == isWarmup }.count + 1
        return Text(isWarmup ? "Warmup \(number)" : "Set \(number)")
            .font(.subheadline)
            .foregroundStyle(isWarmup ? WGJTheme.accentGold : WGJTheme.textSecondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func performanceLabel(_ set: WorkoutPreviousSetSnapshot) -> some View {
        Text(performance(set))
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(WGJTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func performance(_ set: WorkoutPreviousSetSnapshot) -> String {
        let kilograms = set.unit == .bodyweight ? 0 : WorkoutPerformanceMath.normalizedLoadInKilograms(set.weight ?? 0, unit: set.unit)
        if usesAssistance && set.weight == nil && set.unit != .bodyweight { return "Assistance not recorded" }
        return ExerciseSetPerformance(reps: set.reps ?? 0, kilograms: kilograms)
            .label(unit: set.unit, addedWeight: true, assistance: usesAssistance)
    }
}
