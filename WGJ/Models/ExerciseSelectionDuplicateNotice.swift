import Foundation

nonisolated struct ExerciseSelectionDuplicateNotice: Identifiable, Equatable, Sendable {
    nonisolated enum PresentationStyle: Equatable, Sendable {
        case transientBanner
    }

    nonisolated enum Destination: String, Equatable, Sendable {
        case activeWorkout
        case template

        var noun: String {
            switch self {
            case .activeWorkout:
                return "workout"
            case .template:
                return "template"
            }
        }
    }

    let id: String
    let title: String
    let message: String
    let presentationStyle: PresentationStyle

    init(exerciseName: String, destination: Destination) {
        let cleanExerciseName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanExerciseName.isEmpty ? "This exercise" : cleanExerciseName

        id = "\(destination.rawValue)-\(displayName)"
        title = "Exercise already added"
        message = "\(displayName) is already in this \(destination.noun)."
        presentationStyle = .transientBanner
    }
}

nonisolated enum ExercisePickerSelectionResult: Equatable, Sendable {
    case accepted
    case rejected(ExerciseSelectionDuplicateNotice)

    var shouldDismissPicker: Bool {
        switch self {
        case .accepted:
            return true
        case .rejected:
            return false
        }
    }

    var notice: ExerciseSelectionDuplicateNotice? {
        switch self {
        case .accepted:
            return nil
        case .rejected(let notice):
            return notice
        }
    }
}
