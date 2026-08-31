enum CaffeineAppearance {
    static func systemSymbolName(isCaffeinated: Bool) -> String {
        isCaffeinated ? "mug.fill" : "mug"
    }
}
