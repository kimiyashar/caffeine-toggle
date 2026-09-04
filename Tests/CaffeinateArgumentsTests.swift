import XCTest

final class CaffeinateArgumentsTests: XCTestCase {
    func testAssertionsEndWhenOwningHelperDies() {
        XCTAssertEqual(
            CaffeinateArguments.forHelper(pid: 4242),
            ["-d", "-i", "-m", "-s", "-w", "4242"]
        )
    }
}
