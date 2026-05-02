import SwiftUI
import CoreLocation
import Combine

@main
struct SunpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var locationManager: CLLocationManager?
    private var scheduler: SlotScheduler?

    private var currentLocation: CLLocationCoordinate2D?
    private var config: WallpaperConfig = .default
    private var cancellables = Set<AnyCancellable>()

    // Exposed for MenuBarView
    var currentSlot: TimeSlot? {
        scheduler?.currentSlot
    }

    var nextTransition: (slot: TimeSlot, date: Date)? {
        scheduler?.nextTransition
    }

    var todaySchedule: [(slot: TimeSlot, time: Date)] {
        scheduler?.todaySchedule ?? []
    }

    var isDownloading: Bool {
        scheduler?.isDownloading ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard continueLaunchingAfterSingletonCheck() else { return }

        loadConfig()
        setupStatusItem()
        setupLocationManager()
        startScheduler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopScheduler()
    }

    // MARK: - Setup

    private func continueLaunchingAfterSingletonCheck() -> Bool {
        // Skip singleton check during unit tests
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard !isRunningTests else { return true }

        // Ensure single instance (skip during tests)
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        guard runningApps.count <= 1 else {
            quit()
            return false
        }

        return true
    }

    private func loadConfig() {
        let data = UserDefaults.standard.data(forKey: WallpaperConfig.userDefaultsKey)
        config = WallpaperConfig.decodeCompatibleOrDefault(from: data)

        // Use stored location if available
        if let lat = config.latitude, let lon = config.longitude {
            currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            setStatusIcon(isDownloading: false)
        }

        setupPopover()
    }

    private func setupPopover() {
        let menuPopover = NSPopover()
        menuPopover.contentSize = NSSize(width: SunpaperSize.popoverWidth, height: SunpaperSize.popoverHeight)
        menuPopover.behavior = .transient
        popover = menuPopover
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        guard let popover else { return }

        let view = MenuBarView(
            currentSlot: currentSlot,
            nextTransition: nextTransition,
            todaySchedule: todaySchedule,
            lastError: scheduler?.lastError,
            isDownloading: isDownloading,
            onApplySlot: { [weak self] slot in
                Task { @MainActor [weak self] in
                    self?.applySlot(slot)
                    self?.closePopover()
                }
            },
            onOpenSettings: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openSettings()
                }
            },
            onQuit: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.quit()
                }
            }
        )
        popover.contentViewController = NSHostingController(
            rootView: view
                .frame(width: SunpaperSize.popoverWidth)
        )
    }

    private func applySlot(_ slot: TimeSlot) {
        scheduler?.applyWallpaper(source: slot.source)
    }

    private func setupLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager

        // Only request location if we don't have stored coordinates
        if currentLocation == nil {
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        }
    }

    private func startScheduler() {
        cancellables.removeAll()

        let newScheduler = SlotScheduler(
            config: config,
            locationProvider: { [weak self] in
                MainActor.assumeIsolated {
                    self?.currentLocation
                }
            }
        )
        scheduler = newScheduler
        newScheduler.start()

        observeSchedulerState(newScheduler)
    }

    private func stopScheduler() {
        scheduler?.stop()
        cancellables.removeAll()
    }

    private func observeSchedulerState(_ scheduler: SlotScheduler) {
        scheduler.$isDownloading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloading in
                Task { @MainActor [weak self] in
                    self?.setStatusIcon(isDownloading: downloading)
                    self?.updatePopoverContentIfVisible()
                }
            }
            .store(in: &cancellables)

        scheduler.$currentSlot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePopoverContentIfVisible()
                }
            }
            .store(in: &cancellables)

        scheduler.$nextTransition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePopoverContentIfVisible()
                }
            }
            .store(in: &cancellables)

        scheduler.$todaySchedule
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePopoverContentIfVisible()
                }
            }
            .store(in: &cancellables)

        scheduler.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePopoverContentIfVisible()
                }
            }
            .store(in: &cancellables)
    }

    private func setStatusIcon(isDownloading: Bool) {
        guard let button = statusItem?.button else { return }
        let icon = isDownloading ? "icloud.and.arrow.down.fill" : "sun.horizon.fill"
        let description = isDownloading ? "Sunpaper is downloading a wallpaper" : "Sunpaper"
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: description)
    }

    private func updatePopoverContentIfVisible() {
        guard popover?.isShown == true else { return }
        updatePopoverContent()
    }

    // MARK: - Actions

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    func openSettings() {
        closePopover()
        showSettingsWindow()
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }

        // Refresh the view with current state
        updatePopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Make popover window key to receive input
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    private func showSettingsWindow() {
        // Reuse existing window if visible
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        // Create settings window
        let settingsView = SettingsView()
            .frame(
                minWidth: SunpaperSize.settingsMinWidth,
                idealWidth: SunpaperSize.settingsIdealWidth,
                minHeight: SunpaperSize.settingsMinHeight,
                idealHeight: SunpaperSize.settingsIdealHeight
            )
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Sunpaper Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: SunpaperSize.settingsMinWidth, height: SunpaperSize.settingsMinHeight)
        window.setContentSize(NSSize(width: SunpaperSize.settingsIdealWidth, height: SunpaperSize.settingsIdealHeight))
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        // Keep reference and show
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        activateApp()
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    func forceUpdate() {
        scheduler?.forceUpdate()
    }

    // MARK: - Config Updates

    func updateConfig(_ newConfig: WallpaperConfig) {
        config = newConfig

        // Update location if changed
        if let lat = newConfig.latitude, let lon = newConfig.longitude {
            currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        scheduler?.updateConfig(newConfig)
    }

    // MARK: - Location Updates

    private func handleLocationUpdate(latitude: Double?, longitude: Double?) {
        // Only use auto-detected location if no stored location
        guard config.latitude == nil || config.longitude == nil,
              let latitude,
              let longitude else { return }

        currentLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func handleLocationFailure(_ errorDescription: String) {
        #if DEBUG
        print("[Location] Error: \(errorDescription)")
        #endif

        useFallbackLocationIfNeeded()
    }

    private func useFallbackLocationIfNeeded() {
        // Fall back to Chicago if no stored location
        if currentLocation == nil {
            currentLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        }
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways:
            if config.latitude == nil {
                locationManager?.startUpdatingLocation()
            }
        case .denied, .restricted:
            #if DEBUG
            print("[Location] Permission denied")
            #endif
            // Fall back to default
            useFallbackLocationIfNeeded()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension AppDelegate: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        let latitude = coordinate?.latitude
        let longitude = coordinate?.longitude

        Task { @MainActor [weak self] in
            self?.handleLocationUpdate(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let errorDescription = String(describing: error)

        Task { @MainActor [weak self] in
            self?.handleLocationFailure(errorDescription)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor [weak self] in
            self?.handleLocationAuthorizationChange(status)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }
}
