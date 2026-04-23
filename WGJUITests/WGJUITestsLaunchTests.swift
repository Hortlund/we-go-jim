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
            "UITEST_ENABLE_ICLOUD",
        ]
        app.launch()

        let continueWithICloud = app.buttons["Continue with iCloud"]
        if continueWithICloud.waitForExistence(timeout: 10) {
            continueWithICloud.tap()
        } else if app.buttons["Continue Locally"].exists {
            XCTFail("Expected an iCloud-backed launch test, but the app only offered local mode.")
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
            "UITEST_ENABLE_ICLOUD",
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
