import Foundation

// MARK: - Solar Events

/// Solar events that can trigger wallpaper changes
enum SolarEvent: String, Codable, CaseIterable {
    case sunrise
    case sunset
    case civilDawn      // Sun 6° below horizon (enough light to see)
    case civilDusk      // Sun 6° below horizon
    case solarNoon      // Sun at highest point

    var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        case .civilDawn: return "Civil Dawn"
        case .civilDusk: return "Civil Dusk"
        case .solarNoon: return "Solar Noon"
        }
    }

    var icon: String {
        switch self {
        case .sunrise, .civilDawn: return "sunrise.fill"
        case .sunset, .civilDusk: return "sunset.fill"
        case .solarNoon: return "sun.max.fill"
        }
    }
}

// MARK: - Trigger

/// When a wallpaper change should occur
enum Trigger: Codable, Equatable {
    /// Relative to a solar event (offset in seconds, can be negative)
    case solar(event: SolarEvent, offset: TimeInterval)

    /// Fixed time of day (24h format)
    case fixed(hour: Int, minute: Int)

    var displayName: String {
        switch self {
        case .solar(let event, let offset):
            if offset == 0 {
                return event.displayName
            }
            let minutes = Int(abs(offset) / 60)
            let hours = minutes / 60
            let remainingMinutes = minutes % 60

            let direction = offset < 0 ? "before" : "after"
            if hours > 0 && remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m \(direction) \(event.displayName.lowercased())"
            } else if hours > 0 {
                return "\(hours)h \(direction) \(event.displayName.lowercased())"
            } else {
                return "\(remainingMinutes)m \(direction) \(event.displayName.lowercased())"
            }

        case .fixed(let hour, let minute):
            return String(format: "%02d:%02d", hour, minute)
        }
    }

    var icon: String {
        switch self {
        case .solar(let event, _): return event.icon
        case .fixed: return "clock.fill"
        }
    }

    /// Resolve this trigger to an actual time on a given date
    func resolveTime(sunTimes: SunCalculator.SunTimes, on date: Date = Date()) -> Date {
        let calendar = Calendar.current

        switch self {
        case .solar(let event, let offset):
            let baseTime: Date
            switch event {
            case .sunrise:
                baseTime = sunTimes.sunrise
            case .sunset:
                baseTime = sunTimes.sunset
            case .civilDawn:
                baseTime = sunTimes.civilDawn ?? sunTimes.sunrise.addingTimeInterval(-1800)
            case .civilDusk:
                baseTime = sunTimes.civilDusk ?? sunTimes.sunset.addingTimeInterval(1800)
            case .solarNoon:
                baseTime = sunTimes.solarNoon ?? Date(
                    timeIntervalSince1970: (sunTimes.sunrise.timeIntervalSince1970 + sunTimes.sunset.timeIntervalSince1970) / 2
                )
            }
            return baseTime.addingTimeInterval(offset)

        case .fixed(let hour, let minute):
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = 0

            // Handle DST transitions where the time might not exist
            // (e.g., 02:30 during spring forward)
            if let resolved = calendar.date(from: components) {
                return resolved
            }

            // Time doesn't exist (DST gap) - try adding 1 hour
            components.hour = hour + 1
            if let resolved = calendar.date(from: components) {
                return resolved
            }

            // Fallback to noon on the same day
            components.hour = 12
            components.minute = 0
            return calendar.date(from: components) ?? date
        }
    }

    // MARK: - Convenience Initializers

    static func sunrise(offset: TimeInterval = 0) -> Trigger {
        .solar(event: .sunrise, offset: offset)
    }

    static func sunset(offset: TimeInterval = 0) -> Trigger {
        .solar(event: .sunset, offset: offset)
    }

    static func hoursBeforeSunrise(_ hours: Double) -> Trigger {
        .solar(event: .sunrise, offset: -hours * 3600)
    }

    static func hoursAfterSunrise(_ hours: Double) -> Trigger {
        .solar(event: .sunrise, offset: hours * 3600)
    }

    static func hoursBeforeSunset(_ hours: Double) -> Trigger {
        .solar(event: .sunset, offset: -hours * 3600)
    }

    static func hoursAfterSunset(_ hours: Double) -> Trigger {
        .solar(event: .sunset, offset: hours * 3600)
    }
}

// MARK: - Wallpaper Source

/// Where a wallpaper comes from
enum WallpaperSource: Codable, Equatable {
    /// Built-in Apple aerial wallpaper
    case builtIn(assetID: String)

    /// User-provided file
    case custom(path: String)

    /// No wallpaper (skip this slot)
    case none

    var displayName: String {
        switch self {
        case .builtIn(let assetID):
            // Look up friendly name from known assets
            return BuiltInWallpapers.name(for: assetID) ?? "Unknown"
        case .custom(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .none:
            return "None"
        }
    }

    var assetID: String? {
        if case .builtIn(let id) = self { return id }
        return nil
    }
}

// MARK: - Time Slot

/// A single scheduled wallpaper change
struct TimeSlot: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var trigger: Trigger
    var source: WallpaperSource
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        trigger: Trigger,
        source: WallpaperSource = .none,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.source = source
        self.isEnabled = isEnabled
    }

    /// Resolve when this slot triggers on a given day
    func resolvedTime(sunTimes: SunCalculator.SunTimes, on date: Date = Date()) -> Date {
        trigger.resolveTime(sunTimes: sunTimes, on: date)
    }
}

// MARK: - Wallpaper Config

/// Per-display slot configuration
struct DisplayConfig: Codable, Equatable {
    var displayUUID: String
    var slots: [TimeSlot]

    init(displayUUID: String, slots: [TimeSlot] = []) {
        self.displayUUID = displayUUID
        self.slots = slots
    }
}

/// Display mode for wallpaper configuration
enum DisplayMode: String, Codable, Equatable {
    case allDisplays    // Same wallpaper on all displays (default)
    case perDisplay     // Different wallpaper per display
}

/// Main configuration for the app
struct WallpaperConfig: Codable, Equatable {
    var slots: [TimeSlot]
    var enableSolarTracking: Bool
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var displayMode: DisplayMode
    var perDisplayConfigs: [DisplayConfig]

    init(
        slots: [TimeSlot] = [],
        enableSolarTracking: Bool = true,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        displayMode: DisplayMode = .allDisplays,
        perDisplayConfigs: [DisplayConfig] = []
    ) {
        self.slots = slots
        self.enableSolarTracking = enableSolarTracking
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.displayMode = displayMode
        self.perDisplayConfigs = perDisplayConfigs
    }

    /// Get slots for a specific display (when in per-display mode)
    func slots(for displayUUID: String) -> [TimeSlot] {
        guard displayMode == .perDisplay else { return slots }
        return perDisplayConfigs.first(where: { $0.displayUUID == displayUUID })?.slots ?? []
    }

    /// Update slots for a specific display
    mutating func setSlots(_ slots: [TimeSlot], for displayUUID: String) {
        if let index = perDisplayConfigs.firstIndex(where: { $0.displayUUID == displayUUID }) {
            perDisplayConfigs[index].slots = slots
        } else {
            perDisplayConfigs.append(DisplayConfig(displayUUID: displayUUID, slots: slots))
        }
    }

    /// Get slots sorted by resolved time for a given day
    func sortedSlots(sunTimes: SunCalculator.SunTimes, on date: Date = Date()) -> [TimeSlot] {
        slots
            .filter { $0.isEnabled }
            .sorted { $0.resolvedTime(sunTimes: sunTimes, on: date) < $1.resolvedTime(sunTimes: sunTimes, on: date) }
    }

    /// Find which slot is currently active
    func currentSlot(sunTimes: SunCalculator.SunTimes, at date: Date = Date()) -> TimeSlot? {
        let sorted = sortedSlots(sunTimes: sunTimes, on: date)
        return Self.currentSlot(slots: sorted, sunTimes: sunTimes, at: date)
    }

    /// Find which slot is currently active from a list of slots (static helper)
    static func currentSlot(slots: [TimeSlot], sunTimes: SunCalculator.SunTimes, at date: Date = Date()) -> TimeSlot? {
        let sorted = slots
            .filter { $0.isEnabled }
            .sorted { $0.resolvedTime(sunTimes: sunTimes, on: date) < $1.resolvedTime(sunTimes: sunTimes, on: date) }

        guard !sorted.isEmpty else { return nil }

        // Find the last slot whose time has passed
        var current: TimeSlot? = nil
        for slot in sorted {
            if slot.resolvedTime(sunTimes: sunTimes, on: date) <= date {
                current = slot
            } else {
                break
            }
        }

        // If no slot has passed yet today, we're still in yesterday's last slot
        // But we should use TODAY's last slot as proxy (same wallpaper, correct mental model)
        // This avoids needing to fetch yesterday's sun times
        return current ?? sorted.last
    }

    /// Find the next upcoming transition
    func nextTransition(sunTimes: SunCalculator.SunTimes, at date: Date = Date()) -> (slot: TimeSlot, date: Date)? {
        let sorted = sortedSlots(sunTimes: sunTimes, on: date)

        for slot in sorted {
            let time = slot.resolvedTime(sunTimes: sunTimes, on: date)
            if time > date {
                return (slot, time)
            }
        }

        return nil
    }

    // MARK: - Default Configuration

    static let `default` = WallpaperConfig(
        slots: [
            TimeSlot(
                name: "Morning",
                trigger: .hoursBeforeSunrise(1),
                source: .builtIn(assetID: BuiltInWallpapers.tahoe.morning)
            ),
            TimeSlot(
                name: "Day",
                trigger: .hoursAfterSunrise(1),
                source: .builtIn(assetID: BuiltInWallpapers.tahoe.day)
            ),
            TimeSlot(
                name: "Evening",
                trigger: .hoursBeforeSunset(1),
                source: .builtIn(assetID: BuiltInWallpapers.tahoe.evening)
            ),
            TimeSlot(
                name: "Night",
                trigger: .hoursAfterSunset(1),
                source: .builtIn(assetID: BuiltInWallpapers.tahoe.night)
            )
        ],
        enableSolarTracking: true
    )
}

// MARK: - Built-in Wallpapers Registry

/// Registry of known Apple aerial wallpapers
struct BuiltInWallpapers {

    struct WallpaperSet {
        let name: String
        let morning: String
        let day: String
        let evening: String
        let night: String

        var all: [(name: String, assetID: String)] {
            [
                ("Morning", morning),
                ("Day", day),
                ("Evening", evening),
                ("Night", night)
            ]
        }
    }

    static let tahoe = WallpaperSet(
        name: "Tahoe",
        morning: "B2FC91ED-6891-4DEB-85A1-268B2B4160B6",
        day: "4C108785-A7BA-422E-9C79-B0129F1D5550",
        evening: "52ACB9B8-75FC-4516-BC60-4550CFF3B661",
        night: "CF6347E2-4F81-4410-8892-4830991B6C5A"
    )

    static let sequoia = WallpaperSet(
        name: "Sequoia",
        morning: "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B",
        day: "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B",
        evening: "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7",
        night: "97C3047F-ED39-472C-9778-CABF25D8682D"
    )

    static let allSets = [tahoe, sequoia]

    private static let assetNames: [String: String] = {
        var names: [String: String] = [:]
        for set in allSets {
            names[set.morning] = "\(set.name) Morning"
            names[set.day] = "\(set.name) Day"
            names[set.evening] = "\(set.name) Evening"
            names[set.night] = "\(set.name) Night"
        }
        return names
    }()

    static func name(for assetID: String) -> String? {
        assetNames[assetID]
    }
}
