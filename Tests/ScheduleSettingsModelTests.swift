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
        let model = makeModel(store: store)

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
        let model = makeModel(store: CaffeineScheduleStore(defaults: defaults))

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

        let model = makeModel(store: store, calendarProvider: { newYork })
        let onParts = newYork.dateComponents([.hour, .minute], from: model.onTime)
        XCTAssertEqual(onParts.hour, 2)
        XCTAssertEqual(onParts.minute, 30)

        model.save()
        XCTAssertEqual(store.load().onMinutes, 2 * 60 + 30)
    }

    func testTwoHourSessionPersistsExactEndAndCanStop() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: { now })
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
        let model = makeModel(store: store, calendarProvider: { activeCalendar })

        XCTAssertEqual(activeCalendar.component(.hour, from: model.onTime), 9)
        activeCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        model.reload()

        XCTAssertEqual(activeCalendar.component(.hour, from: model.onTime), 9)
        XCTAssertEqual(activeCalendar.component(.hour, from: model.offTime), 17)
    }

    func testCalendarRepeatChoiceSavesYearlyRecurrence() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: { now })

        model.repeatChoice = .everyYear
        model.save()

        let schedule = store.load()
        XCTAssertTrue(schedule.enabled)
        XCTAssertEqual(schedule.recurrence?.frequency, .yearly)
        XCTAssertEqual(schedule.recurrence?.interval, 1)
        XCTAssertEqual(schedule.recurrence?.anchorDate, now)
    }

    func testCustomCalendarRecurrenceSavesFrequencyIntervalDaysAndEnding() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let endDate = now.addingTimeInterval(30 * 24 * 60 * 60)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: { now })

        model.repeatChoice = .custom
        model.customFrequency = .weekly
        model.customInterval = 2
        model.weekdays = [2, 4, 6]
        model.recurrenceEnd = .onDate
        model.recurrenceEndDate = endDate
        model.save()

        let recurrence = store.load().recurrence
        XCTAssertEqual(recurrence?.frequency, .weekly)
        XCTAssertEqual(recurrence?.interval, 2)
        XCTAssertEqual(recurrence?.weekdays, [2, 4, 6])
        XCTAssertEqual(recurrence?.endDate, endDate)
        XCTAssertNil(recurrence?.occurrenceLimit)
    }

    func testSavingExistingRecurrencePreservesItsAnchorDate() {
        let originalAnchor = Date(timeIntervalSinceReferenceDate: 100_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(
            enabled: true,
            recurrence: CaffeineRecurrence(frequency: .monthly, anchorDate: originalAnchor)
        ))
        let model = makeModel(
            store: store,
            calendarProvider: { calendar },
            now: { Date(timeIntervalSinceReferenceDate: 900_000) }
        )

        model.save()

        XCTAssertEqual(
            store.load().recurrence?.localAnchorDate(in: calendar),
            calendar.startOfDay(for: originalAnchor)
        )
    }

    func testCustomNonWeeklyRecurrenceDoesNotRequireWeekdays() {
        let defaultsStore = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: defaultsStore)
        model.repeatChoice = .custom
        model.customFrequency = .monthly
        model.weekdays = []

        model.save()

        XCTAssertEqual(model.message, "Schedule saved. The next scheduled time will take over automatically.")
        XCTAssertTrue(defaultsStore.load().enabled)
        XCTAssertEqual(defaultsStore.load().recurrence?.frequency, .monthly)
    }

    func testCustomRecurrenceRejectsEndDateBeforeAnchor() {
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: { now })
        model.repeatChoice = .custom
        model.customFrequency = .daily
        model.recurrenceEnd = .onDate
        model.recurrenceEndDate = now.addingTimeInterval(-86_400)

        model.save()

        XCTAssertEqual(model.message, "Choose an end date on or after the schedule starts.")
        XCTAssertFalse(store.load().enabled)
    }

    func testReloadingCustomWeeklyRuleDoesNotCollapseSelectedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(
            enabled: true,
            weekdays: [2, 4, 6],
            recurrence: CaffeineRecurrence(
                frequency: .weekly,
                anchorDate: anchor,
                weekdays: [2, 4, 6],
                calendar: calendar
            )
        ))
        let model = makeModel(store: store, calendarProvider: { calendar })

        XCTAssertEqual(model.repeatChoice, .custom)
        model.save()

        XCTAssertEqual(store.load().recurrence?.weekdays, [2, 4, 6])
    }

    func testOpeningCustomFromPresetSeedsDraftFromThatPreset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let model = makeModel(
            store: CaffeineScheduleStore(defaults: defaults),
            calendarProvider: { calendar },
            now: { now }
        )
        model.customFrequency = .weekly
        model.customInterval = 4
        model.recurrenceEnd = .afterOccurrences
        model.repeatChoice = .everyMonth

        model.prepareCustomRecurrence()

        XCTAssertEqual(model.customFrequency, .monthly)
        XCTAssertEqual(model.customInterval, 1)
        XCTAssertEqual(model.recurrenceEnd, .never)
    }

    private func makeModel(
        store: CaffeineScheduleStore,
        calendarProvider: @escaping () -> Calendar = { Calendar.current },
        now: @escaping () -> Date = Date.init
    ) -> ScheduleSettingsModel {
        ScheduleSettingsModel(
            store: store,
            calendarProvider: calendarProvider,
            now: now,
            postNotification: { _ in }
        )
    }
}
