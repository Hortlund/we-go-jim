import XCTest
@testable import WGJ

final class WorkoutSupersetProgressionTests: XCTestCase {
    private let firstID = UUID()
    private let secondID = UUID()

    func testAlternatesMatchingSetsAndRestsOnlyAfterTheRound() {
        var first = [set(), set()]
        var second = [set(), set()]
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[0].id)
        first[0].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[0].id)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 0)
        second[0].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[1].id)
        XCTAssertEqual(plan(first, second).nextStep?.round, 2)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: secondID), 75)
        first[1].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[1].id)
        second[1].isCompleted = true
        XCTAssertNil(plan(first, second).nextStep)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: secondID), 75)
    }

    func testOutOfOrderCompletionWaitsForBothExercisesBeforeRest() {
        var first = [set()]
        let second = [set(completed: true)]
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[0].id)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: secondID), 0)
        first[0].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 75)
    }

    func testDropsMustAllFinishBeforeMovingToPartnerOrResting() {
        var first = [set(completed: true)]
        first[0].dropStages = [WorkoutSessionDropStageDraft(), WorkoutSessionDropStageDraft(isCompleted: true)]
        let second = [set(completed: true)]
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[0].id)
        XCTAssertEqual(plan(first, second).nextStep?.nextDrop, 1)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 0)
        first[0].dropStages[0].isCompleted = true
        XCTAssertNil(plan(first, second).nextStep)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 75)
        XCTAssertTrue(plan(first, second).contains(sourceID: first[0].dropStages[0].id))
        XCTAssertFalse(plan(first, second).contains(sourceID: UUID()))
    }

    func testWarmupsAlternateAndRestOnlyAfterTheirPairedRound() {
        var first = [set(warmup: true), set(warmup: true), set()]
        var second = [set(warmup: true), set(warmup: true), set()]
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[0].id)
        XCTAssertNil(plan(first, second).nextStep?.round)
        first[0].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[0].id)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 0)
        second[0].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: secondID), 75)
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[1].id)
        first[1].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[1].id)
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: firstID), 0)
        second[1].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: secondID), 75)
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[2].id)
        XCTAssertEqual(plan(first, second).nextStep?.round, 1)
    }

    func testUnequalWarmupsDoNotOffsetWorkingRounds() {
        var first = [set(warmup: true), set()]
        var second = [set(warmup: true), set(warmup: true), set()]
        XCTAssertNil(plan(first, second).nextStep?.round)
        first[0].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: firstID), 0)
        second[0].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 0, exerciseID: secondID), 75)
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[1].id)
        second[1].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: secondID), 75)
        first[1].isCompleted = true
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[2].id)
        XCTAssertEqual(plan(first, second).nextStep?.round, 1)
        XCTAssertEqual(plan(first, second).nextStep?.setLabel, "Working Set 1")
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: firstID), 0)
    }

    func testUnequalCountsContinueRemainingSetsAndRestAfterSoloRounds() {
        let first = [set(completed: true)]
        var second = [set(completed: true), set()]
        XCTAssertEqual(plan(first, second).nextStep?.setID, second[1].id)
        second[1].isCompleted = true
        XCTAssertEqual(plan(first, second).restSeconds(afterCompletingSetAt: 1, exerciseID: secondID), 75)
        XCTAssertNil(plan(first, second).nextStep)
        XCTAssertNil(plan([], []).nextStep)
    }

    func testResumeAndUndoRecomputeNextStepFromPersistedDrafts() throws {
        var first = [set(completed: true), set()]
        let second = [set(completed: true), set()]
        let decoded = try JSONDecoder().decode([WorkoutSessionSetDraft].self, from: JSONEncoder().encode(first))
        XCTAssertEqual(plan(decoded, second).nextStep?.setID, first[1].id)
        first[0].isCompleted = false
        XCTAssertEqual(plan(first, second).nextStep?.setID, first[0].id)
    }

    func testSetScrollTargetRoundTripsForWorkoutResume() throws {
        let original = ActiveWorkoutScrollTarget.set(UUID())
        XCTAssertEqual(try JSONDecoder().decode(ActiveWorkoutScrollTarget.self,
            from: JSONEncoder().encode(original)), original)
    }

    private func plan(_ first: [WorkoutSessionSetDraft], _ second: [WorkoutSessionSetDraft]) -> WorkoutSupersetProgression {
        WorkoutSupersetProgression(firstExerciseID: firstID, secondExerciseID: secondID,
            firstDrafts: first, secondDrafts: second, roundRestSeconds: 75)
    }

    private func set(warmup: Bool = false, completed: Bool = false) -> WorkoutSessionSetDraft {
        WorkoutSessionSetDraft(isWarmup: warmup, actualReps: 8, actualWeight: 40, isCompleted: completed)
    }
}
