import XCTest
@testable import WGJ

@MainActor
final class WorkoutCompletionConfettiTests: XCTestCase {
    func testStandardCompletionUsesOneCenteredBoundedBurst() {
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: .overlayCenter,
            intensity: .completedWorkout,
            variant: .standard
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.role, .centralThrow)
        XCTAssertEqual(bursts.first?.origin, .overlayCenter)
        XCTAssertEqual(bursts.first?.pieceCount, 46)
        XCTAssertEqual(bursts.first?.variant, .standard)
        XCTAssertEqual(bursts.first?.delay, 0)
        XCTAssertEqual(WorkoutCompletionConfettiPolicy.automaticCelebrationDelay, .milliseconds(180))
    }

    func testPersonalRecordCompletionIsStrongerButBounded() {
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: .overlayCenter,
            intensity: .completedWorkout,
            variant: .personalRecord
        )

        XCTAssertEqual(bursts.count, 2)
        XCTAssertEqual(bursts.first?.pieceCount, 54)
        XCTAssertEqual(bursts.first?.variant, .personalRecord)
        XCTAssertEqual(bursts.last?.pieceCount, 24)
        XCTAssertEqual(bursts.last?.delay, 0.18)
        XCTAssertGreaterThan(
            WorkoutCompletionConfettiPolicy.colorRoles(for: .personalRecord).filter { $0 == .gold }.count,
            WorkoutCompletionConfettiPolicy.colorRoles(for: .standard).filter { $0 == .gold }.count
        )
    }

    func testManualReplayRetainsTapOriginAndLightCount() {
        let origin = CGPoint(x: 120, y: 220)
        let bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(
            origin: .global(origin),
            intensity: .manualTap,
            variant: .personalRecord
        )

        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts.first?.role, .centralThrow)
        XCTAssertEqual(bursts.first?.origin, .global(origin))
        XCTAssertEqual(bursts.first?.pieceCount, 22)
    }

    func testAutomaticOriginResolvesFromLiveOverlaySize() {
        XCTAssertEqual(
            WorkoutCompletionConfettiLaunchOrigin.overlayCenter.resolvedPoint(
                overlaySize: CGSize(width: 440, height: 880),
                overlayFrameInGlobalSpace: CGRect(x: 12, y: 48, width: 440, height: 880)
            ),
            CGPoint(x: 220, y: 440)
        )
        XCTAssertEqual(
            WorkoutCompletionConfettiLaunchOrigin.global(CGPoint(x: 212, y: 448)).resolvedPoint(
                overlaySize: CGSize(width: 390, height: 844),
                overlayFrameInGlobalSpace: CGRect(x: 12, y: 26, width: 390, height: 844)
            ),
            CGPoint(x: 200, y: 422)
        )
    }

    func testCompletionBackgroundWorkWaitsForCelebrationWindow() {
        XCTAssertEqual(WorkoutCompletionBackgroundWorkPolicy.quiescenceDelay, .seconds(7))
        XCTAssertEqual(
            BoundaryCloudBackupScheduler.enqueueDelay(for: .workoutCompleted),
            WorkoutCompletionBackgroundWorkPolicy.quiescenceDelay
        )
    }

    func testReducedMotionUsesStaticPresentationWithoutParticles() {
        let reduced = WorkoutCompletionCelebrationPresentation.make(
            variant: .standard,
            reduceMotion: true
        )
        let personalRecord = WorkoutCompletionCelebrationPresentation.make(
            variant: .personalRecord,
            reduceMotion: false
        )

        XCTAssertFalse(reduced.showsConfetti)
        XCTAssertEqual(reduced.initialHeroScale, 1)
        XCTAssertEqual(reduced.initialIconScale, 1)
        XCTAssertEqual(reduced.peakIconScale, 1)
        XCTAssertEqual(reduced.peakGlowOpacity, reduced.settledGlowOpacity)

        XCTAssertTrue(personalRecord.showsConfetti)
        XCTAssertEqual(personalRecord.initialHeroScale, 0.96)
        XCTAssertLessThan(personalRecord.initialIconScale, 1)
        XCTAssertGreaterThan(personalRecord.peakIconScale, 1)
        XCTAssertGreaterThan(personalRecord.peakGlowOpacity, personalRecord.settledGlowOpacity)
    }

    func testCelebrationPhaseProjectsOneHeroChoreography() {
        let presentation = WorkoutCompletionCelebrationPresentation.make(
            variant: .personalRecord,
            reduceMotion: false
        )

        XCTAssertEqual(WorkoutCompletionCelebrationPhase.prepared.heroScale(using: presentation), 0.96)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.peak.iconScale(using: presentation), 1.18)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.peak.glowOpacity(using: presentation), 0.46)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.heroScale(using: presentation), 1)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.iconScale(using: presentation), 1)
        XCTAssertEqual(WorkoutCompletionCelebrationPhase.settled.glowOpacity(using: presentation), 0.18)
    }

    func testCelebrationStartRechecksReducedMotion() {
        XCTAssertEqual(
            WorkoutCompletionCelebrationPhase.startingPhase(reduceMotion: false),
            .peak
        )
        XCTAssertEqual(
            WorkoutCompletionCelebrationPhase.startingPhase(reduceMotion: true),
            .settled
        )
    }

    func testConfettiPiecesStartWideAndDriftSlowly() {
        let pieces = WorkoutCompletionConfettiPiece.random(
            seed: 42,
            role: .centralThrow,
            count: 38,
            variant: .standard
        )

        XCTAssertEqual(pieces.count, 38)
        XCTAssertGreaterThanOrEqual(pieces.filter { $0.originX < -0.65 }.count, 8)
        XCTAssertGreaterThanOrEqual(pieces.filter { $0.originX > 0.65 }.count, 8)
        XCTAssertTrue(pieces.allSatisfy { abs($0.driftX) <= 0.27 })
        XCTAssertTrue(pieces.allSatisfy { $0.launchHeight >= 0.30 && $0.launchHeight <= 0.50 })
        XCTAssertTrue(pieces.allSatisfy { $0.duration >= 4.2 && $0.duration <= 5.4 })
        XCTAssertTrue(pieces.allSatisfy { $0.delay >= 0 && $0.delay <= 0.14 })
    }

    func testConfettiPiecesAreVisibleOnFirstAnimationFrame() {
        let pieces = WorkoutCompletionConfettiPiece.random(
            seed: 42,
            role: .centralThrow,
            count: 38,
            variant: .standard
        )

        XCTAssertGreaterThanOrEqual(pieces.filter { $0.progress(at: 1.0 / 30.0) > 0 }.count, 8)
    }

    func testConfettiMotionRisesQuicklyBeforeGentleFall() {
        let piece = WorkoutCompletionConfettiPiece.random(
            seed: 7,
            role: .centralThrow,
            count: 1,
            variant: .standard
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
