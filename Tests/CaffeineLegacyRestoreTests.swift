import XCTest

final class CaffeineLegacyRestoreTests: XCTestCase {
    func testRecentMatchingLegacyRestorePreservesAutomationSnapshot() {
        let capturedAt = Date(timeIntervalSinceReferenceDate: 100)
        let timerEnd = Date(timeIntervalSinceReferenceDate: 3_700)
        let overrideEnd = Date(timeIntervalSinceReferenceDate: 500)
        let snapshot = CaffeineLegacyRestoreSnapshot(
            state: true,
            sessionEndDate: timerEnd,
            manualOverrideUntil: overrideEnd,
            capturedAt: capturedAt
        )

        XCTAssertTrue(snapshot.isValid(restoring: true, at: capturedAt.addingTimeInterval(0.4)))
        XCTAssertEqual(snapshot.sessionEndDate, timerEnd)
        XCTAssertEqual(snapshot.manualOverrideUntil, overrideEnd)
    }

    func testInvalidatedLegacyRestoreCannotOverwriteNewAutomation() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var buffer = CaffeineLegacyRestoreBuffer()
        buffer.capture(CaffeineLegacyRestoreSnapshot(
            state: true,
            sessionEndDate: now.addingTimeInterval(3_600),
            manualOverrideUntil: nil,
            capturedAt: now
        ))

        buffer.invalidate()

        XCTAssertNil(buffer.consume(restoring: true, at: now.addingTimeInterval(0.4)))
    }
}