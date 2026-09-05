import Foundation

struct CaffeineLegacyRestoreSnapshot: Equatable {
    static let maximumAge: TimeInterval = 1

    let state: Bool
    let sessionEndDate: Date?
    let manualOverrideUntil: Date?
    let capturedAt: Date

    func isValid(restoring state: Bool, at date: Date) -> Bool {
        let age = date.timeIntervalSince(capturedAt)
        return self.state == state && age >= 0 && age <= Self.maximumAge
    }
}

struct CaffeineLegacyRestoreBuffer {
    private var snapshot: CaffeineLegacyRestoreSnapshot?

    mutating func capture(_ snapshot: CaffeineLegacyRestoreSnapshot) {
        self.snapshot = snapshot
    }

    mutating func invalidate() {
        snapshot = nil
    }

    mutating func consume(restoring state: Bool, at date: Date) -> CaffeineLegacyRestoreSnapshot? {
        defer { snapshot = nil }
        guard let snapshot, snapshot.isValid(restoring: state, at: date) else { return nil }
        return snapshot
    }
}
