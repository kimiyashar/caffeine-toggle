import XCTest

final class CaffeineDefaultsMigrationTests: XCTestCase {
    func testMigratesCaffeineStateWithoutRestoringBlockedStatusItemMetadata() {
        let suiteName = "CaffeineDefaultsMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("keep current", forKey: "existing")

        CaffeineDefaultsMigration.migrateIfNeeded(
            defaults: defaults,
            bundleIdentifier: CaffeineDefaultsMigration.menuBarBundleIdentifier,
            legacyValues: [
                "isCaffeinated": true,
                "existing": "replace current",
                "NSStatusItem Preferred Position Item-0": 494,
                "NSStatusItem Visible Item-0": false,
            ]
        )

        XCTAssertTrue(defaults.bool(forKey: "isCaffeinated"))
        XCTAssertEqual(defaults.string(forKey: "existing"), "keep current")
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position Item-0"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Visible Item-0"))
        XCTAssertTrue(defaults.bool(forKey: CaffeineDefaultsMigration.completionKey))
    }

    func testDoesNotMigrateForTheLegacyBundleIdentity() {
        let suiteName = "CaffeineDefaultsMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CaffeineDefaultsMigration.migrateIfNeeded(
            defaults: defaults,
            bundleIdentifier: CaffeineDefaultsMigration.legacyBundleIdentifier,
            legacyValues: ["isCaffeinated": true]
        )

        XCTAssertNil(defaults.object(forKey: "isCaffeinated"))
        XCTAssertFalse(defaults.bool(forKey: CaffeineDefaultsMigration.completionKey))
    }

    func testMigratesOriginalDurationForAnActiveLegacyTimer() {
        let suiteName = "CaffeineDefaultsMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        CaffeineDefaultsMigration.migrateIfNeeded(
            defaults: defaults,
            bundleIdentifier: CaffeineDefaultsMigration.menuBarBundleIdentifier,
            legacyValues: [
                "session.endDate": now.addingTimeInterval(600),
                "timer.preferredMinutes": 120,
            ],
            now: now
        )

        XCTAssertEqual(defaults.double(forKey: "session.duration"), 7_200)
    }
}