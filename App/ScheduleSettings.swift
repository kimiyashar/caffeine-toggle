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

@MainActor
final class ScheduleSettingsModel: ObservableObject {
    @Published var enabled: Bool
    @Published var onTime: Date
    @Published var offTime: Date
    @Published var weekdays: Set<Int>
    @Published var sessionMinutes = 120
    @Published var sessionEndDate: Date?
    @Published var message: String?

    private let store: CaffeineScheduleStore
    private let calendarProvider: () -> Calendar
    private let now: () -> Date

    init(
        store: CaffeineScheduleStore = CaffeineScheduleStore(),
        calendarProvider: @escaping () -> Calendar = { Calendar.current },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.calendarProvider = calendarProvider
        self.now = now
        let calendar = calendarProvider()
        let schedule = store.load()
        enabled = schedule.enabled
        onTime = Self.date(for: schedule.onMinutes, calendar: calendar)
        offTime = Self.date(for: schedule.offMinutes, calendar: calendar)
        weekdays = schedule.weekdays
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
        guard enabled else { return "Schedule is off. The Control Center toggle stays fully manual." }
        guard !weekdays.isEmpty else { return "Choose at least one day." }
        let days = Self.daysSummary(weekdays)
        return "\(days): on at \(onTime.formatted(date: .omitted, time: .shortened)), off at \(offTime.formatted(date: .omitted, time: .shortened))."
    }

    var sessionSummary: String? {
        guard let sessionEndDate, sessionEndDate > now() else { return nil }
        return "On until \(sessionEndDate.formatted(date: .omitted, time: .shortened))"
    }

    func startSession() {
        let endDate = now().addingTimeInterval(Double(sessionMinutes) * 60)
        store.sessionEndDate = endDate
        store.manualOverrideUntil = nil
        sessionEndDate = endDate
        post(CaffeineCommand.sessionChangedNotification)
        message = "Session started. Caffeine will turn off automatically."
    }

    func stopSession() {
        store.sessionEndDate = nil
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

    func save() {
        let calendar = calendarProvider()
        let onMinutes = Self.minutes(for: onTime, calendar: calendar)
        let offMinutes = Self.minutes(for: offTime, calendar: calendar)
        if enabled {
            guard !weekdays.isEmpty else {
                message = "Choose at least one day."
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
            enabled: enabled,
            onMinutes: onMinutes,
            offMinutes: offMinutes,
            weekdays: weekdays
        ))
        post(CaffeineCommand.scheduleChangedNotification)
        message = enabled ? "Schedule saved. The next scheduled time will take over automatically." : "Schedule disabled. Manual toggle control restored."
    }

    func reload() {
        let calendar = calendarProvider()
        let schedule = store.load()
        enabled = schedule.enabled
        onTime = Self.date(for: schedule.onMinutes, calendar: calendar)
        offTime = Self.date(for: schedule.offMinutes, calendar: calendar)
        weekdays = schedule.weekdays
        let savedEndDate = store.sessionEndDate
        sessionEndDate = savedEndDate.flatMap { $0 > now() ? $0 : nil }
        if savedEndDate != nil, sessionEndDate == nil {
            store.sessionEndDate = nil
        }
        message = nil
    }

    private func post(_ notificationName: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }

    private static func daysSummary(_ days: Set<Int>) -> String {
        if days == CaffeineSchedule.everyDay { return "Every day" }
        if days == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if days == Set([1, 7]) { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
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

    init(model: ScheduleSettingsModel) {
        self.model = model
        _section = State(initialValue: model.enabled && model.sessionEndDate == nil ? .repeating : .timer)
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

            Text("A manual OFF toggle cancels the timer immediately.")
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
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Use a repeating schedule", isOn: $model.enabled)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("Repeat")
                    .font(.subheadline.weight(.medium))
                Picker("Repeat", selection: Binding(
                    get: { model.repeatPreset },
                    set: { model.repeatPreset = $0 }
                )) {
                    ForEach(ScheduleRepeatPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!model.enabled)

                HStack(spacing: 9) {
                    ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                        let weekday = index + 1
                        Button {
                            model.toggleDay(weekday)
                        } label: {
                            Text(symbol)
                                .font(.caption.weight(.semibold))
                                .frame(width: 34, height: 30)
                                .background(
                                    model.weekdays.contains(weekday) ? Color.brown : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(model.weekdays.contains(weekday) ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.enabled)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[index])
                        .accessibilityValue(model.weekdays.contains(weekday) ? "selected" : "not selected")
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Label("Turn on", systemImage: "sunrise.fill")
                    DatePicker("Turn on", selection: $model.onTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!model.enabled)
                }
                GridRow {
                    Label("Turn off", systemImage: "moon.zzz.fill")
                    DatePicker("Turn off", selection: $model.offTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!model.enabled)
                }
            }

            Text(model.scheduleSummary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Single-click the mug to toggle anytime. The next scheduled boundary takes over; overnight schedules are supported.")
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
