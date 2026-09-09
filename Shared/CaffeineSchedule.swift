import Foundation

enum CaffeineRecurrenceFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly
    case yearly
}

struct CaffeineRecurrence: Equatable, Codable {
    private struct FloatingDate: Equatable, Codable {
        let era: Int?
        let year: Int
        let month: Int
        let day: Int
        let isLeapMonth: Bool?
    }

    var frequency: CaffeineRecurrenceFrequency
    var interval: Int
    var anchorDate: Date
    var weekdays: Set<Int>
    var endDate: Date?
    var occurrenceLimit: Int?
    private var floatingAnchor: FloatingDate?
    private var floatingEnd: FloatingDate?

    init(
        frequency: CaffeineRecurrenceFrequency,
        interval: Int = 1,
        anchorDate: Date,
        weekdays: Set<Int> = [],
        endDate: Date? = nil,
        occurrenceLimit: Int? = nil,
        calendar: Calendar? = nil
    ) {
        self.frequency = frequency
        self.interval = min(99, max(1, interval))
        self.anchorDate = anchorDate
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        self.endDate = endDate.map { max($0, anchorDate) }
        self.occurrenceLimit = occurrenceLimit.map { min(999, max(1, $0)) }
        floatingAnchor = calendar.map { Self.floatingDate(for: anchorDate, calendar: $0) }
        floatingEnd = calendar.flatMap { calendar in
            self.endDate.map { Self.floatingDate(for: $0, calendar: calendar) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case frequency
        case interval
        case anchorDate
        case weekdays
        case endDate
        case occurrenceLimit
        case floatingAnchor
        case floatingEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            frequency: try container.decode(CaffeineRecurrenceFrequency.self, forKey: .frequency),
            interval: try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1,
            anchorDate: try container.decode(Date.self, forKey: .anchorDate),
            weekdays: try container.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? [],
            endDate: try container.decodeIfPresent(Date.self, forKey: .endDate),
            occurrenceLimit: try container.decodeIfPresent(Int.self, forKey: .occurrenceLimit)
        )
        floatingAnchor = try container.decodeIfPresent(FloatingDate.self, forKey: .floatingAnchor)
        floatingEnd = try container.decodeIfPresent(FloatingDate.self, forKey: .floatingEnd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encode(anchorDate, forKey: .anchorDate)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(occurrenceLimit, forKey: .occurrenceLimit)
        try container.encodeIfPresent(floatingAnchor, forKey: .floatingAnchor)
        try container.encodeIfPresent(floatingEnd, forKey: .floatingEnd)
    }

    func includes(_ day: Date, calendar: Calendar) -> Bool {
        let candidate = calendar.startOfDay(for: day)
        let anchor = localAnchorDate(in: calendar)
        guard candidate >= anchor else { return false }
        if let endDate = localEndDate(in: calendar), candidate > endDate { return false }
        guard matchesPattern(candidate, anchor: anchor, calendar: calendar) else { return false }
        if let occurrenceLimit {
            var occurrence = 0
            var cursor = anchor
            while cursor <= candidate {
                if matchesPattern(cursor, anchor: anchor, calendar: calendar) {
                    occurrence += 1
                    if cursor == candidate { return occurrence <= occurrenceLimit }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return false }
                cursor = next
            }
            return false
        }
        return true
    }

    func nextOccurrence(onOrAfter day: Date, calendar: Calendar) -> Date? {
        let anchor = localAnchorDate(in: calendar)
        let target = max(calendar.startOfDay(for: day), anchor)

        switch frequency {
        case .daily:
            let distance = calendar.dateComponents([.day], from: anchor, to: target).day ?? 0
            let steps = (max(0, distance) + interval - 1) / interval
            guard let candidate = calendar.date(byAdding: .day, value: steps * interval, to: anchor) else { return nil }
            return includes(candidate, calendar: calendar) ? candidate : nil

        case .weekly:
            var candidate = target
            for _ in 0..<(interval * 7 + 7) {
                if includes(candidate, calendar: calendar) { return candidate }
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            }
            return nil

        case .monthly:
            guard let anchorDay = calendar.dateComponents([.day], from: anchor).day,
                  let anchorMonthStart = calendar.dateInterval(of: .month, for: anchor)?.start,
                  let targetMonthStart = calendar.dateInterval(of: .month, for: target)?.start else { return nil }
            let monthDistance = calendar.dateComponents(
                [.month],
                from: anchorMonthStart,
                to: targetMonthStart
            ).month ?? 0
            var step = (max(0, monthDistance) + interval - 1) / interval
            for _ in 0..<4_800 {
                guard let monthStart = calendar.date(
                    byAdding: .month,
                    value: step * interval,
                    to: anchorMonthStart
                ) else { return nil }
                if let candidate = exactDate(inMonthContaining: monthStart, day: anchorDay, calendar: calendar),
                   candidate >= target {
                    if includes(candidate, calendar: calendar) { return candidate }
                    if endDate != nil || occurrenceLimit != nil { return nil }
                }
                step += 1
            }
            return nil

        case .yearly:
            let anchorParts = calendar.dateComponents([.month, .day, .isLeapMonth], from: anchor)
            guard let month = anchorParts.month, let day = anchorParts.day,
                  let anchorYearStart = calendar.dateInterval(of: .year, for: anchor)?.start,
                  let targetYearStart = calendar.dateInterval(of: .year, for: target)?.start else { return nil }
            let yearDistance = calendar.dateComponents(
                [.year],
                from: anchorYearStart,
                to: targetYearStart
            ).year ?? 0
            var step = (max(0, yearDistance) + interval - 1) / interval
            for _ in 0..<400 {
                guard let yearStart = calendar.date(
                    byAdding: .year,
                    value: step * interval,
                    to: anchorYearStart
                ) else { return nil }
                if let candidate = exactDate(
                    inYearContaining: yearStart,
                    month: month,
                    day: day,
                    isLeapMonth: anchorParts.isLeapMonth,
                    calendar: calendar
                ), candidate >= target {
                    if includes(candidate, calendar: calendar) { return candidate }
                    if endDate != nil || occurrenceLimit != nil { return nil }
                }
                step += 1
            }
            return nil
        }
    }

    private func exactDate(
        inYearContaining yearStart: Date,
        month: Int,
        day: Int,
        isLeapMonth: Bool?,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.era, .year], from: yearStart)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.month = month
        components.day = day
        components.isLeapMonth = isLeapMonth
        guard let date = calendar.date(from: components) else { return nil }
        let result = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        guard result.era == components.era,
              result.year == components.year,
              result.month == month,
              result.day == day,
              result.isLeapMonth == isLeapMonth else { return nil }
        return date
    }

    private func exactDate(inMonthContaining monthStart: Date, day: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month, .isLeapMonth], from: monthStart)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let result = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        guard result.era == components.era,
              result.year == components.year,
              result.month == components.month,
              result.day == day,
              result.isLeapMonth == components.isLeapMonth else { return nil }
        return date
    }

    func localAnchorDate(in calendar: Calendar) -> Date {
        Self.date(from: floatingAnchor, fallback: anchorDate, calendar: calendar)
    }

    func localEndDate(in calendar: Calendar) -> Date? {
        guard endDate != nil else { return nil }
        let resolved = Self.date(from: floatingEnd, fallback: endDate!, calendar: calendar)
        return max(resolved, localAnchorDate(in: calendar))
    }

    private static func floatingDate(for date: Date, calendar: Calendar) -> FloatingDate {
        let components = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        return FloatingDate(
            era: components.era,
            year: components.year!,
            month: components.month!,
            day: components.day!,
            isLeapMonth: components.isLeapMonth
        )
    }

    private static func date(from floating: FloatingDate?, fallback: Date, calendar: Calendar) -> Date {
        guard let floating else {
            return calendar.startOfDay(for: fallback)
        }
        var components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            era: floating.era,
            year: floating.year,
            month: floating.month,
            day: floating.day
        )
        components.isLeapMonth = floating.isLeapMonth
        guard let date = calendar.date(from: components) else {
            return calendar.startOfDay(for: fallback)
        }
        return calendar.startOfDay(for: date)
    }

    private func matchesPattern(_ candidate: Date, anchor: Date, calendar: Calendar) -> Bool {
        switch frequency {
        case .daily:
            let distance = calendar.dateComponents([.day], from: anchor, to: candidate).day ?? -1
            return distance >= 0 && distance.isMultiple(of: interval)
        case .weekly:
            let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            let candidateWeek = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start ?? candidate
            let distance = calendar.dateComponents([.weekOfYear], from: anchorWeek, to: candidateWeek).weekOfYear ?? -1
            let selectedDays = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : weekdays
            return distance >= 0
                && distance.isMultiple(of: interval)
                && selectedDays.contains(calendar.component(.weekday, from: candidate))
        case .monthly:
            let distance = calendar.dateComponents([.month], from: anchor, to: candidate).month ?? -1
            return distance >= 0
                && distance.isMultiple(of: interval)
                && calendar.component(.day, from: candidate) == calendar.component(.day, from: anchor)
        case .yearly:
            let distance = calendar.dateComponents([.year], from: anchor, to: candidate).year ?? -1
            return distance >= 0
                && distance.isMultiple(of: interval)
                && calendar.component(.month, from: candidate) == calendar.component(.month, from: anchor)
                && calendar.component(.day, from: candidate) == calendar.component(.day, from: anchor)
        }
    }
}

struct CaffeineDayWindow: Equatable, Codable {
    var onMinutes: Int
    var offMinutes: Int

    init(onMinutes: Int, offMinutes: Int) {
        self.onMinutes = min(max(onMinutes, 0), 1_439)
        self.offMinutes = min(max(offMinutes, 0), 1_439)
    }

    var isValid: Bool { onMinutes != offMinutes }

    private enum CodingKeys: String, CodingKey {
        case onMinutes
        case offMinutes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            onMinutes: try values.decode(Int.self, forKey: .onMinutes),
            offMinutes: try values.decode(Int.self, forKey: .offMinutes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(onMinutes, forKey: .onMinutes)
        try values.encode(offMinutes, forKey: .offMinutes)
    }
}

struct CaffeineOneTimeWindow: Equatable, Codable {
    var startDate: Date
    var endDate: Date

    var isValid: Bool { endDate > startDate }
}

struct CaffeineSchedule: Equatable {
    static let defaultOnMinutes = 9 * 60
    static let defaultOffMinutes = 17 * 60
    static let everyDay = Set(1...7)

    var enabled: Bool
    var onMinutes: Int
    var offMinutes: Int
    var weekdays: Set<Int>
    var recurrence: CaffeineRecurrence?
    var weekdayWindows: [Int: CaffeineDayWindow]
    var oneTimeWindow: CaffeineOneTimeWindow?

    init(
        enabled: Bool = false,
        onMinutes: Int = defaultOnMinutes,
        offMinutes: Int = defaultOffMinutes,
        weekdays: Set<Int> = everyDay,
        recurrence: CaffeineRecurrence? = nil,
        weekdayWindows: [Int: CaffeineDayWindow] = [:],
        oneTimeWindow: CaffeineOneTimeWindow? = nil
    ) {
        self.enabled = enabled
        self.onMinutes = Self.normalized(onMinutes)
        self.offMinutes = Self.normalized(offMinutes)
        let validWindows = weekdayWindows.filter { Self.everyDay.contains($0.key) }
        if let oneTimeWindow {
            self.weekdays = []
            self.recurrence = nil
            self.weekdayWindows = [:]
            self.oneTimeWindow = oneTimeWindow
        } else if !validWindows.isEmpty {
            self.weekdays = Set(validWindows.keys)
            self.recurrence = nil
            self.weekdayWindows = validWindows
            self.oneTimeWindow = nil
        } else {
            self.weekdays = weekdays.intersection(Self.everyDay)
            self.recurrence = recurrence
            self.weekdayWindows = [:]
            self.oneTimeWindow = nil
        }
    }

    struct Transition: Equatable {
        let date: Date
        let turnsOn: Bool
    }

    var isValid: Bool {
        if let oneTimeWindow { return oneTimeWindow.isValid }
        if !weekdayWindows.isEmpty { return weekdayWindows.values.allSatisfy(\.isValid) }
        return onMinutes != offMinutes && (recurrence != nil || !weekdays.isEmpty)
    }

    func disablingCompletedOneTime(at date: Date) -> CaffeineSchedule {
        guard enabled, let oneTimeWindow, date >= oneTimeWindow.endDate else { return self }
        var completed = self
        completed.enabled = false
        return completed
    }

    func shouldBeCaffeinated(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, isValid else { return false }
        if let oneTimeWindow {
            return date >= oneTimeWindow.startDate && date < oneTimeWindow.endDate
        }
        if !weekdayWindows.isEmpty {
            return customWindowsAreActive(at: date, calendar: calendar)
        }
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
        if let oneTimeWindow {
            if date < oneTimeWindow.startDate {
                return Transition(date: oneTimeWindow.startDate, turnsOn: true)
            }
            if date < oneTimeWindow.endDate {
                return Transition(date: oneTimeWindow.endDate, turnsOn: false)
            }
            return nil
        }
        if !weekdayWindows.isEmpty {
            let boundaries = Set(
                transitions(relativeTo: date, dayOffsets: -1...8, calendar: calendar)
                    .map(\.date)
                    .filter { $0 > date }
            ).sorted()
            var state = customWindowsAreActive(at: date, calendar: calendar)
            for boundary in boundaries {
                let nextState = customWindowsAreActive(at: boundary, calendar: calendar)
                if nextState != state {
                    return Transition(date: boundary, turnsOn: nextState)
                }
                state = nextState
            }
            return nil
        }
        if let recurrence {
            let referenceDay = calendar.startOfDay(for: date)
            var candidates: [Transition] = []
            if let previousDay = calendar.date(byAdding: .day, value: -1, to: referenceDay),
               recurrence.includes(previousDay, calendar: calendar) {
                candidates += transitions(for: previousDay, calendar: calendar)
            }
            if let occurrence = recurrence.nextOccurrence(onOrAfter: referenceDay, calendar: calendar) {
                candidates += transitions(for: occurrence, calendar: calendar)
                if !candidates.contains(where: { $0.date > date }),
                   let followingDay = calendar.date(byAdding: .day, value: 1, to: occurrence),
                   let nextOccurrence = recurrence.nextOccurrence(onOrAfter: followingDay, calendar: calendar) {
                    candidates += transitions(for: nextOccurrence, calendar: calendar)
                }
            }
            let upcoming = candidates.filter { $0.date > date }
            guard let nextDate = upcoming.map(\.date).min() else { return nil }
            let simultaneous = upcoming.filter { $0.date == nextDate }
            return simultaneous.first { !$0.turnsOn } ?? simultaneous.first
        }
        let candidates = transitions(relativeTo: date, dayOffsets: -1...8, calendar: calendar)
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
            let isIncluded = recurrence?.includes(startDay, calendar: calendar)
                ?? (weekdayWindows.isEmpty ? weekdays.contains(weekday) : weekdayWindows[weekday] != nil)
            guard isIncluded else { continue }
            result += transitions(for: startDay, calendar: calendar)
        }
        return result
    }

    private func transitions(for startDay: Date, calendar: Calendar) -> [Transition] {
        let weekday = calendar.component(.weekday, from: startDay)
        let window = weekdayWindows[weekday]
            ?? CaffeineDayWindow(onMinutes: onMinutes, offMinutes: offMinutes)
        var result: [Transition] = []
        if let onDate = wallClockDate(minutes: window.onMinutes, on: startDay, calendar: calendar) {
            result.append(Transition(date: onDate, turnsOn: true))
        }
        let offDay: Date
        if window.onMinutes < window.offMinutes {
            offDay = startDay
        } else {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startDay) else { return result }
            offDay = nextDay
        }
        if let offDate = wallClockDate(minutes: window.offMinutes, on: offDay, calendar: calendar) {
            result.append(Transition(date: offDate, turnsOn: false))
        }
        return result
    }

    private func customWindowsAreActive(at date: Date, calendar: Calendar) -> Bool {
        let referenceDay = calendar.startOfDay(for: date)
        for offset in -1...0 {
            guard let startDay = calendar.date(byAdding: .day, value: offset, to: referenceDay) else { continue }
            let weekday = calendar.component(.weekday, from: startDay)
            guard weekdayWindows[weekday] != nil else { continue }
            let boundaries = transitions(for: startDay, calendar: calendar)
            guard boundaries.count == 2 else { continue }
            if date >= boundaries[0].date && date < boundaries[1].date {
                return true
            }
        }
        return false
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

enum CaffeineTimerSession: Equatable {
    case inactive
    case running(endDate: Date)
    case paused(remaining: TimeInterval)
}

final class CaffeineScheduleStore {
    private enum Key {
        static let enabled = "schedule.enabled"
        static let onMinutes = "schedule.onMinutes"
        static let offMinutes = "schedule.offMinutes"
        static let weekdaysMask = "schedule.weekdaysMask"
        static let recurrence = "schedule.recurrence"
        static let weekdayWindows = "schedule.weekdayWindows"
        static let oneTimeWindow = "schedule.oneTimeWindow"
        static let manualOverrideUntil = "schedule.manualOverrideUntil"
        static let sessionEndDate = "session.endDate"
        static let pausedSessionRemaining = "session.pausedRemaining"
        static let sessionDuration = "session.duration"
        static let preferredTimerMinutes = "timer.preferredMinutes"
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

    var pausedSessionRemaining: TimeInterval? {
        get {
            guard let value = defaults.object(forKey: Key.pausedSessionRemaining) as? Double,
                  value.isFinite,
                  value > 0 else { return nil }
            return value
        }
        set {
            if let newValue, newValue.isFinite, newValue > 0 {
                defaults.set(newValue, forKey: Key.pausedSessionRemaining)
            } else {
                defaults.removeObject(forKey: Key.pausedSessionRemaining)
            }
        }
    }

    var sessionDuration: TimeInterval? {
        get {
            guard let value = defaults.object(forKey: Key.sessionDuration) as? Double,
                  value.isFinite,
                  value > 0 else { return nil }
            return value
        }
        set {
            if let newValue, newValue.isFinite, newValue > 0 {
                defaults.set(newValue, forKey: Key.sessionDuration)
            } else {
                defaults.removeObject(forKey: Key.sessionDuration)
            }
        }
    }

    func timerSession(at now: Date) -> CaffeineTimerSession {
        if let endDate = sessionEndDate, endDate > now {
            return .running(endDate: endDate)
        }
        if let remaining = pausedSessionRemaining {
            return .paused(remaining: remaining)
        }
        return .inactive
    }

    func startTimer(duration: TimeInterval, at now: Date) {
        let normalizedDuration = max(1, duration)
        pausedSessionRemaining = nil
        sessionDuration = normalizedDuration
        sessionEndDate = now.addingTimeInterval(normalizedDuration)
    }

    @discardableResult
    func pauseTimer(at now: Date) -> Bool {
        guard let endDate = sessionEndDate, endDate > now else { return false }
        pausedSessionRemaining = endDate.timeIntervalSince(now)
        sessionEndDate = nil
        return true
    }

    @discardableResult
    func resumeTimer(at now: Date) -> Bool {
        guard let remaining = pausedSessionRemaining else { return false }
        sessionEndDate = now.addingTimeInterval(remaining)
        pausedSessionRemaining = nil
        return true
    }

    func stopTimer() {
        sessionEndDate = nil
        pausedSessionRemaining = nil
        sessionDuration = nil
    }

    var preferredTimerMinutes: Int {
        get {
            let value = defaults.object(forKey: Key.preferredTimerMinutes) as? Int ?? 120
            return min(10_080, max(1, value))
        }
        set { defaults.set(min(10_080, max(1, newValue)), forKey: Key.preferredTimerMinutes) }
    }

    var hasPersistedSchedule: Bool {
        defaults.object(forKey: Key.enabled) != nil
    }

    func load() -> CaffeineSchedule {
        let mask = defaults.object(forKey: Key.weekdaysMask) as? Int ?? 0b111_1111
        let weekdays = Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
        let recurrence = (defaults.data(forKey: Key.recurrence)).flatMap {
            try? JSONDecoder().decode(CaffeineRecurrence.self, from: $0)
        }
        let weekdayWindows = (defaults.data(forKey: Key.weekdayWindows)).flatMap {
            try? JSONDecoder().decode([Int: CaffeineDayWindow].self, from: $0)
        } ?? [:]
        let oneTimeWindow = (defaults.data(forKey: Key.oneTimeWindow)).flatMap {
            try? JSONDecoder().decode(CaffeineOneTimeWindow.self, from: $0)
        }
        return CaffeineSchedule(
            enabled: defaults.bool(forKey: Key.enabled),
            onMinutes: defaults.object(forKey: Key.onMinutes) as? Int ?? CaffeineSchedule.defaultOnMinutes,
            offMinutes: defaults.object(forKey: Key.offMinutes) as? Int ?? CaffeineSchedule.defaultOffMinutes,
            weekdays: weekdays,
            recurrence: recurrence,
            weekdayWindows: weekdayWindows,
            oneTimeWindow: oneTimeWindow
        )
    }

    func save(_ schedule: CaffeineSchedule) {
        let mask = schedule.weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
        defaults.set(schedule.enabled, forKey: Key.enabled)
        defaults.set(schedule.onMinutes, forKey: Key.onMinutes)
        defaults.set(schedule.offMinutes, forKey: Key.offMinutes)
        defaults.set(mask, forKey: Key.weekdaysMask)
        if let recurrence = schedule.recurrence,
           let data = try? JSONEncoder().encode(recurrence) {
            defaults.set(data, forKey: Key.recurrence)
        } else {
            defaults.removeObject(forKey: Key.recurrence)
        }
        if !schedule.weekdayWindows.isEmpty,
           let data = try? JSONEncoder().encode(schedule.weekdayWindows) {
            defaults.set(data, forKey: Key.weekdayWindows)
        } else {
            defaults.removeObject(forKey: Key.weekdayWindows)
        }
        if let oneTimeWindow = schedule.oneTimeWindow,
           let data = try? JSONEncoder().encode(oneTimeWindow) {
            defaults.set(data, forKey: Key.oneTimeWindow)
        } else {
            defaults.removeObject(forKey: Key.oneTimeWindow)
        }
        defaults.synchronize()
    }
}
