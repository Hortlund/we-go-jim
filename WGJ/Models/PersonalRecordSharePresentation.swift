import Foundation

nonisolated struct WorkoutCompletionPersonalRecord: Identifiable, Equatable, Sendable {
    let id: String
    let exerciseName: String
    let performanceText: String
    let detailText: String
}

/// Deliberately contains only the selected achievement and its date.
nonisolated struct PersonalRecordSharePresentation: Identifiable, Equatable, Sendable {
    var id: String { record.id }
    let record: WorkoutCompletionPersonalRecord
    let achievedAtText: String
    var isMilestone: Bool = false
    var playfulTitle: String? = nil
}
