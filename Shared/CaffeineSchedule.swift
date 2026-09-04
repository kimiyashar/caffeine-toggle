import Foundation

struct CaffeineSchedule: Equatable {
    static let defaultOnMinutes = 9 * 60
    static let defaultOffMinutes = 17 * 60
    static let everyDay = Set(1...7)

    var enabled: Bool
    var onMinutes: Int
    var offMinutes: Int
    var weekdays: Set<Int>

    init(
        enabled: Bool = false,
        onMinutes: Int = defaultOnMinutes,
        offMinutes: Int = defaultOffMinutes,
        weekdays: Set<Int> = everyDay
    ) {
        self.enabled = enabled
        self.onMinutes = Self.normalized(onMinutes)
        self.offMinutes = Self.normalized(offMinutes)
        self.weekdays = weekdays.intersection(Self.everyDay)
    }

    struct Transition: Equatable {
        let date: Date
        let turnsOn: Bool
    }

    var isValid: Bool {
        onMinutes != offMinutes && !weekdays.isEmpty
    }

    func shouldBeCaffeinated(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, isValid else { return false }
        let candidates = transitions(relativeTo: date, dayOffsets: -8...0, calendar: calendar)
            .filter { $0.date <= date }
        guard let mostRecentDate = candidates.map(\.date).max() else { return false }
        let simultaneous = candidates.filter { $0.date == mostRecentDate }
        return !simultaneous.contains { !$0.turnsOn }
    }

    func rebasedManualOverride(
        _ existingBoundary: Date?,
        afterClockChangeAt now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let existingBoundary else { return nil }
        guard existingBoundary > now else { return existingBoundary }
        return nextTransition(after: now, calendar: calendar)?.date
    }

    func nextTransition(after date: Date, calendar: Calendar = .current) -> Transition? {
        guard enabled, isValid else { return nil }
        let candidates = transitions(relativeTo: date, dayOffsets: 0...8, calendar: calendar)
            .filter { $0.date > date }
        guard let nextDate = candidates.map(\.date).min() else { return nil }
        let simultaneous = candidates.filter { $0.date == nextDate }
        return simultaneous.first { !$0.turnsOn } ?? simultaneous.first
    }

    private func transitions(
        relativeTo reference: Date,
        dayOffsets: ClosedRange<Int>,
        calendar: Calendar
    ) -> [Transition] {
        let referenceDay = calendar.startOfDay(for: reference)
        var result: [Transition] = []

        for offset in dayOffsets {
            guard let startDay = calendar.date(byAdding: .day, value: offset, to: referenceDay) else { continue }
            let weekday = calendar.component(.weekday, from: startDay)
            guard weekdays.contains(weekday) else { continue }
            if let onDate = wallClockDate(minutes: onMinutes, on: startDay, calendar: calendar) {
                result.append(Transition(date: onDate, turnsOn: true))
            }

            let offDay: Date
            if onMinutes < offMinutes {
                offDay = startDay
            } else {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startDay) else { continue }
                offDay = nextDay
            }
            if let offDate = wallClockDate(minutes: offMinutes, on: offDay, calendar: calendar) {
                result.append(Transition(date: offDate, turnsOn: false))
            }
        }
        return result
    }

    private func wallClockDate(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    static func parseClockTime(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    private static func normalized(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }
}

final class CaffeineScheduleStore {
    private enum Key {
        static let enabled = "schedule.enabled"
        static let onMinutes = "schedule.onMinutes"
        static let offMinutes = "schedule.offMinutes"
        static let weekdaysMask = "schedule.weekdaysMask"
        static let manualOverrideUntil = "schedule.manualOverrideUntil"
        static let sessionEndDate = "session.endDate"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var manualOverrideUntil: Date? {
        get { defaults.object(forKey: Key.manualOverrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.manualOverrideUntil) }
    }

    var sessionEndDate: Date? {
        get { defaults.object(forKey: Key.sessionEndDate) as? Date }
        set { defaults.set(newValue, forKey: Key.sessionEndDate) }
    }

    func load() -> CaffeineSchedule {
        let mask = defaults.object(forKey: Key.weekdaysMask) as? Int ?? 0b111_1111
        let weekdays = Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
        return CaffeineSchedule(
            enabled: defaults.bool(forKey: Key.enabled),
            onMinutes: defaults.object(forKey: Key.onMinutes) as? Int ?? CaffeineSchedule.defaultOnMinutes,
            offMinutes: defaults.object(forKey: Key.offMinutes) as? Int ?? CaffeineSchedule.defaultOffMinutes,
            weekdays: weekdays
        )
    }

    func save(_ schedule: CaffeineSchedule) {
        let mask = schedule.weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
        defaults.set(schedule.enabled, forKey: Key.enabled)
        defaults.set(schedule.onMinutes, forKey: Key.onMinutes)
        defaults.set(schedule.offMinutes, forKey: Key.offMinutes)
        defaults.set(mask, forKey: Key.weekdaysMask)
        defaults.synchronize()
    }
}
