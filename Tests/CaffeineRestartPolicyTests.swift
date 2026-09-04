import XCTest

final class CaffeineRestartPolicyTests: XCTestCase {
    func testCapsRapidRestartAttemptsAndRecoversAfterWindow() {
        var policy = CaffeineRestartPolicy(maximumRestarts: 3, window: 60)
        let start = Date(timeIntervalSinceReferenceDate: 1000)

        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: start))
        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: start.addingTimeInterval(10)))
        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: start.addingTimeInterval(20)))
        XCTAssertFalse(policy.shouldRestart(afterUnexpectedExitAt: start.addingTimeInterval(30)))
        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: start.addingTimeInterval(91)))
    }

    func testResetClearsRecordedFailures() {
        var policy = CaffeineRestartPolicy(maximumRestarts: 1, window: 60)
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: now))
        XCTAssertFalse(policy.shouldRestart(afterUnexpectedExitAt: now.addingTimeInterval(1)))
        policy.reset()
        XCTAssertTrue(policy.shouldRestart(afterUnexpectedExitAt: now.addingTimeInterval(2)))
    }
}
