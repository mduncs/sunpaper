import Foundation
import CoreLocation
import AppKit

/// Manages wallpaper scheduling based on flexible time slots
class SlotScheduler: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentSlot: TimeSlot?
    @Published private(set) var nextTransition: (slot: TimeSlot, date: Date)?
    @Published private(set) var todaySchedule: [(slot: TimeSlot, time: Date)] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isDownloading = false

    // MARK: - Private State

    private var config: WallpaperConfig
    private var locationProvider: () -> CLLocationCoordinate2D?
    private var timer: Timer?
    private var prefetchTimer: Timer?
    private var verifyTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
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
        startVerifyTimer()
        observeWake()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        prefetchTimer?.invalidate()
        prefetchTimer = nil
        verifyTimer?.invalidate()
        verifyTimer = nil
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
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
    /// Downloads the aerial first if missing from disk.
    func applyWallpaper(source: WallpaperSource, displayUUID: String? = nil) {
        switch source {
        case .builtIn(let assetID):
            if WallpaperService.shared.isAerialDownloaded(assetID: assetID) {
                applyBuiltIn(assetID: assetID, displayUUID: displayUUID)
            } else {
                // Download then apply
                Task { @MainActor in
                    guard let asset = AerialCatalog.shared.asset(for: assetID),
                          let urlString = asset.videoURL,
                          let url = URL(string: urlString) else {
                        lastError = "No download URL for aerial \(assetID)"
                        return
                    }

                    self.isDownloading = true
                    defer { self.isDownloading = false }

                    do {
                        try await WallpaperService.shared.downloadAerial(assetID: assetID, from: url)
                        self.applyBuiltIn(assetID: assetID, displayUUID: displayUUID)
                    } catch {
                        self.lastError = "Download failed: \(error.localizedDescription)"
                    }
                }
            }
        case .custom(let path):
            do {
                try WallpaperService.shared.setCustomWallpaper(path: path)
            } catch {
                lastError = "Failed to set wallpaper: \(error.localizedDescription)"
            }
        case .none:
            return
        }
    }

    private func applyBuiltIn(assetID: String, displayUUID: String?) {
        do {
            try WallpaperService.shared.setWallpaper(assetID: assetID, displayUUID: displayUUID)
            lastError = nil
            #if DEBUG
            print("[Scheduler] Applied wallpaper: \(assetID)")
            #endif
        } catch {
            lastError = "Failed to set wallpaper: \(error.localizedDescription)"
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
        prefetchTimer?.invalidate()

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

            // Prefetch aerial 5 min before transition
            schedulePrefetch(before: next.date)
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

            // Prefetch aerial 5 min before tomorrow's transition
            schedulePrefetch(before: firstTime)
        }
    }

    /// Schedule a prefetch 5 minutes before a transition to download missing aerials
    private func schedulePrefetch(before transitionDate: Date) {
        let prefetchDelay = transitionDate.timeIntervalSinceNow - 300  // 5 min before

        if prefetchDelay > 0 {
            prefetchTimer = Timer.scheduledTimer(withTimeInterval: prefetchDelay, repeats: false) { [weak self] _ in
                self?.prefetchUpcoming()
            }
            #if DEBUG
            print("[Scheduler] Prefetch scheduled in \(Int(prefetchDelay / 60)) min")
            #endif
        } else if transitionDate.timeIntervalSinceNow > 0 {
            // Less than 5 min until transition, prefetch immediately
            prefetchUpcoming()
        }
    }

    // MARK: - Wallpaper Verification

    /// Periodically verify the active wallpaper matches what we expect
    private func startVerifyTimer() {
        verifyTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.verifyCurrentWallpaper()
        }
    }

    /// Re-verify wallpaper after waking from sleep
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Brief delay for system to stabilize after wake
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self?.verifyCurrentWallpaper()
            }
        }
    }

    /// Compare active wallpaper against expected slot; re-download and reapply if mismatched
    private func verifyCurrentWallpaper() {
        guard config.enableSolarTracking else { return }
        guard let location = locationProvider() else { return }

        let sunTimes = SunCalculator.calculate(for: location)
        guard let slot = config.currentSlot(sunTimes: sunTimes) else { return }
        guard case .builtIn(let expectedAssetID) = slot.source else { return }

        // Check what's actually set in the plist
        let currentAssetID = try? WallpaperService.shared.getCurrentAssetID()
        guard currentAssetID != expectedAssetID else { return }

        #if DEBUG
        print("[Scheduler] Wallpaper mismatch: expected \(expectedAssetID), got \(currentAssetID ?? "nil"). Repairing...")
        #endif

        if !WallpaperService.shared.isAerialDownloaded(assetID: expectedAssetID) {
            // Need to download first, then reapply
            Task { @MainActor in
                guard let asset = AerialCatalog.shared.asset(for: expectedAssetID),
                      let urlString = asset.videoURL,
                      let url = URL(string: urlString) else { return }

                self.isDownloading = true
                defer { self.isDownloading = false }

                do {
                    try await WallpaperService.shared.downloadAerial(assetID: expectedAssetID, from: url)
                } catch {
                    #if DEBUG
                    print("[Scheduler] Verify download failed: \(error)")
                    #endif
                    return
                }

                // Force reapply after download
                self.lastAppliedSlotID = nil
                self.updateNow()
            }
        } else {
            // Downloaded but wrong wallpaper active - force reapply
            lastAppliedSlotID = nil
            updateNow()
        }
    }

    // MARK: - Prefetch

    /// Check if upcoming wallpaper aerials are downloaded, download if missing
    private func prefetchUpcoming() {
        guard let location = locationProvider() else { return }
        let sunTimes = SunCalculator.calculate(for: location)

        // Collect all asset IDs needed at the next transition
        var assetIDs: Set<String> = []

        if config.displayMode == .allDisplays {
            if let next = config.nextTransition(sunTimes: sunTimes) {
                if case .builtIn(let assetID) = next.slot.source {
                    assetIDs.insert(assetID)
                }
            }
        } else {
            // Per-display: check each display's next upcoming slot
            let displays = DisplayManager.shared.getDisplays()
            for display in displays {
                let displaySlots = config.slots(for: display.uuid)
                let sorted = displaySlots
                    .filter { $0.isEnabled }
                    .sorted { $0.resolvedTime(sunTimes: sunTimes) < $1.resolvedTime(sunTimes: sunTimes) }
                let now = Date()
                for slot in sorted {
                    if slot.resolvedTime(sunTimes: sunTimes) > now {
                        if case .builtIn(let assetID) = slot.source {
                            assetIDs.insert(assetID)
                        }
                        break
                    }
                }
            }
        }

        // Download any missing aerials
        let missing = assetIDs.filter { !WallpaperService.shared.isAerialDownloaded(assetID: $0) }
        guard !missing.isEmpty else { return }

        #if DEBUG
        print("[Scheduler] Prefetching \(missing.count) missing aerial(s)")
        #endif

        Task { @MainActor in
            self.isDownloading = true
            defer { self.isDownloading = false }

            for assetID in missing {
                guard let asset = AerialCatalog.shared.asset(for: assetID),
                      let urlString = asset.videoURL,
                      let url = URL(string: urlString) else {
                    #if DEBUG
                    print("[Scheduler] No download URL for aerial \(assetID)")
                    #endif
                    continue
                }

                do {
                    try await WallpaperService.shared.downloadAerial(assetID: assetID, from: url)
                } catch {
                    #if DEBUG
                    print("[Scheduler] Prefetch failed for \(assetID): \(error)")
                    #endif
                }
            }
        }
    }
}
