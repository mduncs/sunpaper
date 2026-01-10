import Foundation
import AppKit
import IOKit
import IOKit.graphics

/// Manages display information for per-display wallpaper configuration
final class DisplayManager: Sendable {

    struct Display: Identifiable, Equatable, Codable {
        let uuid: String
        let name: String
        let isPrimary: Bool

        var id: String { uuid }

        var displayName: String {
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

    /// Get UUID for a display ID
    private func getDisplayUUID(displayID: CGDirectDisplayID) -> String? {
        // Get UUID from vendor/model/serial
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        // Create a stable UUID-like string from vendor/model/serial
        // This is more stable than display ID across reboots
        if vendorID != 0 || modelID != 0 || serialNumber != 0 {
            return String(format: "%08X-%08X-%08X", vendorID, modelID, serialNumber)
        }

        // Last resort: use display ID as string (not stable across reboots but better than nothing)
        return String(format: "display-%08X", displayID)
    }

    /// Get human-readable name for a display
    private func getDisplayName(displayID: CGDirectDisplayID) -> String {
        // Check if it's the built-in display
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in Display"
        }

        // Try to get name from NSScreen
        for screen in NSScreen.screens {
            guard let deviceDescription = screen.deviceDescription as? [NSDeviceDescriptionKey: Any],
                  let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
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
