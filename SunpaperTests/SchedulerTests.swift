import XCTest
import CoreLocation
@testable import Sunpaper

@MainActor
final class SchedulerTests: XCTestCase {

    let chicagoLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    // MARK: - SlotScheduler Initialization

    func testSchedulerInitialization() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        XCTAssertNotNil(scheduler)
    }

    func testSchedulerWithNoLocation() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { nil },
            dependencies: testDependencies()
        )

        // Should handle nil location gracefully
        scheduler.start()
        scheduler.stop()
    }

    func testSchedulerConfigUpdate() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        var newConfig = config
        newConfig.enableSolarTracking = false

        // Should not crash
        scheduler.updateConfig(newConfig)
    }

    func testSchedulerForceUpdate() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()
        scheduler.forceUpdate()
        scheduler.stop()

        // Just verify no crashes
    }

    func testSchedulerStopCleansUp() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()
        scheduler.stop()

        // Starting again should work
        scheduler.start()
        scheduler.stop()
    }

    // MARK: - Edge Cases

    func testSchedulerWithEmptySlots() {
        let config = WallpaperConfig(slots: [])
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()

        // Should handle empty slots gracefully
        XCTAssertNil(scheduler.currentSlot)
        XCTAssertNil(scheduler.nextTransition)

        scheduler.stop()
    }

    func testSchedulerWithSingleSlot() {
        let slot = TimeSlot(
            name: "Only Slot",
            trigger: .solar(event: .solarNoon, offset: 0),
            source: .builtIn(assetID: "test-id")
        )
        let config = WallpaperConfig(slots: [slot])
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()

        // Should work with single slot
        XCTAssertNotNil(scheduler.currentSlot)

        scheduler.stop()
    }

    func testSchedulerWithDisabledSolarTracking() {
        var config = WallpaperConfig.default
        config.enableSolarTracking = false

        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()

        // When solar tracking is disabled, scheduler should not update
        // This is expected behavior

        scheduler.stop()
    }

    @MainActor
    func testConfigUpdateClearsScheduleWhenSlotsAreRemovedWithoutLocation() {
        var location: CLLocationCoordinate2D? = chicagoLocation
        let slot = testSlot(name: "Temporary Slot")
        let scheduler = SlotScheduler(
            config: WallpaperConfig(slots: [slot]),
            locationProvider: { location },
            dependencies: testDependencies()
        )

        scheduler.start()

        XCTAssertEqual(scheduler.todaySchedule.map(\.slot.id), [slot.id])
        XCTAssertEqual(scheduler.currentSlot?.id, slot.id)

        location = nil
        scheduler.updateConfig(WallpaperConfig(slots: []))

        XCTAssertTrue(scheduler.todaySchedule.isEmpty)
        XCTAssertNil(scheduler.currentSlot)
        XCTAssertNil(scheduler.nextTransition)

        scheduler.stop()
    }

    @MainActor
    func testConfigUpdateKeepsScheduleVisibleWhenTrackingIsPaused() {
        let slot = testSlot(name: "Temporary Slot")
        let scheduler = SlotScheduler(
            config: WallpaperConfig(slots: [slot]),
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()

        XCTAssertEqual(scheduler.todaySchedule.map(\.slot.id), [slot.id])
        XCTAssertEqual(scheduler.currentSlot?.id, slot.id)

        var disabledConfig = WallpaperConfig(slots: [slot])
        disabledConfig.enableSolarTracking = false
        scheduler.updateConfig(disabledConfig)

        XCTAssertEqual(scheduler.todaySchedule.map(\.slot.id), [slot.id])
        XCTAssertEqual(scheduler.currentSlot?.id, slot.id)
        XCTAssertNotNil(scheduler.nextTransition)
        XCTAssertEqual(scheduler.playbackMode, .paused)

        scheduler.stop()
    }

    // MARK: - Thread Safety

    func testSchedulerMultipleStartStop() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        // Rapid start/stop shouldn't cause issues
        for _ in 0..<10 {
            scheduler.start()
            scheduler.stop()
        }
    }

    func testSchedulerSequentialConfigUpdates() {
        // Note: SlotScheduler is MainActor-bound (ObservableObject with @Published)
        // Testing sequential updates instead of concurrent
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation },
            dependencies: testDependencies()
        )

        scheduler.start()

        // Sequential config updates should not crash
        for i in 0..<10 {
            var newConfig = config
            newConfig.enableSolarTracking = i % 2 == 0
            scheduler.updateConfig(newConfig)
        }

        scheduler.stop()
    }

    func testStoppingDuringDownloadDoesNotApplyAfterDownloadCompletes() async {
        let service = ControlledWallpaperService()
        service.downloaded = false
        let started = expectation(description: "download started")
        var resumeDownload: CheckedContinuation<Void, Never>?
        service.onDownload = {
            started.fulfill()
            await withCheckedContinuation { resumeDownload = $0 }
        }
        var dependencies = testDependencies()
        dependencies.wallpaperService = service
        dependencies.aerialCatalog = DownloadableTestCatalog()
        let scheduler = SlotScheduler(config: .default, locationProvider: { nil }, dependencies: dependencies)
        let request = scheduler.applyWallpaper(source: .builtIn(assetID: "old"))
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(scheduler.isDownloading)
        scheduler.stop()
        resumeDownload?.resume()
        await request?.value
        XCTAssertTrue(service.applied.isEmpty)
        XCTAssertFalse(scheduler.isDownloading)
        XCTAssertNil(scheduler.lastError)
    }

    func testSupersededApplicationCannotPublishStaleError() async {
        let service = ControlledWallpaperService()
        let started = expectation(description: "old application started")
        var resumeOld: CheckedContinuation<Void, Never>?
        service.onApply = { assetID in
            if assetID == "old" {
                started.fulfill()
                await withCheckedContinuation { resumeOld = $0 }
                throw WallpaperError.agentRestartFailed
            }
        }
        var dependencies = testDependencies()
        dependencies.wallpaperService = service
        let scheduler = SlotScheduler(config: .default, locationProvider: { nil }, dependencies: dependencies)
        let old = scheduler.applyWallpaper(source: .builtIn(assetID: "old"))
        await fulfillment(of: [started], timeout: 2)
        let latest = scheduler.applyWallpaper(source: .builtIn(assetID: "new"))
        await latest?.value
        resumeOld?.resume()
        await old?.value
        XCTAssertNil(scheduler.lastError)
        XCTAssertEqual(service.applied, ["old", "new"])
        scheduler.stop()
    }

    func testFailedScheduledChangeIsEligibleForRetry() async {
        let service = ControlledWallpaperService()
        service.onApply = { _ in throw WallpaperError.agentRestartFailed }
        var dependencies = testDependencies()
        dependencies.wallpaperService = service
        let slot = TimeSlot(name: "Every day", trigger: .fixed(hour: 0, minute: 0), source: .builtIn(assetID: "scene"))
        let scheduler = SlotScheduler(config: WallpaperConfig(slots: [slot]), locationProvider: { self.chicagoLocation }, dependencies: dependencies)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertNotNil(scheduler.lastError)
        service.onApply = { _ in }
        scheduler.forceUpdate()
        await scheduler.waitForPendingApplication()
        XCTAssertNil(scheduler.lastError)
        XCTAssertEqual(service.applied, ["scene", "scene"])
        scheduler.stop()
    }

    // MARK: - Playback runtime

    func testFixedTimeScheduleRunsAndTransitionsWithoutLocation() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let timers = TestTimerScheduler()
        let service = ControlledWallpaperService()
        let morning = runtimeSlot("morning", hour: 8)
        let evening = runtimeSlot("evening", hour: 18)
        let scheduler = runtime(config: WallpaperConfig(slots: [morning, evening]), service: service, clock: clock, timers: timers)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.currentSlot?.id, morning.id)
        XCTAssertEqual(scheduler.confirmedSource, morning.source)
        XCTAssertEqual(scheduler.todaySchedule.count, 2)
        XCTAssertEqual(scheduler.nextTransition?.slot.id, evening.id)

        let transition = timers.tokens.first { !$0.repeats && abs($0.interval - (6 * 3600 + 5)) < 0.1 }
        XCTAssertNotNil(transition)
        clock.date = Self.localDate(hour: 18).addingTimeInterval(5)
        transition?.fire()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["morning", "evening"])
        XCTAssertEqual(scheduler.confirmedSource, evening.source)
        scheduler.stop()
    }

    func testSolarRulesRemainUnresolvedWithoutLocationWhileFixedRulesWork() async {
        let fixed = runtimeSlot("fixed", hour: 8)
        let solar = TimeSlot(name: "Solar", trigger: .sunrise(), source: .builtIn(assetID: "solar"))
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: WallpaperConfig(slots: [fixed, solar]), service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.todaySchedule.map(\.slot.id), [fixed.id])
        XCTAssertEqual(service.applied, ["fixed"])
        scheduler.stop()
    }

    func testPausedScheduleStaysVisibleAndManualChoiceRemainsPaused() async {
        let slot = runtimeSlot("scheduled", hour: 8)
        let service = ControlledWallpaperService()
        let wake = TestWakeObserver()
        let timers = TestTimerScheduler()
        let scheduler = runtime(config: WallpaperConfig(slots: [slot], enableSolarTracking: false), service: service, timers: timers, wake: wake)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .paused)
        XCTAssertEqual(scheduler.currentSlot?.id, slot.id)
        XCTAssertNotNil(scheduler.nextTransition)
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertTrue(service.applied.isEmpty)

        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), duration: .oneHour)?.value
        XCTAssertEqual(scheduler.playbackMode, .paused)
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "manual"))
        scheduler.forceUpdate()
        timers.tokens.first(where: \.repeats)?.fire()
        wake.handlers.last?()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["manual"])

        scheduler.resumeSchedule()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .following)
        XCTAssertEqual(scheduler.confirmedSource, slot.source)
        XCTAssertEqual(service.applied, ["manual", "scheduled"])
        scheduler.stop()
    }

    func testExpectedSlotIsNotConfirmedUntilSuccessfulCompletion() async {
        let service = ControlledWallpaperService()
        let started = expectation(description: "setter suspended")
        var completion: CheckedContinuation<Void, Never>?
        service.onApply = { _ in
            started.fulfill()
            await withCheckedContinuation { completion = $0 }
        }
        let slot = runtimeSlot("scheduled", hour: 8)
        let scheduler = runtime(config: WallpaperConfig(slots: [slot]), service: service)
        scheduler.start()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(scheduler.currentSlot?.id, slot.id)
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertTrue(scheduler.isApplying)
        // The suspended setter permits this main-actor state change to run.
        var renamed = WallpaperConfig(slots: [slot])
        renamed.slots[0].name = "Cosmetic rename"
        scheduler.updateConfig(renamed)
        completion?.resume()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertEqual(scheduler.confirmedSource, slot.source)
        XCTAssertFalse(scheduler.isApplying)
        scheduler.stop()
    }

    func testFailedManualChoiceRetainsLastSuccessfulConfirmation() async {
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: WallpaperConfig(slots: []), service: service)
        scheduler.start()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "confirmed"))?.value
        service.onApply = { _ in throw WallpaperError.agentRestartFailed }
        await scheduler.applyWallpaper(source: .builtIn(assetID: "failed"))?.value
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "confirmed"))
        XCTAssertNotNil(scheduler.lastError)
        XCTAssertFalse(scheduler.isApplying)
        scheduler.stop()
    }

    func testOneHourOverrideSurvivesRepairAndCosmeticEditsThenExpires() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let timers = TestTimerScheduler()
        let wake = TestWakeObserver()
        let service = ControlledWallpaperService()
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service, clock: clock, timers: timers, wake: wake)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        let deadline = clock.date.addingTimeInterval(3600)
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), duration: .oneHour)?.value
        let expiry = timers.tokens.first { !$0.invalidated && abs($0.interval - 3600) < 0.1 }
        XCTAssertNotNil(expiry)

        clock.date = clock.date.addingTimeInterval(1800)
        config.slots[0].name = "Renamed"
        config.locationName = "New location label"
        scheduler.updateConfig(config)
        service.currentAssetID = "external"
        timers.tokens.first(where: \.repeats)?.fire()
        wake.handlers.last?()
        scheduler.forceUpdate()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: deadline))
        XCTAssertEqual(service.applied, ["scheduled", "manual"])
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "manual"))

        clock.date = deadline
        expiry?.fire()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .following)
        XCTAssertEqual(service.applied, ["scheduled", "manual", "scheduled"])
        XCTAssertEqual(scheduler.confirmedSource, config.slots[0].source)
        scheduler.stop()
    }

    func testNextChangeOverrideExpiresAtTomorrowsFirstRule() async {
        let clock = TestClock(date: Self.localDate(hour: 20))
        let timers = TestTimerScheduler()
        let service = ControlledWallpaperService()
        let config = WallpaperConfig(slots: [runtimeSlot("morning", hour: 8), runtimeSlot("evening", hour: 18)])
        let scheduler = runtime(config: config, service: service, clock: clock, timers: timers)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Self.localDate(hour: 8))!
        XCTAssertEqual(scheduler.nextTransition?.date, tomorrow)
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"))?.value
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: tomorrow))
        let expiry = timers.tokens.first { !$0.invalidated && abs($0.interval - tomorrow.timeIntervalSince(clock.date)) < 0.1 }
        clock.date = tomorrow
        expiry?.fire()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .following)
        XCTAssertEqual(service.applied, ["evening", "manual", "morning"])
        scheduler.stop()
    }

    func testChangingOverrideDurationUpdatesExpiryWithoutReapplying() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let timers = TestTimerScheduler()
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: WallpaperConfig(slots: []), service: service, clock: clock, timers: timers)
        scheduler.start()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"))?.value
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: nil))
        scheduler.setOverrideDuration(.oneHour)
        let oldExpiry = timers.tokens.first { !$0.invalidated && abs($0.interval - 3600) < 0.1 }
        scheduler.setOverrideDuration(.tomorrow)
        XCTAssertEqual(scheduler.currentOverrideDuration, .tomorrow)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock.date))!
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: midnight))
        XCTAssertEqual(service.applied, ["manual"])
        clock.date = clock.date.addingTimeInterval(3600)
        oldExpiry?.fire(evenIfInvalidated: true)
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: midnight))
        scheduler.stop()
    }

    func testWakeResumesAnOverrideThatExpiredDuringSleep() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let wake = TestWakeObserver()
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)]), service: service, clock: clock, wake: wake)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), duration: .oneHour)?.value
        clock.date = clock.date.addingTimeInterval(7200)
        wake.handlers.last?()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .following)
        XCTAssertEqual(service.applied, ["scheduled", "manual", "scheduled"])
        scheduler.stop()
    }

    func testCosmeticAndInactiveConfigEditsDoNotRestartWallpaper() async {
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8), runtimeSlot("later", hour: 18)])
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        config.slots[0].name = "Renamed current slot"
        config.slots[1].source = .builtIn(assetID: "different later")
        config.locationName = "Renamed city"
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertEqual(scheduler.currentSlot?.name, "Renamed current slot")
        config.slots[0].source = .builtIn(assetID: "changed now")
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled", "changed now"])
        scheduler.stop()
    }

    func testPauseDuringApplySuppressesStaleConfirmationAndError() async {
        let service = ControlledWallpaperService()
        let started = expectation(description: "apply started")
        var finish: CheckedContinuation<Void, Never>?
        service.onApply = { _ in
            started.fulfill()
            await withCheckedContinuation { finish = $0 }
            throw WallpaperError.agentRestartFailed
        }
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        let waiting = Task { await scheduler.waitForPendingApplication() }
        await fulfillment(of: [started], timeout: 2)
        config.enableSolarTracking = false
        scheduler.updateConfig(config)
        XCTAssertEqual(scheduler.playbackMode, .paused)
        XCTAssertTrue(scheduler.isApplying) // Mandatory recovery is still active.
        finish?.resume()
        await waiting.value
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertNil(scheduler.lastError)
        XCTAssertFalse(scheduler.isApplying)
        XCTAssertNotNil(scheduler.currentSlot)
        scheduler.stop()
    }

    func testPerDisplayPartialFailurePreservesOtherDisplayConfirmationAndSupportsCustomImages() async {
        let service = ControlledWallpaperService()
        let displays = [
            DisplayManager.Display(uuid: "first", name: "First", isPrimary: true),
            DisplayManager.Display(uuid: "second", name: "Second", isPrimary: false)
        ]
        var config = WallpaperConfig(slots: [], enableSolarTracking: false, displayMode: .perDisplay, perDisplayConfigs: [
            DisplayConfig(displayUUID: "first", slots: [TimeSlot(name: "Image", trigger: .fixed(hour: 8, minute: 0), source: .custom(path: "/fake/image.jpg"))]),
            DisplayConfig(displayUUID: "second", slots: [runtimeSlot("new second", hour: 8)])
        ])
        let scheduler = runtime(config: config, service: service, displays: displays)
        scheduler.start()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "old first"), displayUUID: "first")?.value
        await scheduler.applyWallpaper(source: .builtIn(assetID: "old second"), displayUUID: "second")?.value
        service.onApply = { _ in throw WallpaperError.agentRestartFailed }
        config.enableSolarTracking = true
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.customApplications.map(\.path), ["/fake/image.jpg"])
        XCTAssertEqual(service.customApplications.map(\.displayUUID), ["first"])
        XCTAssertEqual(scheduler.confirmedSourcesByDisplay["first"], .custom(path: "/fake/image.jpg"))
        XCTAssertEqual(scheduler.confirmedSourcesByDisplay["second"], .builtIn(assetID: "old second"))
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertNotNil(scheduler.lastError)
        XCTAssertNotNil(scheduler.currentSlot) // No global slots are required.
        scheduler.stop()
    }

    func testDelayedWakeFromStoppedLifecycleDoesNotRepairAfterRestart() async {
        let service = ControlledWallpaperService()
        let wake = TestWakeObserver()
        let scheduler = runtime(config: WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)]), service: service, wake: wake)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        let delayedOldWake = wake.handlers[0]
        scheduler.stop()
        service.currentAssetID = "external"
        delayedOldWake()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied.count, 1)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        service.currentAssetID = "external"
        delayedOldWake()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied.count, 2)
        wake.handlers.last?()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied.count, 3)
        scheduler.stop()
    }

    func testRetryFailedManualRequestKeepsItsDeadlineAndScope() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let service = ControlledWallpaperService()
        service.onApply = { _ in throw WallpaperError.agentRestartFailed }
        let display = DisplayManager.Display(uuid: "target", name: "Target", isPrimary: true)
        let scheduler = runtime(config: WallpaperConfig(slots: []), service: service, clock: clock, displays: [display])
        scheduler.start()
        let deadline = clock.date.addingTimeInterval(3600)
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), displayUUID: "target", duration: .oneHour)?.value
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertNotNil(scheduler.lastError)
        clock.date = clock.date.addingTimeInterval(600)
        service.onApply = { _ in }
        scheduler.retryLastApplication()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["manual", "manual"])
        XCTAssertEqual(scheduler.confirmedSourcesByDisplay["target"], .builtIn(assetID: "manual"))
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: deadline))
        XCTAssertNil(scheduler.lastError)
        scheduler.stop()
    }

    func testRevertingConfigDuringApplyCancelsSupersededRequest() async {
        let service = ControlledWallpaperService()
        var config = WallpaperConfig(slots: [runtimeSlot("original", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        let started = expectation(description: "replacement started")
        var finish: CheckedContinuation<Void, Never>?
        service.onApply = { _ in
            started.fulfill()
            await withCheckedContinuation { finish = $0 }
        }
        config.slots[0].source = .builtIn(assetID: "replacement")
        scheduler.updateConfig(config)
        let waiting = Task { await scheduler.waitForPendingApplication() }
        await fulfillment(of: [started], timeout: 2)
        config.slots[0].source = .builtIn(assetID: "original")
        scheduler.updateConfig(config)
        finish?.resume()
        await waiting.value
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "original"))
        XCTAssertNil(scheduler.lastError)
        XCTAssertEqual(service.applied, ["original", "replacement"])
        scheduler.stop()
    }

    func testCosmeticEditDoesNotRetryFailedSetter() async {
        let service = ControlledWallpaperService()
        service.onApply = { _ in throw WallpaperError.agentRestartFailed }
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        config.slots[0].name = "Rename after failure"
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertNotNil(scheduler.lastError)
        scheduler.retryLastApplication()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled", "scheduled"])
        scheduler.stop()
    }

    func testUnassignedRulesDoNotChangeExpectedWallpaperOrExpireOverride() async {
        let clock = TestClock(date: Self.localDate(hour: 20))
        let timers = TestTimerScheduler()
        let service = ControlledWallpaperService()
        let actual = runtimeSlot("scheduled", hour: 8)
        let emptyFixed = TimeSlot(name: "Unassigned time", trigger: .fixed(hour: 21, minute: 0), source: .none)
        let emptySolar = TimeSlot(name: "Unassigned solar", trigger: .sunrise(), source: .none)
        let config = WallpaperConfig(slots: [actual, emptyFixed, emptySolar])
        let scheduler = runtime(config: config, service: service, clock: clock, timers: timers)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Self.localDate(hour: 8))!
        XCTAssertEqual(scheduler.todaySchedule.map(\.slot.id), [actual.id])
        XCTAssertEqual(scheduler.currentSlot?.id, actual.id)
        XCTAssertEqual(scheduler.nextTransition?.date, tomorrow)
        XCTAssertFalse(timers.tokens.contains { !$0.invalidated && $0.interval == 300 })

        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"))?.value
        XCTAssertEqual(scheduler.currentOverrideDuration, .nextChange)
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: tomorrow))
        let expiry = timers.tokens.first { !$0.invalidated && abs($0.interval - tomorrow.timeIntervalSince(clock.date)) < 0.1 }
        clock.date = Self.localDate(hour: 22)
        timers.tokens.first(where: \.repeats)?.fire()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.currentSlot?.id, actual.id)
        XCTAssertEqual(service.applied, ["scheduled", "manual"])
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: tomorrow))

        clock.date = tomorrow
        expiry?.fire()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .following)
        XCTAssertEqual(service.applied, ["scheduled", "manual", "scheduled"])
        scheduler.stop()
    }

    func testManualAllDisplayCustomPartialFailureConfirmsSuccessfulDisplay() async {
        await verifyAllDisplayCustomPartialFailure(scheduled: false)
    }

    func testScheduledAllDisplayCustomPartialFailureConfirmsSuccessfulDisplay() async {
        await verifyAllDisplayCustomPartialFailure(scheduled: true)
    }

    private func verifyAllDisplayCustomPartialFailure(scheduled: Bool) async {
        let displays = [
            DisplayManager.Display(uuid: "first", name: "First", isPrimary: true),
            DisplayManager.Display(uuid: "second", name: "Second", isPrimary: false)
        ]
        let image = WallpaperSource.custom(path: "/fake/new-image.jpg")
        var config = WallpaperConfig(slots: [TimeSlot(name: "Custom image", trigger: .fixed(hour: 8, minute: 0), source: image)], enableSolarTracking: false)
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: config, service: service, displays: displays)
        scheduler.start()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "original"))?.value
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "original"))
        service.onCustomApply = { _, displayUUID in
            if displayUUID == "second" { throw WallpaperError.agentRestartFailed }
        }
        if scheduled {
            config.enableSolarTracking = true
            scheduler.updateConfig(config)
            await scheduler.waitForPendingApplication()
        } else {
            await scheduler.applyWallpaper(source: image)?.value
        }
        XCTAssertEqual(service.customApplications.map(\.displayUUID), ["first", "second"])
        XCTAssertEqual(scheduler.confirmedSourcesByDisplay["first"], image)
        XCTAssertEqual(scheduler.confirmedSourcesByDisplay["second"], .builtIn(assetID: "original"))
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertNotNil(scheduler.lastError)
        XCTAssertFalse(scheduler.isApplying)
        scheduler.stop()
    }

    func testSmoothingDefaultsOnForScheduledAerialApplication() async {
        let service = ControlledWallpaperService()
        let config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        XCTAssertTrue(config.smoothWallpaperChanges)
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertEqual(service.appliedSmoothing, [true])
        scheduler.stop()
    }

    func testDisabledSmoothingReachesEachScheduledDisplayAndManualChoice() async {
        let displays = [
            DisplayManager.Display(uuid: "first", name: "First", isPrimary: true),
            DisplayManager.Display(uuid: "second", name: "Second", isPrimary: false)
        ]
        var config = WallpaperConfig(slots: [], displayMode: .perDisplay, perDisplayConfigs: [
            DisplayConfig(displayUUID: "first", slots: [runtimeSlot("first scene", hour: 8)]),
            DisplayConfig(displayUUID: "second", slots: [runtimeSlot("second scene", hour: 8)])
        ])
        config.smoothWallpaperChanges = false
        let service = ControlledWallpaperService()
        let scheduler = runtime(config: config, service: service, displays: displays)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), displayUUID: "second")?.value
        XCTAssertEqual(service.applied, ["first scene", "second scene", "manual"])
        XCTAssertEqual(service.appliedDisplayUUIDs, ["first", "second", "second"])
        XCTAssertEqual(service.appliedSmoothing, [false, false, false])
        scheduler.stop()
    }

    func testDisablingSmoothingRetriesFailedAutomaticCapture() async {
        let service = ControlledWallpaperService()
        service.onApplyWithSmoothing = { _, smoothChanges in
            if smoothChanges { throw WallpaperTransitionError.capturePermission }
        }
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertNotNil(scheduler.lastError)
        XCTAssertNil(scheduler.confirmedSource)
        XCTAssertEqual(scheduler.playbackMode, .following)

        config.smoothWallpaperChanges = false
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled", "scheduled"])
        XCTAssertEqual(service.appliedSmoothing, [true, false])
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "scheduled"))
        XCTAssertNil(scheduler.lastError)
        XCTAssertEqual(scheduler.playbackMode, .following)
        scheduler.stop()
    }

    func testSmoothingToggleDoesNotRestartConfirmedWallpaper() async {
        let service = ControlledWallpaperService()
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        config.smoothWallpaperChanges = false
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        config.smoothWallpaperChanges = true
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertEqual(service.appliedSmoothing, [true])
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "scheduled"))
        XCTAssertEqual(scheduler.playbackMode, .following)
        scheduler.stop()
    }

    func testSmoothingToggleWhilePausedKeepsPauseAndAffectsNextManualChoice() async {
        let service = ControlledWallpaperService()
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)], enableSolarTracking: false)
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        config.smoothWallpaperChanges = false
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(scheduler.playbackMode, .paused)
        XCTAssertTrue(service.applied.isEmpty)
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), duration: .oneHour)?.value
        XCTAssertEqual(service.appliedSmoothing, [false])
        XCTAssertEqual(scheduler.playbackMode, .paused)
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "manual"))
        scheduler.stop()
    }

    func testFailedManualRetryUsesNewSmoothingWithoutExtendingOverride() async {
        let clock = TestClock(date: Self.localDate(hour: 12))
        let service = ControlledWallpaperService()
        service.onApplyWithSmoothing = { _, smoothChanges in
            if smoothChanges { throw WallpaperTransitionError.capturePermission }
        }
        var config = WallpaperConfig(slots: [])
        let scheduler = runtime(config: config, service: service, clock: clock)
        scheduler.start()
        let deadline = clock.date.addingTimeInterval(3600)
        await scheduler.applyWallpaper(source: .builtIn(assetID: "manual"), duration: .oneHour)?.value
        XCTAssertNotNil(scheduler.lastError)
        clock.date = clock.date.addingTimeInterval(600)
        config.smoothWallpaperChanges = false
        scheduler.updateConfig(config)
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["manual"])
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: deadline))

        scheduler.retryLastApplication()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["manual", "manual"])
        XCTAssertEqual(service.appliedSmoothing, [true, false])
        XCTAssertEqual(scheduler.playbackMode, .temporary(until: deadline))
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "manual"))
        XCTAssertNil(scheduler.lastError)
        scheduler.stop()
    }

    func testSmoothingPolicyIsSnapshottedBeforeSuspendedDownload() async {
        let service = ControlledWallpaperService()
        service.downloaded = false
        let started = expectation(description: "download started")
        var finishDownload: CheckedContinuation<Void, Never>?
        service.onDownload = {
            started.fulfill()
            await withCheckedContinuation { finishDownload = $0 }
        }
        var config = WallpaperConfig(slots: [runtimeSlot("scheduled", hour: 8)])
        let scheduler = runtime(config: config, service: service)
        scheduler.start()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(scheduler.isDownloading)
        config.smoothWallpaperChanges = false
        scheduler.updateConfig(config)
        XCTAssertTrue(scheduler.isApplying)
        finishDownload?.resume()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["scheduled"])
        XCTAssertEqual(service.appliedSmoothing, [true])
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "scheduled"))
        XCTAssertNil(scheduler.lastError)

        service.downloaded = true
        await scheduler.applyWallpaper(source: .builtIn(assetID: "next manual"))?.value
        XCTAssertEqual(service.appliedSmoothing, [true, false])
        scheduler.stop()
    }

    func testNewSmoothingSetterKeepsLegacyServiceFakesCompatible() async {
        let service = TestWallpaperService()
        var config = WallpaperConfig(slots: [runtimeSlot("legacy", hour: 8)])
        config.smoothWallpaperChanges = false
        var dependencies = testDependencies()
        dependencies.wallpaperService = service
        let scheduler = SlotScheduler(config: config, locationProvider: { nil }, dependencies: dependencies)
        scheduler.start()
        await scheduler.waitForPendingApplication()
        XCTAssertEqual(service.applied, ["legacy"])
        XCTAssertEqual(scheduler.confirmedSource, .builtIn(assetID: "legacy"))
        scheduler.stop()
    }

    private func runtimeSlot(_ assetID: String, hour: Int) -> TimeSlot {
        TimeSlot(name: assetID, trigger: .fixed(hour: hour, minute: 0), source: .builtIn(assetID: assetID))
    }

    private func runtime(
        config: WallpaperConfig,
        service: ControlledWallpaperService,
        clock: TestClock? = nil,
        timers: TestTimerScheduler = TestTimerScheduler(),
        wake: TestWakeObserver = TestWakeObserver(),
        displays: [DisplayManager.Display] = []
    ) -> SlotScheduler {
        let clock = clock ?? TestClock(date: Self.localDate(hour: 12))
        var dependencies = testDependencies()
        dependencies.now = { clock.date }
        dependencies.wallpaperService = service
        dependencies.timerScheduler = timers
        dependencies.wakeObserver = wake
        dependencies.displayProvider = TestDisplayProvider(displays: displays)
        dependencies.aerialCatalog = DownloadableTestCatalog()
        return SlotScheduler(config: config, locationProvider: { nil }, dependencies: dependencies)
    }

    private static func localDate(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: hour))!
    }

    private func testSlot(name: String) -> TimeSlot {
        TimeSlot(
            name: name,
            trigger: .fixed(hour: 8, minute: 0),
            source: .builtIn(assetID: name)
        )
    }

    @MainActor
    private func testDependencies() -> SlotSchedulerDependencies {
        SlotSchedulerDependencies(
            now: { Self.testDate },
            calculateSunTimes: { location, date in
                SunCalculator.calculate(for: location, on: date)
            },
            timerScheduler: TestTimerScheduler(),
            wakeObserver: TestWakeObserver(),
            wallpaperService: TestWallpaperService(),
            displayProvider: TestDisplayProvider(),
            aerialCatalog: TestAerialCatalogResolver()
        )
    }

    private static var testDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 5
        components.day = 1
        components.hour = 12
        return components.date!
    }
}

private final class TestTimerToken: SlotSchedulerTimerToken {
    let interval: TimeInterval
    let repeats: Bool
    let handler: @MainActor @Sendable () -> Void
    var invalidated = false

    init(interval: TimeInterval, repeats: Bool, handler: @escaping @MainActor @Sendable () -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.handler = handler
    }

    func invalidate() { invalidated = true }

    @MainActor func fire(evenIfInvalidated: Bool = false) {
        guard !invalidated || evenIfInvalidated else { return }
        if !repeats { invalidated = true }
        handler()
    }
}

private final class TestTimerScheduler: SlotSchedulerTimerScheduling {
    var tokens: [TestTimerToken] = []
    func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) -> SlotSchedulerTimerToken {
        let token = TestTimerToken(interval: interval, repeats: repeats, handler: handler)
        tokens.append(token)
        return token
    }
}

private final class TestWakeObserver: SlotSchedulerWakeObserving {
    var handlers: [@MainActor @Sendable () -> Void] = []
    func observeWake(after delay: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol {
        handlers.append(handler)
        return NSObject()
    }

    func removeObserver(_ observer: NSObjectProtocol) {}
}

private final class TestWallpaperService: SlotSchedulerWallpaperServicing {
    var applied: [String] = []
    func downloadAerial(assetID: String, from url: URL) async throws {}
    func isAerialDownloaded(assetID: String) -> Bool { true }
    func setWallpaper(assetID: String, displayUUID: String?) async throws { applied.append(assetID) }
    func setCustomWallpaper(path: String) throws {}
    func getCurrentAssetID() throws -> String? { nil }
}

private struct TestDisplayProvider: SlotSchedulerDisplayProviding {
    var displays: [DisplayManager.Display] = []
    func getDisplays() -> [DisplayManager.Display] { displays }
}

private struct TestAerialCatalogResolver: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? { nil }
}

@MainActor
private final class ControlledWallpaperService: SlotSchedulerWallpaperServicing {
    var downloaded = true
    var applied: [String] = []
    var appliedSmoothing: [Bool] = []
    var appliedDisplayUUIDs: [String?] = []
    var currentAssetID: String?
    var customApplications: [(path: String, displayUUID: String?)] = []
    var onDownload: () async throws -> Void = {}
    var onApply: (String) async throws -> Void = { _ in }
    var onApplyWithSmoothing: (String, Bool) async throws -> Void = { _, _ in }
    var onCustomApply: (String, String?) throws -> Void = { _, _ in }
    func downloadAerial(assetID: String, from url: URL) async throws { try await onDownload() }
    nonisolated func isAerialDownloaded(assetID: String) -> Bool { MainActor.assumeIsolated { downloaded } }
    func setWallpaper(assetID: String, displayUUID: String?) async throws {
        try await setWallpaper(assetID: assetID, displayUUID: displayUUID, smoothChanges: true)
    }
    func setWallpaper(assetID: String, displayUUID: String?, smoothChanges: Bool) async throws {
        applied.append(assetID)
        appliedSmoothing.append(smoothChanges)
        appliedDisplayUUIDs.append(displayUUID)
        try await onApplyWithSmoothing(assetID, smoothChanges)
        try await onApply(assetID)
        currentAssetID = assetID
    }
    func setCustomWallpaper(path: String) throws {
        try setCustomWallpaper(path: path, displayUUID: nil)
    }
    func setCustomWallpaper(path: String, displayUUID: String?) throws {
        customApplications.append((path, displayUUID))
        try onCustomApply(path, displayUUID)
    }
    nonisolated func getCurrentAssetID() throws -> String? { MainActor.assumeIsolated { currentAssetID } }
}

private struct DownloadableTestCatalog: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? { URL(string: "https://example.invalid/test.mov") }
}

private final class TestClock {
    var date: Date
    init(date: Date) { self.date = date }
}
