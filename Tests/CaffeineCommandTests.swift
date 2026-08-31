import XCTest

final class CaffeineCommandTests: XCTestCase {
    func testOnUsesDistinctDarwinNotification() {
        XCTAssertEqual(CaffeineCommand.notificationName(for: true), "com.kimiyashar.CaffeineToggle.turnOn")
    }

    func testOffUsesDistinctDarwinNotification() {
        XCTAssertEqual(CaffeineCommand.notificationName(for: false), "com.kimiyashar.CaffeineToggle.turnOff")
    }
}
