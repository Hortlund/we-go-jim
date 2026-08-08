import XCTest
@testable import WGJ

final class HistoryOverviewPaginationPolicyTests: XCTestCase {
    func testPaginationRequiresMorePagesAndNoActiveLoad() {
        XCTAssertTrue(HistoryPaginationRequestPolicy.shouldLoadMore(
            isLoading: false,
            hasMore: true
        ))
        XCTAssertFalse(HistoryPaginationRequestPolicy.shouldLoadMore(
            isLoading: true,
            hasMore: true
        ))
        XCTAssertFalse(HistoryPaginationRequestPolicy.shouldLoadMore(
            isLoading: false,
            hasMore: false
        ))
        XCTAssertFalse(HistoryPaginationRequestPolicy.shouldLoadMore(
            isLoading: true,
            hasMore: false
        ))
    }

    func testInactiveBroadcastInvalidatesActiveReloadAndKeepsSnapshotDirty() throws {
        var state = HistorySnapshotRefreshState()
        let initialRequest = try XCTUnwrap(state.beginReload(
            isTabActive: true,
            requiresActiveTab: true
        ))
        XCTAssertTrue(state.finishReload(initialRequest, isTabActive: true))
        XCTAssertFalse(state.needsExplicitRefresh)

        let staleRequest = try XCTUnwrap(state.beginReload(
            isTabActive: true,
            requiresActiveTab: true
        ))
        let scheduledTrigger = state.workoutHistoryDidChange(isTabActive: false)

        XCTAssertNil(scheduledTrigger)
        XCTAssertFalse(state.finishReload(staleRequest, isTabActive: true))
        XCTAssertTrue(state.needsExplicitRefresh)
    }

    func testScheduledBroadcastReloadCannotBeginAfterTabBecomesInactive() throws {
        var state = HistorySnapshotRefreshState()
        let initialRequest = try XCTUnwrap(state.beginReload(
            isTabActive: true,
            requiresActiveTab: true
        ))
        XCTAssertTrue(state.finishReload(initialRequest, isTabActive: true))
        XCTAssertFalse(state.needsExplicitRefresh)

        let scheduledTrigger = try XCTUnwrap(
            state.workoutHistoryDidChange(isTabActive: true)
        )
        let requestAfterLeavingTab = state.beginReload(
            triggeredBy: scheduledTrigger,
            isTabActive: false,
            requiresActiveTab: true
        )

        XCTAssertNil(requestAfterLeavingTab)
        XCTAssertTrue(state.needsExplicitRefresh)
    }

    func testBroadcastReloadThatStartsActiveCannotFinishAfterLeavingTab() throws {
        var state = HistorySnapshotRefreshState()
        let scheduledTrigger = try XCTUnwrap(
            state.workoutHistoryDidChange(isTabActive: true)
        )
        let activeRequest = try XCTUnwrap(state.beginReload(
            triggeredBy: scheduledTrigger,
            isTabActive: true,
            requiresActiveTab: true
        ))

        XCTAssertFalse(state.finishReload(activeRequest, isTabActive: false))
        XCTAssertTrue(state.needsExplicitRefresh)
    }
}
