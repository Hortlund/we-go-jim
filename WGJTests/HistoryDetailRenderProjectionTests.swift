import XCTest
@testable import WGJ

@MainActor
final class HistoryDetailRenderProjectionTests: XCTestCase {
    func testRowsPreserveSnapshotOrderAndStableExerciseIdentity() {
        let sessionID = UUID()
        let exercises = (0..<9).map { index in
            HistoryDetailSnapshotBuilder.ExerciseSnapshot(
                model: WorkoutSessionExercise(
                    sessionID: sessionID,
                    catalogExerciseUUID: "exercise-\(index)",
                    exerciseNameSnapshot: "Exercise \(index)",
                    categorySnapshot: "Strength",
                    muscleSummarySnapshot: "Mixed",
                    sortOrder: index
                )
            )
        }

        let projection = HistoryDetailRenderProjection(exercises: exercises)

        XCTAssertEqual(projection.exerciseRows.map(\.id), exercises.map(\.id))
        XCTAssertEqual(projection.exerciseRows.map(\.index), Array(0..<9))
    }

    func testEmptyProjectionHasNoRows() {
        XCTAssertEqual(HistoryDetailRenderProjection.empty.exerciseRows, [])
    }
}
