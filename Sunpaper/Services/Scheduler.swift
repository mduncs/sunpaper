import Foundation
import CoreLocation
import AppKit

protocol SlotSchedulerTimerToken: AnyObject {
    func invalidate()
}

extension Timer: SlotSchedulerTimerToken {}

protocol SlotSchedulerTimerScheduling {
    @discardableResult
    func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        _ handler: @escaping () -> Void
    ) -> SlotSchedulerTimerToken
}

struct FoundationSlotSchedulerTimerScheduler: SlotSchedulerTimerScheduling {
    @discardableResult
    func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        _ handler: @escaping () -> Void
    ) -> SlotSchedulerTimerToken {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            handler()
        }
    }
}

protocol SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping () -> Void) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
}

struct WorkspaceSlotSchedulerWakeObserver: SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping () -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                handler()
            }
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
}

protocol SlotSchedulerWallpaperServicing {
    func downloadAerial(assetID: String, from url: URL) async throws
    func isAerialDownloaded(assetID: String) -> Bool
    func setWallpaper(assetID: String, displayUUID: String?) throws
    func setCustomWallpaper(path: String) throws
    func getCurrentAssetID() throws -> String?
}

extension WallpaperService: SlotSchedulerWallpaperServicing {}

protocol SlotSchedulerDisplayProviding {
    func getDisplays() -> [DisplayManager.Display]
}

extension DisplayManager: SlotSchedulerDisplayProviding {}

@MainActor
protocol SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL?
}

struct LiveSlotSchedulerAerialCatalogResolver: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? {
        guard let asset = AerialCatalog.shared.asset(for: assetID),
              let urlString = asset.videoURL else {
            return nil
        }

        return URL(string: urlString)
    }
}

struct SlotSchedulerDependencies {
    var now: () -> Date
    var calculateSunTimes: (_ location: CLLocationCoordinate2D, _ date: Date) -> SunCalculator.SunTimes
    var timerScheduler: SlotSchedulerTimerScheduling
    var wakeObserver: SlotSchedulerWakeObserving
    var wallpaperService: SlotSchedulerWallpaperServicing
    var displayProvider: SlotSchedulerDisplayProviding
    var aerialCatalog: SlotSchedulerAerialCatalogResolving

    static var live: SlotSchedulerDependencies {
        SlotSchedulerDependencies(
            now: { Date() },
            calculateSunTimes: { location, date in
                SunCalculator.calculate(for: location, on: date)
            },
            timerScheduler: FoundationSlotSchedulerTimerScheduler(),
            wakeObserver: WorkspaceSlotSchedulerWakeObserver(),
            wallpaperService: WallpaperService.shared,
            displayProvider: DisplayManager.shared,
            aerialCatalog: LiveSlotSchedulerAerialCatalogResolver()
        )
    }
}

/// Manages wallpaper scheduling based on flexible time slots
class SlotScheduler: ObservableObject {

    private enum Timing {
        static let locationRetryInterval: TimeInterval = 300
        static let transitionApplyBuffer: TimeInterval = 5
        static let prefetchLeadTime: TimeInterval = 300
        static let verificationInterval: TimeInterval = 1800
        static let wakeRepairDelay: TimeInterval = 10
        static let noTomorrowSlotsRetryInterval: TimeInterval = 6 * 3600
    }

    // MARK: - Published State

    @Published private(set) var currentSlot: TimeSlot?
    @Published private(set) var nextTransition: (slot: TimeSlot, date: Date)?
    @Published private(set) var todaySchedule: [(slot: TimeSlot, time: Date)] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isDownloading = false

    // MARK: - Private State

    private var config: WallpaperConfig
    private var locationProvider: () -> CLLocationCoordinate2D?
    private let dependencies: SlotSchedulerDependencies
    private var timer: SlotSchedulerTimerToken?
    private var prefetchTimer: SlotSchedulerTimerToken?
    private var verifyTimer: SlotSchedulerTimerToken?
    private var wakeObserverToken: NSObjectProtocol?
    private var lastAppliedSlotID: UUID?

    // MARK: - Init

    init(
        config: WallpaperConfig,
        locationProvider: @escaping () -> CLLocationCoordinate2D?,
        dependencies: SlotSchedulerDependencies = .live
    ) {
        self.config = config
        self.locationProvider = locationProvider
        self.dependencies = dependencies
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
        if let obs = wakeObserverToken {
            dependencies.wakeObserver.removeObserver(obs)
            wakeObserverToken = nil
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
            if dependencies.wallpaperService.isAerialDownloaded(assetID: assetID) {
                applyBuiltIn(assetID: assetID, displayUUID: displayUUID)
            } else {
                // Download then apply
                Task { @MainActor in
                    guard let url = dependencies.aerialCatalog.downloadURL(for: assetID) else {
                        lastError = "No download URL for aerial \(assetID)"
                        return
                    }

                    self.isDownloading = true
                    defer { self.isDownloading = false }

                    do {
                        try await dependencies.wallpaperService.downloadAerial(assetID: assetID, from: url)
                        self.applyBuiltIn(assetID: assetID, displayUUID: displayUUID)
                    } catch {
                        self.lastError = "Download failed: \(error.localizedDescription)"
                    }
                }
            }
        case .custom(let path):
            do {
                try dependencies.wallpaperService.setCustomWallpaper(path: path)
            } catch {
                lastError = "Failed to set wallpaper: \(error.localizedDescription)"
            }
        case .none:
            return
        }
    }

    private func applyBuiltIn(assetID: String, displayUUID: String?) {
        do {
            try dependencies.wallpaperService.setWallpaper(assetID: assetID, displayUUID: displayUUID)
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
        guard config.enableSolarTracking else {
            clearScheduleState()
            return
        }

        guard let location = locationProvider() else {
            clearScheduleState()
            return
        }

        let currentDate = dependencies.now()
        let sunTimes = dependencies.calculateSunTimes(location, currentDate)

        // Update published state
        updateScheduleState(sunTimes: sunTimes, at: currentDate)

        // Find current slot
        guard let slot = config.currentSlot(sunTimes: sunTimes, at: currentDate) else { return }

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
                try dependencies.wallpaperService.setWallpaper(assetID: assetID, displayUUID: nil)
                lastAppliedSlotID = slot.id
                lastError = nil
            } catch {
                lastError = "Failed to set wallpaper: \(error.localizedDescription)"
            }
        } else {
            // Per-display mode - apply to each display individually
            let displays = dependencies.displayProvider.getDisplays()
            var anySuccess = false
            var errors: [String] = []

            for display in displays {
                let displaySlots = config.slots(for: display.uuid)
                guard let displaySlot = WallpaperConfig.currentSlot(
                    slots: displaySlots,
                    sunTimes: sunTimes,
                    at: currentDate
                ) else {
                    continue
                }

                guard case .builtIn(let assetID) = displaySlot.source else {
                    continue
                }

                do {
                    try dependencies.wallpaperService.setWallpaper(assetID: assetID, displayUUID: display.uuid)
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

    private func updateScheduleState(sunTimes: SunCalculator.SunTimes, at date: Date) {
        // Current slot
        currentSlot = config.currentSlot(sunTimes: sunTimes, at: date)

        // Next transition
        nextTransition = config.nextTransition(sunTimes: sunTimes, at: date)

        // Today's full schedule
        let sorted = config.sortedSlots(sunTimes: sunTimes, on: date)
        todaySchedule = sorted.map { slot in
            (slot: slot, time: slot.resolvedTime(sunTimes: sunTimes, on: date))
        }
    }

    private func clearScheduleState() {
        currentSlot = nil
        nextTransition = nil
        todaySchedule = []
    }

    private func scheduleNextUpdate() {
        timer?.invalidate()
        prefetchTimer?.invalidate()

        guard config.enableSolarTracking else { return }

        guard let location = locationProvider() else {
            // Retry in 5 minutes if no location
            timer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: Timing.locationRetryInterval, repeats: false) { [weak self] in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }
            #if DEBUG
            print("[Scheduler] No location, retrying in 5 min")
            #endif
            return
        }

        let currentDate = dependencies.now()
        let sunTimes = dependencies.calculateSunTimes(location, currentDate)

        if let next = config.nextTransition(sunTimes: sunTimes, at: currentDate) {
            let delay = next.date.timeIntervalSince(currentDate) + Timing.transitionApplyBuffer
            #if DEBUG
            print("[Scheduler] Next: \(next.slot.name) in \(Int(delay / 60)) min")
            #endif

            timer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: max(1, delay), repeats: false) { [weak self] in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }

            // Prefetch remains five minutes before each transition.
            schedulePrefetch(before: next.date)
        } else {
            // No more transitions today, schedule for tomorrow morning
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
            let tomorrowSun = dependencies.calculateSunTimes(location, tomorrow)

            // Find first slot tomorrow
            let tomorrowSlots = config.sortedSlots(sunTimes: tomorrowSun, on: tomorrow)
            guard let firstSlot = tomorrowSlots.first else {
                #if DEBUG
                print("[Scheduler] No slots configured for tomorrow")
                #endif
                // Retry in 6 hours
                timer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: Timing.noTomorrowSlotsRetryInterval, repeats: false) { [weak self] in
                    self?.updateNow()
                    self?.scheduleNextUpdate()
                }
                return
            }

            let firstTime = firstSlot.resolvedTime(sunTimes: tomorrowSun, on: tomorrow)
            let delay = firstTime.timeIntervalSince(currentDate) - Timing.prefetchLeadTime

            #if DEBUG
            print("[Scheduler] Next: tomorrow \(firstSlot.name) in \(Int(delay / 3600)) hours")
            #endif

            timer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: max(1, delay), repeats: false) { [weak self] in
                self?.updateNow()
                self?.scheduleNextUpdate()
            }

            // Prefetch remains five minutes before tomorrow's first transition.
            schedulePrefetch(before: firstTime)
        }
    }

    /// Schedule a prefetch 5 minutes before a transition to download missing aerials
    private func schedulePrefetch(before transitionDate: Date) {
        let currentDate = dependencies.now()
        let prefetchDelay = transitionDate.timeIntervalSince(currentDate) - Timing.prefetchLeadTime

        if prefetchDelay > 0 {
            prefetchTimer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: prefetchDelay, repeats: false) { [weak self] in
                self?.prefetchUpcoming()
            }
            #if DEBUG
            print("[Scheduler] Prefetch scheduled in \(Int(prefetchDelay / 60)) min")
            #endif
        } else if transitionDate.timeIntervalSince(currentDate) > 0 {
            // Less than 5 min until transition, prefetch immediately
            prefetchUpcoming()
        }
    }

    // MARK: - Wallpaper Verification

    /// Periodically verify the active wallpaper matches what we expect
    private func startVerifyTimer() {
        verifyTimer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: Timing.verificationInterval, repeats: true) { [weak self] in
            self?.verifyCurrentWallpaper()
        }
    }

    /// Re-verify wallpaper after waking from sleep
    private func observeWake() {
        wakeObserverToken = dependencies.wakeObserver.observeWake(after: Timing.wakeRepairDelay) { [weak self] in
            self?.verifyCurrentWallpaper()
        }
    }

    /// Compare active wallpaper against expected slot; re-download and reapply if mismatched
    private func verifyCurrentWallpaper() {
        guard config.enableSolarTracking else { return }
        guard let location = locationProvider() else { return }

        let currentDate = dependencies.now()
        let sunTimes = dependencies.calculateSunTimes(location, currentDate)
        guard let slot = config.currentSlot(sunTimes: sunTimes, at: currentDate) else { return }
        guard case .builtIn(let expectedAssetID) = slot.source else { return }

        // Check what's actually set in the plist
        let currentAssetID = try? dependencies.wallpaperService.getCurrentAssetID()
        guard currentAssetID != expectedAssetID else { return }

        #if DEBUG
        print("[Scheduler] Wallpaper mismatch: expected \(expectedAssetID), got \(currentAssetID ?? "nil"). Repairing...")
        #endif

        if !dependencies.wallpaperService.isAerialDownloaded(assetID: expectedAssetID) {
            // Need to download first, then reapply
            Task { @MainActor in
                guard let url = dependencies.aerialCatalog.downloadURL(for: expectedAssetID) else { return }

                self.isDownloading = true
                defer { self.isDownloading = false }

                do {
                    try await dependencies.wallpaperService.downloadAerial(assetID: expectedAssetID, from: url)
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
        let currentDate = dependencies.now()
        let sunTimes = dependencies.calculateSunTimes(location, currentDate)

        // Collect all asset IDs needed at the next transition
        var assetIDs: Set<String> = []

        if config.displayMode == .allDisplays {
            if let next = config.nextTransition(sunTimes: sunTimes, at: currentDate) {
                if case .builtIn(let assetID) = next.slot.source {
                    assetIDs.insert(assetID)
                }
            }
        } else {
            // Per-display: check each display's next upcoming slot
            let displays = dependencies.displayProvider.getDisplays()
            for display in displays {
                let displaySlots = config.slots(for: display.uuid)
                let sorted = displaySlots
                    .filter { $0.isEnabled }
                    .sorted { $0.resolvedTime(sunTimes: sunTimes, on: currentDate) < $1.resolvedTime(sunTimes: sunTimes, on: currentDate) }
                for slot in sorted {
                    if slot.resolvedTime(sunTimes: sunTimes, on: currentDate) > currentDate {
                        if case .builtIn(let assetID) = slot.source {
                            assetIDs.insert(assetID)
                        }
                        break
                    }
                }
            }
        }

        // Download any missing aerials
        let missing = assetIDs.filter { !dependencies.wallpaperService.isAerialDownloaded(assetID: $0) }
        guard !missing.isEmpty else { return }

        #if DEBUG
        print("[Scheduler] Prefetching \(missing.count) missing aerial(s)")
        #endif

        Task { @MainActor in
            self.isDownloading = true
            defer { self.isDownloading = false }

            for assetID in missing {
                guard let url = dependencies.aerialCatalog.downloadURL(for: assetID) else {
                    #if DEBUG
                    print("[Scheduler] No download URL for aerial \(assetID)")
                    #endif
                    continue
                }

                do {
                    try await dependencies.wallpaperService.downloadAerial(assetID: assetID, from: url)
                } catch {
                    #if DEBUG
                    print("[Scheduler] Prefetch failed for \(assetID): \(error)")
                    #endif
                }
            }
        }
    }
}
