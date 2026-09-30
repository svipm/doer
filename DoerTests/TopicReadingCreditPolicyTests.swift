import XCTest
@testable import Doer

@MainActor
final class TopicReadingCreditPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func shouldCredit(
        mode: ReadingTimingReportMode,
        idleFor seconds: TimeInterval,
        isAppActive: Bool = true
    ) -> Bool {
        TopicReadingCreditPolicy.shouldCreditTime(
            mode: mode,
            now: now,
            lastInteraction: now.addingTimeInterval(-seconds),
            isAppActive: isAppActive
        )
    }

    func testCreditsWhileThePageIsBeingUsed() {
        XCTAssertTrue(shouldCredit(mode: .realtime, idleFor: 0))
        XCTAssertTrue(shouldCredit(mode: .batched, idleFor: 0))
        XCTAssertTrue(shouldCredit(mode: .realtime, idleFor: 60))
    }

    func testStopsCreditingOnceThePageHasBeenIdle() {
        // Discourse's PAUSE_UNLESS_SCROLLED: three minutes without scrolling.
        XCTAssertTrue(shouldCredit(mode: .realtime, idleFor: 3 * 60))
        XCTAssertFalse(shouldCredit(mode: .realtime, idleFor: 3 * 60 + 1))
        XCTAssertFalse(shouldCredit(mode: .batched, idleFor: 30 * 60))
    }

    func testStopsCreditingWhenTheAppIsNotActive() {
        XCTAssertFalse(shouldCredit(mode: .realtime, idleFor: 0, isAppActive: false))
        XCTAssertFalse(shouldCredit(mode: .batched, idleFor: 0, isAppActive: false))
    }

    func testNeverCreditsWhenReportingIsOff() {
        XCTAssertFalse(shouldCredit(mode: .off, idleFor: 0))
        XCTAssertFalse(shouldCredit(mode: .off, idleFor: 0, isAppActive: false))
    }
}
