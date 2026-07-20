import XCTest
@testable import WGJ

final class WorkoutCardioTrackingTests: XCTestCase {
    func testRolesHaveStableSectionOrder() {
        XCTAssertEqual(WorkoutCardioRole.allCases.sorted { $0.sortOrder < $1.sortOrder }, [.warmUp, .main, .finisher])
    }

    func testDistanceConversionUsesMetersAsCanonicalStorage() {
        XCTAssertEqual(WorkoutDistanceUnit.kilometers.meters(from: 5), 5_000, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.miles.meters(from: 1), 1_609.344, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.meters.value(fromMeters: 500), 500, accuracy: 0.001)
    }

    func testWalkRunMetricsReturnPaceAndSpeed() throws {
        let result = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: 1_500,
            distanceMeters: 5_000,
            displayUnit: .kilometers,
            profile: .walkRun
        )
        XCTAssertEqual(try XCTUnwrap(result.paceSecondsPerDisplayUnit), 300, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.averageSpeedPerHour), 12, accuracy: 0.001)
        XCTAssertNil(result.rowingPaceSecondsPer500Meters)
    }

    func testRowingMetricsNormalizeToFiveHundredMeters() throws {
        let result = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: 480,
            distanceMeters: 2_000,
            displayUnit: .meters,
            profile: .rower
        )
        XCTAssertEqual(try XCTUnwrap(result.rowingPaceSecondsPer500Meters), 120, accuracy: 0.001)
    }

    func testMissingInputProducesNoDerivedMetrics() {
        XCTAssertEqual(
            WorkoutCardioMetricsCalculator.calculate(
                durationSeconds: 600,
                distanceMeters: nil,
                displayUnit: .kilometers,
                profile: .walkRun
            ),
            .empty
        )
    }
}
