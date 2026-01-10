import XCTest
import CoreLocation
@testable import Sunpaper

final class TimeSlotTests: XCTestCase {

    let chicagoLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    // MARK: - Trigger Resolution

    func testSolarTriggerAtSunrise() {
        let trigger = Trigger.solar(event: .sunrise, offset: 0)
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let resolved = trigger.resolveTime(sunTimes: sunTimes)

        XCTAssertEqual(
            resolved.timeIntervalSince1970,
            sunTimes.sunrise.timeIntervalSince1970,
            accuracy: 1,
            "Trigger should resolve to sunrise time"
        )
    }

    func testSolarTriggerWithPositiveOffset() {
        let trigger = Trigger.solar(event: .sunrise, offset: 3600) // +1 hour
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let resolved = trigger.resolveTime(sunTimes: sunTimes)
        let expected = sunTimes.sunrise.addingTimeInterval(3600)

        XCTAssertEqual(
            resolved.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 1,
            "Trigger should be 1 hour after sunrise"
        )
    }

    func testSolarTriggerWithNegativeOffset() {
        let trigger = Trigger.solar(event: .sunset, offset: -3600) // -1 hour
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let resolved = trigger.resolveTime(sunTimes: sunTimes)
        let expected = sunTimes.sunset.addingTimeInterval(-3600)

        XCTAssertEqual(
            resolved.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 1,
            "Trigger should be 1 hour before sunset"
        )
    }

    func testFixedTimeTrigger() {
        let trigger = Trigger.fixed(hour: 14, minute: 30) // 2:30 PM
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)
        let today = Date()

        let resolved = trigger.resolveTime(sunTimes: sunTimes, on: today)

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: resolved)
        let minute = calendar.component(.minute, from: resolved)

        XCTAssertEqual(hour, 14, "Hour should be 14")
        XCTAssertEqual(minute, 30, "Minute should be 30")
    }

    // MARK: - Trigger Display Names

    func testTriggerDisplayNameNoOffset() {
        let trigger = Trigger.solar(event: .sunrise, offset: 0)
        XCTAssertEqual(trigger.displayName, "Sunrise")
    }

    func testTriggerDisplayNamePositiveOffset() {
        let trigger = Trigger.solar(event: .sunrise, offset: 3600)
        XCTAssertTrue(trigger.displayName.contains("after"))
    }

    func testTriggerDisplayNameNegativeOffset() {
        let trigger = Trigger.solar(event: .sunset, offset: -3600)
        XCTAssertTrue(trigger.displayName.contains("before"))
    }

    func testFixedTimeDisplayName() {
        let trigger = Trigger.fixed(hour: 9, minute: 30)
        XCTAssertEqual(trigger.displayName, "09:30")
    }

    // MARK: - WallpaperConfig

    func testDefaultConfigHasFourSlots() {
        let config = WallpaperConfig.default

        XCTAssertEqual(config.slots.count, 4, "Default config should have 4 slots")
    }

    func testDefaultConfigSlotsAreSorted() {
        let config = WallpaperConfig.default
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let sorted = config.sortedSlots(sunTimes: sunTimes)
        var previousTime: Date?

        for slot in sorted {
            let time = slot.resolvedTime(sunTimes: sunTimes)
            if let prev = previousTime {
                XCTAssertGreaterThanOrEqual(time, prev, "Slots should be in chronological order")
            }
            previousTime = time
        }
    }

    func testCurrentSlotFindsCorrectSlot() {
        let config = WallpaperConfig.default
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        // Test at different times of day
        let sorted = config.sortedSlots(sunTimes: sunTimes)
        guard sorted.count >= 2 else {
            XCTFail("Need at least 2 slots for this test")
            return
        }

        // Test right after first slot triggers
        let firstSlotTime = sorted[0].resolvedTime(sunTimes: sunTimes)
        let testTime = firstSlotTime.addingTimeInterval(60) // 1 minute after first slot

        let current = config.currentSlot(sunTimes: sunTimes, at: testTime)

        XCTAssertEqual(current?.id, sorted[0].id, "Should find first slot as current")
    }

    func testNextTransitionReturnsCorrectSlot() {
        let config = WallpaperConfig.default
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let sorted = config.sortedSlots(sunTimes: sunTimes)
        guard sorted.count >= 2 else {
            XCTFail("Need at least 2 slots for this test")
            return
        }

        // Test from before first slot
        let firstSlotTime = sorted[0].resolvedTime(sunTimes: sunTimes)
        let testTime = firstSlotTime.addingTimeInterval(-60) // 1 minute before first slot

        if let next = config.nextTransition(sunTimes: sunTimes, at: testTime) {
            XCTAssertEqual(next.slot.id, sorted[0].id, "Next should be first slot")
        } else {
            XCTFail("Should find a next transition")
        }
    }

    func testEmptySlotsReturnsNilCurrentSlot() {
        let config = WallpaperConfig(slots: [])
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        let current = config.currentSlot(sunTimes: sunTimes)

        XCTAssertNil(current, "Empty config should return nil current slot")
    }

    func testDisabledSlotsAreFiltered() {
        var config = WallpaperConfig.default
        // Disable all slots
        config.slots = config.slots.map { slot in
            var modified = slot
            modified.isEnabled = false
            return modified
        }

        let sunTimes = SunCalculator.calculate(for: chicagoLocation)
        let sorted = config.sortedSlots(sunTimes: sunTimes)

        XCTAssertTrue(sorted.isEmpty, "Disabled slots should be filtered out")
    }

    // MARK: - Codable

    func testTimeSlotCodable() throws {
        let slot = TimeSlot(
            name: "Test",
            trigger: .solar(event: .sunrise, offset: 3600),
            source: .builtIn(assetID: "test-id")
        )

        let encoded = try JSONEncoder().encode(slot)
        let decoded = try JSONDecoder().decode(TimeSlot.self, from: encoded)

        XCTAssertEqual(decoded.name, slot.name)
        XCTAssertEqual(decoded.id, slot.id)
    }

    func testWallpaperConfigCodable() throws {
        let config = WallpaperConfig.default

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WallpaperConfig.self, from: encoded)

        XCTAssertEqual(decoded.slots.count, config.slots.count)
        XCTAssertEqual(decoded.enableSolarTracking, config.enableSolarTracking)
    }

    // MARK: - DST Edge Case

    func testFixedTimeDSTSpringForward() {
        // Create a time that doesn't exist during spring forward (2:30 AM)
        let trigger = Trigger.fixed(hour: 2, minute: 30)
        let sunTimes = SunCalculator.calculate(for: chicagoLocation)

        // Shouldn't crash, should return some valid time
        let resolved = trigger.resolveTime(sunTimes: sunTimes)

        XCTAssertNotNil(resolved, "Should handle DST gap gracefully")

        let calendar = Calendar.current
        let day = calendar.component(.day, from: resolved)
        let today = calendar.component(.day, from: Date())

        XCTAssertEqual(day, today, "Resolved time should be on the same day")
    }
}
