import Foundation
import AppKit
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
    private func getDisplayUUID(displayID: CGDirectDisplayID) -> String? {
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        if vendorID != 0 || modelID != 0 || serialNumber != 0 {
            return String(format: "%08X-%08X-%08X", vendorID, modelID, serialNumber)
        }

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
