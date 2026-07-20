import XCTest
@testable import WGJ

final class WorkoutCardioSetupTests: XCTestCase {
    func testTimeGoalRequiresPositiveDurationAndClearsDistance() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .warmUp,
            goalKind: .time,
            durationMinutesText: "10",
            distanceText: "5",
            distanceUnit: .kilometers,
            trackingProfile: .treadmill
        ))

        XCTAssertEqual(result.targetDurationSeconds, 600)
        XCTAssertNil(result.targetDistanceMeters)
    }

    func testDistanceGoalRequiresPositiveDistanceAndClearsDuration() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .main,
            goalKind: .distance,
            durationMinutesText: "10",
            distanceText: "5",
            distanceUnit: .kilometers,
            trackingProfile: .walkRun
        ))

        XCTAssertEqual(result.targetDurationSeconds, 0)
        XCTAssertEqual(result.targetDistanceMeters, 5_000)
    }

    func testOpenGoalClearsBothTargets() throws {
        let result = try WorkoutCardioSetupValidator.validated(.init(
            role: .finisher,
            goalKind: .open,
            durationMinutesText: "20",
            distanceText: "3.1",
            distanceUnit: .miles,
            trackingProfile: .machineDistance
        ))

        XCTAssertEqual(result.targetDurationSeconds, 0)
        XCTAssertNil(result.targetDistanceMeters)
        XCTAssertEqual(result.preferredDistanceUnit, .miles)
    }

    func testInvalidTimeGoalReturnsDurationInlineValidationError() {
        XCTAssertThrowsError(try WorkoutCardioSetupValidator.validated(.init(
            role: .warmUp,
            goalKind: .time,
            durationMinutesText: "0",
            distanceText: "",
            distanceUnit: .kilometers,
            trackingProfile: .timeOnly
        ))) { error in
            XCTAssertEqual(error as? WorkoutCardioSetupValidationError, .durationMustBePositive)
            XCTAssertEqual(error.localizedDescription, "Enter a duration greater than 0 minutes.")
        }
    }

    func testInvalidDistanceGoalReturnsDistanceInlineValidationError() {
        XCTAssertThrowsError(try WorkoutCardioSetupValidator.validated(.init(
            role: .main,
            goalKind: .distance,
            durationMinutesText: "",
            distanceText: "not a distance",
            distanceUnit: .meters,
            trackingProfile: .rower
        ))) { error in
            XCTAssertEqual(
                error as? WorkoutCardioSetupValidationError,
                .distanceMustBePositive(unit: .meters)
            )
            XCTAssertEqual(error.localizedDescription, "Enter a distance greater than 0 meters.")
        }
    }
}
