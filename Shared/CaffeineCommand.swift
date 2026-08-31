enum CaffeineCommand {
    static let turnOnNotification = "com.kimiyashar.CaffeineToggle.turnOn"
    static let turnOffNotification = "com.kimiyashar.CaffeineToggle.turnOff"

    static func notificationName(for enabled: Bool) -> String {
        enabled ? turnOnNotification : turnOffNotification
    }
}
