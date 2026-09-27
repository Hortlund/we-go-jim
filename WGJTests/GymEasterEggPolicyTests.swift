import XCTest
@testable import WGJ

@MainActor
final class GymEasterEggPolicyTests: XCTestCase {
    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    func testLogoRequiresSevenNearbyTapsAndResetsAfterAPause() {
        var progress = GymLogoTapProgress()
        let now = Date()
        for index in 0..<6 { XCTAssertFalse(progress.tap(at: now.addingTimeInterval(Double(index)))) }
        XCTAssertTrue(progress.tap(at: now.addingTimeInterval(6)))
        XCTAssertEqual(progress.count, 0)
        XCTAssertFalse(progress.tap(at: now.addingTimeInterval(7)))
        XCTAssertFalse(progress.tap(at: now.addingTimeInterval(20)))
        XCTAssertEqual(progress.count, 1)
    }

    func testSearchSecretsDoNotMatchRealExerciseNames() {
        XCTAssertTrue(GymEasterEggPolicy.searchMatches("  MOTIVATION \n"))
        XCTAssertTrue(GymEasterEggPolicy.searchMatches("excuses"))
        XCTAssertFalse(GymEasterEggPolicy.searchMatches("Motivation Press"))
        XCTAssertFalse(GymEasterEggPolicy.searchMatches(""))
    }

    func testCompletionSurprisesStayRareStableAndRelevant() {
        var normalCount = 0
        var weightCount = 0
        var legMessages: Set<String> = []
        var broMessages: Set<String> = []
        for value in 0..<200 {
            let sessionID = id(value)
            let ordinary = GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 6,
                hasWeightPR: false, isLegDay: false, gymBroMode: false)
            if ordinary != nil { normalCount += 1 }
            XCTAssertEqual(ordinary, GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 6,
                hasWeightPR: false, isLegDay: false, gymBroMode: false))
            XCTAssertNotEqual(ordinary, .lightWeight)
            let record = GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 6,
                hasWeightPR: true, isLegDay: false, gymBroMode: false)
            if record == .lightWeight { weightCount += 1 }
            if let legs = GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 6,
                hasWeightPR: false, isLegDay: true, gymBroMode: false), legs == .stairs || legs == .sitting {
                legMessages.insert(legs.message)
            }
            let bro = GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 6,
                hasWeightPR: false, isLegDay: false, gymBroMode: true)
            XCTAssertNotNil(bro)
            if let bro { broMessages.insert(bro.message) }
            XCTAssertNil(GymEasterEggPolicy.completion(sessionID: sessionID, workingSets: 0,
                hasWeightPR: true, isLegDay: true, gymBroMode: true))
        }
        XCTAssertTrue((20...60).contains(normalCount))
        XCTAssertTrue((30...70).contains(weightCount))
        XCTAssertEqual(legMessages.count, 2)
        XCTAssertEqual(broMessages.count, 5)
        XCTAssertFalse(broMessages.contains("See you next episode of we go jim."))
    }

    func testLegDayUsesPerformedMusclesRatherThanWorkoutNames() {
        XCTAssertFalse(GymEasterEggPolicy.isLegDay(scores: [:]))
        XCTAssertFalse(GymEasterEggPolicy.isLegDay(scores: [.chest: 8, .quadriceps: 2]))
        XCTAssertTrue(GymEasterEggPolicy.isLegDay(scores: [.hamstring: 3, .gluteal: 3, .chest: 2]))
    }

    func testRestSecretRequiresGenerousOverrunAndBelongsToCurrentWorkout() throws {
        let end = Date()
        let start = end.addingTimeInterval(-600)
        let eligible = try XCTUnwrap((0..<100).map(id).first { source in
            GymEasterEggPolicy.canRevealRest(completedRest: .init(endsAt: end, exerciseName: nil,
                setLabel: nil, sourceSetID: source), sessionStartedAt: start, now: end.addingTimeInterval(180))
        })
        let snapshot = RestTimerSnapshot(endsAt: end, exerciseName: nil, setLabel: nil, sourceSetID: eligible)
        XCTAssertFalse(GymEasterEggPolicy.canRevealRest(completedRest: snapshot, sessionStartedAt: start, now: end.addingTimeInterval(179)))
        XCTAssertTrue(GymEasterEggPolicy.canRevealRest(completedRest: snapshot, sessionStartedAt: start, now: end.addingTimeInterval(180)))
        XCTAssertFalse(GymEasterEggPolicy.canRevealRest(completedRest: snapshot, sessionStartedAt: start, now: end.addingTimeInterval(900)))
        XCTAssertFalse(GymEasterEggPolicy.canRevealRest(completedRest: snapshot, sessionStartedAt: end.addingTimeInterval(1), now: end.addingTimeInterval(180)))
    }

    func testExpiredRestMetadataClearsWithNextRestOrWorkout() {
        let state = RestTimerState()
        let snapshot = RestTimerSnapshot(endsAt: Date().addingTimeInterval(-200), exerciseName: "Bench Press",
            setLabel: "Set 2", sourceSetID: id(1))
        state.restoreRestTimer(from: snapshot)
        XCTAssertEqual(state.lastCompletedRest, snapshot)
        XCTAssertNil(state.restTimerEndsAt)
        state.startRestTimer(seconds: 60, exerciseName: "Bench Press", setLabel: nil, sourceSetID: id(2), schedulesExpirationTask: false)
        XCTAssertNil(state.lastCompletedRest)
        state.clearRestTimer()
        state.restoreRestTimer(from: snapshot)
        state.clearRestTimer()
        XCTAssertNil(state.lastCompletedRest)
        state.dismissRestTimerPopup()
    }
}
