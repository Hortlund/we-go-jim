import XCTest
@testable import WGJ

@MainActor
final class CloudBackupBannerPresentationTests: XCTestCase {
    func testFastCheckAndBackupDoNotFlashActivityOrSuccess() async throws {
        let presentation = CloudBackupBannerPresentation(delay: .milliseconds(50))
        presentation.update(input(.checking))
        presentation.update(input(.pending, operationID: UUID()))
        presentation.update(input(.backedUp))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(presentation.showsActivity)
        XCTAssertNil(presentation.status)
    }

    func testSlowActivitySurvivesStageChangesAndShowsCompletion() async throws {
        let presentation = CloudBackupBannerPresentation(delay: .milliseconds(50))
        presentation.update(input(.checking))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(presentation.showsActivity)
        presentation.update(input(.pending, operationID: UUID()))
        XCTAssertTrue(presentation.showsActivity)
        XCTAssertEqual(presentation.status?.state, .pending)
        presentation.update(input(.backedUp))
        XCTAssertFalse(presentation.showsActivity)
        XCTAssertEqual(presentation.status?.state, .backedUp)
        presentation.reset()
    }

    func testFastFailureStillAppearsAndCancelledRevealCannotReplaceIt() async throws {
        let presentation = CloudBackupBannerPresentation(delay: .milliseconds(50))
        presentation.update(input(.checking))
        presentation.update(input(.checkFailed))
        XCTAssertEqual(presentation.status?.state, .checkFailed)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(presentation.showsActivity)
        XCTAssertEqual(presentation.status?.state, .checkFailed)
        presentation.reset()
    }

    func testSheetCancelsPendingBannerAndDoesNotRepeatSuccessAfterDismissal() async throws {
        let presentation = CloudBackupBannerPresentation(delay: .milliseconds(50))
        let operationID = UUID()
        presentation.update(input(.pending, operationID: operationID))
        presentation.update(input(.pending, operationID: operationID, sheet: true))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(presentation.showsActivity)
        XCTAssertNil(presentation.status)
        presentation.update(input(.backedUp, sheet: true))
        presentation.update(input(.backedUp))
        XCTAssertNil(presentation.status)
    }

    private func input(_ state: UserDataSyncStateKind, operationID: UUID? = nil, sheet: Bool = false) -> CloudBackupBannerPresentation.Input {
        .init(status: .init(state: state, title: "Status", detail: "", latestLocalMutationAt: nil,
                            latestSuccessfulExportAt: nil, latestErrorDescription: nil),
              operationID: operationID, isSheetPresented: sheet)
    }
}
