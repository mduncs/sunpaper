import XCTest
import CoreLocation
@testable import Sunpaper

final class SunCalculatorTests: XCTestCase {

    // MARK: - Basic Functionality

    func testSunriseBeforeSunset() {
        // Chicago coordinates
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let sunTimes = SunCalculator.calculate(for: location)

        XCTAssertLessThan(sunTimes.sunrise, sunTimes.sunset, "Sunrise should be before sunset")
    }

    func testSunTimesAreOnSameDay() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let date = Date()
        let sunTimes = SunCalculator.calculate(for: location, on: date)

        let calendar = Calendar.current
        let sunriseDay = calendar.component(.day, from: sunTimes.sunrise)
        let sunsetDay = calendar.component(.day, from: sunTimes.sunset)
        let requestedDay = calendar.component(.day, from: date)

        XCTAssertEqual(sunriseDay, requestedDay, "Sunrise should be on the requested day")
        XCTAssertEqual(sunsetDay, requestedDay, "Sunset should be on the requested day")
    }

    func testSolarNoonIsBetweenSunriseAndSunset() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let sunTimes = SunCalculator.calculate(for: location)

        if let solarNoon = sunTimes.solarNoon {
            XCTAssertGreaterThan(solarNoon, sunTimes.sunrise, "Solar noon should be after sunrise")
            XCTAssertLessThan(solarNoon, sunTimes.sunset, "Solar noon should be before sunset")
        } else {
            XCTFail("Solar noon should not be nil")
        }
    }

    func testCivilDawnBeforeSunrise() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let sunTimes = SunCalculator.calculate(for: location)

        if let civilDawn = sunTimes.civilDawn {
            XCTAssertLessThan(civilDawn, sunTimes.sunrise, "Civil dawn should be before sunrise")
        }
    }

    func testCivilDuskAfterSunset() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let sunTimes = SunCalculator.calculate(for: location)

        if let civilDusk = sunTimes.civilDusk {
            XCTAssertGreaterThan(civilDusk, sunTimes.sunset, "Civil dusk should be after sunset")
        }
    }

    // MARK: - Different Locations

    func testEquatorLocation() {
        // Quito, Ecuador (on equator)
        let location = CLLocationCoordinate2D(latitude: 0.0, longitude: -78.5)
        let sunTimes = SunCalculator.calculate(for: location)

        // At equator, day length should be roughly 12 hours year-round
        let dayLength = sunTimes.sunset.timeIntervalSince(sunTimes.sunrise) / 3600
        XCTAssertGreaterThan(dayLength, 11, "Day length at equator should be > 11 hours")
        XCTAssertLessThan(dayLength, 13, "Day length at equator should be < 13 hours")
    }

    func testNorthernLatitude() {
        // Stockholm, Sweden
        let location = CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686)
        let sunTimes = SunCalculator.calculate(for: location)

        // Just verify we get valid times
        XCTAssertLessThan(sunTimes.sunrise, sunTimes.sunset)
    }

    func testSouthernHemisphere() {
        // Sydney, Australia
        let location = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let sunTimes = SunCalculator.calculate(for: location)

        XCTAssertLessThan(sunTimes.sunrise, sunTimes.sunset)
    }

    // MARK: - Edge Cases

    func testPolarRegionWinter() {
        // Barrow, Alaska in winter - near polar night
        let location = CLLocationCoordinate2D(latitude: 71.29, longitude: -156.78)

        // December date
        var components = DateComponents()
        components.year = 2024
        components.month = 12
        components.day = 21
        let winterDate = Calendar.current.date(from: components)!

        let sunTimes = SunCalculator.calculate(for: location, on: winterDate)

        // In polar night, sunrise and sunset should be very close or equal
        // The algorithm clamps values, so we just verify it doesn't crash
        XCTAssertNotNil(sunTimes.sunrise)
        XCTAssertNotNil(sunTimes.sunset)
    }

    func testPolarRegionSummer() {
        // Barrow, Alaska in summer - near midnight sun
        let location = CLLocationCoordinate2D(latitude: 71.29, longitude: -156.78)

        // June date
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 21
        let summerDate = Calendar.current.date(from: components)!

        let sunTimes = SunCalculator.calculate(for: location, on: summerDate)

        XCTAssertNotNil(sunTimes.sunrise)
        XCTAssertNotNil(sunTimes.sunset)
    }

    // MARK: - Specific Dates

    func testWinterSolstice() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

        var components = DateComponents()
        components.year = 2024
        components.month = 12
        components.day = 21
        let winterSolstice = Calendar.current.date(from: components)!

        let sunTimes = SunCalculator.calculate(for: location, on: winterSolstice)
        let dayLength = sunTimes.sunset.timeIntervalSince(sunTimes.sunrise) / 3600

        // Winter solstice should have short day (roughly 9 hours in Chicago)
        XCTAssertLessThan(dayLength, 10, "Winter solstice should have short days")
        XCTAssertGreaterThan(dayLength, 8, "Day should still be > 8 hours in Chicago")
    }

    func testSummerSolstice() {
        let location = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 21
        let summerSolstice = Calendar.current.date(from: components)!

        let sunTimes = SunCalculator.calculate(for: location, on: summerSolstice)
        let dayLength = sunTimes.sunset.timeIntervalSince(sunTimes.sunrise) / 3600

        // Summer solstice should have long day (roughly 15 hours in Chicago)
        XCTAssertGreaterThan(dayLength, 14, "Summer solstice should have long days")
        XCTAssertLessThan(dayLength, 16, "Day shouldn't exceed 16 hours in Chicago")
    }
}
