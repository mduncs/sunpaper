import Foundation
import CoreLocation

/// Calculates sunrise, sunset, and other solar times for a given location
class SunCalculator {

    /// Polar conditions when sunrise/sunset calculations are invalid
    enum PolarCondition: Equatable {
        case normal           // Standard day/night cycle
        case polarDay         // Sun never sets (midnight sun)
        case polarNight       // Sun never rises
    }

    struct SunTimes {
        let sunrise: Date
        let sunset: Date
        let civilDawn: Date?      // Sun 6° below horizon (pre-sunrise)
        let civilDusk: Date?      // Sun 6° below horizon (post-sunset)
        let solarNoon: Date?      // Sun at highest point
        let date: Date
        let polarCondition: PolarCondition  // Whether we're in a polar region
    }

    /// Calculate solar times for a location on a given date
    /// Uses NOAA solar calculator algorithm
    static func calculate(for location: CLLocationCoordinate2D, on date: Date = Date()) -> SunTimes {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)!

        let lat = location.latitude
        let lon = location.longitude
        let latRad = lat * .pi / 180

        // Solar declination
        let declination = 23.45 * sin((360.0 * Double(284 + dayOfYear) / 365.0) * .pi / 180)
        let declinationRad = declination * .pi / 180

        // Equation of time
        let b = (360.0 * Double(dayOfYear - 81) / 365.0) * .pi / 180
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        // Time offset for longitude (4 minutes per degree)
        let timeOffset = eot + 4 * lon

        // Solar noon in minutes from midnight UTC
        let solarNoonMinutes = 720 - timeOffset

        // Get timezone offset in minutes
        let tzOffset = Double(TimeZone.current.secondsFromGMT(for: date)) / 60
        let startOfDay = calendar.startOfDay(for: date)

        // Solar noon
        let solarNoon = startOfDay.addingTimeInterval((solarNoonMinutes + tzOffset) * 60)

        // Calculate sunrise/sunset with official zenith (90.833°)
        let (sunrise, sunset, polarCondition) = calculateSunriseSunset(
            zenith: 90.833,
            latRad: latRad,
            declinationRad: declinationRad,
            solarNoonMinutes: solarNoonMinutes,
            tzOffset: tzOffset,
            startOfDay: startOfDay
        )

        // Calculate civil dawn/dusk with civil twilight zenith (96°)
        let (civilDawn, civilDusk, _) = calculateSunriseSunset(
            zenith: 96.0,
            latRad: latRad,
            declinationRad: declinationRad,
            solarNoonMinutes: solarNoonMinutes,
            tzOffset: tzOffset,
            startOfDay: startOfDay
        )

        return SunTimes(
            sunrise: sunrise,
            sunset: sunset,
            civilDawn: civilDawn,
            civilDusk: civilDusk,
            solarNoon: solarNoon,
            date: date,
            polarCondition: polarCondition
        )
    }

    /// Calculate sunrise and sunset for a given zenith angle
    private static func calculateSunriseSunset(
        zenith: Double,
        latRad: Double,
        declinationRad: Double,
        solarNoonMinutes: Double,
        tzOffset: Double,
        startOfDay: Date
    ) -> (rise: Date, set: Date, condition: PolarCondition) {

        let cosHourAngle = (cos(zenith * .pi / 180) / (cos(latRad) * cos(declinationRad)))
            - tan(latRad) * tan(declinationRad)

        // Detect polar conditions
        let polarCondition: PolarCondition
        if cosHourAngle > 1 {
            // Sun never rises (polar night)
            polarCondition = .polarNight
        } else if cosHourAngle < -1 {
            // Sun never sets (polar day / midnight sun)
            polarCondition = .polarDay
        } else {
            polarCondition = .normal
        }

        // Clamp to valid range (handles polar day/night with approximated times)
        let clampedCos = max(-1, min(1, cosHourAngle))
        let hourAngle = acos(clampedCos) * 180 / .pi

        let riseMinutes = solarNoonMinutes - hourAngle * 4 + tzOffset
        let setMinutes = solarNoonMinutes + hourAngle * 4 + tzOffset

        let rise = startOfDay.addingTimeInterval(riseMinutes * 60)
        let set = startOfDay.addingTimeInterval(setMinutes * 60)

        return (rise, set, polarCondition)
    }

    // MARK: - Polar Region Detection

    /// Check if a location is in a polar region on a given date
    static func isPolarRegion(for location: CLLocationCoordinate2D, on date: Date = Date()) -> Bool {
        let sunTimes = calculate(for: location, on: date)
        return sunTimes.polarCondition != .normal
    }

    /// Get a human-readable description of the polar condition
    static func polarDescription(for condition: PolarCondition) -> String? {
        switch condition {
        case .normal:
            return nil
        case .polarDay:
            return "This location is experiencing midnight sun - the sun doesn't set. Wallpaper transitions may not work as expected."
        case .polarNight:
            return "This location is experiencing polar night - the sun doesn't rise. Wallpaper transitions may not work as expected."
        }
    }

}
