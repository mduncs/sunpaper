import XCTest
import CoreLocation
@testable import Sunpaper

final class SchedulerTests: XCTestCase {

    let chicagoLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    // MARK: - SlotScheduler Initialization

    func testSchedulerInitialization() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation }
        )

        XCTAssertNotNil(scheduler)
    }

    func testSchedulerWithNoLocation() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { nil }
        )

        // Should handle nil location gracefully
        scheduler.start()
        scheduler.stop()
    }

    func testSchedulerConfigUpdate() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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
    func testConfigUpdateClearsScheduleWhenTrackingIsDisabled() {
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

        XCTAssertTrue(scheduler.todaySchedule.isEmpty)
        XCTAssertNil(scheduler.currentSlot)
        XCTAssertNil(scheduler.nextTransition)

        scheduler.stop()
    }

    // MARK: - Thread Safety

    func testSchedulerMultipleStartStop() {
        let config = WallpaperConfig.default
        let scheduler = SlotScheduler(
            config: config,
            locationProvider: { [self] in self.chicagoLocation }
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
            locationProvider: { [self] in self.chicagoLocation }
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

    private func testSlot(name: String) -> TimeSlot {
        TimeSlot(
            name: name,
            trigger: .fixed(hour: 8, minute: 0),
            source: .none
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
    func invalidate() {}
}

private final class TestTimerScheduler: SlotSchedulerTimerScheduling {
    func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        _ handler: @escaping () -> Void
    ) -> SlotSchedulerTimerToken {
        TestTimerToken()
    }
}

private final class TestWakeObserver: SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping () -> Void) -> NSObjectProtocol {
        NSObject()
    }

    func removeObserver(_ observer: NSObjectProtocol) {}
}

private final class TestWallpaperService: SlotSchedulerWallpaperServicing {
    func downloadAerial(assetID: String, from url: URL) async throws {}
    func isAerialDownloaded(assetID: String) -> Bool { true }
    func setWallpaper(assetID: String, displayUUID: String?) throws {}
    func setCustomWallpaper(path: String) throws {}
    func getCurrentAssetID() throws -> String? { nil }
}

private struct TestDisplayProvider: SlotSchedulerDisplayProviding {
    func getDisplays() -> [DisplayManager.Display] { [] }
}

private struct TestAerialCatalogResolver: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? { nil }
}
