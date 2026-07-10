import XCTest
@testable import WGJ

final class WindowGeometryPolicyTests: XCTestCase {
    func testKeyboardOverlapUsesActualContainerFrame() {
        let container = CGRect(x: 512, y: 0, width: 512, height: 768)
        let keyboard = CGRect(x: 0, y: 468, width: 1024, height: 300)

        XCTAssertEqual(
            WGJKeyboardGeometry.bottomOverlap(
                keyboardEndFrame: keyboard,
                containerFrame: container
            ),
            300
        )
    }

    func testFloatingKeyboardDoesNotCreateBottomOverlap() {
        let container = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let keyboard = CGRect(x: 300, y: 300, width: 400, height: 250)

        XCTAssertEqual(
            WGJKeyboardGeometry.bottomOverlap(
                keyboardEndFrame: keyboard,
                containerFrame: container
            ),
            0
        )
    }

    func testKeyboardOutsideSplitContainerDoesNotOverlap() {
        let container = CGRect(x: 0, y: 0, width: 507, height: 768)
        let keyboard = CGRect(x: 520, y: 468, width: 504, height: 300)

        XCTAssertEqual(
            WGJKeyboardGeometry.bottomOverlap(
                keyboardEndFrame: keyboard,
                containerFrame: container
            ),
            0
        )
    }
}
