import AppKit
import SwiftUI
import CoreLocation

// This executable is not SunpaperApp: it creates only never-shown windows.
// All application, download, timer and wake dependencies below are inert.
// Catalog thumbnails come from the Mac's local Apple aerial manifest/cache.
// No standard Sunpaper preferences or real wallpaper setters are used.

private final class RenderTimer: SlotSchedulerTimerToken { func invalidate() {} }
private struct RenderTimers: SlotSchedulerTimerScheduling {
    func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, _ handler: @escaping @MainActor @Sendable () -> Void) -> SlotSchedulerTimerToken { RenderTimer() }
}
private struct RenderWake: SlotSchedulerWakeObserving {
    func observeWake(after delay: TimeInterval, handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol { NSObject() }
    func removeObserver(_ observer: NSObjectProtocol) {}
}
private struct RenderDisplays: SlotSchedulerDisplayProviding {
    func getDisplays() -> [DisplayManager.Display] { [.init(uuid: "preview", name: "Studio Display", isPrimary: true)] }
}
private struct RenderCatalog: SlotSchedulerAerialCatalogResolving {
    func downloadURL(for assetID: String) -> URL? { nil }
}
private struct RenderWallpaper: SlotSchedulerWallpaperServicing {
    func downloadAerial(assetID: String, from url: URL) async throws {}
    func isAerialDownloaded(assetID: String) -> Bool { true }
    func setWallpaper(assetID: String, displayUUID: String?) async throws {}
    func setCustomWallpaper(path: String) throws {}
    func getCurrentAssetID() throws -> String? { BuiltInWallpapers.tahoe.day }
}

@main struct Render {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "SunpaperScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: render OUTPUT_DIRECTORY"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSTimeZone.default = TimeZone(identifier: "America/Chicago")!
        let now = ISO8601DateFormatter().date(from: "2026-09-12T12:00:00-05:00")!
        var config = WallpaperConfig.default
        config.slots = BuiltInWallpapers.Phase.allCases.map { BuiltInWallpapers.tahoe.slot(for: $0) }
        config.locationName = "Chicago"; config.latitude = 41.8781; config.longitude = -87.6298
        let dependencies = SlotSchedulerDependencies(now: { now }, calculateSunTimes: { SunCalculator.calculate(for: $0, on: $1) }, timerScheduler: RenderTimers(), wakeObserver: RenderWake(), wallpaperService: RenderWallpaper(), displayProvider: RenderDisplays(), aerialCatalog: RenderCatalog())
        let controller = SunpaperController(config: config, defaults: nil, dependencies: dependencies, displays: RenderDisplays().getDisplays(), now: { now })
        // A public screenshot must have the actual catalog image, not a placeholder.
        guard AerialCatalog.shared.asset(for: BuiltInWallpapers.tahoe.day)?.thumbnailURL != nil else {
            throw NSError(domain: "SunpaperScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Download the Tahoe collection in macOS Wallpaper settings to populate the aerial catalog first."])
        }
        controller.start()
        defer { controller.stop() }
        await controller.scheduler.waitForPendingApplication()
        for dark in [true, false] {
            try await capture(ScheduleView(controller: controller), name: dark ? "your-day" : "your-day-light", size: .init(width: 780, height: 640), dark: dark, directory: directory)
            try await capture(SettingsView(controller: controller), name: dark ? "settings" : "settings-light", size: .init(width: 580, height: 800), dark: dark, directory: directory)
        }
        try await capture(MenuBarView(controller: controller, onChooseWallpaper: {}, onEditSchedule: {}, onOpenSettings: {}, onQuit: {}), name: "menu", size: .init(width: 328, height: 384), dark: true, directory: directory)
        let temporaryAssetID = AerialCatalog.shared.assets.first(where: { $0.displayName == "Golden Gate Sunset" })?.id ?? BuiltInWallpapers.sequoia.evening
        controller.apply(.builtIn(assetID: temporaryAssetID))
        await controller.scheduler.waitForPendingApplication()
        try await capture(MenuBarView(controller: controller, onChooseWallpaper: {}, onEditSchedule: {}, onOpenSettings: {}, onQuit: {}), name: "menu-temporary", size: .init(width: 328, height: 384), dark: true, directory: directory)
        controller.setFollowing(false)
        try await capture(MenuBarView(controller: controller, onChooseWallpaper: {}, onEditSchedule: {}, onOpenSettings: {}, onQuit: {}), name: "menu-paused", size: .init(width: 328, height: 384), dark: true, directory: directory)
        try await capture(WallpaperGridPicker(selectedSource: .constant(.builtIn(assetID: BuiltInWallpapers.tahoe.day)), title: "Wallpaper for Day", confirmationTitle: "Use for Day", onSelect: { _ in }), name: "wallpaper-picker", size: .init(width: 820, height: 650), dark: true, directory: directory)
        try await capture(TimingEditor(controller: controller, trigger: .hoursBeforeSunset(1), onSave: { _ in }), name: "timing-editor", size: .init(width: 384, height: 284), dark: true, directory: directory)
        try await capture(LocationChooser(controller: controller), name: "location-picker", size: .init(width: 478, height: 460), dark: true, directory: directory)
        controller.setSmoothWallpaperChanges(false)
        try await capture(SettingsView(controller: controller), name: "settings-smoothing-off", size: .init(width: 580, height: 800), dark: true, directory: directory)
    }

    @MainActor static func capture<V: View>(_ view: V, name: String, size: NSSize, dark: Bool, directory: URL) async throws {
        let root = view.environment(\.colorScheme, dark ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        window.contentView = host
        host.frame = .init(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "SunpaperScreenshots", code: 3)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SunpaperScreenshots", code: 4)
        }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        print("Rendered \(name)")
    }
}
