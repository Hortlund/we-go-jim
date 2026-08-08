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

    func testHistoryBroadcastMarksDirtyAndReloadsOnlyWhenTabIsActive() {
        let inactive = HistoryRefreshRequestPolicy.workoutHistoryDidChange(
            isTabActive: false
        )
        let active = HistoryRefreshRequestPolicy.workoutHistoryDidChange(
            isTabActive: true
        )

        XCTAssertTrue(inactive.needsExplicitRefresh)
        XCTAssertFalse(inactive.shouldReload)
        XCTAssertTrue(active.needsExplicitRefresh)
        XCTAssertTrue(active.shouldReload)
    }
}
