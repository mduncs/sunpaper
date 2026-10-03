import Foundation
import AppKit
import ImageIO

// MARK: - Wallpaper Operation Planning

enum WallpaperTargetSelection: Equatable, Sendable {
    case allDisplays
    case display(uuid: String)
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
        /// A property list fragment that replaces the whole value at `keyPath`.
        case xml(String)
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
        case .xml(let value):
            return ["-replace", keyPath, "-xml", value, plistURL.path]
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
    let target: WallpaperTargetSelection
    let payload: WallpaperProviderConfigurationPayload
    let mutations: [WallpaperPlistMutation]
    let restartSequence: WallpaperProcessRestartSequence
    let diagnostics: [WallpaperDiagnostic]
}

/// How WallpaperAgent resolves Index.plist, verified live on macOS 27 (October 2026):
/// - An `AllSpacesAndDisplays` dictionary applies to every display and Space,
///   overriding both `Displays` and `Spaces`.
/// - Per-display wallpapers need `AllSpacesAndDisplays` set to "$null" plus a
///   `Displays.<display UUID>` entry keyed by `CGDisplayCreateUUIDFromDisplayID`.
/// - WallpaperAgent then derives `Spaces.<space>` entries from `Displays`. Those
///   win afterwards (the agent copies them back over `Displays`), so a
///   per-display write drops every Space that references its display.
/// Entries are `{Type: linked, Linked: {Content: {Choices, Shuffle}, LastSet, LastUse}}`.
/// Whole entries are written so a missing parent key path can't fail a change.
enum WallpaperStoreLayout {
    static let nullValue = "$null"
    static let allDisplaysKey = "AllSpacesAndDisplays"
    static let displaysKey = "Displays"
    static let spacesKey = "Spaces"
    static let systemDefaultKey = "SystemDefault"

    static func plan(
        payload: WallpaperProviderConfigurationPayload,
        target: WallpaperTargetSelection,
        connectedDisplayUUIDs: [String],
        plist: [String: Any],
        now: Date
    ) throws -> (mutations: [WallpaperPlistMutation], diagnostics: [WallpaperDiagnostic]) {
        guard let configuration = Data(base64Encoded: payload.base64Configuration) else {
            throw WallpaperError.plistUpdateFailed(keyPath: allDisplaysKey)
        }
        let choice: [String: Any] = [
            "Configuration": configuration,
            "Files": [Any](),
            "Provider": payload.providerIdentifier
        ]
        let allDisplays = plist[allDisplaysKey] as? [String: Any]
        var mutations: [WallpaperPlistMutation] = []
        var diagnostics: [WallpaperDiagnostic] = []

        switch target {
        case .allDisplays:
            mutations.append(WallpaperPlistMutation(
                keyPath: allDisplaysKey,
                value: .xml(try xmlFragment(linkedEntry(choice: choice, reusing: allDisplays, at: now))),
                isRequired: true,
                purpose: "aerial for all displays"
            ))
            if let systemDefault = plist[systemDefaultKey] as? [String: Any] {
                mutations.append(WallpaperPlistMutation(
                    keyPath: systemDefaultKey,
                    value: .xml(try xmlFragment(linkedEntry(choice: choice, reusing: systemDefault, at: now))),
                    isRequired: false,
                    purpose: "system default aerial"
                ))
            }

        case .display(let displayUUID):
            var displays = plist[displaysKey] as? [String: Any] ?? [:]
            if let allDisplays {
                // Leaving all-displays mode: keep every other display on the
                // wallpaper it shows now instead of falling back to a default.
                for other in connectedDisplayUUIDs where other != displayUUID && displays[other] == nil {
                    displays[other] = allDisplays
                }
                diagnostics.append(WallpaperDiagnostic(
                    severity: .info,
                    message: "Switching Index.plist from one wallpaper everywhere to per-display entries.",
                    recoveryHint: nil
                ))
            }
            displays[displayUUID] = linkedEntry(choice: choice, reusing: displays[displayUUID] ?? allDisplays, at: now)
            mutations.append(WallpaperPlistMutation(
                keyPath: displaysKey,
                value: .xml(try xmlFragment(displays)),
                isRequired: true,
                purpose: "per-display aerial"
            ))

            if var spaces = plist[spacesKey] as? [String: Any] {
                let stale = spaces.filter { references($0.value, display: displayUUID) }.map(\.key)
                if !stale.isEmpty {
                    stale.forEach { spaces.removeValue(forKey: $0) }
                    mutations.append(WallpaperPlistMutation(
                        keyPath: spacesKey,
                        value: .xml(try xmlFragment(spaces)),
                        isRequired: true,
                        purpose: "drop Space entries derived from the old per-display wallpaper"
                    ))
                }
            }

            // Last, so a failed write above leaves the all-displays wallpaper in charge.
            if allDisplays != nil {
                mutations.append(WallpaperPlistMutation(
                    keyPath: allDisplaysKey,
                    value: .string(nullValue),
                    isRequired: true,
                    purpose: "enable per-display entries"
                ))
            }
        }
        return (mutations, diagnostics)
    }

    /// The aerial a display (or every display, for nil) is configured to show.
    /// Nil when the store can't answer for that scope, so callers reassert.
    static func currentAssetID(in plist: [String: Any], displayUUID: String?) -> String? {
        if let allDisplays = plist[allDisplaysKey] as? [String: Any] {
            return assetID(inEntry: allDisplays)
        }
        guard let displayUUID else { return nil }
        let spaceEntries = (plist[spacesKey] as? [String: Any] ?? [:]).values.compactMap {
            (($0 as? [String: Any])?[displaysKey] as? [String: Any])?[displayUUID]
        }
        if !spaceEntries.isEmpty {
            let assetIDs = Set(spaceEntries.map(assetID(inEntry:)))
            return assetIDs.count == 1 ? assetIDs.first ?? nil : nil
        }
        return assetID(inEntry: (plist[displaysKey] as? [String: Any])?[displayUUID])
    }

    static func linkedEntry(choice: [String: Any], reusing existing: Any?, at date: Date) -> [String: Any] {
        var content: [String: Any] = ["Choices": [choice], "Shuffle": nullValue]
        let existingContent = ((existing as? [String: Any])?["Linked"] as? [String: Any])?["Content"] as? [String: Any]
        if let options = existingContent?["EncodedOptionValues"] {
            content["EncodedOptionValues"] = options
        }
        return ["Type": "linked", "Linked": ["Content": content, "LastSet": date, "LastUse": date]]
    }

    static func assetID(inEntry entry: Any?) -> String? {
        guard let entry = entry as? [String: Any] else { return nil }
        let sections = (entry["Type"] as? String) == "individual" ? ["Desktop", "Linked"] : ["Linked", "Desktop"]
        for section in sections {
            guard let choices = ((entry[section] as? [String: Any])?["Content"] as? [String: Any])?["Choices"] as? [Any],
                  let choice = choices.first as? [String: Any] else { continue }
            guard choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
                  let data = choice["Configuration"] as? Data,
                  let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return nil
            }
            return configuration["assetID"] as? String
        }
        return nil
    }

    static func xmlFragment(_ value: Any) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        let xml = String(decoding: data, as: UTF8.self)
        guard let start = xml.range(of: "<plist version=\"1.0\">"),
              let end = xml.range(of: "</plist>", options: .backwards) else {
            throw WallpaperError.plistUpdateFailed(keyPath: "xml")
        }
        return xml[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func references(_ space: Any, display displayUUID: String) -> Bool {
        ((space as? [String: Any])?[displaysKey] as? [String: Any])?[displayUUID] != nil
    }
}

/// Service for changing macOS aerial video wallpapers.
/// Works by editing ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist.
final class WallpaperService: @unchecked Sendable {

    static let shared = WallpaperService()

    private enum Constants {
        static let aerialProviderIdentifier = "com.apple.wallpaper.choice.aerials"
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

    private static var defaultVideosDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.apple.wallpaper")
            .appendingPathComponent("aerials")
            .appendingPathComponent("videos")
    }

    private let videosDirectoryURL: URL
    private let downloadFile: @Sendable (URL) async throws -> (URL, URLResponse)

    private convenience init() {
        self.init(videosDirectoryURL: Self.defaultVideosDirectoryURL) {
            try await URLSession.shared.download(from: $0)
        }
    }

    init(videosDirectoryURL: URL,
         downloadFile: @escaping @Sendable (URL) async throws -> (URL, URLResponse)) {
        self.videosDirectoryURL = videosDirectoryURL
        self.downloadFile = downloadFile
    }

    /// Download an aerial video to the local videos directory.
    func downloadAerial(assetID: String, from url: URL) async throws {
        try await downloadAerial(assetID: assetID, from: url, replacingExisting: false)
    }

    /// Download a fresh copy of an aerial, replacing an existing local video
    /// only after the new download succeeds.
    func redownloadAerial(assetID: String, from url: URL) async throws {
        try await downloadAerial(assetID: assetID, from: url, replacingExisting: true)
    }

    private func downloadAerial(
        assetID: String,
        from url: URL,
        replacingExisting: Bool
    ) async throws {
        try Task.checkCancellation()
        let destination = videoURL(assetID: assetID)

        // Already downloaded
        guard replacingExisting || !FileManager.default.fileExists(atPath: destination.path) else { return }

        // Ensure videos directory exists
        try FileManager.default.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)

        #if DEBUG
        print("[WallpaperService] Downloading aerial \(assetID) from \(url)")
        #endif

        let (tempURL, response) = try await downloadFile(url)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WallpaperError.downloadFailed(assetID: assetID)
        }

        // Preserve the working copy until the fresh download has completed.
        do {
            if replacingExisting, FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }
            #if DEBUG
            print("[WallpaperService] \(replacingExisting ? "Redownloaded" : "Downloaded") aerial \(assetID)")
            #endif
        } catch {
            // A concurrent normal download may have completed first.
            guard !replacingExisting,
                  FileManager.default.fileExists(atPath: destination.path) else {
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
        plistData: Data,
        displayUUIDMapping: [String: String] = [:],
        connectedDisplayUUIDs: [String] = [],
        now: Date = Date()
    ) throws -> WallpaperOperationPlan {
        let targetUUID = displayUUID.map { displayUUIDMapping[$0] ?? $0 }
        let payload = try WallpaperProviderConfigurationPayload(
            assetID: assetID,
            providerIdentifier: Constants.aerialProviderIdentifier
        )
        let target = targetUUID.map { WallpaperTargetSelection.display(uuid: $0) } ?? .allDisplays
        var diagnostics: [WallpaperDiagnostic] = []
        let parsed = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        let plist = parsed as? [String: Any] ?? [:]
        if parsed == nil || plist.isEmpty {
            diagnostics.append(WallpaperDiagnostic(
                severity: .warning,
                message: "Index.plist could not be read as a dictionary; writing complete entries.",
                recoveryHint: "Change the wallpaper in System Settings to regenerate a valid wallpaper plist."
            ))
        }
        let layout = try WallpaperStoreLayout.plan(
            payload: payload, target: target, connectedDisplayUUIDs: connectedDisplayUUIDs,
            plist: plist, now: now)
        return WallpaperOperationPlan(
            target: target,
            payload: payload,
            mutations: layout.mutations,
            restartSequence: .directIndexPlistMutation,
            diagnostics: diagnostics + layout.diagnostics
        )
    }

    /// Set wallpaper by asset ID for all displays.
    /// - Parameter assetID: UUID of the aerial wallpaper (e.g., "4C108785-A7BA-422E-9C79-B0129F1D5550")
    @MainActor
    func setWallpaper(assetID: String) async throws {
        try await setWallpaper(assetID: assetID, displayUUID: nil)
    }

    /// Set wallpaper by asset ID for a specific display or all displays.
    /// - Parameters:
    ///   - assetID: UUID of the aerial wallpaper
    ///   - displayUUID: UUID of the display to set wallpaper for, or nil for all displays
    @MainActor
    static var isChangingWallpaper: Bool { changeGate.isBusy }

    @MainActor
    static func waitForPendingChanges() async {
        try? await changeGate.perform {}
    }

    @MainActor
    private static let changeGate = WallpaperChangeGate()

    @MainActor
    func setWallpaper(assetID: String, displayUUID: String?) async throws {
        try await setWallpaper(assetID: assetID, displayUUID: displayUUID, smoothChanges: true)
    }

    @MainActor
    func setWallpaper(assetID: String, displayUUID: String?, smoothChanges: Bool) async throws {
        try await Self.changeGate.perform {
            guard FileManager.default.fileExists(atPath: indexPlistURL.path) else {
                throw WallpaperError.plistNotFound
            }
            guard isAerialDownloaded(assetID: assetID) else {
                throw WallpaperError.aerialNotDownloaded(assetID: assetID)
            }
            // Snapshot before any process is stopped; recovery uses the exact
            // configuration, including custom providers and per-Space entries.
            let original = try Data(contentsOf: indexPlistURL)
            var displayUUIDMapping: [String: String] = [:]
            if let displayUUID {
                guard let nativeUUID = DisplayManager.shared.getWallpaperDisplayUUID(for: displayUUID) else {
                    throw WallpaperError.noMainScreen
                }
                displayUUIDMapping[displayUUID] = nativeUUID
            }
            let plan = try planAerialWallpaperChange(assetID: assetID, displayUUID: displayUUID,
                plistData: original, displayUUIDMapping: displayUUIDMapping,
                connectedDisplayUUIDs: DisplayManager.shared.connectedWallpaperDisplayUUIDs())
            logDiagnostics(plan.diagnostics)
            try await WallpaperTransition.shared.perform(videoURL: videoURL(assetID: assetID), displayUUID: displayUUID, smoothChanges: smoothChanges) {
                // Process waits and plist tools must not block AppKit's cover rendering.
                try await Task.detached { [self] in
                    killWallpaperProcesses()
                    try await Task.sleep(nanoseconds: UInt64(Constants.preMutationDelay * 1_000_000_000))
                    try applyMutations(plan.mutations)
                    forceWallpaperReload()
                }.value
            } restore: { [self] in
                try await Task.detached { [self] in
                    killWallpaperProcesses()
                    try await Task.sleep(nanoseconds: UInt64(Constants.preMutationDelay * 1_000_000_000))
                    try original.write(to: indexPlistURL, options: .atomic)
                    forceWallpaperReload()
                }.value
            }
        }
    }

    /// Set a supported still image on all displays, or one selected display.
    @MainActor
    func setCustomWallpaper(path: String) throws {
        try setCustomWallpaper(path: path, displayUUID: nil)
    }

    @MainActor
    func setCustomWallpaper(path: String, displayUUID: String?) throws {
        let url = try validateCustomWallpaper(path: path)
        try WallpaperTransition.shared.ensureRecovered()
        guard !Self.changeGate.isBusy else { throw WallpaperError.transitionInProgress }
        try setStaticWallpaper(url: url, displayUUID: displayUUID)
    }

    /// Validation stays fixture-safe; unit tests must never invoke NSWorkspace.
    @discardableResult
    func validateCustomWallpaper(path: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: path) else {
            throw WallpaperError.customFileNotFound(path: path)
        }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if ["heic", "jpg", "jpeg", "png", "tiff", "bmp"].contains(ext) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) == 1,
                  CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
                throw WallpaperError.customImageUnreadable
            }
            return url
        } else if ["mov", "mp4", "m4v"].contains(ext) {
            throw WallpaperError.customVideoNotSupported
        } else {
            throw WallpaperError.unsupportedFormat(ext: ext)
        }
    }

    @MainActor
    private func screens(for displayUUID: String?) -> [NSScreen] {
        NSScreen.screens.filter { screen in
            guard let displayUUID else { return true }
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return DisplayManager.shared.getDisplayUUID(displayID: number.uint32Value) == displayUUID
        }
    }

    @MainActor
    private func setStaticWallpaper(url: URL, displayUUID: String?) throws {
        let workspace = NSWorkspace.shared
        let screens = screens(for: displayUUID)
        guard !screens.isEmpty else { throw WallpaperError.noMainScreen }
        for screen in screens { try workspace.setDesktopImageURL(url, for: screen, options: [:]) }
        #if DEBUG
        print("[WallpaperService] Set static wallpaper: \(url.lastPathComponent)")
        #endif
    }

    /// Get the aerial shown on every display without mutating Index.plist.
    func getCurrentAssetID() throws -> String? {
        try getCurrentAssetID(displayUUID: nil)
    }

    /// Get the aerial a display is configured to show, or the one shown on
    /// every display for nil. Nil when Index.plist can't answer for that scope.
    func getCurrentAssetID(displayUUID: String?) throws -> String? {
        guard let data = FileManager.default.contents(atPath: indexPlistURL.path),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        var nativeUUID: String?
        if let displayUUID {
            guard let uuid = DisplayManager.shared.getWallpaperDisplayUUID(for: displayUUID) else { return nil }
            nativeUUID = uuid
        }
        return WallpaperStoreLayout.currentAssetID(in: plist, displayUUID: nativeUUID)
    }

    /// Whether every targeted screen currently shows the still image at `path`.
    @MainActor
    func isShowingCustomWallpaper(path: String, displayUUID: String?) -> Bool {
        let expected = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return screens(for: displayUUID).allSatisfy { screen in
            NSWorkspace.shared.desktopImageURL(for: screen)?.resolvingSymlinksInPath().path == expected
        }
    }

    private func videoURL(assetID: String) -> URL {
        videosDirectoryURL.appendingPathComponent("\(assetID).mov")
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
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            #if DEBUG
            print("[WallpaperService] Could not launch killall: \(error)")
            #endif
        }
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
    case transitionInProgress
    case plistNotFound
    case plistUpdateFailed(keyPath: String)
    case agentRestartFailed
    case customFileNotFound(path: String)
    case customVideoNotSupported
    case customImageUnreadable
    case unsupportedFormat(ext: String)
    case noMainScreen
    case aerialNotDownloaded(assetID: String)
    case downloadFailed(assetID: String)

    var errorDescription: String? {
        switch self {
        case .transitionInProgress:
            return "A wallpaper change is already in progress. Try again when it finishes."
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
        case .customImageUnreadable:
            return "This file could not be read as a still image. Choose a supported image with a single frame."
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
        case .transitionInProgress:
            return "A wallpaper change is already in progress. Try again when it finishes."
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
        case .customImageUnreadable:
            return "Choose a readable HEIC, JPG, JPEG, PNG, TIFF, or BMP still image."
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
