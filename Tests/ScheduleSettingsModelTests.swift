import XCTest

@MainActor
final class ScheduleSettingsModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScheduleSettingsModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDisablingAllowsEmptyDaysAndEqualTimes() {
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60))
        let model = ScheduleSettingsModel(store: store)

        model.enabled = false
        model.weekdays = []
        model.offTime = model.onTime
        model.save()

        let saved = store.load()
        XCTAssertFalse(saved.enabled)
        XCTAssertTrue(saved.weekdays.isEmpty)
        XCTAssertEqual(saved.onMinutes, saved.offMinutes)
        XCTAssertEqual(model.message, "Schedule disabled. Manual toggle control restored.")
    }

    func testRepeatPresetsSelectExpectedDays() {
        let model = ScheduleSettingsModel(store: CaffeineScheduleStore(defaults: defaults))

        model.repeatPreset = .weekdays
        XCTAssertEqual(model.weekdays, Set([2, 3, 4, 5, 6]))
        model.repeatPreset = .weekends
        XCTAssertEqual(model.weekdays, Set([1, 7]))
        model.repeatPreset = .everyDay
        XCTAssertEqual(model.weekdays, CaffeineSchedule.everyDay)
    }

    func testTimePickerDatesPreserveWallClockMinutesAcrossDSTZones() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(enabled: true, onMinutes: 2 * 60 + 30, offMinutes: 4 * 60))

        let model = ScheduleSettingsModel(store: store, calendarProvider: { newYork })
        let onParts = newYork.dateComponents([.hour, .minute], from: model.onTime)
        XCTAssertEqual(onParts.hour, 2)
        XCTAssertEqual(onParts.minute, 30)

        model.save()
        XCTAssertEqual(store.load().onMinutes, 2 * 60 + 30)
    }

    func testTwoHourSessionPersistsExactEndAndCanStop() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = ScheduleSettingsModel(store: store, now: { now })
        model.sessionMinutes = 120

        model.startSession()

        XCTAssertEqual(store.sessionEndDate, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(model.sessionEndDate, store.sessionEndDate)
        model.stopSession()
        XCTAssertNil(store.sessionEndDate)
        XCTAssertNil(model.sessionEndDate)
    }

    func testReloadUsesCurrentTimeZoneInsteadOfCapturedCalendar() throws {
        var activeCalendar = Calendar(identifier: .gregorian)
        activeCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60))
        let model = ScheduleSettingsModel(store: store, calendarProvider: { activeCalendar })

        XCTAssertEqual(activeCalendar.component(.hour, from: model.onTime), 9)
        activeCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        model.reload()

        XCTAssertEqual(activeCalendar.component(.hour, from: model.onTime), 9)
        XCTAssertEqual(activeCalendar.component(.hour, from: model.offTime), 17)
    }
}
