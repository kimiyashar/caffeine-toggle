import XCTest

final class ClamshellControllerTests: XCTestCase {
    func testCanDisableAndRestoreClamshellSleep() {
        XCTAssertEqual(ClamshellController.setSleepDisabled(true), kIOReturnSuccess)
        XCTAssertEqual(ClamshellController.setSleepDisabled(false), kIOReturnSuccess)
    }
}
