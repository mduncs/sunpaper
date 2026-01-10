import SwiftUI
import CoreLocation

@main
struct SunpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var locationManager: CLLocationManager!
    private var scheduler: SlotScheduler?

    private var currentLocation: CLLocationCoordinate2D?
    private var config: WallpaperConfig = .default

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip singleton check during unit tests
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        // Ensure single instance (skip during tests)
        if !isRunningTests {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            if runningApps.count > 1 {
                NSApp.terminate(nil)
                return
            }
        }

        loadConfig()
        setupStatusItem()
        setupLocationManager()
        startScheduler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
    }

    // MARK: - Setup

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: "wallpaperConfig"),
           let loaded = try? JSONDecoder().decode(WallpaperConfig.self, from: data) {
            config = loaded

            // Use stored location if available
            if let lat = config.latitude, let lon = config.longitude {
                currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Sunpaper")
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 300)
        popover.behavior = .transient
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        let view = MenuBarView(
            currentSlot: currentSlot,
            nextTransition: nextTransition,
            todaySchedule: todaySchedule,
            lastError: scheduler?.lastError,
            onApplySlot: { [weak self] slot in
                self?.applySlot(slot)
                self?.popover.performClose(nil)
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func applySlot(_ slot: TimeSlot) {
        scheduler?.applyWallpaper(source: slot.source)
    }

    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        // Only request location if we don't have stored coordinates
        if currentLocation == nil {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
    }

    private func startScheduler() {
        scheduler = SlotScheduler(
            config: config,
            locationProvider: { [weak self] in self?.currentLocation }
        )
        scheduler?.start()
    }

    // MARK: - Actions

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Refresh the view with current state
                updatePopoverContent()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Make popover window key to receive input
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func openSettings() {
        popover.performClose(nil)

        // Reuse existing window if visible
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings window
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Sunpaper Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()
        window.delegate = self

        // Keep reference and show
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func forceUpdate() {
        scheduler?.forceUpdate()
    }

    // MARK: - Config Updates

    func updateConfig(_ newConfig: WallpaperConfig) {
        config = newConfig
        scheduler?.updateConfig(newConfig)

        // Update location if changed
        if let lat = newConfig.latitude, let lon = newConfig.longitude {
            currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Only use auto-detected location if no stored location
        if config.latitude == nil || config.longitude == nil {
            currentLocation = locations.last?.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[Location] Error: \(error)")
        #endif

        // Fall back to Chicago if no stored location
        if currentLocation == nil {
            currentLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            if config.latitude == nil {
                manager.startUpdatingLocation()
            }
        case .denied, .restricted:
            #if DEBUG
            print("[Location] Permission denied")
            #endif
            // Fall back to default
            if currentLocation == nil {
                currentLocation = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
            }
        case .notDetermined:
            break
        @unknown default:
            break
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
