import Foundation
import AppKit

// MARK: - Wallpaper Operation Planning

enum WallpaperPlistMode: Equatable, Sendable, CustomStringConvertible {
    case linked
    case individual(displayUUIDs: [String])
    case idle(displayUUIDs: [String])
    case unknown(type: String?, displayUUIDs: [String], reason: String)

    var description: String {
        switch self {
        case .linked:
            return "linked"
        case .individual(let displayUUIDs):
            return "individual(\(displayUUIDs.count) display(s))"
        case .idle(let displayUUIDs):
            return "idle(\(displayUUIDs.count) display(s))"
        case .unknown(let type, _, let reason):
            return "unknown(type: \(type ?? "nil"), reason: \(reason))"
        }
    }
}

enum WallpaperTargetSelection: Equatable, Sendable {
    case allDisplays
    case display(uuid: String)
}

struct WallpaperPlistKeyPath: Equatable, Sendable {
    let configuration: String

    var provider: String {
        configuration.replacingOccurrences(of: ".Configuration", with: ".Provider")
    }

    static let linkedConfigurationKeyPaths: [WallpaperPlistKeyPath] = [
        WallpaperPlistKeyPath(configuration: "AllSpacesAndDisplays.Linked.Content.Choices.0.Configuration"),
        WallpaperPlistKeyPath(configuration: "SystemDefault.Linked.Content.Choices.0.Configuration")
    ]

    static let linkedCurrentConfigurationKeyPaths: [WallpaperPlistKeyPath] = linkedConfigurationKeyPaths

    static func desktopConfiguration(for displayUUID: String) -> WallpaperPlistKeyPath {
        WallpaperPlistKeyPath(configuration: "Displays.\(displayUUID).Desktop.Content.Choices.0.Configuration")
    }

    static func idleConfiguration(for displayUUID: String) -> WallpaperPlistKeyPath {
        WallpaperPlistKeyPath(configuration: "Displays.\(displayUUID).Idle.Content.Choices.0.Configuration")
    }
}

struct WallpaperProviderConfigurationPayload: Equatable, Sendable {
    let assetID: String
    let providerIdentifier: String
    let base64Configuration: String

    init(assetID: String, providerIdentifier: String) throws {
        let config: [String: String] = ["assetID": assetID]
        let binaryPlist = try PropertyListSerialization.data(
            fromPropertyList: config,
            format: .binary,
            options: 0
        )

        self.assetID = assetID
        self.providerIdentifier = providerIdentifier
        self.base64Configuration = binaryPlist.base64EncodedString()
    }
}

struct WallpaperDiagnostic: Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case info
        case warning
    }

    let severity: Severity
    let message: String
    let recoveryHint: String?
}

struct WallpaperPlistMutation: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case string(String)
        case base64Data(String)
    }

    let keyPath: String
    let value: Value
    let isRequired: Bool
    let purpose: String

    func plutilArguments(plistURL: URL) -> [String] {
        switch value {
        case .string(let value):
            return ["-replace", keyPath, "-string", value, plistURL.path]
        case .base64Data(let value):
            return ["-replace", keyPath, "-data", value, plistURL.path]
        }
    }
}

struct WallpaperProcessRestartSequence: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case kill(processNames: [String])
        case sleep(seconds: TimeInterval)
        case mutateIndexPlist
    }

    let steps: [Step]

    static let directIndexPlistMutation = WallpaperProcessRestartSequence(steps: [
        .kill(processNames: ["WallpaperAgent", "WallpaperAerialsExtension"]),
        .sleep(seconds: 0.3),
        .mutateIndexPlist,
        .sleep(seconds: 0.1),
        .kill(processNames: ["WallpaperAgent"])
    ])
}

struct WallpaperOperationPlan: Equatable, Sendable {
    let mode: WallpaperPlistMode
    let target: WallpaperTargetSelection
    let configurationKeyPaths: [WallpaperPlistKeyPath]
    let payload: WallpaperProviderConfigurationPayload
    let mutations: [WallpaperPlistMutation]
    let restartSequence: WallpaperProcessRestartSequence
    let diagnostics: [WallpaperDiagnostic]
}

/// Service for changing macOS aerial video wallpapers.
/// Works by editing ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist.
final class WallpaperService: @unchecked Sendable {

    static let shared = WallpaperService()

    private enum Constants {
        static let aerialProviderIdentifier = "com.apple.wallpaper.choice.aerials"
        static let allSpacesTypeKeyPath = "AllSpacesAndDisplays.Type"
        static let linkedTypeValue = "linked"
        static let preMutationProcesses = ["WallpaperAgent", "WallpaperAerialsExtension"]
        static let reloadProcesses = ["WallpaperAgent"]
        static let preMutationDelay: TimeInterval = 0.3
        static let postMutationDelay: TimeInterval = 0.1
    }

    private struct CommandResult {
        let terminationStatus: Int32
        let standardError: String

        var succeeded: Bool {
            terminationStatus == 0
        }
    }

    private let indexPlistURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.apple.wallpaper")
            .appendingPathComponent("Store")
            .appendingPathComponent("Index.plist")
    }()

    private let videosDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.apple.wallpaper")
            .appendingPathComponent("aerials")
            .appendingPathComponent("videos")
    }()

    private init() {}

    /// Download an aerial video to the local videos directory.
    func downloadAerial(assetID: String, from url: URL) async throws {
        let destination = videoURL(assetID: assetID)

        // Already downloaded
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        // Ensure videos directory exists
        try FileManager.default.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)

        #if DEBUG
        print("[WallpaperService] Downloading aerial \(assetID) from \(url)")
        #endif

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw WallpaperError.downloadFailed(assetID: assetID)
        }

        // Atomic move to destination. If another download finished first, that's fine.
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            #if DEBUG
            print("[WallpaperService] Downloaded aerial \(assetID)")
            #endif
        } catch {
            // File already exists (race condition) - clean up temp
            try? FileManager.default.removeItem(at: tempURL)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw error
            }
        }
    }

    /// Check if an aerial video is downloaded.
    func isAerialDownloaded(assetID: String) -> Bool {
        FileManager.default.fileExists(atPath: videoURL(assetID: assetID).path)
    }

    /// Builds a fixture-safe plan for an aerial wallpaper update without mutating the real wallpaper plist.
    func planAerialWallpaperChange(
        assetID: String,
        displayUUID: String? = nil,
        plistData: Data
    ) throws -> WallpaperOperationPlan {
        try makeAerialWallpaperPlan(assetID: assetID, displayUUID: displayUUID, plistData: plistData)
    }

    /// Set wallpaper by asset ID for all displays.
    /// - Parameter assetID: UUID of the aerial wallpaper (e.g., "4C108785-A7BA-422E-9C79-B0129F1D5550")
    func setWallpaper(assetID: String) throws {
        try setWallpaper(assetID: assetID, displayUUID: nil)
    }

    /// Set wallpaper by asset ID for a specific display or all displays.
    /// - Parameters:
    ///   - assetID: UUID of the aerial wallpaper
    ///   - displayUUID: UUID of the display to set wallpaper for, or nil for all displays
    func setWallpaper(assetID: String, displayUUID: String?) throws {
        // Check if Index.plist exists
        guard FileManager.default.fileExists(atPath: indexPlistURL.path) else {
            throw WallpaperError.plistNotFound
        }

        // Check if the aerial video is downloaded
        guard isAerialDownloaded(assetID: assetID) else {
            throw WallpaperError.aerialNotDownloaded(assetID: assetID)
        }

        let plistData = FileManager.default.contents(atPath: indexPlistURL.path)
        let plan = try makeAerialWallpaperPlan(assetID: assetID, displayUUID: displayUUID, plistData: plistData)
        logDiagnostics(plan.diagnostics)

        // CRITICAL: Kill wallpaper processes FIRST, then modify plist.
        // Processes write cached state on exit, so we must kill before modifying.
        killWallpaperProcesses()

        // Small delay to ensure processes are dead.
        Thread.sleep(forTimeInterval: Constants.preMutationDelay)

        try applyMutations(plan.mutations)

        // Force reload to pick up new plist values.
        forceWallpaperReload()
    }

    /// Set a custom image/video wallpaper from file path.
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

    /// Get current wallpaper asset ID without mutating Index.plist.
    func getCurrentAssetID() throws -> String? {
        let plistData = FileManager.default.contents(atPath: indexPlistURL.path)
        let mode = Self.detectPlistMode(plistData: plistData).mode
        let keyPaths = Self.currentConfigurationKeyPaths(for: mode)

        for keyPath in keyPaths {
            guard let base64String = try extractRawConfiguration(at: keyPath.configuration),
                  let configData = Data(base64Encoded: base64String) else {
                continue
            }

            let config = try PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: String]
            if let assetID = config?["assetID"] {
                return assetID
            }
        }

        return nil
    }

    private func videoURL(assetID: String) -> URL {
        videosDirectoryURL.appendingPathComponent("\(assetID).mov")
    }

    private func makeAerialWallpaperPlan(
        assetID: String,
        displayUUID: String?,
        plistData: Data?
    ) throws -> WallpaperOperationPlan {
        let payload = try WallpaperProviderConfigurationPayload(
            assetID: assetID,
            providerIdentifier: Constants.aerialProviderIdentifier
        )
        let target = displayUUID.map { WallpaperTargetSelection.display(uuid: $0) } ?? .allDisplays
        let detection = Self.detectPlistMode(plistData: plistData)
        var diagnostics = detection.diagnostics

        let resolution = Self.configurationKeyPaths(
            mode: detection.mode,
            target: target
        )
        diagnostics.append(contentsOf: resolution.diagnostics)

        var mutations: [WallpaperPlistMutation] = []
        if resolution.shouldForceLinkedMode {
            mutations.append(WallpaperPlistMutation(
                keyPath: Constants.allSpacesTypeKeyPath,
                value: .string(Constants.linkedTypeValue),
                isRequired: false,
                purpose: "idle mode linked recovery"
            ))
        }

        for keyPath in resolution.keyPaths {
            mutations.append(WallpaperPlistMutation(
                keyPath: keyPath.provider,
                value: .string(payload.providerIdentifier),
                isRequired: false,
                purpose: "aerial provider"
            ))
            mutations.append(WallpaperPlistMutation(
                keyPath: keyPath.configuration,
                value: .base64Data(payload.base64Configuration),
                isRequired: true,
                purpose: "aerial configuration"
            ))
        }

        return WallpaperOperationPlan(
            mode: detection.mode,
            target: target,
            configurationKeyPaths: resolution.keyPaths,
            payload: payload,
            mutations: mutations,
            restartSequence: .directIndexPlistMutation,
            diagnostics: diagnostics
        )
    }

    private static func detectPlistMode(plistData: Data?) -> (
        mode: WallpaperPlistMode,
        diagnostics: [WallpaperDiagnostic]
    ) {
        guard let plistData else {
            return (
                .unknown(type: nil, displayUUIDs: [], reason: "Index.plist could not be read"),
                [WallpaperDiagnostic(
                    severity: .warning,
                    message: "Index.plist could not be read for planning; falling back to linked key paths.",
                    recoveryHint: "Check wallpaper plist permissions or open Wallpaper settings once before retrying."
                )]
            )
        }

        do {
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
                return (
                    .unknown(type: nil, displayUUIDs: [], reason: "Index.plist root is not a dictionary"),
                    [WallpaperDiagnostic(
                        severity: .warning,
                        message: "Index.plist root is not a dictionary; falling back to linked key paths.",
                        recoveryHint: "Change the wallpaper in System Settings to regenerate a valid wallpaper plist."
                    )]
                )
            }

            return (detectPlistMode(plist: plist), [])
        } catch {
            return (
                .unknown(type: nil, displayUUIDs: [], reason: "Index.plist could not be parsed: \(error.localizedDescription)"),
                [WallpaperDiagnostic(
                    severity: .warning,
                    message: "Index.plist could not be parsed; falling back to linked key paths.",
                    recoveryHint: "Change the wallpaper in System Settings to regenerate a valid wallpaper plist."
                )]
            )
        }
    }

    private static func detectPlistMode(plist: [String: Any]) -> WallpaperPlistMode {
        let displayUUIDs = (plist["Displays"] as? [String: Any])?.keys.sorted() ?? []
        let typeValue = (plist["AllSpacesAndDisplays"] as? [String: Any])?["Type"] as? String

        switch typeValue {
        case "linked":
            return .linked
        case "individual":
            return .individual(displayUUIDs: displayUUIDs)
        case "idle":
            return .idle(displayUUIDs: displayUUIDs)
        case .some(let unknownType):
            if !displayUUIDs.isEmpty {
                return .individual(displayUUIDs: displayUUIDs)
            }
            return .unknown(
                type: unknownType,
                displayUUIDs: displayUUIDs,
                reason: "Unrecognized AllSpacesAndDisplays.Type"
            )
        case nil:
            if !displayUUIDs.isEmpty {
                return .individual(displayUUIDs: displayUUIDs)
            }
            return .unknown(
                type: nil,
                displayUUIDs: displayUUIDs,
                reason: "Missing AllSpacesAndDisplays.Type"
            )
        }
    }

    private static func configurationKeyPaths(
        mode: WallpaperPlistMode,
        target: WallpaperTargetSelection
    ) -> (
        keyPaths: [WallpaperPlistKeyPath],
        shouldForceLinkedMode: Bool,
        diagnostics: [WallpaperDiagnostic]
    ) {
        var diagnostics: [WallpaperDiagnostic] = []

        switch target {
        case .display(let displayUUID):
            switch mode {
            case .individual(let displayUUIDs) where !displayUUIDs.contains(displayUUID):
                diagnostics.append(WallpaperDiagnostic(
                    severity: .warning,
                    message: "Target display \(displayUUID) is not present in Index.plist Displays.",
                    recoveryHint: "Reconnect the display or change per-display wallpaper once in System Settings."
                ))
            case .linked:
                diagnostics.append(WallpaperDiagnostic(
                    severity: .info,
                    message: "Per-display target requested while Index.plist is linked; preserving direct Desktop key-path write.",
                    recoveryHint: nil
                ))
            case .idle:
                diagnostics.append(WallpaperDiagnostic(
                    severity: .warning,
                    message: "Per-display target requested while Index.plist is idle; preserving existing Desktop key-path behavior.",
                    recoveryHint: "If macOS ignores the update, switch out of idle wallpaper mode in System Settings."
                ))
            case .unknown(_, _, let reason):
                diagnostics.append(WallpaperDiagnostic(
                    severity: .warning,
                    message: "Per-display target planned with unknown plist mode: \(reason).",
                    recoveryHint: "The plutil write will fail if the display Desktop key path does not exist."
                ))
            default:
                break
            }

            return ([.desktopConfiguration(for: displayUUID)], false, diagnostics)

        case .allDisplays:
            switch mode {
            case .linked:
                return (WallpaperPlistKeyPath.linkedConfigurationKeyPaths, false, diagnostics)

            case .idle:
                diagnostics.append(WallpaperDiagnostic(
                    severity: .warning,
                    message: "Index.plist is in idle mode; plan includes a non-fatal linked-mode recovery before aerial writes.",
                    recoveryHint: "Idle mode uses different key paths, so direct aerial writes target linked mode after recovery."
                ))
                return (WallpaperPlistKeyPath.linkedConfigurationKeyPaths, true, diagnostics)

            case .individual(let displayUUIDs):
                guard !displayUUIDs.isEmpty else {
                    diagnostics.append(WallpaperDiagnostic(
                        severity: .warning,
                        message: "Index.plist is individual mode but has no display entries; falling back to linked key paths.",
                        recoveryHint: "Open Wallpaper settings and configure at least one display if per-display updates are expected."
                    ))
                    return (WallpaperPlistKeyPath.linkedConfigurationKeyPaths, false, diagnostics)
                }

                return (displayUUIDs.map(WallpaperPlistKeyPath.desktopConfiguration), false, diagnostics)

            case .unknown(_, let displayUUIDs, let reason):
                diagnostics.append(WallpaperDiagnostic(
                    severity: .warning,
                    message: "Wallpaper plist mode is unknown: \(reason).",
                    recoveryHint: "The plan uses the safest known key-path fallback for the available plist structure."
                ))

                if displayUUIDs.isEmpty {
                    return (WallpaperPlistKeyPath.linkedConfigurationKeyPaths, false, diagnostics)
                }

                return (displayUUIDs.map(WallpaperPlistKeyPath.desktopConfiguration), false, diagnostics)
            }
        }
    }

    private static func currentConfigurationKeyPaths(for mode: WallpaperPlistMode) -> [WallpaperPlistKeyPath] {
        switch mode {
        case .linked:
            return WallpaperPlistKeyPath.linkedCurrentConfigurationKeyPaths
        case .individual(let displayUUIDs):
            let displayKeyPaths = displayUUIDs.map(WallpaperPlistKeyPath.desktopConfiguration)
            return displayKeyPaths.isEmpty ? WallpaperPlistKeyPath.linkedCurrentConfigurationKeyPaths : displayKeyPaths
        case .idle(let displayUUIDs):
            var keyPaths = [
                WallpaperPlistKeyPath(configuration: "AllSpacesAndDisplays.Idle.Content.Choices.0.Configuration")
            ]
            keyPaths.append(contentsOf: displayUUIDs.map(WallpaperPlistKeyPath.idleConfiguration))
            return keyPaths
        case .unknown(_, let displayUUIDs, _):
            let displayKeyPaths = displayUUIDs.map(WallpaperPlistKeyPath.desktopConfiguration)
            return displayKeyPaths.isEmpty ? WallpaperPlistKeyPath.linkedCurrentConfigurationKeyPaths : displayKeyPaths
        }
    }

    private func applyMutations(_ mutations: [WallpaperPlistMutation]) throws {
        var completedRequiredMutations: [String] = []

        for mutation in mutations {
            do {
                let result = try runPlutil(arguments: mutation.plutilArguments(plistURL: indexPlistURL))

                if !result.succeeded {
                    logMutationFailure(mutation, result: result)

                    guard !mutation.isRequired else {
                        logPartialFailureIfNeeded(completedRequiredMutations: completedRequiredMutations)
                        throw WallpaperError.plistUpdateFailed(keyPath: mutation.keyPath)
                    }
                } else if mutation.isRequired {
                    completedRequiredMutations.append(mutation.keyPath)
                }
            } catch {
                guard !mutation.isRequired else {
                    logPartialFailureIfNeeded(completedRequiredMutations: completedRequiredMutations)
                    throw error
                }

                #if DEBUG
                print("[WallpaperService] Non-fatal plist mutation failed for \(mutation.keyPath): \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func extractRawConfiguration(at keyPath: String) throws -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = [
            "-extract",
            keyPath,
            "raw",
            indexPlistURL.path
        ]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runPlutil(arguments: [String]) throws -> CommandResult {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = arguments
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let standardError = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardError: standardError
        )
    }

    private func killWallpaperProcesses() {
        // Kill ALL wallpaper processes - the appex extensions cache state
        // and will restore old values if only WallpaperAgent is killed.
        for processName in Constants.preMutationProcesses {
            killProcess(named: processName)
        }
    }

    /// Force wallpaper reload by killing WallpaperAgent after plist is modified.
    private func forceWallpaperReload() {
        // Small delay to ensure plist writes are flushed.
        Thread.sleep(forTimeInterval: Constants.postMutationDelay)

        for processName in Constants.reloadProcesses {
            killProcess(named: processName)
        }
    }

    private func killProcess(named processName: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [processName]
        try? process.run()
        process.waitUntilExit()
    }

    private func logDiagnostics(_ diagnostics: [WallpaperDiagnostic]) {
        #if DEBUG
        for diagnostic in diagnostics {
            let hint = diagnostic.recoveryHint.map { " Hint: \($0)" } ?? ""
            print("[WallpaperService] \(diagnostic.severity.rawValue.uppercased()): \(diagnostic.message)\(hint)")
        }
        #endif
    }

    private func logMutationFailure(_ mutation: WallpaperPlistMutation, result: CommandResult) {
        #if DEBUG
        let stderr = result.standardError.isEmpty ? "no stderr" : result.standardError
        print(
            "[WallpaperService] plutil \(mutation.purpose) failed at \(mutation.keyPath) " +
            "(status \(result.terminationStatus)): \(stderr)"
        )
        #endif
    }

    private func logPartialFailureIfNeeded(completedRequiredMutations: [String]) {
        #if DEBUG
        guard !completedRequiredMutations.isEmpty else { return }
        print(
            "[WallpaperService] Partial plist update: completed \(completedRequiredMutations.count) " +
            "required configuration write(s) before failure."
        )
        #endif
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
    case aerialNotDownloaded(assetID: String)
    case downloadFailed(assetID: String)

    var errorDescription: String? {
        switch self {
        case .plistNotFound:
            return "Wallpaper configuration file not found: Index.plist. Try changing your wallpaper in System Settings first."
        case .plistUpdateFailed(let keyPath):
            return "Failed to update Index.plist at \(keyPath). Some display entries may already have been changed."
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
        case .aerialNotDownloaded(let assetID):
            return "Aerial wallpaper not downloaded. Open System Settings > Wallpaper and download the aerial collection first. (Asset: \(assetID))"
        case .downloadFailed(let assetID):
            return "Failed to download aerial wallpaper. (Asset: \(assetID))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .plistNotFound:
            return "Open System Settings > Wallpaper once so macOS creates the wallpaper Index.plist."
        case .plistUpdateFailed:
            return "Retry after opening Wallpaper settings. If only some displays changed, apply the wallpaper again."
        case .agentRestartFailed:
            return "Quit and relaunch Sunpaper, then try the wallpaper change again."
        case .customFileNotFound:
            return "Choose an existing image file."
        case .customVideoNotSupported:
            return "Use a built-in aerial video wallpaper or choose a static image file."
        case .unsupportedFormat:
            return "Choose a HEIC, JPG, JPEG, PNG, TIFF, or BMP image."
        case .noMainScreen:
            return "Connect or wake a display, then try again."
        case .aerialNotDownloaded:
            return "Download the aerial in System Settings > Wallpaper, then retry."
        case .downloadFailed:
            return "Confirm the aerial catalog entry has a valid video URL and that the network is available."
        }
    }
}
