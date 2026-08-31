import XCTest

final class CaffeineAppearanceTests: XCTestCase {
    func testDecaffeinatedUsesSupportedEmptyMugSymbol() {
        XCTAssertEqual(CaffeineAppearance.systemSymbolName(isCaffeinated: false), "mug")
    }

    func testCaffeinatedUsesSupportedFilledMugSymbol() {
        XCTAssertEqual(CaffeineAppearance.systemSymbolName(isCaffeinated: true), "mug.fill")
    }
}
