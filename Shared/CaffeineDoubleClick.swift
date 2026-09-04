enum CaffeineDoubleClick {
    static let maximumInterval: Double = 0.55

    static func detect(previous: Double?, current: Double) -> Bool {
        guard let previous else { return false }
        let interval = current - previous
        return interval >= 0 && interval <= maximumInterval
    }
}
