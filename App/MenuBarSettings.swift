import AppKit
import Combine
import Foundation
import SwiftUI

enum CaffeineScheduleMode: String, CaseIterable, Identifiable {
    case oneTime = "One-Time"
    case everyDay = "Every Day"
    case weekdays = "Weekdays"
    case custom = "Custom"

    var id: String { rawValue }
}

@MainActor
final class MenuBarSettingsModel: ObservableObject {
    @Published var timerHours: Int { didSet { persistTimerDuration() } }
    @Published var timerMinutes: Int { didSet { persistTimerDuration() } }
    @Published private(set) var scheduleEnabled: Bool
    @Published private(set) var scheduleMode: CaffeineScheduleMode
    @Published private(set) var sharedWindow: CaffeineDayWindow
    @Published private(set) var customWindows: [Int: CaffeineDayWindow]
    @Published private(set) var oneTimeStart: Date
    @Published private(set) var oneTimeEnd: Date
    @Published private(set) var timerState: CaffeineTimerSession

    private let store: CaffeineScheduleStore
    private let now: () -> Date
    private let post: (String) -> Void

    init(
        store: CaffeineScheduleStore = CaffeineScheduleStore(),
        now: @escaping () -> Date = Date.init,
        post: @escaping (String) -> Void
    ) {
        self.store = store
        self.now = now
        self.post = post

        let duration = store.preferredTimerMinutes
        timerHours = duration / 60
        timerMinutes = duration % 60
        timerState = store.timerSession(at: now())

        let snapshot = Self.snapshot(
            for: store.load(),
            now: now(),
            hasPersistedSchedule: store.hasPersistedSchedule
        )
        scheduleEnabled = snapshot.enabled
        scheduleMode = snapshot.mode
        sharedWindow = snapshot.sharedWindow
        customWindows = snapshot.customWindows
        oneTimeStart = snapshot.oneTimeStart
        oneTimeEnd = snapshot.oneTimeEnd
    }

    var timerDurationMinutes: Int {
        min(10_080, max(1, timerHours * 60 + timerMinutes))
    }

    var timerIsActive: Bool {
        timerState != .inactive
    }

    var hasUnsupportedSchedule: Bool {
        Self.isUnsupportedSchedule(store.load())
    }

    var timerInitialDurationSeconds: TimeInterval {
        let remaining: TimeInterval
        switch timerState {
        case let .running(endDate):
            remaining = max(0, endDate.timeIntervalSince(now()))
        case let .paused(pausedRemaining):
            remaining = pausedRemaining
        case .inactive:
            remaining = 0
        }
        return max(remaining, store.sessionDuration ?? Double(timerDurationMinutes * 60))
    }

    var timerEndDate: Date? {
        guard case let .running(endDate) = timerState else { return nil }
        return endDate
    }

    func startTimer() {
        store.startTimer(duration: Double(timerDurationMinutes) * 60, at: now())
        store.manualOverrideUntil = nil
        timerState = store.timerSession(at: now())
        post(CaffeineCommand.sessionChangedNotification)
    }

    func stopTimer() {
        store.stopTimer()
        timerState = .inactive
        post(CaffeineCommand.sessionChangedNotification)
    }

    func selectScheduleMode(_ mode: CaffeineScheduleMode) {
        guard !hasUnsupportedSchedule else { return }
        scheduleMode = mode
    }

    func setScheduleEnabled(_ enabled: Bool) {
        if hasUnsupportedSchedule {
            scheduleEnabled = enabled
            var schedule = store.load()
            schedule.enabled = enabled
            store.save(schedule)
            post(CaffeineCommand.scheduleChangedNotification)
            return
        }
        if enabled {
            guard scheduleMode != .custom || !customWindows.isEmpty else { return }
            scheduleEnabled = true
            saveSelectedSchedule()
        } else {
            guard scheduleIsEnabled(scheduleMode) else { return }
            scheduleEnabled = false
            var schedule = store.load()
            schedule.enabled = false
            store.save(schedule)
            post(CaffeineCommand.scheduleChangedNotification)
        }
    }

    func scheduleIsEnabled(_ mode: CaffeineScheduleMode) -> Bool {
        guard scheduleEnabled, store.hasPersistedSchedule else { return false }
        return Self.snapshot(
            for: store.load(),
            now: now(),
            hasPersistedSchedule: true
        ).mode == mode
    }

    func setSharedWindow(_ window: CaffeineDayWindow) {
        guard !hasUnsupportedSchedule else { return }
        guard window.isValid else { return }
        sharedWindow = window
        guard scheduleIsEnabled(scheduleMode) else { return }
        switch scheduleMode {
        case .everyDay:
            saveRecurring(days: CaffeineSchedule.everyDay, window: window)
        case .weekdays:
            saveRecurring(days: Set(2...6), window: window)
        case .custom, .oneTime:
            break
        }
    }

    func setCustomDay(_ weekday: Int, enabled: Bool) {
        guard !hasUnsupportedSchedule else { return }
        guard CaffeineSchedule.everyDay.contains(weekday) else { return }
        if enabled {
            customWindows[weekday] = customWindows[weekday] ?? sharedWindow
        } else {
            customWindows.removeValue(forKey: weekday)
        }
        if scheduleIsEnabled(.custom) {
            saveCustom()
        }
    }

    func setCustomWindow(_ window: CaffeineDayWindow, for weekday: Int) {
        guard !hasUnsupportedSchedule else { return }
        guard window.isValid, customWindows[weekday] != nil else { return }
        customWindows[weekday] = window
        if scheduleIsEnabled(.custom) {
            saveCustom()
        }
    }

    func setOneTime(start: Date, end: Date) {
        guard !hasUnsupportedSchedule else { return }
        oneTimeStart = start
        oneTimeEnd = max(end, start.addingTimeInterval(60))
        if scheduleIsEnabled(.oneTime) {
            saveOneTime()
        }
    }

    func reload() {
        let duration = store.preferredTimerMinutes
        timerHours = duration / 60
        timerMinutes = duration % 60
        timerState = store.timerSession(at: now())
        let snapshot = Self.snapshot(
            for: store.load(),
            now: now(),
            hasPersistedSchedule: store.hasPersistedSchedule
        )
        scheduleEnabled = snapshot.enabled
        scheduleMode = snapshot.mode
        sharedWindow = snapshot.sharedWindow
        customWindows = snapshot.customWindows
        oneTimeStart = snapshot.oneTimeStart
        oneTimeEnd = snapshot.oneTimeEnd
    }

    private func saveSelectedSchedule() {
        switch scheduleMode {
        case .oneTime:
            saveOneTime()
        case .everyDay:
            saveRecurring(days: CaffeineSchedule.everyDay, window: sharedWindow)
        case .weekdays:
            saveRecurring(days: Set(2...6), window: sharedWindow)
        case .custom:
            saveCustom()
        }
    }

    private func saveRecurring(days: Set<Int>, window: CaffeineDayWindow) {
        let windows = Dictionary(uniqueKeysWithValues: days.map { ($0, window) })
        customWindows = windows
        store.save(CaffeineSchedule(
            enabled: scheduleEnabled,
            onMinutes: window.onMinutes,
            offMinutes: window.offMinutes,
            weekdays: days,
            weekdayWindows: windows
        ))
        post(CaffeineCommand.scheduleChangedNotification)
    }

    private func saveCustom() {
        scheduleEnabled = scheduleEnabled && !customWindows.isEmpty
        store.save(CaffeineSchedule(
            enabled: scheduleEnabled,
            onMinutes: sharedWindow.onMinutes,
            offMinutes: sharedWindow.offMinutes,
            weekdays: Set(customWindows.keys),
            weekdayWindows: customWindows
        ))
        post(CaffeineCommand.scheduleChangedNotification)
    }

    private func saveOneTime() {
        let end = max(oneTimeEnd, oneTimeStart.addingTimeInterval(60))
        oneTimeEnd = end
        store.save(CaffeineSchedule(
            enabled: scheduleEnabled,
            oneTimeWindow: CaffeineOneTimeWindow(startDate: oneTimeStart, endDate: end)
        ))
        post(CaffeineCommand.scheduleChangedNotification)
    }

    private func persistTimerDuration() {
        store.preferredTimerMinutes = timerDurationMinutes
    }

    private struct Snapshot {
        let enabled: Bool
        let mode: CaffeineScheduleMode
        let sharedWindow: CaffeineDayWindow
        let customWindows: [Int: CaffeineDayWindow]
        let oneTimeStart: Date
        let oneTimeEnd: Date
    }

    private static func isUnsupportedSchedule(_ schedule: CaffeineSchedule) -> Bool {
        guard let recurrence = schedule.recurrence else { return false }
        return ![.daily, .weekly].contains(recurrence.frequency)
            || recurrence.interval != 1
            || recurrence.endDate != nil
            || recurrence.occurrenceLimit != nil
    }

    private static func snapshot(
        for schedule: CaffeineSchedule,
        now: Date,
        hasPersistedSchedule: Bool
    ) -> Snapshot {
        let fallbackWindow = CaffeineDayWindow(
            onMinutes: schedule.onMinutes,
            offMinutes: schedule.offMinutes
        )
        let defaultStart = now.addingTimeInterval(60 * 60)
        let defaultEnd = now.addingTimeInterval(2 * 60 * 60)
        if let oneTime = schedule.oneTimeWindow {
            return Snapshot(
                enabled: schedule.enabled,
                mode: .oneTime,
                sharedWindow: fallbackWindow,
                customWindows: [:],
                oneTimeStart: oneTime.startDate,
                oneTimeEnd: oneTime.endDate
            )
        }

        var windows = schedule.weekdayWindows
        if hasPersistedSchedule,
           windows.isEmpty,
           schedule.recurrence == nil || [.daily, .weekly].contains(schedule.recurrence?.frequency) {
            let days = schedule.recurrence?.frequency == .daily
                ? CaffeineSchedule.everyDay
                : schedule.weekdays
            windows = Dictionary(uniqueKeysWithValues: days.map { ($0, fallbackWindow) })
        }
        let uniqueWindows = Set(windows.values.map { "\($0.onMinutes):\($0.offMinutes)" })
        let days = Set(windows.keys)
        let mode: CaffeineScheduleMode
        if days == CaffeineSchedule.everyDay, uniqueWindows.count == 1 {
            mode = .everyDay
        } else if days == Set(2...6), uniqueWindows.count == 1 {
            mode = .weekdays
        } else {
            mode = .custom
        }
        return Snapshot(
            enabled: schedule.enabled,
            mode: mode,
            sharedWindow: windows.values.first ?? fallbackWindow,
            customWindows: windows,
            oneTimeStart: defaultStart,
            oneTimeEnd: defaultEnd
        )
    }
}

enum TimerCountdownFormatter {
    static func string(remainingSeconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(remainingSeconds)))
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

enum CoffeeTimerGauge {
    static func fillFraction(
        remainingSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        isActive: Bool
    ) -> Double {
        guard isActive else { return 0 }
        return min(1, max(0, remainingSeconds / max(1, durationSeconds)))
    }
}

@MainActor
final class MenuBarState: ObservableObject {
    @Published private(set) var isCaffeinated: Bool
    private let setState: (Bool) -> Void

    init(isCaffeinated: Bool, setState: @escaping (Bool) -> Void) {
        self.isCaffeinated = isCaffeinated
        self.setState = setState
    }

    func toggle() { set(!isCaffeinated) }

    func set(_ enabled: Bool) {
        isCaffeinated = enabled
        setState(enabled)
    }

    func refresh(_ enabled: Bool) {
        isCaffeinated = enabled
    }
}

private enum MenuBarExpandedSection {
    case timer
    case schedule
}

private struct LatteSwitchToggleStyle: ToggleStyle {
    let accessibilityLabel: String

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? latteBrown : Color.secondary.opacity(0.28))
                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            }
            .frame(width: 52, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private var latteBrown: Color {
        Color(
            red: CaffeineAppearance.latteBrown.red,
            green: CaffeineAppearance.latteBrown.green,
            blue: CaffeineAppearance.latteBrown.blue
        )
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var state: MenuBarState
    @ObservedObject var settings: MenuBarSettingsModel
    @State private var expanded: MenuBarExpandedSection?
    @State private var selectedScheduleMode: CaffeineScheduleMode?

    init(state: MenuBarState, settings: MenuBarSettingsModel) {
        self.state = state
        self.settings = settings
        _expanded = State(initialValue: settings.timerIsActive ? .timer : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    state.isCaffeinated ? "Caffeinated" : "Decaffeinated",
                    systemImage: CaffeineAppearance.systemSymbolName(isCaffeinated: state.isCaffeinated)
                )
                .font(.headline)
                Spacer()
                Toggle("Caffeine", isOn: Binding(
                    get: { state.isCaffeinated },
                    set: { state.set($0) }
                ))
                .labelsHidden()
                .toggleStyle(LatteSwitchToggleStyle(accessibilityLabel: "Caffeine"))
            }
            .frame(minHeight: 44)

            Divider()
            sectionButton("Timer", symbol: "timer", section: .timer)
            if expanded == .timer {
                timerEditor
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            Divider()
            sectionButton("Schedule", symbol: "calendar", section: .schedule)
            if expanded == .schedule {
                scheduleEditor
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionButton(
        _ title: String,
        symbol: String,
        section: MenuBarExpandedSection
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                if expanded == section {
                    expanded = nil
                } else {
                    expanded = section
                    if section == .schedule {
                        selectedScheduleMode = nil
                    }
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
                Image(systemName: expanded == section ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timerEditor: some View {
        VStack(spacing: 10) {
            if settings.timerIsActive {
                activeTimer
            } else {
                CoffeeCupCountdown(fillFraction: 0)

                Text("No timer running")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(darkCoffeeBrown.opacity(0.72))

                HStack {
                    Stepper(value: $settings.timerHours, in: 0...168) {
                        Text("\(settings.timerHours) hr")
                            .monospacedDigit()
                            .frame(width: 58, alignment: .leading)
                    }
                    Stepper(value: $settings.timerMinutes, in: 0...59) {
                        Text("\(settings.timerMinutes) min")
                            .monospacedDigit()
                            .frame(width: 66, alignment: .leading)
                    }
                }
                Button("Start Timer") { settings.startTimer() }
                    .buttonStyle(.borderedProminent)
                    .tint(cream)
                    .foregroundStyle(darkCoffeeBrown)
                    .disabled(settings.timerHours == 0 && settings.timerMinutes == 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var activeTimer: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = remainingTimerSeconds(at: context.date)
                VStack(spacing: 7) {
                    CoffeeCupCountdown(fillFraction: CoffeeTimerGauge.fillFraction(
                        remainingSeconds: remaining,
                        durationSeconds: settings.timerInitialDurationSeconds,
                        isActive: settings.timerIsActive
                    ))
                    Text(TimerCountdownFormatter.string(remainingSeconds: remaining))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(darkCoffeeBrown)
                    Text("Remaining")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(darkCoffeeBrown.opacity(0.58))
                }
            }

            Button("Stop", role: .destructive) { settings.stopTimer() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private var darkCoffeeBrown: Color {
        Color(
            red: CaffeineAppearance.darkCoffeeBrown.red,
            green: CaffeineAppearance.darkCoffeeBrown.green,
            blue: CaffeineAppearance.darkCoffeeBrown.blue
        )
    }

    private var cream: Color {
        Color(red: 1, green: 0.976, blue: 0.933)
    }

    private func remainingTimerSeconds(at date: Date) -> TimeInterval {
        switch settings.timerState {
        case let .running(endDate):
            return max(0, endDate.timeIntervalSince(date))
        case let .paused(remaining):
            return remaining
        case .inactive:
            return 0
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.hasUnsupportedSchedule {
                HStack(spacing: 12) {
                    Text("Advanced schedule enabled")
                    Toggle("Advanced schedule enabled", isOn: Binding(
                        get: { settings.scheduleEnabled },
                        set: { settings.setScheduleEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                Text("This advanced recurrence is preserved and can only be enabled or disabled here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Schedule type", selection: Binding<CaffeineScheduleMode?>(
                get: { selectedScheduleMode },
                set: { mode in
                    selectedScheduleMode = mode
                    if let mode {
                        settings.selectScheduleMode(mode)
                    }
                }
            )) {
                ForEach(CaffeineScheduleMode.allCases) { mode in
                    Text(mode == .oneTime ? "One Time" : mode.rawValue)
                        .tag(Optional(mode))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: 28)

            if let selectedScheduleMode {
                HStack(spacing: 12) {
                    Text("Schedule enabled")
                    Toggle("Schedule enabled", isOn: Binding(
                        get: { settings.scheduleIsEnabled(selectedScheduleMode) },
                        set: { settings.setScheduleEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                switch selectedScheduleMode {
                case .oneTime:
                    dateTimeRow("Start", date: Binding(
                        get: { settings.oneTimeStart },
                        set: { settings.setOneTime(start: $0, end: settings.oneTimeEnd) }
                    ))
                    dateTimeRow("Stop", date: Binding(
                        get: { settings.oneTimeEnd },
                        set: { settings.setOneTime(start: settings.oneTimeStart, end: $0) }
                    ))
                case .everyDay, .weekdays:
                    timeWindowRows(settings.sharedWindow) { settings.setSharedWindow($0) }
                case .custom:
                    customEditor
                }
            }
            }
        }
        .padding(.horizontal, 4)
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    let weekday = index + 1
                    let selected = settings.customWindows[weekday] != nil
                    Button {
                        settings.setCustomDay(weekday, enabled: !selected)
                    } label: {
                        Text(symbol)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                        .buttonStyle(.plain)
                        .background(selected ? darkCoffeeBrown : Color.secondary.opacity(0.14), in: Circle())
                        .foregroundStyle(selected ? .white : .primary)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[index])
                }
            }
            if !settings.customWindows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(settings.customWindows.keys.sorted(), id: \.self) { weekday in
                            if let window = settings.customWindows[weekday] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Calendar.current.shortWeekdaySymbols[weekday - 1])
                                        .font(.subheadline.weight(.semibold))
                                    timeWindowRows(window) { settings.setCustomWindow($0, for: weekday) }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(settings.customWindows.count) * 86, 300))
            }
        }
    }

    private func dateTimeRow(_ label: String, date: Binding<Date>) -> some View {
        HStack {
            Text(label).frame(width: 42, alignment: .trailing)
            DatePicker(label, selection: date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
    }

    private func timeWindowRows(
        _ window: CaffeineDayWindow,
        onChange: @escaping (CaffeineDayWindow) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            timeRow("Start", minutes: window.onMinutes) {
                onChange(CaffeineDayWindow(onMinutes: $0, offMinutes: window.offMinutes))
            }
            timeRow("Stop", minutes: window.offMinutes) {
                onChange(CaffeineDayWindow(onMinutes: window.onMinutes, offMinutes: $0))
            }
        }
    }

    private func timeRow(
        _ label: String,
        minutes: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack {
            Text(label).frame(width: 42, alignment: .trailing)
            DatePicker(label, selection: Binding(
                get: { Self.date(for: minutes) },
                set: { onChange(Self.minutes(for: $0)) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
    }

    private static func date(for minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: minutes / 60,
            minute: minutes % 60
        ))!
    }

    private static func minutes(for date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

enum MenuBarAnchorValidator {
    static func isReady(buttonRect: CGRect, screenFrame: CGRect) -> Bool {
        guard buttonRect.width > 0, buttonRect.height > 0 else { return false }
        let topMenuBarBand = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - 60,
            width: screenFrame.width,
            height: 65
        )
        return topMenuBarBand.intersects(buttonRect)
    }

    static func attachedOriginY(statusWindowFrame: CGRect, popoverHeight: CGFloat) -> CGFloat {
        statusWindowFrame.minY - popoverHeight
    }

    static func attachedOriginX(
        statusWindowFrame: CGRect,
        popoverWidth: CGFloat,
        visibleFrame: CGRect
    ) -> CGFloat {
        let centered = statusWindowFrame.midX - popoverWidth / 2
        let maximum = max(visibleFrame.minX, visibleFrame.maxX - popoverWidth)
        return min(max(centered, visibleFrame.minX), maximum)
    }
}

enum MenuBarPanelPresenter {
    static func prepareForPresentation(_ panel: NSPanel) {
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
    }
}

enum MenuBarStatusItemPresenter {
    static let autosaveName: NSStatusItem.AutosaveName? = nil
    static let behavior: NSStatusItem.Behavior = []

    static func prepare(_ statusItem: NSStatusItem) {
        statusItem.autosaveName = autosaveName
        statusItem.behavior = behavior
        statusItem.isVisible = true
    }
}

private struct CoffeeCupBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.maxY - 15))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 20, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 8, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + 20, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 7, y: rect.maxY - 15),
            control: CGPoint(x: rect.minX + 8, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct CoffeeCupCountdown: View {
    let fillFraction: Double

    private var clampedFill: CGFloat {
        CGFloat(min(1, max(0, fillFraction)))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .stroke(cream, lineWidth: 6)
                .frame(width: 20, height: 29)
                .offset(x: 34, y: 4)

            ZStack {
                CoffeeCupBody()
                    .fill(panelGray)

                GeometryReader { proxy in
                    let fillHeight = proxy.size.height * clampedFill
                    VStack(spacing: -2) {
                        Ellipse()
                            .fill(coffeeHighlight)
                            .frame(height: min(6, fillHeight))
                        Rectangle()
                            .fill(coffeeBrown)
                    }
                    .frame(height: fillHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(clampedFill > 0 ? 1 : 0)
                }
                .mask(CoffeeCupBody())

                CoffeeCupBody()
                    .stroke(cream, lineWidth: 6)
            }
            .frame(width: 59, height: 55)
            .offset(x: -4)
        }
        .frame(width: 76, height: 67)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clampedFill > 0 ? "Coffee timer remaining" : "No timer running")
    }

    private var coffeeBrown: Color {
        Color(red: 0.35, green: 0.22, blue: 0.13)
    }

    private var coffeeHighlight: Color {
        Color(red: 0.58, green: 0.40, blue: 0.27)
    }

    private var panelGray: Color {
        Color(
            red: CaffeineAppearance.panelGray.red,
            green: CaffeineAppearance.panelGray.green,
            blue: CaffeineAppearance.panelGray.blue
        )
    }

    private var cream: Color {
        Color(red: 1, green: 0.976, blue: 0.933)
    }
}

private struct MenuBarPopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MenuBarPanelRoot: View {
    @ObservedObject var state: MenuBarState
    @ObservedObject var settings: MenuBarSettingsModel
    let sizeChanged: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuBarPopoverArrow()
                .fill(panelGray)
                .frame(width: 24, height: 11)
            MenuBarPopoverView(state: state, settings: settings)
                .background(panelGray, in: RoundedRectangle(cornerRadius: 18))
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            sizeChanged(size)
        }
    }

    private var panelGray: Color {
        Color(
            red: CaffeineAppearance.panelGray.red,
            green: CaffeineAppearance.panelGray.green,
            blue: CaffeineAppearance.panelGray.blue
        )
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let state: MenuBarState
    private let settings: MenuBarSettingsModel
    private weak var anchorWindow: NSWindow?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(
        isCaffeinated: Bool,
        setState: @escaping (Bool) -> Void,
        post: @escaping (String) -> Void
    ) {
        state = MenuBarState(isCaffeinated: isCaffeinated, setState: setState)
        settings = MenuBarSettingsModel(post: post)
        super.init()
        MenuBarStatusItemPresenter.prepare(statusItem)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        resetPanelContent()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.panel.orderOut(nil) }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.panel.isVisible, event.window !== self.panel {
                self.panel.orderOut(nil)
            }
            return event
        }
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: CaffeineAppearance.systemSymbolName(isCaffeinated: isCaffeinated),
                accessibilityDescription: "Caffeine"
            )
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func refresh(isCaffeinated: Bool) {
        state.refresh(isCaffeinated)
        statusItem.button?.image = NSImage(
            systemSymbolName: CaffeineAppearance.systemSymbolName(isCaffeinated: isCaffeinated),
            accessibilityDescription: isCaffeinated ? "Caffeine on" : "Caffeine off"
        )
        settings.reload()
    }

    func showPopover(attempt: Int = 0) {
        guard
            let button = statusItem.button,
            let window = button.window,
            let screen = window.screen
        else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        if !MenuBarAnchorValidator.isReady(buttonRect: buttonRect, screenFrame: screen.frame),
           attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showPopover(attempt: attempt + 1)
            }
            return
        }
        settings.reload()
        anchorWindow = window
        resetPanelContent()
        panel.contentView?.layoutSubtreeIfNeeded()
        resizeAndAttachPanel(to: panel.contentView?.fittingSize ?? NSSize(width: 340, height: 188))
        MenuBarPanelPresenter.prepareForPresentation(panel)
        panel.orderFrontRegardless()
    }

    private func resizeAndAttachPanel(to size: CGSize) {
        guard
            let anchorWindow,
            let screen = anchorWindow.screen,
            size.width > 0,
            size.height > 0
        else { return }
        let origin = CGPoint(
            x: MenuBarAnchorValidator.attachedOriginX(
                statusWindowFrame: anchorWindow.frame,
                popoverWidth: size.width,
                visibleFrame: screen.visibleFrame
            ),
            y: MenuBarAnchorValidator.attachedOriginY(
                statusWindowFrame: anchorWindow.frame,
                popoverHeight: size.height
            )
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func resetPanelContent() {
        panel.contentViewController = NSHostingController(
            rootView: MenuBarPanelRoot(state: state, settings: settings) { [weak self] size in
                DispatchQueue.main.async { self?.resizeAndAttachPanel(to: size) }
            }
        )
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showPopover()
        } else {
            state.toggle()
        }
    }
}
