import XCTest

final class CaffeineScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, year: Int = 2026, month: Int = 9, day: Int = 4) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testSameDayWindowIsActiveFromOnTimeUntilOffTime() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)

        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(8, 59), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(9, 0), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(16, 59), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(17, 0), calendar: calendar))
    }

    func testNextTransitionChoosesUpcomingOnTime() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)

        let transition = schedule.nextTransition(after: date(8, 30), calendar: calendar)

        XCTAssertEqual(transition, CaffeineSchedule.Transition(date: date(9, 0), turnsOn: true))
    }

    func testParsesTwentyFourHourClockTime() {
        XCTAssertEqual(CaffeineSchedule.parseClockTime("22:15"), 22 * 60 + 15)
    }

    func testOvernightWindowWrapsAcrossMidnight() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 22 * 60, offMinutes: 6 * 60)

        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(21, 59), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(22, 0), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(0, 0), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(5, 59), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(6, 0), calendar: calendar))
    }

    func testDisabledScheduleNeverCaffeinates() {
        let schedule = CaffeineSchedule(enabled: false, onMinutes: 9 * 60, offMinutes: 17 * 60)

        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0), calendar: calendar))
        XCTAssertNil(schedule.nextTransition(after: date(12, 0), calendar: calendar))
    }

    func testEqualTimesAreRejectedAsAnEmptyWindow() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 9 * 60)

        XCTAssertFalse(schedule.isValid)
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(9, 0), calendar: calendar))
        XCTAssertNil(schedule.nextTransition(after: date(8, 0), calendar: calendar))
    }

    func testMinutesAreClampedToOneDay() {
        XCTAssertEqual(CaffeineSchedule(enabled: true, onMinutes: -4, offMinutes: 9_999).onMinutes, 0)
        XCTAssertEqual(CaffeineSchedule(enabled: true, onMinutes: -4, offMinutes: 9_999).offMinutes, 1_439)
    }

    func testNextTransitionChoosesUpcomingOffTime() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)

        XCTAssertEqual(
            schedule.nextTransition(after: date(12, 0), calendar: calendar),
            CaffeineSchedule.Transition(date: date(17, 0), turnsOn: false)
        )
    }

    func testNextTransitionRollsToTomorrow() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)

        XCTAssertEqual(
            schedule.nextTransition(after: date(18, 0), calendar: calendar),
            CaffeineSchedule.Transition(date: date(9, 0, day: 5), turnsOn: true)
        )
    }

    func testExactOnBoundaryAdvancesToOffBoundary() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)

        XCTAssertEqual(
            schedule.nextTransition(after: date(9, 0), calendar: calendar),
            CaffeineSchedule.Transition(date: date(17, 0), turnsOn: false)
        )
    }

    func testOvernightNextTransitionTurnsOffNextMorning() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 22 * 60, offMinutes: 6 * 60)

        XCTAssertEqual(
            schedule.nextTransition(after: date(23, 0), calendar: calendar),
            CaffeineSchedule.Transition(date: date(6, 0, day: 5), turnsOn: false)
        )
    }

    func testOvernightNextTransitionAfterMidnightStillFindsMorningOff() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 22 * 60, offMinutes: 6 * 60)

        XCTAssertEqual(
            schedule.nextTransition(after: date(2, 0, day: 5), calendar: calendar),
            CaffeineSchedule.Transition(date: date(6, 0, day: 5), turnsOn: false)
        )
    }

    func testSpringForwardUsesNextValidWallClockTime() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let beforeJump = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)))
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 2 * 60 + 30, offMinutes: 4 * 60)

        let transition = try XCTUnwrap(schedule.nextTransition(after: beforeJump, calendar: newYork))
        let parts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: transition.date)

        XCTAssertTrue(transition.turnsOn)
        XCTAssertEqual(parts, DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 0))
    }

    func testFallBackUsesFirstOccurrenceOfRepeatedOnTime() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let beforeRepeat = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30)))
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 1 * 60 + 30, offMinutes: 3 * 60)

        let transition = try XCTUnwrap(schedule.nextTransition(after: beforeRepeat, calendar: newYork))
        let parts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: transition.date)

        XCTAssertTrue(transition.turnsOn)
        XCTAssertEqual(parts, DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))
        XCTAssertEqual(newYork.timeZone.secondsFromGMT(for: transition.date), -4 * 60 * 60)
    }

    func testFallBackDoesNotReactivateDuringSecondRepeatedHour() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let firstOneAM = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1)))
        let secondOneAM = firstOneAM.addingTimeInterval(60 * 60)
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 30, offMinutes: 90)

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: firstOneAM, calendar: newYork))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: secondOneAM, calendar: newYork))
    }

    func testClockParserRejectsMalformedOrOutOfRangeValues() {
        for value in ["", "9", "9:", ":30", "24:00", "12:60", "-1:00", "12:30:00", "noon"] {
            XCTAssertNil(CaffeineSchedule.parseClockTime(value), "Expected \\(value) to be rejected")
        }
    }

    func testClockParserAllowsSingleDigitHour() {
        XCTAssertEqual(CaffeineSchedule.parseClockTime("7:05"), 7 * 60 + 5)
    }

    func testSelectedWeekdaysLimitSameDaySchedule() {
        let mondayOnly = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60, weekdays: [2])

        XCTAssertTrue(mondayOnly.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 7), calendar: calendar))
        XCTAssertFalse(mondayOnly.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 8), calendar: calendar))
    }

    func testNextTransitionSkipsUnselectedDays() {
        let mondayOnly = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60, weekdays: [2])
        let fridayEvening = date(18, 0, year: 2026, month: 9, day: 4)

        XCTAssertEqual(
            mondayOnly.nextTransition(after: fridayEvening, calendar: calendar),
            CaffeineSchedule.Transition(date: date(9, 0, year: 2026, month: 9, day: 7), turnsOn: true)
        )
    }

    func testManualOverrideRebasesToNextBoundaryInNewTimeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)
        let now = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 8)))
        let oldBoundary = try XCTUnwrap(schedule.nextTransition(after: now, calendar: newYork)?.date)

        let rebased = schedule.rebasedManualOverride(oldBoundary, afterClockChangeAt: now, calendar: losAngeles)

        XCTAssertEqual(rebased, schedule.nextTransition(after: now, calendar: losAngeles)?.date)
        XCTAssertNotEqual(rebased, oldBoundary)
    }

    func testExpiredManualOverrideRemainsExpiredForReconciliation() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60)
        let now = date(12, 0)
        let expired = date(9, 0)
        XCTAssertEqual(
            schedule.rebasedManualOverride(expired, afterClockChangeAt: now, calendar: calendar),
            expired
        )
    }

    func testOvernightWindowBelongsToItsStartingWeekday() {
        let mondayNight = CaffeineSchedule(enabled: true, onMinutes: 22 * 60, offMinutes: 6 * 60, weekdays: [2])

        XCTAssertTrue(mondayNight.shouldBeCaffeinated(at: date(23, 0, year: 2026, month: 9, day: 7), calendar: calendar))
        XCTAssertTrue(mondayNight.shouldBeCaffeinated(at: date(5, 59, year: 2026, month: 9, day: 8), calendar: calendar))
        XCTAssertFalse(mondayNight.shouldBeCaffeinated(at: date(6, 0, year: 2026, month: 9, day: 8), calendar: calendar))
        XCTAssertFalse(mondayNight.shouldBeCaffeinated(at: date(23, 0, year: 2026, month: 9, day: 8), calendar: calendar))
    }

    func testOvernightOffTransitionFallsOnFollowingDay() {
        let mondayNight = CaffeineSchedule(enabled: true, onMinutes: 22 * 60, offMinutes: 6 * 60, weekdays: [2])

        XCTAssertEqual(
            mondayNight.nextTransition(after: date(23, 0, year: 2026, month: 9, day: 7), calendar: calendar),
            CaffeineSchedule.Transition(date: date(6, 0, year: 2026, month: 9, day: 8), turnsOn: false)
        )
    }

    func testEmptyCustomDaySelectionIsInvalid() {
        let schedule = CaffeineSchedule(enabled: true, onMinutes: 9 * 60, offMinutes: 17 * 60, weekdays: [])

        XCTAssertFalse(schedule.isValid)
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0), calendar: calendar))
        XCTAssertNil(schedule.nextTransition(after: date(12, 0), calendar: calendar))
    }

    func testSampledDailyWindowsMatchCircularTimeArithmetic() {
        for onMinutes in stride(from: 0, to: 1_440, by: 37) {
            for offMinutes in stride(from: 0, to: 1_440, by: 41) where offMinutes != onMinutes {
                let schedule = CaffeineSchedule(enabled: true, onMinutes: onMinutes, offMinutes: offMinutes)
                let duration = (offMinutes - onMinutes + 1_440) % 1_440

                for minute in stride(from: 0, to: 1_440, by: 29) {
                    let elapsed = (minute - onMinutes + 1_440) % 1_440
                    let expected = elapsed < duration
                    XCTAssertEqual(
                        schedule.shouldBeCaffeinated(at: date(minute / 60, minute % 60), calendar: calendar),
                        expected,
                        "on=\(onMinutes), off=\(offMinutes), minute=\(minute)"
                    )
                }
            }
        }
    }

    func testDailyRecurrenceCanRunEveryOtherDayFromAnchor() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .daily,
                interval: 2,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 4)
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 4), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 5), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 6), calendar: calendar))
    }

    func testWeeklyRecurrenceUsesSelectedDaysEveryOtherWeek() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .weekly,
                interval: 2,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 7),
                weekdays: [2, 4, 6]
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 9), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 16), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 23), calendar: calendar))
    }

    func testMonthlyRecurrenceUsesAnchorDayAndInterval() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .monthly,
                interval: 2,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 15)
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 15), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 10, day: 15), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 11, day: 15), calendar: calendar))
    }

    func testYearlyRecurrenceUsesAnchorMonthAndDay() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .yearly,
                interval: 2,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 15)
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 15), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2027, month: 9, day: 15), calendar: calendar))
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2028, month: 9, day: 15), calendar: calendar))
    }

    func testRecurrenceCanEndAfterASetNumberOfOccurrences() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .daily,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 4),
                occurrenceLimit: 3
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 6), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 7), calendar: calendar))
    }

    func testRecurrenceEndDateIsInclusive() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .daily,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 4),
                endDate: date(0, 0, year: 2026, month: 9, day: 6)
            )
        )

        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 6), calendar: calendar))
        XCTAssertFalse(schedule.shouldBeCaffeinated(at: date(12, 0, year: 2026, month: 9, day: 7), calendar: calendar))
    }

    func testNextTransitionFindsSparseYearlyOccurrence() throws {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .yearly,
                anchorDate: date(0, 0, year: 2026, month: 12, day: 25)
            )
        )

        let transition = try XCTUnwrap(schedule.nextTransition(
            after: date(12, 0, year: 2026, month: 9, day: 4),
            calendar: calendar
        ))
        XCTAssertTrue(transition.turnsOn)
        XCTAssertEqual(transition.date, date(9, 0, year: 2026, month: 12, day: 25))
    }

    func testNonWeeklyRecurrenceDoesNotRequireWeekdaySelection() {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            weekdays: [],
            recurrence: CaffeineRecurrence(
                frequency: .monthly,
                anchorDate: date(0, 0, year: 2026, month: 9, day: 4)
            )
        )

        XCTAssertTrue(schedule.isValid)
        XCTAssertTrue(schedule.shouldBeCaffeinated(at: date(12, 0), calendar: calendar))
    }

    func testYearlyLeapDayRecurrenceFindsNextValidLeapYear() throws {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .yearly,
                anchorDate: date(0, 0, year: 2024, month: 2, day: 29)
            )
        )

        let transition = try XCTUnwrap(schedule.nextTransition(
            after: date(12, 0, year: 2025, month: 3, day: 1),
            calendar: calendar
        ))
        XCTAssertEqual(transition.date, date(9, 0, year: 2028, month: 2, day: 29))
    }

    func testMonthlyTwelveMonthLeapDayRecurrenceFindsNextLeapYear() throws {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .monthly,
                interval: 12,
                anchorDate: date(0, 0, year: 2024, month: 2, day: 29)
            )
        )

        let transition = try XCTUnwrap(schedule.nextTransition(
            after: date(12, 0, year: 2025, month: 3, day: 1),
            calendar: calendar
        ))
        XCTAssertEqual(transition.date, date(9, 0, year: 2028, month: 2, day: 29))
    }

    func testYearlyLeapDayRecurrenceSkipsNonLeapCentury() throws {
        let schedule = CaffeineSchedule(
            enabled: true,
            onMinutes: 9 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .yearly,
                anchorDate: date(0, 0, year: 2096, month: 2, day: 29)
            )
        )

        let transition = try XCTUnwrap(schedule.nextTransition(
            after: date(12, 0, year: 2097, month: 3, day: 1),
            calendar: calendar
        ))
        XCTAssertEqual(transition.date, date(9, 0, year: 2104, month: 2, day: 29))
    }

    func testPersistedFloatingAnchorKeepsItsCalendarDayAcrossTimeZones() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let tokyoAnchor = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let recurrence = CaffeineRecurrence(
            frequency: .monthly,
            anchorDate: tokyoAnchor,
            calendar: tokyo
        )
        let persisted = try JSONDecoder().decode(
            CaffeineRecurrence.self,
            from: JSONEncoder().encode(recurrence)
        )
        let losAngelesSeptemberFifth = losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 5))!

        XCTAssertTrue(persisted.includes(losAngelesSeptemberFifth, calendar: losAngeles))
    }

    func testMonthlyRecurrenceSupportsCalendarsWithLeapMonths() throws {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(hebrew.date(from: DateComponents(year: 5784, month: 1, day: 15)))
        let target = try XCTUnwrap(hebrew.date(from: DateComponents(year: 5784, month: 13, day: 1)))
        let recurrence = CaffeineRecurrence(
            frequency: .monthly,
            interval: 12,
            anchorDate: anchor
        )

        let occurrence = try XCTUnwrap(recurrence.nextOccurrence(onOrAfter: target, calendar: hebrew))

        let components = hebrew.dateComponents([.year, .month, .day], from: occurrence)
        XCTAssertEqual(components.year, 5784)
        XCTAssertEqual(components.month, 13)
        XCTAssertEqual(components.day, 15)
    }

    func testYearlyRecurrenceSupportsCalendarsWhoseYearResetsAcrossEras() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = gregorian.timeZone
        let anchor = gregorian.date(from: DateComponents(year: 2018, month: 9, day: 4))!
        let target = gregorian.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let expected = gregorian.date(from: DateComponents(year: 2020, month: 9, day: 4))!
        let recurrence = CaffeineRecurrence(
            frequency: .yearly,
            anchorDate: anchor,
            calendar: japanese
        )
        let persisted = try JSONDecoder().decode(
            CaffeineRecurrence.self,
            from: JSONEncoder().encode(recurrence)
        )

        XCTAssertEqual(persisted.nextOccurrence(onOrAfter: target, calendar: japanese), expected)
    }
}
