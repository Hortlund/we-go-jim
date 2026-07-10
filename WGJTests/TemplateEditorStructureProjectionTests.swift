import XCTest
@testable import WGJ

final class TemplateEditorStructureProjectionTests: XCTestCase {
    func testProjectionBuildsOrderedSupersetMetadataInOnePass() {
        let groupID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let inputs = [
            TemplateEditorStructureProjection.Input(
                id: firstID,
                exerciseName: "Bench Press",
                superset: ExerciseSupersetMembershipDraft(
                    groupID: groupID,
                    position: .first,
                    roundRestSeconds: 75
                )
            ),
            TemplateEditorStructureProjection.Input(
                id: secondID,
                exerciseName: "Row",
                superset: ExerciseSupersetMembershipDraft(
                    groupID: groupID,
                    position: .second,
                    roundRestSeconds: 75
                )
            ),
            TemplateEditorStructureProjection.Input(
                id: thirdID,
                exerciseName: "Squat",
                superset: nil
            ),
        ]

        let projection = TemplateEditorStructureProjection.make(inputs: inputs)

        XCTAssertEqual(projection.presentationByExerciseID[firstID]?.label, "A1")
        XCTAssertEqual(projection.presentationByExerciseID[firstID]?.pairedExerciseName, "Row")
        XCTAssertEqual(projection.presentationByExerciseID[secondID]?.label, "A2")
        XCTAssertEqual(projection.presentationByExerciseID[secondID]?.pairedExerciseName, "Bench Press")
        XCTAssertNil(projection.presentationByExerciseID[thirdID])
    }

    func testProjectionLabelsGroupsByFirstAppearance() {
        let groupA = UUID()
        let groupB = UUID()
        let inputs = [
            input(name: "A1", groupID: groupA, position: .first),
            input(name: "A2", groupID: groupA, position: .second),
            input(name: "B1", groupID: groupB, position: .first),
            input(name: "B2", groupID: groupB, position: .second),
        ]

        let projection = TemplateEditorStructureProjection.make(inputs: inputs)

        XCTAssertEqual(projection.presentationByExerciseID[inputs[0].id]?.label, "A1")
        XCTAssertEqual(projection.presentationByExerciseID[inputs[2].id]?.label, "B1")
    }

    private func input(
        name: String,
        groupID: UUID,
        position: SupersetExercisePosition
    ) -> TemplateEditorStructureProjection.Input {
        TemplateEditorStructureProjection.Input(
            id: UUID(),
            exerciseName: name,
            superset: ExerciseSupersetMembershipDraft(
                groupID: groupID,
                position: position,
                roundRestSeconds: 90
            )
        )
    }
}
