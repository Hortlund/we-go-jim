import XCTest
@testable import WGJ

@MainActor
final class WorkoutCompletionConfettiTests: XCTestCase {
    func testCompletedWorkoutCelebrationUsesSingleCentralThrowBurst() {
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: CGPoint(x: 200, y: 180),
            intensity: .completedWorkout
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.role, .centralThrow)
        XCTAssertEqual(bursts.first?.origin, CGPoint(x: 200, y: 180))
        XCTAssertEqual(bursts.first?.pieceCount, 34)
        XCTAssertEqual(bursts.first?.delay, 0)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.automaticCelebrationDelay, .milliseconds(180))
    }

    func testManualTapCelebrationUsesSingleUpwardBurst() {
        let origin = CGPoint(x: 120, y: 220)
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: origin,
            intensity: .manualTap
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.role, .centralThrow)
        XCTAssertEqual(bursts.first?.origin, origin)
        XCTAssertEqual(bursts.first?.pieceCount, 18)
    }

    func testAutomaticCelebrationHasVisibleFallbackOriginBeforeHeroLayout() {
        let origin = WorkoutCompletionConfettiOrigin.defaultOrigin(
            heroFrame: .zero,
            fallbackScreenWidth: 390
        )

        XCTAssertEqual(origin, CGPoint(x: 195, y: 220))
    }

    func testConfettiPiecesStartWideAndDriftSlowly() {
        let pieces = WorkoutCompletionConfettiPiece.random(
            seed: 42,
            role: .centralThrow,
            count: 38
        )

        XCTAssertEqual(pieces.count, 38)
        XCTAssertGreaterThanOrEqual(pieces.filter { $0.originX < -0.65 }.count, 8)
        XCTAssertGreaterThanOrEqual(pieces.filter { $0.originX > 0.65 }.count, 8)
        XCTAssertTrue(pieces.allSatisfy { abs($0.driftX) <= 0.27 })
        XCTAssertTrue(pieces.allSatisfy { $0.duration >= 4.2 && $0.duration <= 5.4 })
        XCTAssertTrue(pieces.allSatisfy { $0.delay >= 0 && $0.delay <= 0.14 })
    }

    func testConfettiPiecesAreVisibleOnFirstAnimationFrame() {
        let pieces = WorkoutCompletionConfettiPiece.random(
            seed: 42,
            role: .centralThrow,
            count: 38
        )

        XCTAssertGreaterThanOrEqual(pieces.filter { $0.progress(at: 1.0 / 30.0) > 0 }.count, 8)
    }

    func testConfettiMotionRisesQuicklyBeforeGentleFall() {
        let piece = WorkoutCompletionConfettiPiece.random(
            seed: 7,
            role: .centralThrow,
            count: 1
        )[0]

        XCTAssertLessThan(piece.yOffset(progress: 0.20), 0)
        XCTAssertLessThan(piece.yOffset(progress: 0.34), 0)
        XCTAssertGreaterThan(piece.yOffset(progress: 1.0), 0)
        XCTAssertEqual(piece.opacity(progress: 0.4), 1)
        XCTAssertLessThan(piece.opacity(progress: 0.95), 1)
    }

    func testConfettiScalesAcrossCompactAndLargeIPhones() {
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.initialSpreadX(for: 320), 112)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.initialSpreadY(for: 568), 42)

        XCTAssertEqual(WorkoutCompletionConfettiPolicy.initialSpreadX(for: 393), 133.62, accuracy: 0.01)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.initialSpreadY(for: 852), 59.64, accuracy: 0.01)

        XCTAssertEqual(WorkoutCompletionConfettiPolicy.initialSpreadX(for: 440), 149.6, accuracy: 0.01)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.horizontalMotionScale(for: 320), 320)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.horizontalMotionScale(for: 440), 440)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.verticalMotionScale(for: 568), 568)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.verticalMotionScale(for: 932), 680)
    }
}
