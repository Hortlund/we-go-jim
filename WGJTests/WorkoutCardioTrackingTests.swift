import XCTest
@testable import WGJ

final class WorkoutCardioTrackingTests: XCTestCase {
    func testNonFiniteDistancesDoNotProduceMetrics() {
        for distance in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(WorkoutCardioMetricsCalculator.calculate(
                durationSeconds: 600, distanceMeters: distance,
                displayUnit: .kilometers, profile: .walkRun
            ), .empty)
        }
    }

    func testExtremeDistancesDoNotProduceUnrepresentablePacesOrSpeeds() {
        for distance in [Double.leastNonzeroMagnitude, 1e-20, Double.greatestFiniteMagnitude] {
            for profile in [WorkoutCardioTrackingProfile.walkRun, .rower, .machineDistance] {
                let result = WorkoutCardioMetricsCalculator.calculate(
                    durationSeconds: 600, distanceMeters: distance,
                    displayUnit: .kilometers, profile: profile
                )
                for pace in [result.paceSecondsPerDisplayUnit, result.rowingPaceSecondsPer500Meters].compactMap({ $0 }) {
                    XCTAssertNotNil(Int(exactly: pace.rounded()))
                }
                if let speed = result.averageSpeedPerHour {
                    XCTAssertTrue(speed.isFinite)
                    XCTAssertGreaterThan(speed, 0)
                }
            }
        }
    }

    func testRolesHaveStableSectionOrder() {
        XCTAssertEqual(WorkoutCardioRole.allCases.sorted { $0.sortOrder < $1.sortOrder }, [.warmUp, .main, .finisher])
    }

    func testDistanceConversionUsesMetersAsCanonicalStorage() {
        XCTAssertEqual(WorkoutDistanceUnit.kilometers.meters(from: 5), 5_000, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.miles.meters(from: 1), 1_609.344, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.meters.value(fromMeters: 500), 500, accuracy: 0.001)
    }

    func testRegionalDistanceDefaultsUseLocaleMeasurementSystems() {
        XCTAssertEqual(WorkoutDistanceUnit.regionalDefault(locale: Locale(identifier: "en_US")), .miles)
        XCTAssertEqual(WorkoutDistanceUnit.regionalDefault(locale: Locale(identifier: "en_GB")), .miles)
        XCTAssertEqual(WorkoutDistanceUnit.regionalDefault(locale: Locale(identifier: "sv_SE")), .kilometers)
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
