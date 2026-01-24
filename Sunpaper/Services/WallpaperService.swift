import Foundation
import AppKit

/// Service for changing macOS aerial video wallpapers
/// Works by editing ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
class WallpaperService {

    static let shared = WallpaperService()

    private let indexPlistURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.apple.wallpaper")
            .appendingPathComponent("Store")
            .appendingPathComponent("Index.plist")
    }()

    private init() {}

    /// Set wallpaper by asset ID for all displays
    /// - Parameter assetID: UUID of the aerial wallpaper (e.g., "4C108785-A7BA-422E-9C79-B0129F1D5550")
    func setWallpaper(assetID: String) throws {
        try setWallpaper(assetID: assetID, displayUUID: nil)
    }

    /// Set wallpaper by asset ID for a specific display or all displays
    /// - Parameters:
    ///   - assetID: UUID of the aerial wallpaper
    ///   - displayUUID: UUID of the display to set wallpaper for, or nil for all displays
    func setWallpaper(assetID: String, displayUUID: String?) throws {
        // Check if Index.plist exists
        guard FileManager.default.fileExists(atPath: indexPlistURL.path) else {
            throw WallpaperError.plistNotFound
        }

        // Create config dict
        let config: [String: String] = ["assetID": assetID]

        // Encode as binary plist
        let binaryPlist = try PropertyListSerialization.data(
            fromPropertyList: config,
            format: .binary,
            options: 0
        )

        // Base64 encode
        let base64Config = binaryPlist.base64EncodedString()

        // Determine key paths based on displayUUID
        let keyPaths: [String]
        if let displayUUID = displayUUID {
            // Per-display configuration - Desktop for wallpaper
            keyPaths = [
                "Displays.\(displayUUID).Desktop.Content.Choices.0.Configuration"
            ]
        } else {
            // All displays - need to update each display's Desktop key
            // First get all display UUIDs from the plist
            keyPaths = try getAllDisplayKeyPaths()
        }

        // CRITICAL: Kill wallpaper processes FIRST, then modify plist
        // Processes write cached state on exit, so we must kill before modifying
        killWallpaperProcesses()

        // Small delay to ensure processes are dead
        Thread.sleep(forTimeInterval: 0.3)
        for keyPath in keyPaths {
            // Set Provider to aerials (required for aerial videos)
            let providerPath = keyPath.replacingOccurrences(of: ".Configuration", with: ".Provider")
            let providerProcess = Process()
            providerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            providerProcess.arguments = [
                "-replace", providerPath,
                "-string", "com.apple.wallpaper.choice.aerials",
                indexPlistURL.path
            ]
            try? providerProcess.run()
            providerProcess.waitUntilExit()

            // Set Configuration with assetID
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = [
                "-replace", keyPath,
                "-data", base64Config,
                indexPlistURL.path
            ]
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw WallpaperError.plistUpdateFailed(keyPath: keyPath)
            }
        }

        // Force reload to pick up new plist values
        forceWallpaperReload()
    }

    /// Set a custom image/video wallpaper from file path
    func setCustomWallpaper(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw WallpaperError.customFileNotFound(path: path)
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if ["heic", "jpg", "jpeg", "png", "tiff", "bmp"].contains(ext) {
            // Static image - use NSWorkspace
            try setStaticWallpaper(url: url)
        } else if ["mov", "mp4", "m4v"].contains(ext) {
            // Video - requires more complex plist editing
            #if DEBUG
            print("[WallpaperService] Custom video wallpapers not yet fully supported")
            #endif
            throw WallpaperError.customVideoNotSupported
        } else {
            throw WallpaperError.unsupportedFormat(ext: ext)
        }
    }

    private func setStaticWallpaper(url: URL) throws {
        let workspace = NSWorkspace.shared
        guard let screen = NSScreen.main else {
            throw WallpaperError.noMainScreen
        }

        try workspace.setDesktopImageURL(url, for: screen, options: [:])
        #if DEBUG
        print("[WallpaperService] Set static wallpaper: \(url.lastPathComponent)")
        #endif
    }

    /// Get current wallpaper asset ID
    func getCurrentAssetID() throws -> String? {
        // Try to get from first display's config (uses same mode detection as setting)
        let keyPaths = (try? getAllDisplayKeyPaths()) ?? ["AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration"]
        guard let firstKeyPath = keyPaths.first else { return nil }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = [
            "-extract",
            firstKeyPath,
            "raw",
            indexPlistURL.path
        ]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let base64String = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let configData = Data(base64Encoded: base64String) else {
            return nil
        }

        let config = try PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: String]
        return config?["assetID"]
    }

    /// Get all display key paths from the Index.plist
    /// Detects whether plist uses "linked" mode (all displays same) or "individual" mode (per-display)
    /// If plist is in "idle" mode, forces it to "linked" mode first
    private func getAllDisplayKeyPaths() throws -> [String] {
        guard let plistData = FileManager.default.contents(atPath: indexPlistURL.path),
              let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            // Fallback to linked mode keypaths
            return [
                "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration",
                "SystemDefault.Linked.Content.Choices.0.Configuration"
            ]
        }

        // Check the wallpaper mode from AllSpacesAndDisplays.Type
        if let allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any],
           let typeValue = allSpaces["Type"] as? String {

            if typeValue == "linked" {
                // Linked mode: all displays use the same wallpaper
                return [
                    "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration",
                    "SystemDefault.Linked.Content.Choices.0.Configuration"
                ]
            }

            if typeValue == "idle" {
                // Idle mode: need to force to linked mode for our changes to work
                // The plist structure is different in idle mode and our writes won't take effect
                forceLinkedMode()
                return [
                    "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration",
                    "SystemDefault.Linked.Content.Choices.0.Configuration"
                ]
            }
        }

        // Individual/per-display mode: each display has its own config
        if let displays = plist["Displays"] as? [String: Any], !displays.isEmpty {
            var keyPaths: [String] = []
            for displayUUID in displays.keys {
                keyPaths.append("Displays.\(displayUUID).Desktop.Content.Choices.0.Configuration")
            }
            return keyPaths
        }

        // Fallback to linked mode
        return [
            "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration",
            "SystemDefault.Linked.Content.Choices.0.Configuration"
        ]
    }

    /// Force the plist into linked mode when it's in idle mode
    /// This is necessary because idle mode has a different structure that doesn't respond to our writes
    private func forceLinkedMode() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = [
            "-replace", "AllSpacesAndDisplays.Type",
            "-string", "linked",
            indexPlistURL.path
        ]
        try? process.run()
        process.waitUntilExit()

        #if DEBUG
        print("[WallpaperService] Forced plist from idle to linked mode")
        #endif
    }

    private func killWallpaperProcesses() {
        // Kill ALL wallpaper processes - the appex extensions cache state
        // and will restore old values if only WallpaperAgent is killed
        // Must kill BEFORE modifying plist because processes write state on exit
        let processesToKill = [
            "WallpaperAgent",
            "WallpaperAerialsExtension"
        ]

        for processName in processesToKill {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [processName]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Force wallpaper reload by killing WallpaperAgent after plist is modified
    private func forceWallpaperReload() {
        // Small delay to ensure plist writes are flushed
        Thread.sleep(forTimeInterval: 0.1)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
        process.waitUntilExit()
    }
}

enum WallpaperError: LocalizedError {
    case plistNotFound
    case plistUpdateFailed(keyPath: String)
    case agentRestartFailed
    case customFileNotFound(path: String)
    case customVideoNotSupported
    case unsupportedFormat(ext: String)
    case noMainScreen

    var errorDescription: String? {
        switch self {
        case .plistNotFound:
            return "Wallpaper configuration file not found. Try changing your wallpaper in System Settings first."
        case .plistUpdateFailed(let keyPath):
            return "Failed to update Index.plist at \(keyPath)"
        case .agentRestartFailed:
            return "Failed to restart WallpaperAgent"
        case .customFileNotFound(let path):
            return "Custom wallpaper file not found: \(path)"
        case .customVideoNotSupported:
            return "Custom video wallpapers are not yet supported. Use Apple's built-in aerials for video backgrounds."
        case .unsupportedFormat(let ext):
            return "Unsupported wallpaper format: .\(ext)"
        case .noMainScreen:
            return "No main screen found"
        }
    }
}
