struct CaffeineRGB {
    let red: Double
    let green: Double
    let blue: Double
}

enum CaffeineAppearance {
    static let latteBrown = CaffeineRGB(
        red: 0.788235294,
        green: 0.654901961,
        blue: 0.486274510
    )
    static let panelGray = CaffeineRGB(
        red: 0.93,
        green: 0.93,
        blue: 0.93
    )
    static let darkCoffeeBrown = CaffeineRGB(
        red: 0.435294118,
        green: 0.305882353,
        blue: 0.215686275
    )

    static func systemSymbolName(isCaffeinated: Bool) -> String {
        isCaffeinated ? "mug.fill" : "mug"
    }
}
