import XCTest
@testable import WGJ

final class WorkoutSessionExerciseGridProjectionTests: XCTestCase {
    func testProjectionBuildsStableRowsAndLookupIndexesInOnePass() {
        let warmupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let workingID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let thirdID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let dropID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let drafts = [
            WorkoutSessionSetDraft(id: warmupID, isWarmup: true),
            WorkoutSessionSetDraft(
                id: workingID,
                actualReps: 8,
                actualWeight: 100,
                isCompleted: true,
                dropStages: [WorkoutSessionDropStageDraft(id: dropID, isCompleted: true)]
            ),
            WorkoutSessionSetDraft(id: thirdID),
        ]

        let projection = WorkoutSessionExerciseGridProjectionBuilder.build(setDrafts: drafts)

        XCTAssertEqual(projection.indexBySetID[warmupID], 0)
        XCTAssertEqual(projection.indexBySetID[workingID], 1)
        XCTAssertEqual(
            projection.dropStageLocationByID[dropID],
            WorkoutDropStageLocation(setIndex: 1, stageIndex: 0)
        )
        XCTAssertEqual(projection.rows.map(\.id), [warmupID, workingID, thirdID])
        XCTAssertEqual(projection.completedSetCount, 1)

        var editedDrafts = drafts
        editedDrafts[1].actualWeight = 110
        let edited = WorkoutSessionExerciseGridProjectionBuilder.build(setDrafts: editedDrafts)
        XCTAssertEqual(edited.rows.map(\.id), projection.rows.map(\.id))
    }
}
