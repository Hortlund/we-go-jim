import XCTest
@testable import WGJ

final class CardioActivityQuickPickerTests: XCTestCase {
    func testQuickChoicesUseStablePromotedOrder() {
        XCTAssertEqual(CardioActivityQuickChoice.all.map(\.remoteUUID), [
            "seed-treadmill-walk", "seed-treadmill-run", "seed-outdoor-walk", "seed-outdoor-run",
            "seed-bike", "seed-crosstrainer", "seed-row-machine", "seed-stair-climber",
        ])
    }

    func testQuickChoicesCarryExpectedTrackingProfiles() {
        XCTAssertEqual(CardioActivityQuickChoice.all.map(\.trackingProfile), [
            .treadmill, .treadmill, .walkRun, .walkRun,
            .machineDistance, .machineDistance, .rower, .stairClimber,
        ])
    }

    func testInclineWalkRemainsOutsidePromotedChoices() {
        XCTAssertFalse(CardioActivityQuickChoice.all.contains {
            $0.remoteUUID == "seed-incline-treadmill-walk"
        })
    }
}
