import Foundation

nonisolated enum WorkoutPreviousPerformanceApplicationMode: Equatable, Sendable {
    case overwriteExisting
    case fillMissing
}

nonisolated enum WorkoutPreviousPerformanceResolution: Equatable, Sendable {
    case loading
    case resolved([Int: WorkoutPreviousSetSnapshot])
    case noTemplateHistory(WorkoutPreviousWorkoutSource?)
    indirect case remappable(WorkoutPreviousPerformanceResolution, WorkoutPreviousPerformanceHistory)

    func remapped(to drafts: [WorkoutSessionSetDraft]) -> WorkoutPreviousPerformanceResolution {
        guard case .remappable(let initial, let history) = self else { return self }
        let flags = drafts.map(\.isWarmup)
        return flags == history.initialWarmupFlags ? initial : history.resolve(warmupFlags: flags)
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var previousBySetIndex: [Int: WorkoutPreviousSetSnapshot] {
        switch self {
        case .loading, .noTemplateHistory:
            return [:]
        case .resolved(let map):
            return map
        case .remappable(let initial, _):
            return initial.previousBySetIndex
        }
    }

    func previous(at index: Int) -> WorkoutPreviousSetSnapshot? {
        previousBySetIndex[index]
    }
}

nonisolated enum WorkoutSetPreviousPerformanceApplicationController {
    static func copyOtherWorkout(_ source: WorkoutPreviousWorkoutSource, to drafts: [WorkoutSessionSetDraft]) -> [WorkoutSessionSetDraft] {
        drafts.enumerated().map { index, draft in
            guard !draft.isCompleted, !draft.isLocked else { return draft }
            return draft.applyingPreviousPerformance(source.sets[index], mode: .fillMissing)
        }
    }

    static func applyPreviousPerformance(
        to drafts: [WorkoutSessionSetDraft],
        at index: Int,
        previousResolution: WorkoutPreviousPerformanceResolution,
        mode: WorkoutPreviousPerformanceApplicationMode = .fillMissing
    ) -> [WorkoutSessionSetDraft]? {
        guard drafts.indices.contains(index),
              let previous = previousResolution.remapped(to: drafts).previous(at: index)
        else {
            return nil
        }

        var updatedDrafts = drafts
        updatedDrafts[index] = WorkoutSetPreviousPerformanceApplicationResolver.resolve(
            draft: updatedDrafts[index],
            previous: previous,
            mode: mode
        )
        return updatedDrafts
    }
}
