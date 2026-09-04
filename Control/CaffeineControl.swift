import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private final class CaffeineStateResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool?, Never>?
    private var observer: UnsafeMutableRawPointer?

    init(continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func configure(observer: UnsafeMutableRawPointer) {
        self.observer = observer
    }

    func finish(with value: Bool?) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        if let observer {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterRemoveObserver(
                center,
                observer,
                CFNotificationName(CaffeineCommand.stateIsOnNotification as CFString),
                nil
            )
            CFNotificationCenterRemoveObserver(
                center,
                observer,
                CFNotificationName(CaffeineCommand.stateIsOffNotification as CFString),
                nil
            )
        }
        continuation.resume(returning: value)
    }
}

private enum SharedState {
    static let key = "isCaffeinated"
    static let lastToggleTimeKey = "lastToggleTime"
    static let doubleClickOriginalStateKey = "doubleClickOriginalState"
    static let pendingShowKey = "schedule.pendingShow"
    private static let gestureLock = NSLock()

    static var isCaffeinated: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    static var lastToggleTime: Double? {
        get { UserDefaults.standard.object(forKey: lastToggleTimeKey) as? Double }
        set { UserDefaults.standard.set(newValue, forKey: lastToggleTimeKey) }
    }

    static var doubleClickOriginalState: Bool? {
        get { UserDefaults.standard.object(forKey: doubleClickOriginalStateKey) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: doubleClickOriginalStateKey) }
    }

    static func currentHostState(timeout: TimeInterval = 0.2) async -> Bool? {
        await withCheckedContinuation { continuation in
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let response = CaffeineStateResponse(continuation: continuation)
            let pointer = Unmanaged.passUnretained(response).toOpaque()
            response.configure(observer: pointer)
            let callback: CFNotificationCallback = { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let response = Unmanaged<CaffeineStateResponse>.fromOpaque(observer).takeUnretainedValue()
                switch name.rawValue as String {
                case CaffeineCommand.stateIsOnNotification:
                    response.finish(with: true)
                case CaffeineCommand.stateIsOffNotification:
                    response.finish(with: false)
                default:
                    break
                }
            }
            CFNotificationCenterAddObserver(
                center,
                pointer,
                callback,
                CaffeineCommand.stateIsOnNotification as CFString,
                nil,
                .deliverImmediately
            )
            CFNotificationCenterAddObserver(
                center,
                pointer,
                callback,
                CaffeineCommand.stateIsOffNotification as CFString,
                nil,
                .deliverImmediately
            )
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                response.finish(with: nil)
            }
            post(CaffeineCommand.requestStateNotification)
        }
    }

    static func handleTap(value: Bool, now: Double) async -> Bool? {
        let liveState = await currentHostState() ?? isCaffeinated
        return gestureLock.withLock {
            if CaffeineDoubleClick.detect(previous: lastToggleTime, current: now) {
                let restoredValue = doubleClickOriginalState ?? liveState
                lastToggleTime = nil
                doubleClickOriginalState = nil
                isCaffeinated = restoredValue
                return restoredValue
            }

            lastToggleTime = now
            doubleClickOriginalState = liveState
            isCaffeinated = value
            notifyMainApp(enabled: value)
            return nil
        }
    }

    static func notifyMainApp(enabled: Bool) {
        post(CaffeineCommand.notificationName(for: enabled))
    }

    static func showSchedule(restoring enabled: Bool? = nil) {
        UserDefaults.standard.set(true, forKey: pendingShowKey)
        UserDefaults.standard.synchronize()
        if let enabled {
            post(enabled
                ? CaffeineCommand.showScheduleRestoringOnNotification
                : CaffeineCommand.showScheduleRestoringOffNotification)
        } else {
            post(CaffeineCommand.showScheduleNotification)
        }
    }

    private static func post(_ notificationName: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

struct CaffeineControl: ControlWidget {
    static let kind = CaffeineCommand.controlKind

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle(
                "Caffeine",
                isOn: value,
                action: SetCaffeineIntent(),
                valueLabel: { isOn in
                    Label {
                        Text(isOn ? "Caffeinated" : "Decaffeinated")
                    } icon: {
                        Image(systemName: CaffeineAppearance.systemSymbolName(isCaffeinated: isOn))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: isOn)
                    }
                }
            )
        }
        .displayName("Caffeine")
        .description("Single-click to toggle. Double-click to set a timer or repeating schedule.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            let value = await SharedState.currentHostState() ?? SharedState.isCaffeinated
            SharedState.isCaffeinated = value
            return value
        }
    }
}

struct SetCaffeineIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Caffeine"

    @Parameter(title: "Caffeinated")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let restoredState = await SharedState.handleTap(
            value: value,
            now: Date.timeIntervalSinceReferenceDate
        )
        if let restoredState {
            SharedState.showSchedule(restoring: restoredState)
        }
        return .result()
    }
}

struct ShowScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Caffeine Schedule"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        SharedState.showSchedule()
        return .result()
    }
}

struct CaffeineScheduleControl: ControlWidget {
    static let kind = "com.kimiyashar.CaffeineToggle.schedule"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ShowScheduleIntent()) {
                Label("Timer & Repeat", systemImage: "clock.badge")
            }
        }
        .displayName("Caffeine Timer & Repeat")
        .description("Open one-off Timer and repeating schedule settings.")
    }
}

@main
struct CaffeineControlsBundle: WidgetBundle {
    var body: some Widget {
        CaffeineControl()
        CaffeineScheduleControl()
    }
}
