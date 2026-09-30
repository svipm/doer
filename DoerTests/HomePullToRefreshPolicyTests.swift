import XCTest
@testable import Doer

final class HomePullToRefreshPolicyTests: XCTestCase {
    func testTriggersAtShorterReleaseDistance() {
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 55,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: false
            )
        )
        XCTAssertTrue(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 56,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: false
            )
        )
    }

    func testDoesNotTriggerWhileRefreshIsAlreadyRunning() {
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: true,
                isLoading: false,
                hasReloadTask: false
            )
        )
        // A load that never finished (hung DoH / offline) must stay replaceable, so
        // neither a pending load nor a live reload task blocks a pull.
        XCTAssertTrue(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: false,
                isLoading: true,
                hasReloadTask: false
            )
        )
        XCTAssertTrue(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: true
            )
        )
    }
}
