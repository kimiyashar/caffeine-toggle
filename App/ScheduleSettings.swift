import AppKit
import SwiftUI

enum ScheduleRepeatPreset: String, CaseIterable, Identifiable {
    case everyDay = "Every day"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case custom = "Custom"

    var id: String { rawValue }

    var days: Set<Int>? {
        switch self {
        case .everyDay: CaffeineSchedule.everyDay
        case .weekdays: [2, 3, 4, 5, 6]
        case .weekends: [1, 7]
        case .custom: nil
        }
    }
}

enum CalendarRepeatChoice: String, CaseIterable, Identifiable {
    case never = "Never"
    case everyDay = "Every Day"
    case everyWeek = "Every Week"
    case everyMonth = "Every Month"
    case everyYear = "Every Year"
    case custom = "Custom…"

    var id: String { rawValue }
}

enum RecurrenceEndChoice: String, CaseIterable, Identifiable {
    case never = "Never"
    case onDate = "On"
    case afterOccurrences = "After"

    var id: String { rawValue }
}

@MainActor
final class ScheduleSettingsModel: ObservableObject {
    @Published var enabled: Bool
    @Published var onTime: Date
    @Published var offTime: Date
    @Published var weekdays: Set<Int>
    @Published var repeatChoice: CalendarRepeatChoice {
        didSet {
            enabled = repeatChoice != .never
            if oldValue != repeatChoice { recurrenceAnchorDate = now() }
        }
    }
    @Published var customFrequency: CaffeineRecurrenceFrequency
    @Published var customInterval: Int
    @Published var recurrenceEnd: RecurrenceEndChoice
    @Published var recurrenceEndDate: Date
    @Published var recurrenceCount: Int
    @Published var sessionMinutes = 120
    @Published var sessionEndDate: Date?
    @Published var message: String?

    private let store: CaffeineScheduleStore
    private let calendarProvider: () -> Calendar
    private let now: () -> Date
    private let postNotification: (String) -> Void
    private var recurrenceAnchorDate: Date

    init(
        store: CaffeineScheduleStore = CaffeineScheduleStore(),
        calendarProvider: @escaping () -> Calendar = { Calendar.current },
        now: @escaping () -> Date = Date.init,
        postNotification: @escaping (String) -> Void = { notificationName in
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(notificationName as CFString),
                nil,
                nil,
                true
            )
        }
    ) {
        self.store = store
        self.calendarProvider = calendarProvider
        self.now = now
        self.postNotification = postNotification
        let calendar = calendarProvider()
        let schedule = store.load()
        enabled = schedule.enabled
        onTime = Self.date(for: schedule.onMinutes, calendar: calendar)
        offTime = Self.date(for: schedule.offMinutes, calendar: calendar)
        weekdays = schedule.weekdays
        repeatChoice = Self.choice(for: schedule, calendar: calendar)
        recurrenceAnchorDate = schedule.recurrence?.localAnchorDate(in: calendar) ?? now()
        customFrequency = schedule.recurrence?.frequency ?? .weekly
        customInterval = schedule.recurrence?.interval ?? 1
        recurrenceEnd = schedule.recurrence?.endDate != nil ? .onDate
            : schedule.recurrence?.occurrenceLimit != nil ? .afterOccurrences : .never
        recurrenceEndDate = schedule.recurrence?.localEndDate(in: calendar) ?? now().addingTimeInterval(30 * 24 * 60 * 60)
        recurrenceCount = schedule.recurrence?.occurrenceLimit ?? 10
        let savedEndDate = store.sessionEndDate
        sessionEndDate = savedEndDate.flatMap { $0 > now() ? $0 : nil }
        if savedEndDate != nil, sessionEndDate == nil {
            store.sessionEndDate = nil
        }
    }

    var repeatPreset: ScheduleRepeatPreset {
        get {
            ScheduleRepeatPreset.allCases.first { $0.days == weekdays } ?? .custom
        }
        set {
            if let days = newValue.days {
                weekdays = days
            }
        }
    }

    var scheduleSummary: String {
        guard enabled else { return "Schedule is off. The menu-bar toggle stays fully manual." }
        guard !weekdays.isEmpty else { return "Choose at least one day." }
        let days = Self.daysSummary(weekdays)
        return "\(days): on at \(onTime.formatted(date: .omitted, time: .shortened)), off at \(offTime.formatted(date: .omitted, time: .shortened))."
    }

    var sessionSummary: String? {
        guard let sessionEndDate, sessionEndDate > now() else { return nil }
        return "On until \(sessionEndDate.formatted(date: .omitted, time: .shortened))"
    }

    func startSession() {
        store.startTimer(duration: Double(sessionMinutes) * 60, at: now())
        store.manualOverrideUntil = nil
        sessionEndDate = store.sessionEndDate
        post(CaffeineCommand.sessionChangedNotification)
        message = "Session started. Caffeine will turn off automatically."
    }

    func stopSession() {
        store.stopTimer()
        sessionEndDate = nil
        post(CaffeineCommand.sessionChangedNotification)
        message = "Session stopped."
    }

    func toggleDay(_ weekday: Int) {
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        message = nil
    }

    func prepareCustomRecurrence() {
        guard repeatChoice != .custom else { return }
        let calendar = calendarProvider()
        switch repeatChoice {
        case .never:
            customFrequency = .weekly
            weekdays = [calendar.component(.weekday, from: recurrenceAnchorDate)]
        case .everyDay:
            customFrequency = .daily
        case .everyWeek:
            customFrequency = .weekly
            weekdays = [calendar.component(.weekday, from: recurrenceAnchorDate)]
        case .everyMonth:
            customFrequency = .monthly
        case .everyYear:
            customFrequency = .yearly
        case .custom:
            return
        }
        customInterval = 1
        recurrenceEnd = .never
    }

    func save() {
        let calendar = calendarProvider()
        let onMinutes = Self.minutes(for: onTime, calendar: calendar)
        let offMinutes = Self.minutes(for: offTime, calendar: calendar)
        let scheduleEnabled = enabled && repeatChoice != .never
        if scheduleEnabled {
            if repeatChoice == .custom, customFrequency == .weekly, weekdays.isEmpty {
                message = "Choose at least one day."
                NSSound.beep()
                return
            }
            if repeatChoice == .custom,
               recurrenceEnd == .onDate,
               calendar.startOfDay(for: recurrenceEndDate) < calendar.startOfDay(for: recurrenceAnchorDate) {
                message = "Choose an end date on or after the schedule starts."
                NSSound.beep()
                return
            }
            guard onMinutes != offMinutes else {
                message = "Choose different on and off times."
                NSSound.beep()
                return
            }
        }

        store.save(CaffeineSchedule(
            enabled: scheduleEnabled,
            onMinutes: onMinutes,
            offMinutes: offMinutes,
            weekdays: weekdays,
            recurrence: recurrenceForSave(calendar: calendar)
        ))
        enabled = scheduleEnabled
        post(CaffeineCommand.scheduleChangedNotification)
        message = scheduleEnabled ? "Schedule saved. The next scheduled time will take over automatically." : "Schedule disabled. Manual toggle control restored."
    }

    func reload() {
        let calendar = calendarProvider()
        let schedule = store.load()
        enabled = schedule.enabled
        onTime = Self.date(for: schedule.onMinutes, calendar: calendar)
        offTime = Self.date(for: schedule.offMinutes, calendar: calendar)
        weekdays = schedule.weekdays
        repeatChoice = Self.choice(for: schedule, calendar: calendar)
        recurrenceAnchorDate = schedule.recurrence?.localAnchorDate(in: calendar) ?? now()
        customFrequency = schedule.recurrence?.frequency ?? .weekly
        customInterval = schedule.recurrence?.interval ?? 1
        recurrenceEnd = schedule.recurrence?.endDate != nil ? .onDate
            : schedule.recurrence?.occurrenceLimit != nil ? .afterOccurrences : .never
        recurrenceEndDate = schedule.recurrence?.localEndDate(in: calendar) ?? now().addingTimeInterval(30 * 24 * 60 * 60)
        recurrenceCount = schedule.recurrence?.occurrenceLimit ?? 10
        let savedEndDate = store.sessionEndDate
        sessionEndDate = savedEndDate.flatMap { $0 > now() ? $0 : nil }
        if savedEndDate != nil, sessionEndDate == nil {
            store.sessionEndDate = nil
        }
        message = nil
    }

    private func post(_ notificationName: String) {
        postNotification(notificationName)
    }

    private static func daysSummary(_ days: Set<Int>) -> String {
        if days == CaffeineSchedule.everyDay { return "Every day" }
        if days == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if days == Set([1, 7]) { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    private static func choice(for schedule: CaffeineSchedule, calendar: Calendar) -> CalendarRepeatChoice {
        guard schedule.enabled else { return .never }
        guard let recurrence = schedule.recurrence else { return .custom }
        guard recurrence.interval == 1, recurrence.endDate == nil, recurrence.occurrenceLimit == nil else {
            return .custom
        }
        switch recurrence.frequency {
        case .daily: return .everyDay
        case .weekly:
            let anchorWeekday = calendar.component(.weekday, from: recurrence.localAnchorDate(in: calendar))
            let selectedDays = recurrence.weekdays.isEmpty ? Set([anchorWeekday]) : recurrence.weekdays
            return selectedDays == Set([anchorWeekday]) ? .everyWeek : .custom
        case .monthly: return .everyMonth
        case .yearly: return .everyYear
        }
    }

    private func recurrenceForSave(calendar: Calendar) -> CaffeineRecurrence? {
        let anchor = recurrenceAnchorDate
        switch repeatChoice {
        case .never: return nil
        case .everyDay:
            return CaffeineRecurrence(frequency: .daily, anchorDate: anchor, calendar: calendar)
        case .everyWeek:
            return CaffeineRecurrence(
                frequency: .weekly,
                anchorDate: anchor,
                weekdays: [calendar.component(.weekday, from: anchor)],
                calendar: calendar
            )
        case .everyMonth:
            return CaffeineRecurrence(frequency: .monthly, anchorDate: anchor, calendar: calendar)
        case .everyYear:
            return CaffeineRecurrence(frequency: .yearly, anchorDate: anchor, calendar: calendar)
        case .custom:
            return CaffeineRecurrence(
                frequency: customFrequency,
                interval: customInterval,
                anchorDate: anchor,
                weekdays: weekdays,
                endDate: recurrenceEnd == .onDate ? recurrenceEndDate : nil,
                occurrenceLimit: recurrenceEnd == .afterOccurrences ? recurrenceCount : nil,
                calendar: calendar
            )
        }
    }

    private static func date(for minutes: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = minutes / 60
        components.minute = minutes % 60
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private static func minutes(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

enum CaffeineEditorSection: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case repeating = "Repeat"

    var id: String { rawValue }
}

struct ScheduleSettingsView: View {
    @ObservedObject var model: ScheduleSettingsModel
    @State private var section: CaffeineEditorSection
    @State private var showsCustomRepeat = false

    init(model: ScheduleSettingsModel, showsCustomRepeat: Bool = false) {
        self.model = model
        _section = State(initialValue: model.enabled && model.sessionEndDate == nil ? .repeating : .timer)
        _showsCustomRepeat = State(initialValue: showsCustomRepeat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.brown)
                    .frame(width: 48, height: 48)
                    .background(.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Caffeine")
                        .font(.title2.weight(.semibold))
                    Text("Let the mug fill and empty itself.")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Mode", selection: $section) {
                Label("Timer", systemImage: "timer").tag(CaffeineEditorSection.timer)
                Label("Repeat", systemImage: "repeat").tag(CaffeineEditorSection.repeating)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if section == .timer {
                timerView
            } else {
                repeatView
            }
        }
        .padding(24)
        .frame(width: 470, height: 560, alignment: .top)
        .sheet(isPresented: $showsCustomRepeat) {
            CustomRepeatView(
                frequency: model.customFrequency,
                interval: model.customInterval,
                weekdays: model.weekdays,
                endChoice: model.recurrenceEnd,
                endDate: model.recurrenceEndDate,
                occurrenceCount: model.recurrenceCount,
                onCancel: { showsCustomRepeat = false },
                onSave: { frequency, interval, weekdays, endChoice, endDate, count in
                    model.customFrequency = frequency
                    model.customInterval = interval
                    model.weekdays = weekdays
                    model.recurrenceEnd = endChoice
                    model.recurrenceEndDate = endDate
                    model.recurrenceCount = count
                    model.repeatChoice = .custom
                    showsCustomRepeat = false
                }
            )
        }
    }

    private var timerView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keep Caffeine on for…")
                    .font(.headline)
                Text("It turns off automatically when the timer ends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Duration", selection: $model.sessionMinutes) {
                Text("30 min").tag(30)
                Text("1 hr").tag(60)
                Text("2 hr").tag(120)
                Text("4 hr").tag(240)
                Text("8 hr").tag(480)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            ZStack {
                Circle()
                    .fill(Color.brown.opacity(0.10))
                Circle()
                    .stroke(Color.brown.opacity(0.28), lineWidth: 2)
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.brown)
                    Text(timerDurationLabel)
                        .font(.title2.weight(.semibold))
                }
            }
            .frame(width: 174, height: 174)
            .frame(maxWidth: .infinity)

            if let summary = model.sessionSummary {
                HStack {
                    Label(summary, systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Stop Timer", role: .destructive) { model.stopSession() }
                }
            }

            Button(model.sessionSummary == nil ? "Start Timer" : "Restart Timer") {
                model.startSession()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("A manual OFF toggle pauses the timer; turning Caffeine on resumes it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var timerDurationLabel: String {
        switch model.sessionMinutes {
        case 30: "30 minutes"
        case 60: "1 hour"
        default: "\(model.sessionMinutes / 60) hours"
        }
    }

    private var repeatView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Schedule Caffeine")
                .font(.headline)

            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text("Turn on:")
                    DatePicker("Turn on", selection: $model.onTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Turn off:")
                    DatePicker("Turn off", selection: $model.offTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Repeat:")
                    Picker("Repeat", selection: Binding(
                        get: { model.repeatChoice },
                        set: { choice in
                            if choice == .custom {
                                model.prepareCustomRecurrence()
                                showsCustomRepeat = true
                            } else {
                                model.repeatChoice = choice
                            }
                        }
                    )) {
                        ForEach(CalendarRepeatChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            Text(repeatSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Like Calendar, Custom… lets you choose frequency, interval, weekdays, and when the recurrence ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Divider()

            HStack {
                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Choose") ? .red : .secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Save Repeat") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var repeatSummary: String {
        if model.repeatChoice == .never { return "No repeating schedule. The mug stays fully manual." }
        let on = model.onTime.formatted(date: .omitted, time: .shortened)
        let off = model.offTime.formatted(date: .omitted, time: .shortened)
        return "Caffeine turns on at \(on) and off at \(off). Overnight schedules are supported."
    }
}

private struct CustomRepeatView: View {
    @State private var frequency: CaffeineRecurrenceFrequency
    @State private var interval: Int
    @State private var weekdays: Set<Int>
    @State private var endChoice: RecurrenceEndChoice
    @State private var endDate: Date
    @State private var occurrenceCount: Int

    let onCancel: () -> Void
    let onSave: (CaffeineRecurrenceFrequency, Int, Set<Int>, RecurrenceEndChoice, Date, Int) -> Void

    init(
        frequency: CaffeineRecurrenceFrequency,
        interval: Int,
        weekdays: Set<Int>,
        endChoice: RecurrenceEndChoice,
        endDate: Date,
        occurrenceCount: Int,
        onCancel: @escaping () -> Void,
        onSave: @escaping (CaffeineRecurrenceFrequency, Int, Set<Int>, RecurrenceEndChoice, Date, Int) -> Void
    ) {
        _frequency = State(initialValue: frequency)
        _interval = State(initialValue: interval)
        _weekdays = State(initialValue: weekdays)
        _endChoice = State(initialValue: endChoice)
        _endDate = State(initialValue: endDate)
        _occurrenceCount = State(initialValue: occurrenceCount)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("Frequency:")
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag(CaffeineRecurrenceFrequency.daily)
                        Text("Weekly").tag(CaffeineRecurrenceFrequency.weekly)
                        Text("Monthly").tag(CaffeineRecurrenceFrequency.monthly)
                        Text("Yearly").tag(CaffeineRecurrenceFrequency.yearly)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                GridRow {
                    Text("Every:")
                    HStack(spacing: 8) {
                        TextField("Interval", value: $interval, format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $interval, in: 1...99)
                            .labelsHidden()
                        Text(intervalUnit)
                            .frame(width: 92, alignment: .leading)
                    }
                }
            }

            if frequency == .weekly {
                weekdayButtons
                    .frame(maxWidth: .infinity)
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                Text("End:")
                    .frame(width: 72, alignment: .trailing)
                VStack(alignment: .leading, spacing: 12) {
                    endRow(.never) { EmptyView() }
                    endRow(.onDate) {
                        DatePicker("End date", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(endChoice != .onDate)
                    }
                    endRow(.afterOccurrences) {
                        HStack(spacing: 8) {
                            TextField("Count", value: $occurrenceCount, format: .number)
                                .frame(width: 44)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $occurrenceCount, in: 1...999)
                                .labelsHidden()
                            Text("occurrences")
                        }
                        .disabled(endChoice != .afterOccurrences)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    onSave(frequency, interval, weekdays, endChoice, endDate, occurrenceCount)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(frequency == .weekly && weekdays.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private var weekdayButtons: some View {
        HStack(spacing: 11) {
            ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = index + 1
                Button {
                    if weekdays.contains(weekday) {
                        weekdays.remove(weekday)
                    } else {
                        weekdays.insert(weekday)
                    }
                } label: {
                    Text(symbol)
                        .font(.callout)
                        .frame(width: 30, height: 30)
                        .background(weekdays.contains(weekday) ? Color.accentColor : Color.secondary.opacity(0.13), in: Circle())
                        .foregroundStyle(weekdays.contains(weekday) ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[index])
            }
        }
    }

    private var intervalUnit: String {
        let plural = interval == 1 ? "" : "s"
        switch frequency {
        case .daily: return "day\(plural)"
        case .weekly: return "week\(plural)"
        case .monthly: return "month\(plural)"
        case .yearly: return "year\(plural)"
        }
    }

    private func endRow<Content: View>(
        _ choice: RecurrenceEndChoice,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                endChoice = choice
            } label: {
                Image(systemName: endChoice == choice ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.plain)
            Text(choice.rawValue)
                .frame(width: 42, alignment: .leading)
            content()
        }
    }
}

@MainActor
final class ScheduleWindowController: NSWindowController, NSWindowDelegate {
    private let model: ScheduleSettingsModel

    init(store: CaffeineScheduleStore = CaffeineScheduleStore()) {
        model = ScheduleSettingsModel(store: store)
        let controller = NSHostingController(rootView: ScheduleSettingsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Caffeine Timer & Repeat"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        model.reload()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        model.reload()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
