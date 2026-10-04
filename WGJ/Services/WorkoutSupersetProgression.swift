import Foundation

/// Derives guidance from logged drafts so resume, undo, and plan edits need no separate cursor.
nonisolated struct WorkoutSupersetProgression: Sendable {
    struct Step: Equatable, Sendable {
        let exerciseID: UUID
        let setID: UUID
        let position: SupersetExercisePosition
        let setLabel: String
        let round: Int?
        let nextDrop: Int?

        var label: String {
            let base = "\(position.label) · \(setLabel)"
            return nextDrop.map { "\(base) · Drop \($0)" } ?? base
        }
    }

    let firstExerciseID: UUID
    let secondExerciseID: UUID
    let firstDrafts: [WorkoutSessionSetDraft]
    let secondDrafts: [WorkoutSessionSetDraft]
    let roundRestSeconds: Int

    var nextStep: Step? {
        // Pair warmups separately so they alternate without shifting working rounds.
        for isWarmup in [true, false] {
            let rounds = members.map { member in member.2.indices.filter { member.2[$0].isWarmup == isWarmup } }
            for roundIndex in 0..<max(rounds[0].count, rounds[1].count) {
                for (memberIndex, member) in members.enumerated() {
                    guard rounds[memberIndex].indices.contains(roundIndex) else { continue }
                    let index = rounds[memberIndex][roundIndex]
                    if !member.2[index].isCycleCompleted {
                        return step(exerciseID: member.0, position: member.1, drafts: member.2,
                                    index: index, round: isWarmup ? nil : roundIndex + 1)
                    }
                }
            }
        }
        return nil
    }

    func restSeconds(afterCompletingSetAt index: Int, exerciseID: UUID) -> Int {
        guard exerciseID == firstExerciseID || exerciseID == secondExerciseID else { return 0 }
        let drafts = exerciseID == firstExerciseID ? firstDrafts : secondDrafts
        guard drafts.indices.contains(index), drafts[index].isCycleCompleted else { return 0 }
        let isWarmup = drafts[index].isWarmup
        let ownRounds = drafts.indices.filter { drafts[$0].isWarmup == isWarmup }
        guard let round = ownRounds.firstIndex(of: index) else { return 0 }
        let paired = exerciseID == firstExerciseID ? secondDrafts : firstDrafts
        let pairedRounds = paired.filter { $0.isWarmup == isWarmup }
        // Unequal set counts continue as solo rounds once the partner has no matching set.
        guard !pairedRounds.indices.contains(round) || pairedRounds[round].isCycleCompleted else { return 0 }
        return roundRestSeconds
    }

    func contains(sourceID: UUID?) -> Bool {
        guard let sourceID else { return false }
        return (firstDrafts + secondDrafts).contains { draft in
            draft.id == sourceID || draft.dropStages.contains { $0.id == sourceID }
        }
    }

    private var members: [(UUID, SupersetExercisePosition, [WorkoutSessionSetDraft])] {
        [(firstExerciseID, .first, firstDrafts), (secondExerciseID, .second, secondDrafts)]
    }

    private func step(exerciseID: UUID, position: SupersetExercisePosition,
                      drafts: [WorkoutSessionSetDraft], index: Int, round: Int?) -> Step {
        let draft = drafts[index]
        let drop = draft.isCompleted ? draft.dropStages.firstIndex(where: { !$0.isCompleted }).map { $0 + 1 } : nil
        return Step(exerciseID: exerciseID, setID: draft.id, position: position,
                    setLabel: WorkoutRestTimerContextBuilder.setLabel(for: index, in: drafts) ?? "Set",
                    round: round, nextDrop: drop)
    }
}

nonisolated struct WorkoutSupersetSetCue: Equatable, Sendable {
    let setID: UUID
    let text: String
}
