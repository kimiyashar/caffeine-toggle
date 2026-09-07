import XCTest

final class CaffeineAppearanceTests: XCTestCase {
    func testDecaffeinatedUsesSupportedEmptyMugSymbol() {
        XCTAssertEqual(CaffeineAppearance.systemSymbolName(isCaffeinated: false), "mug")
    }

    func testCaffeinatedUsesSupportedFilledMugSymbol() {
        XCTAssertEqual(CaffeineAppearance.systemSymbolName(isCaffeinated: true), "mug.fill")
    }

    func testCaffeineToggleUsesLightLatteBrown() {
        XCTAssertEqual(CaffeineAppearance.latteBrown.red, 0.788235294, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.latteBrown.green, 0.654901961, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.latteBrown.blue, 0.486274510, accuracy: 0.000_000_001)
    }

    func testPanelUsesStableNeutralLightGray() {
        XCTAssertEqual(CaffeineAppearance.panelGray.red, 0.93, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.panelGray.green, 0.93, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.panelGray.blue, 0.93, accuracy: 0.000_000_001)
    }

    func testSelectedWeekdaysUseDarkCoffeeBrown() {
        XCTAssertEqual(CaffeineAppearance.darkCoffeeBrown.red, 0.435294118, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.darkCoffeeBrown.green, 0.305882353, accuracy: 0.000_000_001)
        XCTAssertEqual(CaffeineAppearance.darkCoffeeBrown.blue, 0.215686275, accuracy: 0.000_000_001)
    }
}
