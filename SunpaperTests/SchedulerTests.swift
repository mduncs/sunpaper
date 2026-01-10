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
}
