import XCTest

final class CaffeineCommandTests: XCTestCase {
    func testOnUsesDistinctDarwinNotification() {
        XCTAssertEqual(CaffeineCommand.notificationName(for: true), "com.kimiyashar.CaffeineToggle.turnOn")
    }

    func testOffUsesDistinctDarwinNotification() {
        XCTAssertEqual(CaffeineCommand.notificationName(for: false), "com.kimiyashar.CaffeineToggle.turnOff")
    }

    func testScheduleChangesUseDedicatedNotification() {
        XCTAssertEqual(CaffeineCommand.scheduleChangedNotification, "com.kimiyashar.CaffeineToggle.scheduleChanged")
    }

    func testSessionChangesUseDedicatedNotification() {
        XCTAssertEqual(CaffeineCommand.sessionChangedNotification, "com.kimiyashar.CaffeineToggle.sessionChanged")
    }

    func testScheduleWindowUsesDistinctDarwinNotification() {
        XCTAssertEqual(CaffeineCommand.showScheduleNotification, "com.kimiyashar.CaffeineToggle.showSchedule")
        XCTAssertEqual(CaffeineCommand.showScheduleRestoringOnNotification, "com.kimiyashar.CaffeineToggle.showScheduleRestoringOn")
        XCTAssertEqual(CaffeineCommand.showScheduleRestoringOffNotification, "com.kimiyashar.CaffeineToggle.showScheduleRestoringOff")
    }

    func testControlStateIdentifiersStayStableAcrossAppAndExtension() {
        XCTAssertEqual(CaffeineCommand.controlBundleIdentifier, "com.kimiyashar.CaffeineToggle.Controls")
        XCTAssertEqual(CaffeineCommand.controlKind, "com.kimiyashar.CaffeineToggle.control")
        XCTAssertEqual(CaffeineCommand.scheduleControlKind, "com.kimiyashar.CaffeineToggle.schedule")
        XCTAssertNotEqual(CaffeineCommand.scheduleControlKind, CaffeineCommand.controlKind)
        XCTAssertEqual(CaffeineCommand.requestStateNotification, "com.kimiyashar.CaffeineToggle.requestState")
        XCTAssertEqual(CaffeineCommand.stateIsOnNotification, "com.kimiyashar.CaffeineToggle.stateIsOn")
        XCTAssertEqual(CaffeineCommand.stateIsOffNotification, "com.kimiyashar.CaffeineToggle.stateIsOff")
    }
}
