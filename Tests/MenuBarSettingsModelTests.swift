import SwiftUI
import XCTest

@MainActor
final class MenuBarSettingsModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var notifications: [String]!

    override func setUp() {
        super.setUp()
        suiteName = "MenuBarSettingsModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        notifications = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        notifications = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartTimerUsesCustomHoursAndMinutes() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: now)
        model.timerHours = 1
        model.timerMinutes = 25

        model.startTimer()

        XCTAssertEqual(store.sessionEndDate, now.addingTimeInterval(85 * 60))
        XCTAssertEqual(notifications, [CaffeineCommand.sessionChangedNotification])
    }

    func testActiveTimerStateReplacesStartControlsAndFormatsCountdown() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store, now: now)
        model.timerHours = 2
        model.timerMinutes = 0

        model.startTimer()

        XCTAssertEqual(
            model.timerState,
            .running(endDate: now.addingTimeInterval(2 * 60 * 60))
        )
        XCTAssertTrue(model.timerIsActive)
        XCTAssertEqual(TimerCountdownFormatter.string(remainingSeconds: 7_199), "1:59:59")
        XCTAssertEqual(TimerCountdownFormatter.string(remainingSeconds: 59), "0:00:59")
    }

    func testCoffeeGaugeIsEmptyWhenTimerIsInactive() {
        XCTAssertEqual(
            CoffeeTimerGauge.fillFraction(
                remainingSeconds: 3_600,
                durationSeconds: 120 * 60,
                isActive: false
            ),
            0
        )
    }

    func testCoffeeGaugeTracksAndClampsRemainingDuration() {
        XCTAssertEqual(
            CoffeeTimerGauge.fillFraction(
                remainingSeconds: 45 * 60,
                durationSeconds: 90 * 60,
                isActive: true
            ),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CoffeeTimerGauge.fillFraction(
                remainingSeconds: 10_000,
                durationSeconds: 60,
                isActive: true
            ),
            1
        )
        XCTAssertEqual(
            CoffeeTimerGauge.fillFraction(
                remainingSeconds: -1,
                durationSeconds: 90 * 60,
                isActive: true
            ),
            0
        )
    }

    func testCoffeeGaugeAlwaysStartsFullAndEndsEmptyRegardlessOfDuration() {
        let durations: [TimeInterval] = [60, 5 * 60, 7 * 24 * 60 * 60]
        for duration in durations {
            XCTAssertEqual(
                CoffeeTimerGauge.fillFraction(
                    remainingSeconds: duration,
                    durationSeconds: duration,
                    isActive: true
                ),
                1
            )
            XCTAssertEqual(
                CoffeeTimerGauge.fillFraction(
                    remainingSeconds: 0,
                    durationSeconds: duration,
                    isActive: true
                ),
                0
            )
        }
    }

    func testActiveTimerGaugeUsesPersistedSessionDurationInsteadOfPickerPreference() {
        let now = Date(timeIntervalSinceReferenceDate: 71_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        store.preferredTimerMinutes = 123
        store.startTimer(duration: 5 * 60, at: now)

        let model = makeModel(store: store, now: now)

        XCTAssertEqual(model.timerInitialDurationSeconds, 5 * 60)
    }

    func testPausedTimerReloadsAsActiveAndCanBeStopped() {
        let now = Date(timeIntervalSinceReferenceDate: 30_000)
        let store = CaffeineScheduleStore(defaults: defaults)
        store.pausedSessionRemaining = 3_599
        let model = makeModel(store: store, now: now)

        XCTAssertEqual(model.timerState, .paused(remaining: 3_599))
        XCTAssertTrue(model.timerIsActive)

        model.stopTimer()

        XCTAssertEqual(model.timerState, .inactive)
        XCTAssertFalse(model.timerIsActive)
        XCTAssertNil(store.pausedSessionRemaining)
    }

    func testSelectingScheduleModeOnlyBrowsesWithoutEnablingOrSaving() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)

        model.selectScheduleMode(.everyDay)

        XCTAssertFalse(model.scheduleEnabled)
        XCTAssertFalse(store.hasPersistedSchedule)
        XCTAssertTrue(notifications.isEmpty)
    }

    func testEveryDayDraftSavesOnlyWhenEnabled() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)

        model.selectScheduleMode(.everyDay)
        model.setSharedWindow(CaffeineDayWindow(onMinutes: 8 * 60, offMinutes: 16 * 60))

        XCTAssertFalse(store.hasPersistedSchedule)

        model.setScheduleEnabled(true)

        let schedule = store.load()
        XCTAssertTrue(schedule.enabled)
        XCTAssertEqual(Set(schedule.weekdayWindows.keys), CaffeineSchedule.everyDay)
        XCTAssertTrue(schedule.weekdayWindows.values.allSatisfy {
            $0 == CaffeineDayWindow(onMinutes: 8 * 60, offMinutes: 16 * 60)
        })
    }

    func testCustomDraftSavesOnlyWhenEnabled() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)
        model.selectScheduleMode(.custom)
        model.setCustomDay(2, enabled: true)
        model.setCustomDay(4, enabled: true)

        model.setCustomWindow(CaffeineDayWindow(onMinutes: 9 * 60, offMinutes: 12 * 60), for: 2)
        model.setCustomWindow(CaffeineDayWindow(onMinutes: 14 * 60, offMinutes: 18 * 60), for: 4)

        XCTAssertFalse(store.hasPersistedSchedule)

        model.setScheduleEnabled(true)

        XCTAssertEqual(store.load().weekdayWindows[2], CaffeineDayWindow(onMinutes: 9 * 60, offMinutes: 12 * 60))
        XCTAssertEqual(store.load().weekdayWindows[4], CaffeineDayWindow(onMinutes: 14 * 60, offMinutes: 18 * 60))
    }

    func testOneTimeDraftSavesOnlyWhenEnabled() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)
        let start = Date(timeIntervalSinceReferenceDate: 20_000)
        let end = Date(timeIntervalSinceReferenceDate: 24_000)

        model.selectScheduleMode(.oneTime)
        model.setOneTime(start: start, end: end)

        XCTAssertFalse(store.hasPersistedSchedule)

        model.setScheduleEnabled(true)

        XCTAssertEqual(store.load().oneTimeWindow, CaffeineOneTimeWindow(startDate: start, endDate: end))
    }

    func testScheduleCanBeDisabledWithoutLosingItsConfiguration() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)
        model.selectScheduleMode(.weekdays)
        model.setScheduleEnabled(true)

        model.setScheduleEnabled(false)

        XCTAssertFalse(store.load().enabled)
        XCTAssertEqual(Set(store.load().weekdayWindows.keys), Set(2...6))
    }

    func testBrowsingAnotherModeDoesNotReplaceTheActiveSchedule() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)
        model.selectScheduleMode(.everyDay)
        model.setScheduleEnabled(true)
        let activeSchedule = store.load()

        model.selectScheduleMode(.custom)
        model.setCustomDay(2, enabled: true)

        XCTAssertEqual(store.load(), activeSchedule)
        XCTAssertTrue(model.scheduleIsEnabled(.everyDay))
        XCTAssertFalse(model.scheduleIsEnabled(.custom))
        XCTAssertTrue(notifications.count == 1)
    }

    func testLegacyWeekdayScheduleIsInferredWithoutChangingStoredSchedule() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let legacy = CaffeineSchedule(
            enabled: true,
            onMinutes: 8 * 60,
            offMinutes: 17 * 60,
            weekdays: Set(2...6)
        )
        store.save(legacy)

        let model = makeModel(store: store)

        XCTAssertEqual(model.scheduleMode, .weekdays)
        XCTAssertEqual(Set(model.customWindows.keys), Set(2...6))
        XCTAssertEqual(store.load(), legacy)
    }

    func testDisabledLegacyWeekdayScheduleIsStillInferred() {
        let store = CaffeineScheduleStore(defaults: defaults)
        store.save(CaffeineSchedule(
            enabled: false,
            onMinutes: 8 * 60,
            offMinutes: 17 * 60,
            weekdays: Set(2...6)
        ))

        let model = makeModel(store: store)

        XCTAssertFalse(model.scheduleEnabled)
        XCTAssertEqual(model.scheduleMode, .weekdays)
        XCTAssertEqual(Set(model.customWindows.keys), Set(2...6))
    }

    func testAdvancedRecurrenceIsPreservedByCompactEditorMutations() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let advanced = CaffeineSchedule(
            enabled: true,
            onMinutes: 8 * 60,
            offMinutes: 17 * 60,
            recurrence: CaffeineRecurrence(
                frequency: .monthly,
                interval: 2,
                anchorDate: Date(timeIntervalSinceReferenceDate: 70_000)
            )
        )
        store.save(advanced)
        let model = makeModel(store: store)

        XCTAssertTrue(model.hasUnsupportedSchedule)
        model.selectScheduleMode(.custom)
        model.setCustomDay(2, enabled: true)
        model.setSharedWindow(CaffeineDayWindow(onMinutes: 600, offMinutes: 900))
        XCTAssertEqual(store.load(), advanced)

        model.setScheduleEnabled(false)
        var disabled = advanced
        disabled.enabled = false
        XCTAssertEqual(store.load(), disabled)

        model.setScheduleEnabled(true)
        XCTAssertEqual(store.load(), advanced)
    }

    func testPopoverAnchorMustBeInsideTheTopMenuBarBand() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)

        XCTAssertFalse(MenuBarAnchorValidator.isReady(
            buttonRect: CGRect(x: 8, y: -14.5, width: 22, height: 29),
            screenFrame: screen
        ))
        XCTAssertTrue(MenuBarAnchorValidator.isReady(
            buttonRect: CGRect(x: 929, y: 951, width: 22, height: 29),
            screenFrame: screen
        ))
        XCTAssertEqual(
            MenuBarAnchorValidator.attachedOriginY(
                statusWindowFrame: CGRect(x: 929, y: 949, width: 38, height: 33),
                popoverHeight: 188
            ),
            761
        )
    }

    func testPopoverHorizontalOriginStaysInsideTheVisibleScreen() {
        let visibleFrame = CGRect(x: 100, y: 0, width: 1_000, height: 760)

        XCTAssertEqual(
            MenuBarAnchorValidator.attachedOriginX(
                statusWindowFrame: CGRect(x: 90, y: 760, width: 30, height: 30),
                popoverWidth: 340,
                visibleFrame: visibleFrame
            ),
            100
        )
        XCTAssertEqual(
            MenuBarAnchorValidator.attachedOriginX(
                statusWindowFrame: CGRect(x: 1_085, y: 760, width: 30, height: 30),
                popoverWidth: 340,
                visibleFrame: visibleFrame
            ),
            760
        )
    }

    func testPanelPresentationReappliesMenuLevelAfterContentChanges() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal

        MenuBarPanelPresenter.prepareForPresentation(panel)

        XCTAssertEqual(panel.level, .popUpMenu)
    }

    func testStatusItemPresentationRestoresAHiddenCup() {
        XCTAssertNil(MenuBarStatusItemPresenter.autosaveName)
        XCTAssertTrue(MenuBarStatusItemPresenter.behavior.isEmpty)
    }

    func testPassiveApplicationReopenDoesNotPresentPanel() {
        XCTAssertFalse(MenuBarReopenPolicy.shouldPresentPanel(hasPendingShowRequest: false))
    }

    func testExplicitPendingRequestCanPresentPanelOnReopen() {
        XCTAssertTrue(MenuBarReopenPolicy.shouldPresentPanel(hasPendingShowRequest: true))
    }

    func testDuplicateLaunchDoesNotRequestPanelPresentation() {
        XCTAssertFalse(MenuBarLaunchPolicy.requestsPanelForDuplicateLaunch)
    }

    func testReloadSynchronizesAnExternalScheduleChange() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)
        store.save(CaffeineSchedule(
            enabled: true,
            weekdayWindows: [
                2: CaffeineDayWindow(onMinutes: 600, offMinutes: 720),
                4: CaffeineDayWindow(onMinutes: 780, offMinutes: 900),
            ]
        ))

        model.reload()

        XCTAssertTrue(model.scheduleEnabled)
        XCTAssertEqual(model.scheduleMode, .custom)
        XCTAssertEqual(Set(model.customWindows.keys), [2, 4])
    }

    func testEmptyCustomSelectionKeepsPublishedAndStoredEnabledStateConsistent() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let model = makeModel(store: store)

        model.selectScheduleMode(.custom)

        XCTAssertFalse(model.scheduleEnabled)
        XCTAssertFalse(store.load().enabled)
    }

    func testCollapsedPopoverUsesCompactIntrinsicSize() {
        let store = CaffeineScheduleStore(defaults: defaults)
        let settings = makeModel(store: store)
        let state = MenuBarState(isCaffeinated: false) { _ in }
        let hostingView = NSHostingView(rootView: MenuBarPopoverView(state: state, settings: settings))

        let size = hostingView.fittingSize

        XCTAssertEqual(size.width, 340, accuracy: 1)
        XCTAssertGreaterThan(size.height, 110)
        XCTAssertLessThan(size.height, 175)
    }

    private func makeModel(
        store: CaffeineScheduleStore,
        now: Date = Date(timeIntervalSinceReferenceDate: 10_000)
    ) -> MenuBarSettingsModel {
        MenuBarSettingsModel(
            store: store,
            now: { now },
            post: { [weak self] in self?.notifications.append($0) }
        )
    }
}