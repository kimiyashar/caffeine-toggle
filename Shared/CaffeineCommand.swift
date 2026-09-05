enum CaffeineCommand {
    static let controlBundleIdentifier = "com.kimiyashar.CaffeineToggle.Controls"
    static let controlKind = "com.kimiyashar.CaffeineToggle.control"
    static let scheduleControlKind = "com.kimiyashar.CaffeineToggle.schedule"
    static let turnOnNotification = "com.kimiyashar.CaffeineToggle.turnOn"
    static let turnOffNotification = "com.kimiyashar.CaffeineToggle.turnOff"
    static let scheduleChangedNotification = "com.kimiyashar.CaffeineToggle.scheduleChanged"
    static let sessionChangedNotification = "com.kimiyashar.CaffeineToggle.sessionChanged"
    static let showScheduleNotification = "com.kimiyashar.CaffeineToggle.showSchedule"
    static let showScheduleRestoringOnNotification = "com.kimiyashar.CaffeineToggle.showScheduleRestoringOn"
    static let showScheduleRestoringOffNotification = "com.kimiyashar.CaffeineToggle.showScheduleRestoringOff"
    static let requestStateNotification = "com.kimiyashar.CaffeineToggle.requestState"
    static let stateIsOnNotification = "com.kimiyashar.CaffeineToggle.stateIsOn"
    static let stateIsOffNotification = "com.kimiyashar.CaffeineToggle.stateIsOff"

    static func notificationName(for enabled: Bool) -> String {
        enabled ? turnOnNotification : turnOffNotification
    }
}
