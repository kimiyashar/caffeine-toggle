import Foundation

struct CaffeineRestartPolicy {
    let maximumRestarts: Int
    let window: TimeInterval
    private var unexpectedExits: [Date] = []

    init(maximumRestarts: Int = 3, window: TimeInterval = 60) {
        self.maximumRestarts = maximumRestarts
        self.window = window
    }

    mutating func shouldRestart(afterUnexpectedExitAt date: Date = Date()) -> Bool {
        unexpectedExits.removeAll { date.timeIntervalSince($0) > window }
        unexpectedExits.append(date)
        return unexpectedExits.count <= maximumRestarts
    }

    mutating func reset() {
        unexpectedExits.removeAll()
    }
}
