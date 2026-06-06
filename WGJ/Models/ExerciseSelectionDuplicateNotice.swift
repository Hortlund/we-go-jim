import Foundation

struct ExerciseSelectionDuplicateNotice: Identifiable, Equatable {
    enum Destination: String, Equatable {
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

    init(exerciseName: String, destination: Destination) {
        let cleanExerciseName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanExerciseName.isEmpty ? "This exercise" : cleanExerciseName

        id = "\(destination.rawValue)-\(displayName)"
        title = "Exercise already added"
        message = "\(displayName) is already in this \(destination.noun)."
    }
}
