import Foundation

enum WorkoutPreviousPerformanceApplicationMode: Equatable, Sendable {
    case overwriteExisting
    case fillMissing
}

enum WorkoutPreviousPerformanceResolution: Equatable, Sendable {
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

enum WorkoutSetBozarCompletionDecision: Equatable, Sendable {
    case waitForPreviousPerformance(setID: UUID)
    case completeImmediately([WorkoutSessionSetDraft])
}

enum WorkoutSetBozarCompletionController {
    static func decision(
        drafts: [WorkoutSessionSetDraft],
        at index: Int,
        previousResolution: WorkoutPreviousPerformanceResolution
    ) -> WorkoutSetBozarCompletionDecision? {
        guard drafts.indices.contains(index) else {
            return nil
        }

        switch previousResolution {
        case .loading:
            return .waitForPreviousPerformance(setID: drafts[index].id)
        case .resolved:
            let updatedDrafts = applyPreviousPerformance(
                to: drafts,
                at: index,
                previousResolution: previousResolution,
                mode: .fillMissing
            ) ?? drafts
            return .completeImmediately(updatedDrafts)
        }
    }

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
        updatedDrafts[index] = WorkoutSetBozarCompletionResolver.resolve(
            draft: updatedDrafts[index],
            previous: previous,
            mode: mode
        )
        return updatedDrafts
    }
}
