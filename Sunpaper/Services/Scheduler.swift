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
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) -> SlotSchedulerTimerToken
}

struct FoundationSlotSchedulerTimerScheduler: SlotSchedulerTimerScheduling {
    @discardableResult
    func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) -> SlotSchedulerTimerToken {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}

protocol SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
}

struct WorkspaceSlotSchedulerWakeObserver: SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol {
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
    @MainActor func downloadAerial(assetID: String, from url: URL) async throws
    func isAerialDownloaded(assetID: String) -> Bool
    @MainActor func setWallpaper(assetID: String, displayUUID: String?) async throws
    @MainActor func setWallpaper(assetID: String, displayUUID: String?, smoothChanges: Bool) async throws
    @MainActor func setCustomWallpaper(path: String) throws
    @MainActor func setCustomWallpaper(path: String, displayUUID: String?) throws
    func getCurrentAssetID() throws -> String?
}

extension SlotSchedulerWallpaperServicing {
    @MainActor func setWallpaper(assetID: String, displayUUID: String?, smoothChanges: Bool) async throws {
        try await setWallpaper(assetID: assetID, displayUUID: displayUUID)
    }

    @MainActor func setCustomWallpaper(path: String, displayUUID: String?) throws {
        try setCustomWallpaper(path: path)
    }
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
    var hasCapturePermission: @MainActor () -> Bool = { true }

    @MainActor static var live: SlotSchedulerDependencies {
        SlotSchedulerDependencies(
            now: { Date() },
            calculateSunTimes: { location, date in
                SunCalculator.calculate(for: location, on: date)
            },
            timerScheduler: FoundationSlotSchedulerTimerScheduler(),
            wakeObserver: WorkspaceSlotSchedulerWakeObserver(),
            wallpaperService: WallpaperService.shared,
            displayProvider: DisplayManager.shared,
            aerialCatalog: LiveSlotSchedulerAerialCatalogResolver(),
            hasCapturePermission: { WallpaperTransition.hasCapturePermission }
        )
    }
}

enum WallpaperPlaybackMode: Equatable {
    case following
    case paused
    case temporary(until: Date?)
}

enum WallpaperOverrideDuration: String, CaseIterable, Identifiable {
    case nextChange
    case oneHour
    case tomorrow

    var id: String { rawValue }
}

/// Expected schedule and confirmed wallpaper are deliberately separate: a slot
/// becoming current does not mean its wallpaper has successfully been installed.
@MainActor
class SlotScheduler: ObservableObject {
    private enum Timing {
        static let locationRetryInterval: TimeInterval = 300
        static let transitionApplyBuffer: TimeInterval = 5
        static let prefetchLeadTime: TimeInterval = 300
        static let verificationInterval: TimeInterval = 1800
        static let wakeRepairDelay: TimeInterval = 10
        static let noSlotsRetryInterval: TimeInterval = 6 * 3600
    }

    @Published private(set) var currentSlot: TimeSlot?
    @Published private(set) var nextTransition: (slot: TimeSlot, date: Date)?
    @Published private(set) var todaySchedule: [(slot: TimeSlot, time: Date)] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isDownloading = false
    @Published private(set) var confirmedSource: WallpaperSource?
    @Published private(set) var confirmedSourcesByDisplay: [String: WallpaperSource] = [:]
    @Published private(set) var isApplying = false
    @Published private(set) var smoothingUnavailableBecauseOfPermission = false
    @Published private(set) var playbackMode: WallpaperPlaybackMode

    private struct ApplicationTarget: Equatable {
        let source: WallpaperSource
        let displayUUID: String?
    }

    private struct ApplicationJob {
        let target: ApplicationTarget
        let label: String
    }

    private var config: WallpaperConfig
    private let locationProvider: () -> CLLocationCoordinate2D?
    private let dependencies: SlotSchedulerDependencies
    private var timer: SlotSchedulerTimerToken?
    private var prefetchTimer: SlotSchedulerTimerToken?
    private var verifyTimer: SlotSchedulerTimerToken?
    private var overrideTimer: SlotSchedulerTimerToken?
    private var wakeObserverToken: NSObjectProtocol?
    private var applicationTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var applicationGeneration = 0
    private var lifecycleGeneration = 0
    private var scheduleGeneration = 0
    private var overrideGeneration = 0
    private var activeDownloads = 0
    private var activeApplications = 0
    private var isRunning = false
    private var lastAppliedTargets: [ApplicationTarget]?
    private var lastScheduledAttemptTargets: [ApplicationTarget]?
    private var applyingScheduledTargets: [ApplicationTarget]?
    private var failedManualJobs: [ApplicationJob]?
    @Published private var overrideDuration: WallpaperOverrideDuration = .nextChange

    var currentOverrideDuration: WallpaperOverrideDuration { overrideDuration }

    init(
        config: WallpaperConfig,
        locationProvider: @escaping () -> CLLocationCoordinate2D?,
        dependencies: SlotSchedulerDependencies? = nil
    ) {
        self.config = config
        self.locationProvider = locationProvider
        self.dependencies = dependencies ?? .live
        self.playbackMode = config.isFollowingSchedule ? .following : .paused
    }

    // MARK: - Public API

    func start() {
        stop()
        isRunning = true
        updateNow()
        scheduleNextUpdate()
        scheduleOverrideExpiry()
        startVerifyTimer()
        observeWake()
    }

    func stop() {
        isRunning = false
        lifecycleGeneration += 1
        scheduleGeneration += 1
        cancelApplication()
        lastAppliedTargets = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        timer?.invalidate()
        timer = nil
        prefetchTimer?.invalidate()
        prefetchTimer = nil
        verifyTimer?.invalidate()
        verifyTimer = nil
        invalidateOverrideTimer()
        if let observer = wakeObserverToken {
            dependencies.wakeObserver.removeObserver(observer)
            wakeObserverToken = nil
        }
    }

    func updateConfig(_ newConfig: WallpaperConfig) {
        let executionChanged = config.isFollowingSchedule != newConfig.isFollowingSchedule
        let smoothingChanged = config.smoothWallpaperChanges != newConfig.smoothWallpaperChanges
        config = newConfig
        if executionChanged {
            cancelApplication()
            prefetchTask?.cancel()
            lastAppliedTargets = nil
            failedManualJobs = nil
            playbackMode = config.isFollowingSchedule ? .following : .paused
            invalidateOverrideTimer()
        }
        // A temporary selection keeps its original deadline across edits. In
        // particular, renaming a slot/location must not extend the override.
        // Smoothing is not part of wallpaper identity, so successful/in-flight
        // work stays put.
        updateNow(retryFailures: executionChanged || smoothingChanged)
        scheduleNextUpdate()
    }

    func forceUpdate() {
        lastAppliedTargets = nil
        updateNow()
        scheduleNextUpdate()
    }

    /// A manual choice while paused remains paused. Otherwise it temporarily
    /// takes precedence over transitions, periodic repair, and wake repair.
    @discardableResult
    func applyWallpaper(
        source: WallpaperSource,
        displayUUID: String? = nil,
        duration: WallpaperOverrideDuration = .nextChange
    ) -> Task<Void, Never>? {
        guard source != .none else { cancelApplication(); return nil }
        overrideDuration = duration
        lastAppliedTargets = nil
        prefetchTask?.cancel()
        if playbackMode != .paused {
            playbackMode = .temporary(until: overrideDeadline(for: duration))
            scheduleOverrideExpiry()
        }
        beginApplication(jobs: [ApplicationJob(
            target: ApplicationTarget(source: source, displayUUID: displayUUID), label: "Wallpaper"
        )], scheduled: false)
        scheduleNextUpdate()
        return applicationTask
    }

    func resumeSchedule() {
        config.isFollowingSchedule = true
        playbackMode = .following
        invalidateOverrideTimer()
        cancelApplication()
        lastAppliedTargets = nil
        failedManualJobs = nil
        updateNow()
        scheduleNextUpdate()
    }

    /// Retry the failed manual intent without silently extending its expiry.
    func retryLastApplication() {
        guard applicationTask == nil else { return }
        expireOverrideIfNeeded(at: dependencies.now())
        if let jobs = failedManualJobs, playbackMode != .following {
            beginApplication(jobs: jobs, scheduled: false)
        } else {
            forceUpdate()
        }
    }

    func setOverrideDuration(_ duration: WallpaperOverrideDuration) {
        overrideDuration = duration
        guard case .temporary = playbackMode else { return }
        playbackMode = .temporary(until: overrideDeadline(for: duration))
        scheduleOverrideExpiry()
    }

    /// The service does not return until any required rollback has finished.
    func waitForPendingApplication() async {
        await applicationTask?.value
    }

    // MARK: - Applying and confirmation

    private func cancelApplication() {
        applicationGeneration += 1
        applicationTask?.cancel()
        applicationTask = nil
        applyingScheduledTargets = nil
    }

    private func beginApplication(jobs: [ApplicationJob], scheduled: Bool) {
        guard !jobs.isEmpty else { return }
        cancelApplication()
        let generation = applicationGeneration
        // Snapshot before any suspension, including a missing-aerial download.
        // One application uses one policy even if settings change mid-flight.
        let smoothChanges = config.smoothWallpaperChanges
        let targets = jobs.map(\.target)
        // An aerial all-display change is one service transaction. Custom
        // images use independent screen setters, so split a global request to
        // confirm each screen immediately instead of losing partial success.
        let displayJobs = jobs.flatMap { job -> [ApplicationJob] in
            guard case .custom = job.target.source, job.target.displayUUID == nil else { return [job] }
            let displays = dependencies.displayProvider.getDisplays()
            guard !displays.isEmpty else { return [job] }
            return displays.map { display in
                ApplicationJob(target: ApplicationTarget(source: job.target.source, displayUUID: display.uuid), label: display.displayName)
            }
        }
        failedManualJobs = nil
        applyingScheduledTargets = scheduled ? targets : nil
        if scheduled { lastScheduledAttemptTargets = targets }
        activeApplications += 1
        isApplying = true
        applicationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var errors: [String] = []
            defer {
                activeApplications -= 1
                isApplying = activeApplications > 0
                if generation == applicationGeneration {
                    applicationTask = nil
                    applyingScheduledTargets = nil
                }
            }
            for job in displayJobs {
                do {
                    try Task.checkCancellation()
                    try await applySource(job.target.source, displayUUID: job.target.displayUUID, smoothChanges: smoothChanges)
                    try Task.checkCancellation()
                    guard generation == applicationGeneration else { return }
                    recordConfirmation(job.target)
                } catch is CancellationError {
                    return
                } catch {
                    // Superseded work can finish mandatory recovery, but cannot
                    // publish stale confirmation/errors or start another job.
                    guard generation == applicationGeneration, !Task.isCancelled else { return }
                    errors.append("\(job.label): \(error.localizedDescription)")
                }
            }
            guard generation == applicationGeneration else { return }
            lastError = errors.isEmpty ? nil : errors.joined(separator: "; ")
            // Keep partial failures eligible for repair while retaining each
            // display's actual successful confirmation.
            if scheduled, errors.isEmpty { lastAppliedTargets = targets }
            if !scheduled, !errors.isEmpty { failedManualJobs = jobs }
        }
    }

    private func recordConfirmation(_ target: ApplicationTarget) {
        let displays = dependencies.displayProvider.getDisplays()
        if let displayUUID = target.displayUUID {
            confirmedSourcesByDisplay[displayUUID] = target.source
            // A single global source is meaningful only when every connected
            // display has actually been confirmed with the same source.
            let sources = displays.compactMap { confirmedSourcesByDisplay[$0.uuid] }
            confirmedSource = !displays.isEmpty && sources.count == displays.count && sources.allSatisfy { $0 == target.source }
                ? target.source : nil
        } else {
            confirmedSource = target.source
            for display in displays { confirmedSourcesByDisplay[display.uuid] = target.source }
        }
    }

    private func applySource(_ source: WallpaperSource, displayUUID: String?, smoothChanges: Bool) async throws {
        switch source {
        case .builtIn(let assetID):
            if !dependencies.wallpaperService.isAerialDownloaded(assetID: assetID) {
                guard let url = dependencies.aerialCatalog.downloadURL(for: assetID) else {
                    throw WallpaperError.aerialNotDownloaded(assetID: assetID)
                }
                try await download(assetID: assetID, from: url)
            }
            try Task.checkCancellation()
            let hasCapturePermission = dependencies.hasCapturePermission()
            let useSmoothing = smoothChanges && hasCapturePermission
            if hasCapturePermission || smoothChanges {
                smoothingUnavailableBecauseOfPermission = !hasCapturePermission
            }
            try await dependencies.wallpaperService.setWallpaper(
                assetID: assetID, displayUUID: displayUUID, smoothChanges: useSmoothing)
        case .custom(let path):
            try Task.checkCancellation()
            try dependencies.wallpaperService.setCustomWallpaper(path: path, displayUUID: displayUUID)
        case .none:
            break
        }
    }

    private func download(assetID: String, from url: URL) async throws {
        activeDownloads += 1
        isDownloading = true
        defer {
            activeDownloads -= 1
            isDownloading = activeDownloads > 0
        }
        try await dependencies.wallpaperService.downloadAerial(assetID: assetID, from: url)
    }

    // MARK: - Schedule resolution

    /// Fixed triggers need no solar estimate or invented location. Unresolved
    /// solar triggers are omitted until location becomes available.
    private func resolvedSchedule(slots: [TimeSlot], on date: Date) -> [(slot: TimeSlot, time: Date)] {
        let enabled = slots.filter { $0.isEnabled && $0.source != .none }
        let hasSolar = enabled.contains { if case .solar = $0.trigger { return true }; return false }
        let sunTimes = hasSolar ? locationProvider().map { dependencies.calculateSunTimes($0, date) } : nil
        return enabled.compactMap { slot in
            let time: Date?
            switch slot.trigger {
            case .fixed(let hour, let minute):
                time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
            case .solar:
                time = sunTimes.map { slot.resolvedTime(sunTimes: $0, on: date) }
            }
            return time.map { (slot: slot, time: $0) }
        }.sorted { $0.time < $1.time }
    }

    private func activeSlot(in slots: [TimeSlot], at date: Date) -> TimeSlot? {
        let today = resolvedSchedule(slots: slots, on: date)
        if let current = today.last(where: { $0.time <= date }) { return current.slot }
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return nil }
        return resolvedSchedule(slots: slots, on: yesterday).last?.slot
    }

    private func upcomingTransition(in slots: [TimeSlot], after date: Date) -> (slot: TimeSlot, date: Date)? {
        if let next = resolvedSchedule(slots: slots, on: date).first(where: { $0.time > date }) {
            return (next.slot, next.time)
        }
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date),
              let first = resolvedSchedule(slots: slots, on: tomorrow).first else { return nil }
        return (first.slot, first.time)
    }

    private var scheduleGroups: [[TimeSlot]] {
        if config.displayMode == .allDisplays { return [config.slots] }
        let displays = dependencies.displayProvider.getDisplays()
        if displays.isEmpty { return config.perDisplayConfigs.map(\.slots) }
        return displays.map { config.slots(for: $0.uuid) }
    }

    private func earliestTransition(after date: Date) -> (slot: TimeSlot, date: Date)? {
        scheduleGroups.compactMap { upcomingTransition(in: $0, after: date) }.min { $0.date < $1.date }
    }

    private func scheduledJobs(at date: Date) -> [ApplicationJob] {
        if config.displayMode == .allDisplays {
            guard let slot = activeSlot(in: config.slots, at: date), slot.source != .none else { return [] }
            return [ApplicationJob(target: ApplicationTarget(source: slot.source, displayUUID: nil), label: "Wallpaper")]
        }
        return dependencies.displayProvider.getDisplays().compactMap { display in
            guard let slot = activeSlot(in: config.slots(for: display.uuid), at: date),
                  slot.source != .none else { return nil }
            return ApplicationJob(target: ApplicationTarget(source: slot.source, displayUUID: display.uuid), label: display.displayName)
        }
    }

    private func updateNow(retryFailures: Bool = true) {
        let now = dependencies.now()
        let visibleSlots = scheduleGroups.first ?? []
        todaySchedule = resolvedSchedule(slots: visibleSlots, on: now)
        currentSlot = activeSlot(in: visibleSlots, at: now)
        nextTransition = earliestTransition(after: now)
        if case .temporary(until: nil) = playbackMode, overrideDuration == .nextChange,
           let nextTransition {
            playbackMode = .temporary(until: nextTransition.date)
            scheduleOverrideExpiry()
        }
        expireOverrideIfNeeded(at: now)
        guard isRunning, playbackMode == .following else { return }

        let jobs = scheduledJobs(at: now)
        let targets = jobs.map(\.target)
        guard !targets.isEmpty else {
            if applyingScheduledTargets != nil { cancelApplication() }
            lastAppliedTargets = nil
            lastScheduledAttemptTargets = nil
            return
        }
        // Names, IDs, inactive slots, and location labels are not application
        // identity. Reconcile only when the effective source/target changes.
        if let applyingScheduledTargets, applyingScheduledTargets != targets {
            cancelApplication()
        }
        guard targets != lastAppliedTargets, targets != applyingScheduledTargets else { return }
        guard retryFailures || targets != lastScheduledAttemptTargets else { return }
        beginApplication(jobs: jobs, scheduled: true)
    }

    // MARK: - Temporary overrides

    private func overrideDeadline(for duration: WallpaperOverrideDuration) -> Date? {
        let now = dependencies.now()
        switch duration {
        case .nextChange: return earliestTransition(after: now)?.date
        case .oneHour: return now.addingTimeInterval(3600)
        case .tomorrow:
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        }
    }

    private func expireOverrideIfNeeded(at date: Date) {
        guard case .temporary(let until) = playbackMode, let until, until <= date else { return }
        playbackMode = config.isFollowingSchedule ? .following : .paused
        invalidateOverrideTimer()
        cancelApplication()
        lastAppliedTargets = nil
        lastScheduledAttemptTargets = nil
        failedManualJobs = nil
    }

    private func invalidateOverrideTimer() {
        overrideGeneration += 1
        overrideTimer?.invalidate()
        overrideTimer = nil
    }

    private func scheduleOverrideExpiry() {
        invalidateOverrideTimer()
        guard case .temporary(let until) = playbackMode, let until else { return }
        let generation = overrideGeneration
        overrideTimer = dependencies.timerScheduler.scheduledTimer(
            withTimeInterval: max(0.01, until.timeIntervalSince(dependencies.now())), repeats: false
        ) { [weak self] in
            guard let self, generation == overrideGeneration else { return }
            updateNow()
            scheduleNextUpdate()
            // A wall-clock adjustment may cause the timer to fire before expiry.
            scheduleOverrideExpiry()
        }
    }

    // MARK: - Timers and repair

    private func scheduleNextUpdate() {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        timer?.invalidate()
        timer = nil
        prefetchTimer?.invalidate()
        prefetchTimer = nil
        guard isRunning else { return }
        let now = dependencies.now()
        let next = earliestTransition(after: now)
        let needsLocation = locationProvider() == nil && scheduleGroups.joined().contains {
            guard $0.isEnabled, $0.source != .none else { return false }
            if case .solar = $0.trigger { return true }
            return false
        }
        let transitionDelay = next.map { $0.date.timeIntervalSince(now) + Timing.transitionApplyBuffer }
        let retry = needsLocation ? Timing.locationRetryInterval : Timing.noSlotsRetryInterval
        let delay = needsLocation ? min(transitionDelay ?? retry, retry) : transitionDelay ?? retry
        timer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: max(1, delay), repeats: false) { [weak self] in
            guard let self, isRunning, generation == scheduleGeneration else { return }
            updateNow()
            scheduleNextUpdate()
        }
        guard playbackMode == .following, let next else { return }
        let prefetchDelay = next.date.timeIntervalSince(now) - Timing.prefetchLeadTime
        if prefetchDelay > 0 {
            prefetchTimer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: prefetchDelay, repeats: false) { [weak self] in
                guard let self, isRunning, generation == scheduleGeneration else { return }
                prefetchUpcoming()
            }
        } else {
            prefetchUpcoming()
        }
    }

    private func startVerifyTimer() {
        let generation = lifecycleGeneration
        verifyTimer = dependencies.timerScheduler.scheduledTimer(withTimeInterval: Timing.verificationInterval, repeats: true) { [weak self] in
            guard let self, isRunning, generation == lifecycleGeneration else { return }
            verifyCurrentWallpaper()
        }
    }

    private func observeWake() {
        let generation = lifecycleGeneration
        wakeObserverToken = dependencies.wakeObserver.observeWake(after: Timing.wakeRepairDelay) { [weak self] in
            // Removing an observer cannot retract an already queued delayed wake.
            guard let self, isRunning, generation == lifecycleGeneration else { return }
            verifyCurrentWallpaper()
            scheduleNextUpdate()
        }
    }

    private func verifyCurrentWallpaper() {
        guard isRunning else { return }
        updateNow() // Also handles overrides that expired while the Mac slept.
        guard playbackMode == .following, applicationTask == nil,
              config.displayMode == .allDisplays,
              let job = scheduledJobs(at: dependencies.now()).first,
              case .builtIn(let expectedAssetID) = job.target.source else { return }
        let currentAssetID = try? dependencies.wallpaperService.getCurrentAssetID()
        guard currentAssetID != expectedAssetID else { return }
        lastAppliedTargets = nil
        updateNow()
    }

    private func prefetchUpcoming() {
        guard isRunning, playbackMode == .following else { return }
        let now = dependencies.now()
        let assetIDs = Set(scheduleGroups.compactMap { upcomingTransition(in: $0, after: now)?.slot.source.assetID })
        let missing = assetIDs.filter { !dependencies.wallpaperService.isAerialDownloaded(assetID: $0) }
        guard !missing.isEmpty else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for assetID in missing {
                guard !Task.isCancelled, playbackMode == .following else { return }
                guard let url = dependencies.aerialCatalog.downloadURL(for: assetID) else { continue }
                do {
                    try await download(assetID: assetID, from: url)
                } catch {
                    #if DEBUG
                    print("[Scheduler] Prefetch failed for \(assetID): \(error)")
                    #endif
                }
            }
        }
    }
}
