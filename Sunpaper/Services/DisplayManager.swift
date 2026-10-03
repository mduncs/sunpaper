import Foundation
import AppKit
import ColorSync
import IOKit
import IOKit.graphics

/// Manages display information for per-display wallpaper configuration
final class DisplayManager: Sendable {

    struct Display: Identifiable, Equatable, Codable {
        enum IdentitySource: Equatable {
            case hardwareDescriptor
            case displayIDFallback

            var isStableAcrossReboots: Bool {
                switch self {
                case .hardwareDescriptor:
                    return true
                case .displayIDFallback:
                    return false
                }
            }
        }

        let uuid: String
        let name: String
        let isPrimary: Bool

        var id: String { uuid }

        var displayName: String {
            Self.displayName(for: name, isPrimary: isPrimary)
        }

        /// Describes how the persisted display identifier was derived.
        ///
        /// Existing user configs store only `uuid`, so this remains a computed
        /// property and does not alter the Codable shape.
        var identitySource: IdentitySource {
            uuid.hasPrefix(Self.displayIDFallbackPrefix) ? .displayIDFallback : .hardwareDescriptor
        }

        /// False when macOS did not expose vendor/model/serial data and the app
        /// had to fall back to a display ID that may change after reconnects.
        var hasStableIdentity: Bool {
            identitySource.isStableAcrossReboots
        }

        var identityDescription: String {
            switch identitySource {
            case .hardwareDescriptor:
                return "Hardware descriptor"
            case .displayIDFallback:
                return "Temporary display ID"
            }
        }

        private static let displayIDFallbackPrefix = "display-"

        private static func displayName(for name: String, isPrimary: Bool) -> String {
            isPrimary ? "\(name) (Primary)" : name
        }
    }

    static let shared = DisplayManager()

    private init() {}

    /// Get all connected displays with their UUIDs
    func getDisplays() -> [Display] {
        var displays: [Display] = []

        // Get list of active display IDs
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))

        let result = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard result == .success else {
            #if DEBUG
            print("[DisplayManager] Failed to get active displays: \(result)")
            #endif
            return []
        }

        let mainDisplayID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]

            // Get UUID
            guard let uuid = getDisplayUUID(displayID: displayID) else {
                continue
            }

            // Get name
            let name = getDisplayName(displayID: displayID)
            let isPrimary = (displayID == mainDisplayID)

            displays.append(Display(uuid: uuid, name: name, isPrimary: isPrimary))
        }

        // Sort: primary first, then by name
        return displays.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary
            }
            return lhs.name < rhs.name
        }
    }

    /// Get the persisted identifier for a display.
    ///
    /// Prefer vendor/model/serial because it is usually stable across reboots
    /// and reconnects. If macOS does not expose those values, keep the existing
    /// `display-XXXXXXXX` fallback so existing per-display config remains
    /// compatible, even though that fallback is not guaranteed to be stable.
    func getDisplayUUID(displayID: CGDirectDisplayID) -> String? {
        let connected = Set(activeDisplayIDs()).union([displayID]).map { id in
            (id: id, hardware: hardwareIdentifier(displayID: id), native: nativeDisplayUUID(displayID: id))
        }
        return Self.persistedIdentifiers(for: connected)[displayID]
    }

    /// Identical displays without serial numbers share a hardware descriptor.
    /// Only connected twins get macOS's display UUID appended, so every other
    /// saved identifier stays unchanged.
    static func persistedIdentifiers(
        for displays: [(id: CGDirectDisplayID, hardware: String, native: String?)]
    ) -> [CGDirectDisplayID: String] {
        let counts = Dictionary(displays.map { ($0.hardware, 1) }, uniquingKeysWith: +)
        return Dictionary(displays.map { display in
            guard counts[display.hardware, default: 0] > 1, let native = display.native else {
                return (display.id, display.hardware)
            }
            return (display.id, "\(display.hardware)-\(native)")
        }, uniquingKeysWith: { first, _ in first })
    }

    private func hardwareIdentifier(displayID: CGDirectDisplayID) -> String {
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        if vendorID != 0 || modelID != 0 || serialNumber != 0 {
            return String(format: "%08X-%08X-%08X", vendorID, modelID, serialNumber)
        }

        return String(format: "display-%08X", displayID)
    }

    private func nativeDisplayUUID(displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Index.plist uses macOS display UUIDs, not our persisted hardware identifiers.
    /// Keep saved schedule identifiers unchanged and translate only at the write boundary.
    func getWallpaperDisplayUUID(for displayUUID: String) -> String? {
        activeDisplayIDs().first { getDisplayUUID(displayID: $0) == displayUUID }.flatMap(nativeDisplayUUID)
    }

    /// The Index.plist keys of every connected display.
    func connectedWallpaperDisplayUUIDs() -> [String] {
        activeDisplayIDs().compactMap(nativeDisplayUUID)
    }

    /// Get human-readable name for a display
    private func getDisplayName(displayID: CGDirectDisplayID) -> String {
        // Check if it's the built-in display
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in Display"
        }

        // Try to get name from NSScreen
        for screen in NSScreen.screens {
            let deviceDescription = screen.deviceDescription
            guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  screenNumber == displayID else {
                continue
            }
            return screen.localizedName
        }

        // Fallback to vendor/model info
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        if vendorID != 0 || modelID != 0 {
            return String(format: "Display %04X-%04X", vendorID, modelID)
        }

        return "Display \(displayID)"
    }
}
