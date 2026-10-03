import AppKit
import Combine
import CoreLocation

/// One owner for persisted preferences and runtime state. Constructing the
/// controller is inert; only the app delegate starts wallpaper scheduling.
@MainActor
final class SunpaperController: ObservableObject {
    static let shared = SunpaperController()

    @Published private(set) var config: WallpaperConfig
    @Published private(set) var displays: [DisplayManager.Display]
    @Published var selectedDisplayUUID: String?
    @Published var message: String?
    @Published var isChoosingWallpaper = false
    @Published private(set) var redownloadingAssets: Set<String> = []
    let scheduler: SlotScheduler
    let undoManager = UndoManager()
    private let defaults: UserDefaults?
    private let hasNewerStoredSchema: Bool
    private let now: () -> Date
    private var observation: AnyCancellable?
    private var displayObservation: NSObjectProtocol?
    private var displayChangeTask: Task<Void, Never>?
    private let recovery: WallpaperRecovering
    private var started = false
    private final class LocationBox { var coordinate: CLLocationCoordinate2D? }
    private let location: LocationBox

    init(config initialConfig: WallpaperConfig? = nil,
         defaults: UserDefaults? = .standard,
         dependencies: SlotSchedulerDependencies? = nil,
         displays: [DisplayManager.Display]? = nil,
         recovery: WallpaperRecovering? = nil,
         now: @escaping () -> Date = Date.init) {
        let storedData = defaults?.data(forKey: WallpaperConfig.userDefaultsKey)
        let decodedConfig = storedData.flatMap { WallpaperConfig.decodeCompatible(from: $0) }
        let hasNewerStoredSchema = storedData.flatMap { WallpaperConfig.storedSchemaVersion(from: $0) }
            .map { $0 > WallpaperConfig.currentSchemaVersion } ?? false
        if let storedData, decodedConfig == nil,
           defaults?.object(forKey: WallpaperConfig.unreadableBackupKey) == nil {
            defaults?.set(storedData, forKey: WallpaperConfig.unreadableBackupKey)
        }
        let config = initialConfig ?? decodedConfig ?? .default
        self.config = config
        self.defaults = defaults
        self.hasNewerStoredSchema = hasNewerStoredSchema
        self.recovery = recovery ?? WallpaperTransition.shared
        self.now = now
        self.displays = displays ?? DisplayManager.shared.getDisplays()
        let location = LocationBox()
        location.coordinate = Self.validCoordinate(latitude: config.latitude, longitude: config.longitude)
        self.location = location
        scheduler = SlotScheduler(config: config, locationProvider: { location.coordinate }, dependencies: dependencies)
        observation = scheduler.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if hasNewerStoredSchema {
            message = "A newer version of Sunpaper saved these settings. Changes made here won’t be saved by this version."
        } else if storedData != nil && decodedConfig == nil {
            message = "Your settings couldn’t be read. Defaults are in use, and the old data was kept."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        scheduler.start()
        displayObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.displays = DisplayManager.shared.getDisplays()
                // Wake and reconnection post several changes while macOS settles
                // the layout. A covered change started mid-way can't be verified.
                self.displayChangeTask?.cancel()
                self.displayChangeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: Self.displaySettleDelay)
                    guard !Task.isCancelled else { return }
                    await self?.displayLayoutDidSettle()
                }
            }
        }
    }

    static let displaySettleDelay: Duration = .seconds(2)

    /// Covers retained for a layout that no longer exists can only be removed
    /// by restoring, so try that once before reconciling the schedule.
    func displayLayoutDidSettle() async {
        guard started else { return }
        if recovery.needsRecovery { await recovery.retryRecovery() }
        guard started else { return }
        scheduler.forceUpdate()
    }

    /// A retained cover blocks every change until restoration succeeds, so
    /// Retry restores the desktop first instead of failing on the same guard.
    func retryWallpaperChange() async {
        if recovery.needsRecovery {
            await recovery.retryRecovery()
            guard !recovery.needsRecovery else { return }
        }
        scheduler.retryLastApplication()
    }

    func stop() {
        started = false
        displayChangeTask?.cancel()
        displayChangeTask = nil
        scheduler.stop()
        if let displayObservation { NotificationCenter.default.removeObserver(displayObservation) }
        displayObservation = nil
    }

    var scope: String? {
        guard config.displayMode == .perDisplay else { return nil }
        return selectedDisplayUUID ?? displays.first?.uuid ?? config.perDisplayConfigs.first?.displayUUID
    }

    var scopeName: String {
        guard let scope else { return "All displays" }
        return displays.first(where: { $0.uuid == scope })?.name ?? "Disconnected display"
    }

    var slots: [TimeSlot] {
        guard let scope else { return config.displayMode == .allDisplays ? config.slots : [] }
        return config.slots(for: scope)
    }

    var shownSource: WallpaperSource? {
        if let scope { return scheduler.confirmedSourcesByDisplay[scope] }
        return scheduler.confirmedSource
    }

    var needsLocation: Bool {
        location.coordinate == nil && slots.contains { slot in
            if case .solar = slot.trigger { return true }; return false
        }
    }

    var collectionName: String {
        for set in BuiltInWallpapers.allSets {
            if slots.count == 4 && zip(slots, BuiltInWallpapers.Phase.allCases).allSatisfy({
                $0.0.source == .builtIn(assetID: set.assetID(for: $0.1))
            }) { return set.name }
        }
        return "Custom"
    }

    /// The schedule's clock, so views agree with injected time.
    var currentDate: Date { now() }

    var polarCondition: SunCalculator.PolarCondition? {
        guard let coordinate = location.coordinate else { return nil }
        return SunCalculator.calculate(for: coordinate, on: currentDate).polarCondition
    }

    func resolvedTime(for trigger: Trigger, on date: Date? = nil) -> Date? {
        let date = date ?? now()
        switch trigger {
        case .fixed(let hour, let minute):
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        case .solar:
            guard let coordinate = location.coordinate else { return nil }
            return trigger.resolveTime(sunTimes: SunCalculator.calculate(for: coordinate, on: date), on: date)
        }
    }

    var expectedSlot: TimeSlot? {
        let today = now()
        let candidates = (-2...2).flatMap { offset -> [(TimeSlot, Date)] in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return [] }
            return slots.filter { $0.isEnabled && $0.source != .none }.compactMap { slot in
                resolvedTime(for: slot.trigger, on: date).map { (slot, $0) }
            }
        }
        return candidates.filter { $0.1 <= today }.max(by: { $0.1 < $1.1 })?.0
    }

    var nextChange: (slot: TimeSlot, date: Date)? {
        let today = now()
        let candidates = (-2...2).flatMap { offset -> [(TimeSlot, Date)] in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return [] }
            return slots.filter { $0.isEnabled && $0.source != .none }.compactMap { slot in
                resolvedTime(for: slot.trigger, on: date).map { (slot, $0) }
            }
        }
        return candidates.filter { $0.1 > today }.min(by: { $0.1 < $1.1 }).map { (slot: $0.0, date: $0.1) }
    }

    var stateTitle: String {
        if scheduler.isDownloading { return "Downloading wallpaper…" }
        if scheduler.isApplying { return "Changing wallpaper…" }
        if scheduler.lastError != nil { return "Wallpaper needs attention" }
        switch scheduler.playbackMode {
        case .paused: return "Schedule paused"
        case .temporary: return "Temporary wallpaper"
        case .following:
            if !slots.contains(where: { $0.isEnabled && $0.source != .none }) { return "No active changes" }
            if shownSource == nil && needsLocation { return "Choose a location to begin" }
            return "Following schedule"
        }
    }

    var stateDetail: String {
        switch scheduler.playbackMode {
        case .paused: return "Keeping this wallpaper until you resume."
        case .temporary(let until):
            if let until { return "Schedule resumes \(Self.relativeTime(until, now: now()))." }
            return "Keeping this wallpaper until you resume."
        case .following:
            if let next = nextChange { return "Next: \(next.slot.name) \(Self.relativeTime(next.date, now: now()))" }
            return needsLocation ? "Solar times need a location. Fixed times work without one." : "Add or enable a change in Your day."
        }
    }

    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDate(date, inSameDayAs: now) ? "at \(time)" : "tomorrow at \(time)"
    }

    func setFollowing(_ value: Bool) {
        var copy = config
        copy.isFollowingSchedule = value
        replaceConfig(copy)
        if value && started && scheduler.playbackMode != .following { scheduler.resumeSchedule() }
    }

    func setSmoothWallpaperChanges(_ value: Bool) {
        var copy = config
        copy.smoothWallpaperChanges = value
        replaceConfig(copy)
    }

    func apply(_ source: WallpaperSource, duration: WallpaperOverrideDuration = .nextChange) {
        apply(source, displayUUID: scope, duration: duration)
    }

    func apply(_ source: WallpaperSource, displayUUID: String?, duration: WallpaperOverrideDuration = .nextChange) {
        guard started else { return }
        scheduler.applyWallpaper(source: source, displayUUID: displayUUID, duration: duration)
    }

    func downloadAgain(assetID: String) {
        guard started, !redownloadingAssets.contains(assetID),
              let url = AerialCatalog.shared.asset(for: assetID)?.downloadURL else { return }
        redownloadingAssets.insert(assetID)
        Task { [weak self] in
            guard let self else { return }
            defer { redownloadingAssets.remove(assetID) }
            do {
                try await WallpaperService.shared.redownloadAerial(assetID: assetID, from: url)
                message = "\(wallpaperName(.builtIn(assetID: assetID))) is downloaded again. Use Retry if the wallpaper still needs to change."
            } catch { message = "Couldn’t download the wallpaper: \(error.localizedDescription)" }
        }
    }

    func change(_ action: String, _ edit: (inout WallpaperConfig) -> Void) {
        var copy = config
        edit(&copy)
        replaceConfig(copy, undoAction: action)
    }

    private func replaceConfig(_ newConfig: WallpaperConfig, undoAction: String? = nil) {
        guard newConfig != config else { return }
        if let undoAction {
            let previous = config
            undoManager.registerUndo(withTarget: self) { target in
                var restored = previous
                // Pause/resume is not an edit to the schedule. Undoing an older
                // edit must never silently start a deliberately paused day.
                if previous.isFollowingSchedule == newConfig.isFollowingSchedule {
                    restored.isFollowingSchedule = target.config.isFollowingSchedule
                }
                if previous.smoothWallpaperChanges == newConfig.smoothWallpaperChanges {
                    restored.smoothWallpaperChanges = target.config.smoothWallpaperChanges
                }
                target.replaceConfig(restored, undoAction: undoAction)
            }
            undoManager.setActionName(undoAction)
        }
        config = newConfig
        location.coordinate = Self.validCoordinate(latitude: config.latitude, longitude: config.longitude)
        if hasNewerStoredSchema {
            message = "A newer version of Sunpaper saved these settings. Changes made here won’t be saved by this version."
        } else if let defaults {
            do {
                let envelope = config.persistenceEnvelope(
                    createdByAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    updatedAt: now())
                defaults.set(try JSONEncoder().encode(envelope), forKey: WallpaperConfig.userDefaultsKey)
            } catch { message = "Your changes couldn’t be saved: \(error.localizedDescription)" }
        }
        // An inactive scheduler resolves state but never applies wallpaper.
        scheduler.updateConfig(config)
    }

    func editSlots(_ action: String, _ edit: (inout [TimeSlot]) -> Void) {
        let target = scope
        guard config.displayMode == .allDisplays || target != nil else { return }
        editSlots(action, displayUUID: target, edit)
    }

    /// An editor captures this scope when presented. Changing the selected
    /// display in another window must not retarget an already-open edit.
    func editSlots(_ action: String, displayUUID target: String?, _ edit: (inout [TimeSlot]) -> Void) {
        change(action) { config in
            var slots = target.map { id in config.perDisplayConfigs.first(where: { $0.displayUUID == id })?.slots ?? [] } ?? config.slots
            edit(&slots)
            if let target { config.setSlots(slots, for: target) } else { config.slots = slots }
        }
    }

    func updateSlot(_ slot: TimeSlot) {
        updateSlot(slot, displayUUID: scope)
    }

    func updateSlot(_ slot: TimeSlot, displayUUID: String?) {
        editSlots("Edit change", displayUUID: displayUUID) { slots in
            if let index = slots.firstIndex(where: { $0.id == slot.id }) { slots[index] = slot }
        }
    }

    func useCollection(_ set: BuiltInWallpapers.WallpaperSet) {
        editSlots("Use \(set.name) collection") { $0 = BuiltInWallpapers.Phase.allCases.map { set.slot(for: $0) } }
    }

    func setDisplayMode(_ mode: DisplayMode) {
        change("Change display mode") { config in
            if mode == .perDisplay {
                for display in displays where !config.perDisplayConfigs.contains(where: { $0.displayUUID == display.uuid }) {
                    config.setSlots(config.slots, for: display.uuid)
                }
            }
            config.displayMode = mode
        }
    }

    func setLocation(name: String, latitude: Double, longitude: Double) {
        guard Self.validCoordinate(latitude: latitude, longitude: longitude) != nil else {
            message = "Choose a valid location to use solar times."
            return
        }
        change("Change location") { config in
            config.locationName = name
            config.latitude = latitude
            config.longitude = longitude
        }
    }

    private static func validCoordinate(latitude: Double?, longitude: Double?) -> CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}
