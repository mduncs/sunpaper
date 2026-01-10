import Foundation
import CoreLocation

/// Manages wallpaper scheduling based on flexible time slots
class SlotScheduler: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentSlot: TimeSlot?
    @Published private(set) var nextTransition: (slot: TimeSlot, date: Date)?
    @Published private(set) var todaySchedule: [(slot: TimeSlot, time: Date)] = []
    @Published private(set) var lastError: String?

    // MARK: - Private State

    private var config: WallpaperConfig
    private var locationProvider: () -> CLLocationCoordinate2D?
    private var timer: Timer?
    private var lastAppliedSlotID: UUID?

    // MARK: - Init

    init(config: WallpaperConfig, locationProvider: @escaping () -> CLLocationCoordinate2D?) {
        self.config = config
        self.locationProvider = locationProvider
    }

    // MARK: - Public API

    func start() {
        updateNow()
        scheduleNextUpdate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateConfig(_ newConfig: WallpaperConfig) {
        config = newConfig
        lastAppliedSlotID = nil  // Force reapply
        updateNow()
        scheduleNextUpdate()
    }

    func forceUpdate() {
        lastAppliedSlotID = nil  // Force reapply even if slot unchanged
        updateNow()
    }

    /// Apply a specific wallpaper immediately (for preview/manual override)
    func applyWallpaper(source: WallpaperSource, displayUUID: String? = nil) {
        do {
            switch source {
            case .builtIn(let assetID):
                try WallpaperService.shared.setWallpaper(assetID: assetID, displayUUID: displayUUID)
            case .custom(let path):
                try WallpaperService.shared.setCustomWallpaper(path: path)
            case .none:
                return
            }
            #if DEBUG
            print("[Scheduler] Applied wallpaper: \(source.displayName)")
            #endif
        } catch {
            #if DEBUG
            print("[Scheduler] Failed to apply wallpaper: \(error)")
            #endif
        }
    }

    // MARK: - Private

    private func updateNow() {
        guard config.enableSolarTracking else { return }
        guard let location = locationProvider() else { return }

        let sunTimes = SunCalculator.calculate(for: location)

        // Update published state
        updateScheduleState(sunTimes: sunTimes)

        // Find current slot
        guard let slot = config.currentSlot(sunTimes: sunTimes) else { return }

        // Only apply if slot changed
        guard slot.id != lastAppliedSlotID else { return }

        // Apply the wallpaper based on display mode
        if config.displayMode == .allDisplays {
            // All displays mode - apply once to all
            guard case .builtIn(let assetID) = slot.source else {
                // Don't update lastAppliedSlotID - allows reapply when wallpaper is assigned
                lastError = nil
                return
            }

            do {
                try WallpaperService.shared.setWallpaper(assetID: assetID)
                lastAppliedSlotID = slot.id
                lastError = nil
            } catch {
                lastError = "Failed to set wallpaper: \(error.localizedDescription)"
            }
        } else {
            // Per-display mode - apply to each display individually
            let displays = DisplayManager.shared.getDisplays()
            var anySuccess = false
            var errors: [String] = []

            for display in displays {
                let displaySlots = config.slots(for: display.uuid)
                guard let displaySlot = WallpaperConfig.currentSlot(
                    slots: displaySlots,
                    sunTimes: sunTimes
                ) else {
                    continue
                }

                guard case .builtIn(let assetID) = displaySlot.source else {
                    continue
                }

                do {
                    try WallpaperService.shared.setWallpaper(assetID: assetID, displayUUID: display.uuid)
                    #if DEBUG
                    print("[Scheduler] Applied \(displaySlot.name) to \(display.displayName)")
                    #endif
                    anySuccess = true
                } catch {
                    #if DEBUG
                    print("[Scheduler] Failed to set wallpaper on \(display.displayName): \(error)")
                    #endif
                    errors.append("\(display.displayName): \(error.localizedDescription)")
                }
            }

            if anySuccess {
                lastAppliedSlotID = slot.id
                lastError = errors.isEmpty ? nil : "Partial failure: \(errors.joined(separator: "; "))"
            } else if !errors.isEmpty {
                lastError = "Failed to set wallpaper: \(errors.joined(separator: "; "))"
            }
        }
    }

    private func updateScheduleState(sunTimes: SunCalculator.SunTimes) {
        let now = Date()

        // Current slot
        currentSlot = config.currentSlot(sunTimes: sunTimes, at: now)

        // Next transition
        nextTransition = config.nextTransition(sunTimes: sunTimes, at: now)

        // Today's full schedule
        let sorted = config.sortedSlots(sunTimes: sunTimes, on: now)
        todaySchedule = sorted.map { slot in
            (slot: slot, time: slot.resolvedTime(sunTimes: sunTimes, on: now))
        }
    }

    private func scheduleNextUpdate() {
        timer?.invalidate()

        guard config.enableSolarTracking else { return }

        guard let location = locationProvider() else {
            // Retry in 5 minutes if no location
            timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }
            #if DEBUG
            print("[Scheduler] No location, retrying in 5 min")
            #endif
            return
        }

        let sunTimes = SunCalculator.calculate(for: location)

        if let next = config.nextTransition(sunTimes: sunTimes) {
            let delay = next.date.timeIntervalSinceNow + 5  // 5 second buffer
            #if DEBUG
            print("[Scheduler] Next: \(next.slot.name) in \(Int(delay / 60)) min")
            #endif

            timer = Timer.scheduledTimer(withTimeInterval: max(1, delay), repeats: false) { [weak self] _ in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }
        } else {
            // No more transitions today, schedule for tomorrow morning
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let tomorrowSun = SunCalculator.calculate(for: location, on: tomorrow)

            // Find first slot tomorrow
            let tomorrowSlots = config.sortedSlots(sunTimes: tomorrowSun, on: tomorrow)
            guard let firstSlot = tomorrowSlots.first else {
                #if DEBUG
                print("[Scheduler] No slots configured for tomorrow")
                #endif
                // Retry in 6 hours
                timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: false) { [weak self] _ in
                    self?.updateNow()
                    self?.scheduleNextUpdate()
                }
                return
            }

            let firstTime = firstSlot.resolvedTime(sunTimes: tomorrowSun, on: tomorrow)
            let delay = firstTime.timeIntervalSinceNow - 300  // 5 min early

            #if DEBUG
            print("[Scheduler] Next: tomorrow \(firstSlot.name) in \(Int(delay / 3600)) hours")
            #endif

            timer = Timer.scheduledTimer(withTimeInterval: max(1, delay), repeats: false) { [weak self] _ in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }
        }
    }
}
