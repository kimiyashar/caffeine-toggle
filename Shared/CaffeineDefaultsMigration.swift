import Foundation

enum CaffeineDefaultsMigration {
    static let legacyBundleIdentifier = "com.kimiyashar.CaffeineToggle"
    static let menuBarBundleIdentifier = "com.kimiyashar.CaffeineToggle.MenuBarApp"
    static let completionKey = "migration.menuBarBundleIdentity.v1"

    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        legacyValues: [String: Any]? = nil,
        now: Date = Date()
    ) {
        guard bundleIdentifier == menuBarBundleIdentifier,
              !defaults.bool(forKey: completionKey)
        else { return }

        let values = legacyValues
            ?? defaults.persistentDomain(forName: legacyBundleIdentifier)
            ?? [:]
        for (key, value) in values
        where defaults.object(forKey: key) == nil && !key.hasPrefix("NSStatusItem ") {
            defaults.set(value, forKey: key)
        }
        migrateLegacyTimerDuration(defaults: defaults, now: now)
        defaults.set(true, forKey: completionKey)
        defaults.synchronize()
    }

    private static func migrateLegacyTimerDuration(defaults: UserDefaults, now: Date) {
        guard defaults.object(forKey: "session.duration") == nil else { return }
        let runningRemaining = (defaults.object(forKey: "session.endDate") as? Date)?
            .timeIntervalSince(now)
        let pausedRemaining = defaults.object(forKey: "session.pausedRemaining") as? Double
        let remaining = [runningRemaining, pausedRemaining]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 > 0 }
            .max()
        guard let remaining else { return }
        let preferredMinutes = defaults.object(forKey: "timer.preferredMinutes") as? Int ?? 120
        let preferredDuration = Double(min(10_080, max(1, preferredMinutes)) * 60)
        defaults.set(max(remaining, preferredDuration), forKey: "session.duration")
    }
}