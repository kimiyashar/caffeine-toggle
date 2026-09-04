import XCTest

final class CaffeineScheduleStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CaffeineScheduleStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsSchedule() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let expected = CaffeineSchedule(enabled: true, onMinutes: 22 * 60 + 15, offMinutes: 6 * 60 + 45)

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testFreshStoreUsesSafeDisabledDefaults() {
        let schedule = CaffeineScheduleStore(defaults: defaults).load()

        XCTAssertFalse(schedule.enabled)
        XCTAssertEqual(schedule.onMinutes, 9 * 60)
        XCTAssertEqual(schedule.offMinutes, 17 * 60)
    }

    func testSaveCanDisableWithoutLosingChosenTimes() {
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(enabled: true, onMinutes: 21 * 60, offMinutes: 7 * 60))
        store.save(CaffeineSchedule(enabled: false, onMinutes: 21 * 60, offMinutes: 7 * 60))

        XCTAssertEqual(store.load(), CaffeineSchedule(enabled: false, onMinutes: 21 * 60, offMinutes: 7 * 60))
    }

    func testRoundTripsCustomWeekdays() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let expected = CaffeineSchedule(enabled: true, onMinutes: 7 * 60, offMinutes: 19 * 60, weekdays: [2, 4, 6])

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testPersistsAndClearsManualOverrideBoundary() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let boundary = Date(timeIntervalSinceReferenceDate: 123_456)

        store.manualOverrideUntil = boundary
        XCTAssertEqual(store.manualOverrideUntil, boundary)
        store.manualOverrideUntil = nil
        XCTAssertNil(store.manualOverrideUntil)
    }

    func testPersistsAndClearsSessionEndDate() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let endDate = Date(timeIntervalSinceReferenceDate: 654_321)

        store.sessionEndDate = endDate
        XCTAssertEqual(store.sessionEndDate, endDate)
        store.sessionEndDate = nil
        XCTAssertNil(store.sessionEndDate)
    }

    func testRoundTripsAdvancedRecurrence() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let recurrence = CaffeineRecurrence(
            frequency: .weekly,
            interval: 3,
            anchorDate: Date(timeIntervalSinceReferenceDate: 123_000),
            weekdays: [2, 4, 6],
            endDate: Date(timeIntervalSinceReferenceDate: 999_000),
            occurrenceLimit: 12
        )
        let expected = CaffeineSchedule(
            enabled: true,
            onMinutes: 8 * 60,
            offMinutes: 18 * 60,
            recurrence: recurrence
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testDecodedRecurrenceNormalizesUntrustedPersistedValues() throws {
        let data = Data(#"{"frequency":"weekly","interval":0,"anchorDate":1000,"weekdays":[0,2,9],"endDate":0,"occurrenceLimit":0}"#.utf8)

        let recurrence = try JSONDecoder().decode(CaffeineRecurrence.self, from: data)

        XCTAssertEqual(recurrence.interval, 1)
        XCTAssertEqual(recurrence.weekdays, [2])
        XCTAssertEqual(recurrence.occurrenceLimit, 1)
        XCTAssertEqual(recurrence.endDate, recurrence.anchorDate)

        let oversizedData = Data(#"{"frequency":"daily","interval":9223372036854775807,"anchorDate":0,"weekdays":[],"occurrenceLimit":9223372036854775807}"#.utf8)
        let oversized = try JSONDecoder().decode(CaffeineRecurrence.self, from: oversizedData)
        XCTAssertEqual(oversized.interval, 99)
        XCTAssertEqual(oversized.occurrenceLimit, 999)
    }
}
