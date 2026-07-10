import Foundation

nonisolated struct HistoryDetailRenderProjection: Equatable, Sendable {
    nonisolated struct ExerciseRow: Identifiable, Equatable, Sendable {
        let id: UUID
        let index: Int
        let exercise: HistoryDetailSnapshotBuilder.ExerciseSnapshot
    }

    let exerciseRows: [ExerciseRow]

    static let empty = HistoryDetailRenderProjection(exerciseRows: [])

    init(exercises: [HistoryDetailSnapshotBuilder.ExerciseSnapshot]) {
        exerciseRows = exercises.enumerated().map { index, exercise in
            ExerciseRow(id: exercise.id, index: index, exercise: exercise)
        }
    }

    private init(exerciseRows: [ExerciseRow]) {
        self.exerciseRows = exerciseRows
    }
}
