import XCTest

final class CloudBackupProgressUITests: XCTestCase {
    @MainActor
    func testRestoreRetryReplacesVisibleErrorAndDisablesDismissalAgain() {
        let app = launch("RETRY")
        let title = app.staticTexts["Restoring from iCloud"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Restore stopped"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["cloud-backup-progress-done"].exists)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Restoring your data…"].exists)
        XCTAssertFalse(app.buttons["cloud-backup-progress-done"].exists)
        title.swipeDown()
        XCTAssertTrue(title.exists)
        XCTAssertTrue(app.staticTexts["Restore complete"].waitForExistence(timeout: 20))
        app.buttons["cloud-backup-progress-done"].tap()
    }

    @MainActor
    func testRestoreShowsCountsBlocksSwipeDismissalAndKeepsCompletion() {
        let app = launch("RESTORE")
        let title = app.staticTexts["Restoring from iCloud"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["50 of 200 backup parts"].exists)
        XCTAssertTrue(app.staticTexts["Please keep WGJ open until this finishes. Large backups can take a few minutes."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Restore progress"
        attachment.lifetime = .keepAlways
        add(attachment)
        title.swipeDown()
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["cloud-backup-progress-done"].exists)
        XCTAssertTrue(app.staticTexts["Restore complete"].waitForExistence(timeout: 20))
        let done = app.buttons["cloud-backup-progress-done"]
        XCTAssertGreaterThan(done.frame.width, app.frame.width * 0.75)
        let completion = XCTAttachment(screenshot: app.screenshot())
        completion.name = "Restore complete polished"
        completion.lifetime = .keepAlways
        add(completion)
        done.tap()
        XCTAssertFalse(app.staticTexts["Restore complete"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testRestoreFailureStopsActivityAndCanBeDismissed() {
        let app = launch("FAILURE")
        XCTAssertTrue(app.staticTexts["Restoring from iCloud"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Restore stopped"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["The connection was interrupted. Check your connection and try again."].exists)
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
        app.buttons["cloud-backup-progress-done"].tap()
    }

    @MainActor
    func testAutomaticBackupStaysInBanner() {
        let app = launch("AUTOMATIC")
        XCTAssertTrue(app.staticTexts["Backing up to iCloud"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["cloud-backup-status-banner"].exists)
        XCTAssertFalse(app.staticTexts["Please keep WGJ open until this finishes. Large backups can take a few minutes."].exists)
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Automatic backup banner"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SKIP_SPLASH", "UITEST_IN_MEMORY_STORE", "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT", "UITEST_BACKUP_PROGRESS_\(scenario)"]
        app.launch()
        let continueLocally = app.buttons["Continue Locally"].firstMatch
        XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
        continueLocally.tap()
        return app
    }
}
