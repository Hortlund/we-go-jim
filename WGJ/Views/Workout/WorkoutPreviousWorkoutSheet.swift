import SwiftUI

struct WorkoutPreviousWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: WorkoutPreviousWorkoutSource
    let drafts: [WorkoutSessionSetDraft]
    let usesAssistance: Bool
    let onUse: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.name).font(.title2.bold())
                        Text(source.date, format: .dateTime.day().month(.wide).year())
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    Text("These sets are from another workout. Only empty fields in unfinished, unlocked sets will be filled.")
                        .foregroundStyle(WGJTheme.textSecondary)
                    ForEach(source.sets.keys.sorted(), id: \.self) { index in
                        if drafts.indices.contains(index), let set = source.sets[index] {
                            HStack {
                                Text(drafts[index].isWarmup ? "Warmup set" : "Working set \(drafts.prefix(index).filter { !$0.isWarmup }.count + 1)")
                                Spacer()
                                Text(performance(set)).fontWeight(.semibold)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .wgjScreenBackground()
            .navigationTitle("Previous workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Use These Values") {
                    onUse()
                    dismiss()
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .padding()
                .accessibilityIdentifier("use-other-workout-values")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func performance(_ set: WorkoutPreviousSetSnapshot) -> String {
        let kilograms = set.unit == .bodyweight ? 0 : WorkoutPerformanceMath.normalizedLoadInKilograms(set.weight ?? 0, unit: set.unit)
        if usesAssistance && set.weight == nil && set.unit != .bodyweight { return "Assistance not recorded" }
        return ExerciseSetPerformance(reps: set.reps ?? 0, kilograms: kilograms)
            .label(unit: set.unit, addedWeight: true, assistance: usesAssistance)
    }
}
