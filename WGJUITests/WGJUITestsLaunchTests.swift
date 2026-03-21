//
//  WGJUITestsLaunchTests.swift
//  WGJUITests
//
//  Created by Andreas Hortlund on 2026-02-06.
//

import XCTest

final class WGJUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
        ]
        app.launch()

        let continueLocally = app.buttons["Continue Locally"]
        if continueLocally.waitForExistence(timeout: 5) {
            continueLocally.tap()
        }

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Main Tabs"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchDirectEntryFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
            "UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue Locally"].exists)
        XCTAssertFalse(app.buttons["Continue with iCloud"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Direct Entry Main Tabs"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
