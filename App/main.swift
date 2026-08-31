import AppKit
import Foundation
import IOKit

private enum SharedState {
    static let key = "isCaffeinated"
    static let changed = CFNotificationName("com.kimiyashar.CaffeineToggle.stateChanged" as CFString)
    static let turnOn = CFNotificationName(CaffeineCommand.turnOnNotification as CFString)
    static let turnOff = CFNotificationName(CaffeineCommand.turnOffNotification as CFString)

    static var isCaffeinated: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    static func notify() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            changed,
            nil,
            nil,
            true
        )
    }
}

// Command mode is used for installation checks and local automation.
if CommandLine.arguments.count > 1 {
    switch CommandLine.arguments[1] {
    case "--on":
        SharedState.isCaffeinated = true
        SharedState.notify()
        exit(0)
    case "--off":
        SharedState.isCaffeinated = false
        SharedState.notify()
        exit(0)
    case "--toggle":
        SharedState.isCaffeinated.toggle()
        SharedState.notify()
        exit(0)
    case "--status":
        print(SharedState.isCaffeinated ? "caffeinated" : "decaffeinated")
        exit(0)
    default:
        break
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var caffeinateProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
                guard let observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                let receivedName = name?.rawValue as String?
                DispatchQueue.main.async {
                    if receivedName == CaffeineCommand.turnOnNotification {
                        SharedState.isCaffeinated = true
                    } else if receivedName == CaffeineCommand.turnOffNotification {
                        SharedState.isCaffeinated = false
                    }
                    delegate.applyDesiredState()
                }
        }
        for name in [SharedState.changed, SharedState.turnOn, SharedState.turnOff] {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                callback,
                name.rawValue,
                nil,
                .deliverImmediately
            )
        }
        applyDesiredState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [SharedState.changed, SharedState.turnOn, SharedState.turnOff] {
            CFNotificationCenterRemoveObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                name,
                nil
            )
        }
        stopCaffeinating()
    }

    fileprivate func applyDesiredState() {
        if SharedState.isCaffeinated {
            startCaffeinating()
        } else {
            stopCaffeinating()
        }
    }

    private func startCaffeinating() {
        guard caffeinateProcess?.isRunning != true else { return }
        let clamshellResult = ClamshellController.setSleepDisabled(true)
        guard clamshellResult == kIOReturnSuccess else {
            NSLog("Caffeine Toggle could not disable clamshell sleep: 0x%08x", clamshellResult)
            SharedState.isCaffeinated = false
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-i", "-m", "-s"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.caffeinateProcess === finished else { return }
                self.caffeinateProcess = nil
            }
        }
        do {
            try process.run()
            caffeinateProcess = process
        } catch {
            NSLog("Caffeine Toggle could not start caffeinate: %@", error.localizedDescription)
            ClamshellController.setSleepDisabled(false)
            SharedState.isCaffeinated = false
        }
    }

    private func stopCaffeinating() {
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
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
