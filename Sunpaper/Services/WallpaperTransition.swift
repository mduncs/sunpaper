import AppKit
import AVFoundation
import ScreenCaptureKit

/// Serializes manual changes, scheduled changes, and recovery across every display.
/// Cancellation of a queued request never skips the operation already in flight.
@MainActor
final class WallpaperChangeGate {
    private var occupied = false
    var isBusy: Bool { occupied }
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform(_ operation: () async throws -> Void) async throws {
        if occupied {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            occupied = true
        }
        defer {
            if waiters.isEmpty { occupied = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await operation()
    }
}

enum WallpaperTransitionError: LocalizedError {
    case capturePermission, unavailableDesktop, referenceUnavailable, notReady, recoveryFailed, uncoveredRecoveryFailed

    var errorDescription: String? {
        switch self {
        case .capturePermission:
            return "Allow screen capture in Settings → Smooth changes, or turn smoothing off to change wallpapers without it. Your wallpaper has not been changed."
        case .unavailableDesktop:
            return "The desktop is unavailable or its displays changed. Try again after unlocking your Mac."
        case .referenceUnavailable:
            return "Sunpaper could not read the downloaded wallpaper video. Download it again and retry."
        case .notReady:
            return "The new wallpaper did not become ready. The previous wallpaper was restored."
        case .recoveryFailed:
            return "macOS has not restored the desktop yet. Sunpaper is keeping the previous picture visible. Keep Sunpaper open and retry restoration in Settings → Smooth changes."
        case .uncoveredRecoveryFailed:
            return "The wallpaper change failed and its previous configuration couldn’t be restored. Try again, or choose a wallpaper in macOS Wallpaper settings."
        }
    }
}

/// Low-resolution, spatial RGB comparison, independent of scene color or asset ID.
/// Reference images are aspect-filled to match the native desktop. No captured
/// images are saved to disk. Uniform frames are deliberately inconclusive: a
/// flat gray/black frame cannot establish that the renderer loaded the asset.
struct WallpaperFrameSignature {
    let values: [Double]
    let centered: [Double]
    let energy: Double

    init(image: CGImage, aspectRatio: CGFloat? = nil) {
        let width = 32, height = 24
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ratio = aspectRatio ?? CGFloat(image.width) / CGFloat(image.height)
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)
        var crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if imageRatio > ratio {
            crop.size.width = crop.height * ratio
            crop.origin.x = (CGFloat(image.width) - crop.width) / 2
        } else {
            crop.size.height = crop.width / ratio
            crop.origin.y = (CGFloat(image.height) - crop.height) / 2
        }
        let cropped = image.cropping(to: crop) ?? image
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.init(rgb: stride(from: 0, to: bytes.count, by: 4).flatMap { i in
            (0..<3).map { Double(bytes[i + $0]) / 255 }
        })
    }

    init(rgb: [Double]) {
        precondition(!rgb.isEmpty && rgb.count.isMultiple(of: 3))
        values = rgb
        let count = Double(rgb.count / 3)
        let means = (0..<3).map { channel in
            stride(from: channel, to: rgb.count, by: 3).reduce(0.0) { $0 + rgb[$1] } / count
        }
        centered = rgb.enumerated().map { $0.element - means[$0.offset % 3] }
        energy = centered.reduce(0) { $0 + $1 * $1 }
    }

    var hasDetail: Bool { energy / Double(values.count) > 0.000064 }

    func matches(_ reference: Self) -> Bool {
        guard values.count == reference.values.count, hasDetail, reference.hasDetail else { return false }
        let difference = zip(values, reference.values).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(values.count)
        let correlation = zip(centered, reference.centered).reduce(0.0) { $0 + $1.0 * $1.1 } / sqrt(energy * reference.energy)
        if (difference < 0.035 && correlation > 0.85) || (difference < 0.14 && correlation > 0.88) { return true }
        // macOS can dim an inactive display's wallpaper. Fit one exposure
        // multiplier, not independent colors: the spatial structure and color
        // relationships must still match. This also supports genuinely dark
        // scenes without accepting the uniform renderer placeholder.
        let referencePower = reference.values.reduce(0.0) { $0 + $1 * $1 }
        let exposure = zip(values, reference.values).reduce(0.0) { $0 + $1.0 * $1.1 } / referencePower
        guard (0.35...1.3).contains(exposure), correlation > 0.94 else { return false }
        let adjustedDifference = zip(values, reference.values).reduce(0.0) { $0 + abs($1.0 / exposure - $1.1) } / Double(values.count)
        return adjustedDifference < 0.055
    }
}

struct WallpaperReadiness {
    private(set) var consecutiveMatches = 0
    mutating func observe(allDisplaysMatch: Bool) -> Bool {
        consecutiveMatches = allDisplaysMatch ? consecutiveMatches + 1 : 0
        return consecutiveMatches >= 3
    }
}

/// Tracks each display's reload separately: an already-visible matching image
/// cannot establish that the restart has completed.
struct WallpaperReloadReadiness {
    let originals: [CGDirectDisplayID: WallpaperFrameSignature]
    let expected: [CGDirectDisplayID: [WallpaperFrameSignature]]
    private var departed: Set<CGDirectDisplayID> = []
    private var readiness = WallpaperReadiness()

    init(originals: [CGDirectDisplayID: WallpaperFrameSignature],
         expected: [CGDirectDisplayID: [WallpaperFrameSignature]]) {
        self.originals = originals
        self.expected = expected
    }

    mutating func observe(_ frames: [CGDirectDisplayID: WallpaperFrameSignature]) -> Bool {
        guard !originals.isEmpty, Set(frames.keys) == Set(originals.keys), Set(expected.keys) == Set(originals.keys) else {
            return readiness.observe(allDisplaysMatch: false)
        }
        for (id, frame) in frames {
            if let original = originals[id], !frame.matches(original) { departed.insert(id) }
        }
        let matches = frames.allSatisfy { id, frame in
            expected[id]?.contains(where: { frame.matches($0) }) == true
        }
        return readiness.observe(allDisplaysMatch: departed.count == originals.count && matches)
    }
}

/// Recovery must finish even when a scheduler or preview task was cancelled.
@MainActor
enum WallpaperTransitionTransaction {
    static func perform(change: () async throws -> Void,
                        finish: () async throws -> Void,
                        recover: @escaping @MainActor () async throws -> Void,
                        recoveryFailure: WallpaperTransitionError = .recoveryFailed) async throws {
        try Task.checkCancellation()
        do {
            try await change()
            try Task.checkCancellation()
            try await finish()
        } catch {
            let originalError = error
            let recovery = Task { @MainActor in try await recover() }
            do { try await recovery.value }
            catch { throw recoveryFailure }
            throw originalError
        }
    }
}

@MainActor
final class WallpaperTransition: ObservableObject {
    static let shared = WallpaperTransition()
    @Published private(set) var needsRecovery = false
    @Published private(set) var recoveryError: String?
    @Published private(set) var isRecovering = false
    private var retainedRecovery: (() async throws -> Void)?

    private struct Desktop {
        let id: CGDirectDisplayID
        let frame: CGRect
        let screen: NSScreen
        let window: SCWindow
    }

    private final class Cover: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
        let original: CGImage
        let desktop: Desktop

        init(desktop: Desktop, image: CGImage) {
            self.desktop = desktop
            original = image
            super.init(contentRect: desktop.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            title = "Sunpaper Wallpaper Transition"
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ignoresMouseEvents = true
            isOpaque = true
            backgroundColor = .black
            hasShadow = false
            animationBehavior = .none
            isReleasedWhenClosed = false
            let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            contentView = view
            show(image)
        }

        func show(_ image: CGImage) {
            contentView?.subviews.forEach { $0.removeFromSuperview() }
            (contentView as? NSImageView)?.image = NSImage(cgImage: image, size: frame.size)
            displayIfNeeded()
        }
    }

    static var hasCapturePermission: Bool { CGPreflightScreenCaptureAccess() }

    static func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            guard application != nil, error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Called only by the explicit Settings button, never by the scheduler.
    static func requestCapturePermission() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func retryRecovery() async {
        guard !isRecovering, let retainedRecovery else { return }
        isRecovering = true
        defer { isRecovering = false }
        do {
            try await retainedRecovery()
            self.retainedRecovery = nil
            needsRecovery = false
            recoveryError = nil
        } catch {
            recoveryError = WallpaperTransitionError.recoveryFailed.localizedDescription
        }
    }

    func ensureRecovered() throws {
        guard !needsRecovery else { throw WallpaperTransitionError.recoveryFailed }
    }

    func perform(videoURL: URL, displayUUID: String?, smoothChanges: Bool = true,
                 change: () async throws -> Void,
                 restore: @escaping @MainActor () async throws -> Void) async throws {
        // An explicit opt-out never abandons a cover retained for recovery.
        try ensureRecovered()
        if !smoothChanges {
            // No screen capture, permission check, overlay or visual-readiness
            // polling. Still reject an unreadable video before touching macOS.
            _ = try await referenceFrames(videoURL, firstFrameOnly: true)
            try await WallpaperTransitionTransaction.perform(
                change: change, finish: {}, recover: restore,
                recoveryFailure: .uncoveredRecoveryFailed)
            return
        }
        guard Self.hasCapturePermission else { throw WallpaperTransitionError.capturePermission }
        let references = try await referenceFrames(videoURL)
        try Task.checkCancellation()
        let desktops = try await discoverDesktops()
        // A targeted mutation still restarts the shared agent: cover ALL displays.
        if let displayUUID, !desktops.contains(where: {
            DisplayManager.shared.getDisplayUUID(displayID: $0.id) == displayUUID
        }) { throw WallpaperTransitionError.unavailableDesktop }
        var covers: [Cover] = []
        var retainCovers = false
        // The transaction completes recovery before throwing. Only a failed
        // recovery may keep windows alive beyond this operation.
        defer { if !retainCovers { for cover in covers { cover.close() } } }
        var expected: [CGDirectDisplayID: [WallpaperFrameSignature]] = [:]
        for desktop in desktops {
            let image = try await capture(desktop.window, scale: desktop.screen.backingScaleFactor)
            guard WallpaperFrameSignature(image: image).hasDetail else {
                throw WallpaperTransitionError.unavailableDesktop
            }
            covers.append(Cover(desktop: desktop, image: image))
            let isTarget = displayUUID == nil || DisplayManager.shared.getDisplayUUID(displayID: desktop.id) == displayUUID
            expected[desktop.id] = isTarget
                ? references.map { WallpaperFrameSignature(image: $0, aspectRatio: desktop.frame.width / desktop.frame.height) }
                : [WallpaperFrameSignature(image: image)]
        }
        try Task.checkCancellation()
        try validateLayout(covers)
        for cover in covers { cover.orderFrontRegardless(); cover.displayIfNeeded() }
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 200_000_000)
        try validateLayout(covers)
        try Task.checkCancellation()
        // Once visible, every error path must either reveal a verified desktop or
        // retain the covers. Never defer an unconditional close over a mutation.
        let recovery: @MainActor () async throws -> Void = { [self, covers] in
            for cover in covers { cover.show(cover.original) }
            CATransaction.flush()
            let originals = Dictionary(uniqueKeysWithValues: covers.map {
                ($0.desktop.id, [WallpaperFrameSignature(image: $0.original)])
            })
            let images = try await observeReload(covers: covers, expected: originals, change: restore)
            try await reveal(covers: covers, images: images, expected: originals)
        }
        var replacementImages: [CGDirectDisplayID: CGImage] = [:]
        do {
            try await WallpaperTransitionTransaction.perform(change: {
                replacementImages = try await observeReload(covers: covers, expected: expected, change: change)
            }, finish: {
                try await reveal(covers: covers, images: replacementImages, expected: expected)
            }, recover: recovery)
        } catch WallpaperTransitionError.recoveryFailed {
            // No polling loop left running. The explicit Settings retry owns the
            // next attempt, with the exact pre-change configuration retained.
            retainCovers = true
            retainedRecovery = recovery
            needsRecovery = true
            throw WallpaperTransitionError.recoveryFailed
        }
    }

    private func referenceFrames(_ url: URL, firstFrameOnly: Bool = false) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw WallpaperTransitionError.referenceUnavailable }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        var frames: [CGImage] = []
        for seconds in [0.0, 0.5, 1, 3, 5, 10, 20, 30, 45, 60] where seconds < duration {
            try Task.checkCancellation()
            if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                frames.append(result.image)
                if firstFrameOnly { break }
            }
        }
        guard !frames.isEmpty else { throw WallpaperTransitionError.referenceUnavailable }
        return frames
    }

    private func discoverDesktops() async throws -> [Desktop] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var desktops: [Desktop] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }),
                  let window = content.windows.first(where: {
                      $0.owningApplication?.bundleIdentifier == "com.apple.WindowManager" &&
                      $0.title == "Wallpaper" && $0.frame == display.frame &&
                      $0.windowLayer < Int(CGWindowLevelForKey(.desktopWindow))
                  }) else { throw WallpaperTransitionError.unavailableDesktop }
            desktops.append(Desktop(id: id, frame: display.frame, screen: screen, window: window))
        }
        guard !desktops.isEmpty else { throw WallpaperTransitionError.unavailableDesktop }
        return desktops
    }

    private func validateLayout(_ covers: [Cover]) throws {
        let screens = NSScreen.screens
        guard screens.count == covers.count, covers.allSatisfy({ cover in
            screens.contains { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == cover.desktop.id &&
                screen.frame == cover.frame
            }
        }) else { throw WallpaperTransitionError.unavailableDesktop }
    }

    private func capture(_ window: SCWindow, scale: CGFloat = 1) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        // This filter captures ONLY the native wallpaper, never other apps or
        // our own cover. https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }

    private func captureImages(covers: [Cover]) async throws -> [CGDirectDisplayID: CGImage] {
        try validateLayout(covers)
        let desktops = try await discoverDesktops() // Window IDs can change after an agent restart.
        var images: [CGDirectDisplayID: CGImage] = [:]
        for desktop in desktops {
            images[desktop.id] = try await capture(desktop.window, scale: desktop.screen.backingScaleFactor)
        }
        return images
    }

    private func allMatch(_ images: [CGDirectDisplayID: CGImage],
                          expected: [CGDirectDisplayID: [WallpaperFrameSignature]]) -> Bool {
        guard Set(images.keys) == Set(expected.keys) else { return false }
        return images.allSatisfy { id, image in
            let signature = WallpaperFrameSignature(image: image)
            return expected[id]?.contains(where: { signature.matches($0) }) == true
        }
    }

    private func observeReload(covers: [Cover], expected: [CGDirectDisplayID: [WallpaperFrameSignature]],
                               change: () async throws -> Void) async throws -> [CGDirectDisplayID: CGImage] {
        // Start sampling BEFORE the restart, not after it. A similar-looking old
        // scene must not count as the new wallpaper before the renderer reloads.
        let readinessTask = Task { @MainActor in
            try await waitUntilReady(covers: covers, expected: expected)
        }
        defer { readinessTask.cancel() }
        return try await withTaskCancellationHandler {
            try await change()
            try Task.checkCancellation()
            return try await readinessTask.value
        } onCancel: {
            readinessTask.cancel()
        }
    }

    private func waitUntilReady(covers: [Cover], expected: [CGDirectDisplayID: [WallpaperFrameSignature]]) async throws -> [CGDirectDisplayID: CGImage] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        let originals = Dictionary(uniqueKeysWithValues: covers.map {
            ($0.desktop.id, WallpaperFrameSignature(image: $0.original))
        })
        var readiness = WallpaperReloadReadiness(originals: originals, expected: expected)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let images = try? await captureImages(covers: covers) {
                if readiness.observe(images.mapValues { WallpaperFrameSignature(image: $0) }) {
                    return images
                }
            } else {
                _ = readiness.observe([:])
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw WallpaperTransitionError.notReady
    }

    private func reveal(covers: [Cover], images: [CGDirectDisplayID: CGImage],
                        expected: [CGDirectDisplayID: [WallpaperFrameSignature]]) async throws {
        var incoming: [NSImageView] = []
        for cover in covers {
            guard let image = images[cover.desktop.id], let content = cover.contentView else {
                throw WallpaperTransitionError.notReady
            }
            let view = NSImageView(frame: content.bounds)
            view.image = NSImage(cgImage: image, size: cover.frame.size)
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.alphaValue = 0
            content.addSubview(view)
            incoming.append(view)
        }
        // Fade pictures INSIDE fully opaque windows. Fading the window itself
        // caused a measured black dip in the prototype.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for view in incoming { view.alphaValue = 1 }
        } else {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 1
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for view in incoming { view.animator().alphaValue = 1 }
            }
        }
        try Task.checkCancellation()
        let latest = try await captureImages(covers: covers)
        guard allMatch(latest, expected: expected) else {
            throw WallpaperTransitionError.notReady
        }
        for cover in covers { if let image = latest[cover.desktop.id] { cover.show(image) } }
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 100_000_000)
        try validateLayout(covers)
        for cover in covers { cover.orderOut(nil); cover.close() }
    }
}
