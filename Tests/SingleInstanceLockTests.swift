import XCTest

final class SingleInstanceLockTests: XCTestCase {
    func testOnlyOneOwnerCanHoldLockAndItReleasesOnDeinit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("helper.lock").path

        var first: SingleInstanceLock? = SingleInstanceLock(path: path)
        XCTAssertNotNil(first)
        XCTAssertNil(SingleInstanceLock(path: path))

        first = nil
        XCTAssertNotNil(SingleInstanceLock(path: path))
    }
}
