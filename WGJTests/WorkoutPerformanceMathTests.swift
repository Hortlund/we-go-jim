import XCTest
@testable import WGJ

final class WorkoutPerformanceMathTests: XCTestCase {
    func testEstimatedOneRepMaxUsesEpleyFormula() {
        XCTAssertEqual(
            WorkoutPerformanceMath.estimatedOneRepMax(weight: 100, reps: 5),
            116.666_666_666_7,
            accuracy: 0.000_001
        )
    }

    func testEstimatedOneRepMaxKeepsSingleRepWeight() {
        XCTAssertEqual(
            WorkoutPerformanceMath.estimatedOneRepMax(weight: 100, reps: 1),
            100
        )
    }

    func testNormalizedLoadConvertsPoundsToKilograms() {
        XCTAssertEqual(
            WorkoutPerformanceMath.normalizedLoadInKilograms(220.462_262, unit: .lb),
            100,
            accuracy: 0.000_1
        )
    }

    func testWeightedVolumeNormalizesBeforeMultiplyingRepetitions() {
        XCTAssertEqual(
            WorkoutPerformanceMath.weightedVolumeInKilograms(
                weight: 220.462_262,
                reps: 5,
                unit: .lb
            ),
            500,
            accuracy: 0.001
        )
    }

    func testWeightedVolumeDoesNotProduceNegativeWork() {
        XCTAssertEqual(
            WorkoutPerformanceMath.weightedVolumeInKilograms(
                weight: 100,
                reps: -5,
                unit: .kg
            ),
            0
        )
    }

    func testWeightedVolumeDoesNotFabricateBodyweightLoad() {
        XCTAssertEqual(
            WorkoutPerformanceMath.weightedVolumeInKilograms(
                weight: 100,
                reps: 5,
                unit: .bodyweight
            ),
            0
        )
    }
}
