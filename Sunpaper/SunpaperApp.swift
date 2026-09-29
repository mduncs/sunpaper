import SwiftUI
import Combine

@main
struct SunpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView(controller: .shared) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(before: .appSettings) {
                    Button("Your day…") { appDelegate.openSchedule() }
                        .keyboardShortcut("1", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var scheduleWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var observation: AnyCancellable?
    private var controller: SunpaperController { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A test host must never start scheduling, location prompts or UI.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        guard running.count <= 1 else { NSApp.terminate(nil); return }
        setupStatusItem()
        controller.start()
        observation = controller.scheduler.$isDownloading.sink { [weak self] downloading in
            self?.statusItem?.button?.image = NSImage(
                systemSymbolName: downloading ? "icloud.and.arrow.down.fill" : "sun.horizon.fill",
                accessibilityDescription: downloading ? "Sunpaper is downloading a wallpaper" : "Sunpaper")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Sunpaper")
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: SunpaperSize.popoverWidth, height: SunpaperSize.popoverHeight)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(
            controller: controller,
            onChooseWallpaper: { [weak self] in self?.openWallpaperPicker() },
            onEditSchedule: { [weak self] in self?.openSchedule() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }))
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openSchedule() {
        popover?.performClose(nil)
        if scheduleWindow == nil {
            scheduleWindow = makeWindow(
                title: "Sunpaper", view: ScheduleView(controller: controller, openSettings: { [weak self] in self?.openSettings() }),
                size: NSSize(width: SunpaperSize.scheduleWidth, height: SunpaperSize.scheduleHeight),
                minimum: NSSize(width: SunpaperSize.scheduleMinWidth, height: SunpaperSize.scheduleMinHeight), autosave: "SunpaperYourDay")
        }
        show(scheduleWindow)
    }

    func openSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Sunpaper Settings", view: SettingsView(controller: controller),
                size: NSSize(width: SunpaperSize.settingsIdealWidth, height: SunpaperSize.settingsIdealHeight),
                minimum: NSSize(width: SunpaperSize.settingsMinWidth, height: SunpaperSize.settingsMinHeight), autosave: "SunpaperPreferences")
        }
        show(settingsWindow)
    }

    private func openWallpaperPicker() {
        openSchedule()
        controller.isChoosingWallpaper = true
    }

    private func makeWindow<V: View>(title: String, view: V, size: NSSize, minimum: NSSize, autosave: String) -> NSWindow {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.contentMinSize = minimum
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func show(_ window: NSWindow?) {
        // Only user-initiated commands reach this path.
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { controller.undoManager }

    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === scheduleWindow { scheduleWindow = nil }
        if window === settingsWindow { settingsWindow = nil }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard WallpaperService.isChangingWallpaper || WallpaperTransition.shared.needsRecovery else { return .terminateNow }
        controller.stop()
        Task { @MainActor in
            await WallpaperService.waitForPendingChanges()
            if WallpaperTransition.shared.needsRecovery {
                let alert = NSAlert()
                alert.messageText = "The desktop is still being restored"
                alert.informativeText = "Sunpaper is keeping the previous wallpaper visible. Quitting removes that cover. You can retry restoration in Settings → Smooth changes."
                alert.addButton(withTitle: "Keep Sunpaper Open")
                alert.addButton(withTitle: "Quit Anyway")
                let quit = alert.runModal() == .alertSecondButtonReturn
                sender.reply(toApplicationShouldTerminate: quit)
                if !quit { controller.start() }
            } else { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Avoid creating the live singleton when a test host exits.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        controller.stop()
    }
}
