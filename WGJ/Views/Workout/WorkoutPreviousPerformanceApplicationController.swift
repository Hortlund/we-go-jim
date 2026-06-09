import Foundation

nonisolated enum WorkoutPreviousPerformanceApplicationMode: Equatable, Sendable {
    case overwriteExisting
    case fillMissing
}

nonisolated enum WorkoutPreviousPerformanceResolution: Equatable, Sendable {
    case loading
    case resolved([Int: WorkoutPreviousSetSnapshot])

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var previousBySetIndex: [Int: WorkoutPreviousSetSnapshot] {
        switch self {
        case .loading:
            return [:]
        case .resolved(let map):
            return map
        }
    }

    func previous(at index: Int) -> WorkoutPreviousSetSnapshot? {
        previousBySetIndex[index]
    }
}

nonisolated enum WorkoutSetPreviousPerformanceApplicationController {
    static func applyPreviousPerformance(
        to drafts: [WorkoutSessionSetDraft],
        at index: Int,
        previousResolution: WorkoutPreviousPerformanceResolution,
        mode: WorkoutPreviousPerformanceApplicationMode = .overwriteExisting
    ) -> [WorkoutSessionSetDraft]? {
        guard drafts.indices.contains(index),
              let previous = previousResolution.previous(at: index)
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
