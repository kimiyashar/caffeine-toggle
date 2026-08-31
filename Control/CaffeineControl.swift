import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private enum SharedState {
    static let key = "isCaffeinated"

    static var isCaffeinated: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    static func notifyMainApp(enabled: Bool) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CaffeineCommand.notificationName(for: enabled) as CFString),
            nil,
            nil,
            true
        )
    }
}

struct CaffeineControl: ControlWidget {
    static let kind = "com.kimiyashar.CaffeineToggle.control"

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
        .description("Keep this Mac and its display awake.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            SharedState.isCaffeinated
        }
    }
}

struct SetCaffeineIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Caffeine"

    @Parameter(title: "Caffeinated")
    var value: Bool

    func perform() async throws -> some IntentResult {
        SharedState.isCaffeinated = value
        SharedState.notifyMainApp(enabled: value)
        return .result()
    }
}

@main
struct CaffeineControlsBundle: WidgetBundle {
    var body: some Widget {
        CaffeineControl()
    }
}
