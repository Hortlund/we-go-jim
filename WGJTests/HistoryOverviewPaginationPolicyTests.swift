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
}
