import XCTest

final class CaffeineDoubleClickTests: XCTestCase {
    func testSecondTapWithinWindowIsDoubleClick() {
        XCTAssertTrue(CaffeineDoubleClick.detect(previous: 100, current: 100.4))
    }

    func testFirstTapIsNotDoubleClick() {
        XCTAssertFalse(CaffeineDoubleClick.detect(previous: nil, current: 100))
    }

    func testSlowSecondTapIsNotDoubleClick() {
        XCTAssertFalse(CaffeineDoubleClick.detect(previous: 100, current: 100.8))
    }

    func testClockMovingBackwardIsNotDoubleClick() {
        XCTAssertFalse(CaffeineDoubleClick.detect(previous: 101, current: 100))
    }
}
