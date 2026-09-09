import AppKit
import Foundation
import IOKit

CaffeineDefaultsMigration.migrateIfNeeded()

private enum SharedState {
    static let key = "isCaffeinated"
    static let pendingShowKey = "schedule.pendingShow"
    static let changed = CFNotificationName("com.kimiyashar.CaffeineToggle.stateChanged" as CFString)
    static let turnOn = CFNotificationName(CaffeineCommand.turnOnNotification as CFString)
    static let turnOff = CFNotificationName(CaffeineCommand.turnOffNotification as CFString)
    static let scheduleChanged = CFNotificationName(CaffeineCommand.scheduleChangedNotification as CFString)
    static let sessionChanged = CFNotificationName(CaffeineCommand.sessionChangedNotification as CFString)
    static let showSchedule = CFNotificationName(CaffeineCommand.showScheduleNotification as CFString)
    static let showScheduleRestoringOn = CFNotificationName(CaffeineCommand.showScheduleRestoringOnNotification as CFString)
    static let showScheduleRestoringOff = CFNotificationName(CaffeineCommand.showScheduleRestoringOffNotification as CFString)
    static let requestState = CFNotificationName(CaffeineCommand.requestStateNotification as CFString)

    static var isCaffeinated: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    static var hasPendingShowRequest: Bool {
        get { UserDefaults.standard.bool(forKey: pendingShowKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: pendingShowKey)
            UserDefaults.standard.synchronize()
        }
    }

    static func post(_ name: CFNotificationName = changed) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }
}

private func clockString(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

// Command mode is used for installation checks and deterministic automation.
if CommandLine.arguments.count > 1 {
    let command = CommandLine.arguments[1]
    switch command {
    case "--on":
        SharedState.isCaffeinated = true
        SharedState.post()
        exit(0)
    case "--off":
        SharedState.isCaffeinated = false
        SharedState.post()
        exit(0)
    case "--toggle":
        SharedState.isCaffeinated.toggle()
        SharedState.post()
        exit(0)
    case "--status":
        print(SharedState.isCaffeinated ? "caffeinated" : "decaffeinated")
        exit(0)
    case "--session":
        guard
            CommandLine.arguments.count == 3,
            let minutes = Int(CommandLine.arguments[2]),
            (1...(7 * 24 * 60)).contains(minutes)
        else {
            fputs("usage: CaffeineToggle --session MINUTES (1...10080)\n", stderr)
            exit(64)
        }
        let store = CaffeineScheduleStore()
        store.startTimer(duration: Double(minutes) * 60, at: Date())
        store.manualOverrideUntil = nil
        SharedState.post(SharedState.sessionChanged)
        print("session started for \(minutes) minute\(minutes == 1 ? "" : "s")")
        exit(0)
    case "--stop-session":
        CaffeineScheduleStore().stopTimer()
        SharedState.post(SharedState.sessionChanged)
        print("session stopped")
        exit(0)
    case "--session-status":
        switch CaffeineScheduleStore().timerSession(at: Date()) {
        case let .running(endDate):
            print("active until \(endDate.formatted(date: .abbreviated, time: .standard))")
        case let .paused(remaining):
            print("paused with \(TimerCountdownFormatter.string(remainingSeconds: remaining)) remaining")
        case .inactive:
            print("inactive")
        }
        exit(0)
    case "--schedule":
        guard
            CommandLine.arguments.count == 4,
            let onMinutes = CaffeineSchedule.parseClockTime(CommandLine.arguments[2]),
            let offMinutes = CaffeineSchedule.parseClockTime(CommandLine.arguments[3]),
            onMinutes != offMinutes
        else {
            fputs("usage: CaffeineToggle --schedule HH:mm HH:mm (times must differ)\n", stderr)
            exit(64)
        }
        let schedule = CaffeineSchedule(enabled: true, onMinutes: onMinutes, offMinutes: offMinutes)
        CaffeineScheduleStore().save(schedule)
        SharedState.post(SharedState.scheduleChanged)
        print("schedule enabled: \(clockString(onMinutes))-\(clockString(offMinutes))")
        exit(0)
    case "--disable-schedule":
        let store = CaffeineScheduleStore()
        var schedule = store.load()
        schedule.enabled = false
        store.save(schedule)
        SharedState.post(SharedState.scheduleChanged)
        print("schedule disabled")
        exit(0)
    case "--schedule-status":
        let schedule = CaffeineScheduleStore().load()
        if schedule.enabled {
            print("enabled \(clockString(schedule.onMinutes))-\(clockString(schedule.offMinutes))")
        } else {
            print("disabled \(clockString(schedule.onMinutes))-\(clockString(schedule.offMinutes))")
        }
        exit(0)
    case "--show-schedule":
        SharedState.hasPendingShowRequest = true
        SharedState.post(SharedState.showSchedule)
        exit(0)
    default:
        break
    }
}

private let instanceLockPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Caffeine Toggle/helper.lock")
    .path
private let instanceLock = SingleInstanceLock(path: instanceLockPath)
if instanceLock == nil {
    if MenuBarLaunchPolicy.requestsPanelForDuplicateLaunch {
        SharedState.hasPendingShowRequest = true
        SharedState.post(SharedState.showSchedule)
    }
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var caffeinateProcess: Process?
    private var scheduleTimer: Timer?
    private var restartPolicy = CaffeineRestartPolicy()
    private var legacyRestoreBuffer = CaffeineLegacyRestoreBuffer()
    private let scheduleStore = CaffeineScheduleStore()
    private lazy var menuBarController = MenuBarController(
        isCaffeinated: SharedState.isCaffeinated,
        setState: { [weak self] enabled in self?.handleManualStateChange(to: enabled) },
        post: { notificationName in
            SharedState.post(CFNotificationName(notificationName as CFString))
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = menuBarController
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
            let receivedName = name?.rawValue as String?
            DispatchQueue.main.async {
                delegate.handleDarwinNotification(named: receivedName)
            }
        }
        for name in observedDarwinNotifications {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                callback,
                name.rawValue,
                nil,
                .deliverImmediately
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockChanged),
            name: NSNotification.Name.NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockChanged),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemClockChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if SharedState.hasPendingShowRequest {
            menuBarController.showPopover()
            SharedState.hasPendingShowRequest = false
        }
        reconcileAutomationWithCurrentTime()
        SharedState.isCaffeinated = SharedState.isCaffeinated
        applyDesiredState()
        scheduleNextTransition()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduleTimer?.invalidate()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in observedDarwinNotifications {
            CFNotificationCenterRemoveObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                name,
                nil
            )
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopCaffeinating()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard MenuBarReopenPolicy.shouldPresentPanel(
            hasPendingShowRequest: SharedState.hasPendingShowRequest
        ) else { return false }
        menuBarController.showPopover()
        SharedState.hasPendingShowRequest = false
        return true
    }

    private var observedDarwinNotifications: [CFNotificationName] {
        [
            SharedState.changed,
            SharedState.turnOn,
            SharedState.turnOff,
            SharedState.scheduleChanged,
            SharedState.sessionChanged,
            SharedState.showSchedule,
            SharedState.showScheduleRestoringOn,
            SharedState.showScheduleRestoringOff,
            SharedState.requestState
        ]
    }

    private func handleDarwinNotification(named name: String?) {
        switch name {
        case CaffeineCommand.turnOnNotification:
            handleManualStateChange(to: true)
        case CaffeineCommand.turnOffNotification:
            handleManualStateChange(to: false)
        case CaffeineCommand.scheduleChangedNotification:
            legacyRestoreBuffer.invalidate()
            scheduleStore.manualOverrideUntil = nil
            reconcileAutomationWithCurrentTime(respectingManualOverride: false)
            applyDesiredState()
            scheduleNextTransition()
        case CaffeineCommand.sessionChangedNotification:
            legacyRestoreBuffer.invalidate()
            scheduleStore.manualOverrideUntil = nil
            reconcileAutomationWithCurrentTime(
                respectingManualOverride: false,
                turnOffIfNoAutomation: true
            )
            applyDesiredState()
            scheduleNextTransition()
        case CaffeineCommand.requestStateNotification:
            SharedState.post(CFNotificationName(
                (SharedState.isCaffeinated
                    ? CaffeineCommand.stateIsOnNotification
                    : CaffeineCommand.stateIsOffNotification) as CFString
            ))
        case CaffeineCommand.showScheduleRestoringOnNotification:
            restoreStateAfterDoubleClickAndShow(enabled: true)
        case CaffeineCommand.showScheduleRestoringOffNotification:
            restoreStateAfterDoubleClickAndShow(enabled: false)
        case CaffeineCommand.showScheduleNotification:
            menuBarController.showPopover()
            SharedState.hasPendingShowRequest = false
        default:
            handleManualStateChange(to: SharedState.isCaffeinated)
        }
    }

    private func restoreStateAfterDoubleClickAndShow(enabled: Bool) {
        let now = Date()
        guard let snapshot = legacyRestoreBuffer.consume(restoring: enabled, at: now) else {
            menuBarController.showPopover()
            SharedState.hasPendingShowRequest = false
            return
        }
        scheduleStore.sessionEndDate = snapshot.sessionEndDate
        scheduleStore.manualOverrideUntil = snapshot.manualOverrideUntil
        SharedState.isCaffeinated = enabled
        reconcileAutomationWithCurrentTime(now: now)
        applyDesiredState()
        scheduleNextTransition(now: now)
        menuBarController.showPopover()
        SharedState.hasPendingShowRequest = false
    }

    private func handleManualStateChange(to enabled: Bool, now: Date = Date()) {
        legacyRestoreBuffer.capture(CaffeineLegacyRestoreSnapshot(
            state: SharedState.isCaffeinated,
            sessionEndDate: scheduleStore.sessionEndDate,
            manualOverrideUntil: scheduleStore.manualOverrideUntil,
            capturedAt: now
        ))
        if !enabled, scheduleStore.pauseTimer(at: now) {
            SharedState.isCaffeinated = false
            scheduleStore.manualOverrideUntil = nil
            applyDesiredState()
            scheduleNextTransition(now: now)
            return
        }
        if enabled, scheduleStore.resumeTimer(at: now) {
            SharedState.isCaffeinated = true
            scheduleStore.manualOverrideUntil = nil
            applyDesiredState()
            scheduleNextTransition(now: now)
            return
        }
        SharedState.isCaffeinated = enabled
        let schedule = scheduleStore.load()
        scheduleStore.manualOverrideUntil = schedule.nextTransition(after: now)?.date
        applyDesiredState()
        scheduleNextTransition(now: now)
    }

    @objc private func systemClockChanged() {
        let now = Date()
        legacyRestoreBuffer.invalidate()
        let schedule = scheduleStore.load()
        scheduleStore.manualOverrideUntil = schedule.rebasedManualOverride(
            scheduleStore.manualOverrideUntil,
            afterClockChangeAt: now
        )
        reconcileAutomationWithCurrentTime(now: now)
        applyDesiredState()
        scheduleNextTransition(now: now)
    }

    @objc private func scheduleTimerFired() {
        reconcileAutomationWithCurrentTime()
        applyDesiredState()
        scheduleNextTransition()
    }

    private func reconcileAutomationWithCurrentTime(
        now: Date = Date(),
        respectingManualOverride: Bool = true,
        turnOffIfNoAutomation: Bool = false
    ) {
        var sessionExpired = false
        switch scheduleStore.timerSession(at: now) {
        case .running:
            SharedState.isCaffeinated = true
            return
        case .paused:
            SharedState.isCaffeinated = false
            return
        case .inactive:
            if scheduleStore.sessionEndDate != nil {
                sessionExpired = true
                scheduleStore.stopTimer()
            }
        }

        if respectingManualOverride,
           let overrideUntil = scheduleStore.manualOverrideUntil,
           overrideUntil > now {
            return
        }
        scheduleStore.manualOverrideUntil = nil

        var schedule = scheduleStore.load()
        let completedSchedule = schedule.disablingCompletedOneTime(at: now)
        if completedSchedule != schedule {
            schedule = completedSchedule
            scheduleStore.save(schedule)
            SharedState.isCaffeinated = false
        }
        if sessionExpired || turnOffIfNoAutomation {
            SharedState.isCaffeinated = false
            scheduleStore.manualOverrideUntil = schedule.nextTransition(after: now)?.date
        } else if schedule.enabled, schedule.isValid {
            SharedState.isCaffeinated = schedule.shouldBeCaffeinated(at: now)
        }
    }

    private func scheduleNextTransition(now: Date = Date()) {
        scheduleTimer?.invalidate()
        scheduleTimer = nil

        var dates: [Date] = []
        if let transition = scheduleStore.load().nextTransition(after: now) {
            dates.append(transition.date)
        }
        if let sessionEndDate = scheduleStore.sessionEndDate, sessionEndDate > now {
            dates.append(sessionEndDate)
        }
        if let overrideUntil = scheduleStore.manualOverrideUntil, overrideUntil > now {
            dates.append(overrideUntil)
        }
        guard let nextDate = dates.min() else { return }

        let timer = Timer(
            fireAt: nextDate,
            interval: 0,
            target: self,
            selector: #selector(scheduleTimerFired),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    fileprivate func applyDesiredState() {
        if SharedState.isCaffeinated {
            startCaffeinating()
        } else {
            stopCaffeinating()
        }
        menuBarController.refresh(isCaffeinated: SharedState.isCaffeinated)
    }

    private func startCaffeinating() {
        guard caffeinateProcess?.isRunning != true else { return }
        let clamshellResult = ClamshellController.setSleepDisabled(true)
        guard clamshellResult == kIOReturnSuccess else {
            NSLog("Caffeine Toggle could not disable clamshell sleep: 0x%08x", clamshellResult)
            SharedState.isCaffeinated = false
            applyDesiredState()
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = CaffeinateArguments.forHelper(pid: getpid())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.caffeinateProcess === finished else { return }
                self.caffeinateProcess = nil
                guard SharedState.isCaffeinated else { return }
                guard self.restartPolicy.shouldRestart() else {
                    NSLog("Caffeine: caffeinate exited repeatedly; restoring normal sleep")
                    SharedState.isCaffeinated = false
                    self.applyDesiredState()
                    return
                }
                NSLog("Caffeine: caffeinate exited unexpectedly; restarting")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.applyDesiredState()
                }
            }
        }
        do {
            try process.run()
            caffeinateProcess = process
        } catch {
            NSLog("Caffeine Toggle could not start caffeinate: %@", error.localizedDescription)
            ClamshellController.setSleepDisabled(false)
            SharedState.isCaffeinated = false
            applyDesiredState()
        }
    }

    private func stopCaffeinating() {
        restartPolicy.reset()
        let restoreResult = ClamshellController.setSleepDisabled(false)
        if restoreResult != kIOReturnSuccess {
            NSLog("Caffeine Toggle could not restore clamshell sleep: 0x%08x", restoreResult)
        }
        let process = caffeinateProcess
        caffeinateProcess = nil
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
