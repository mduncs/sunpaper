import SwiftUI
import AppKit
import CoreImage
import ImageIO

enum SunpaperSize {
    static let popoverWidth: CGFloat = 376
    static let popoverHeight: CGFloat = 470
    static let scheduleWidth: CGFloat = 780
    static let scheduleHeight: CGFloat = 720
    static let scheduleMinWidth: CGFloat = 720
    static let scheduleMinHeight: CGFloat = 600
    static let settingsMinWidth: CGFloat = 540
    static let settingsMinHeight: CGFloat = 560
    static let settingsIdealWidth: CGFloat = 580
    static let settingsIdealHeight: CGFloat = 620
}

enum SunpaperColor {
    /// The person's system accent (the asset color only applies under Multicolor).
    static let accent = Color.accentColor
    /// Text and symbols drawn on an accent fill.
    static let onAccent = Color.white
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let separator = Color.primary.opacity(0.1)
}

/// Sky colors for a local day. Ambient surfaces are always drawn dark, so these do not vary by appearance.
enum SunpaperSky {
    static let night = Color(red: 0.10, green: 0.12, blue: 0.24)
    static let twilight = Color(red: 0.42, green: 0.33, blue: 0.62)
    static let glow = Color(red: 0.94, green: 0.52, blue: 0.43)
    static let gold = Color(red: 0.98, green: 0.77, blue: 0.42)
    static let day = Color(red: 0.53, green: 0.77, blue: 0.95)

    /// Night, dawn glow, day and dusk placed at sunrise and sunset (fractions of the day).
    static func gradient(sunrise: Double?, sunset: Double?) -> LinearGradient {
        guard let rise = sunrise, let set = sunset, rise < set else {
            return LinearGradient(colors: [night, twilight, day, twilight, night], startPoint: .leading, endPoint: .trailing)
        }
        let stops: [(Double, Color)] = [
            (0, night), (rise - 0.05, night), (rise - 0.02, twilight), (rise, glow), (rise + 0.025, gold), (rise + 0.07, day),
            (set - 0.07, day), (set - 0.025, gold), (set, glow), (set + 0.02, twilight), (set + 0.05, night), (1, night)
        ]
        let sorted = stops.map { Gradient.Stop(color: $0.1, location: min(max($0.0, 0), 1)) }.sorted { $0.location < $1.location }
        return LinearGradient(stops: sorted, startPoint: .leading, endPoint: .trailing)
    }
}

@MainActor
func wallpaperName(_ source: WallpaperSource?) -> String {
    guard let source else { return "Desktop wallpaper" }
    switch source {
    case .builtIn(let id):
        return BuiltInWallpapers.name(for: id) ?? AerialCatalog.shared.asset(for: id)?.displayName ?? "Apple wallpaper"
    case .custom(let path): return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    case .none: return "Choose wallpaper"
    }
}

struct WallpaperThumbnail: View {
    let source: WallpaperSource?
    var size = CGSize(width: 84, height: 54)
    var cornerRadius: CGFloat = 7
    @ObservedObject private var catalog = AerialCatalog.shared

    var body: some View {
        Group {
            switch source {
            case .builtIn(let id):
                AsyncThumbnail(url: catalog.asset(for: id)?.thumbnailURL, size: size)
            case .custom(let path):
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else { placeholder }
            case Optional.none, .some(.none): placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.primary.opacity(0.055)
            Image(systemName: "photo").font(.title3).foregroundStyle(.tertiary)
        }
    }
}

extension Trigger {
    var readableName: String {
        switch self {
        case .fixed(let hour, let minute):
            let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        case .solar(let event, let offset):
            guard offset != 0 else { return event.displayName }
            let minutes = Int(abs(offset) / 60)
            let hours = minutes / 60
            var parts: [String] = []
            if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
            if minutes % 60 > 0 { parts.append("\(minutes % 60) min") }
            return "\(parts.joined(separator: " ")) \(offset < 0 ? "before" : "after") \(event.displayName.lowercased())"
        }
    }

    var symbolName: String {
        switch self {
        case .fixed: return "clock"
        case .solar(let event, _): return event.icon
        }
    }
}

extension WallpaperOverrideDuration {
    var title: String {
        switch self {
        case .nextChange: return "Until next change"
        case .oneHour: return "For one hour"
        case .tomorrow: return "Until tomorrow"
        }
    }
}

// MARK: - Status

enum SunpaperStatusTone {
    case following, paused, temporary, busy, attention

    var color: Color {
        switch self {
        case .following: return SunpaperSky.gold
        case .paused: return Color.white.opacity(0.55)
        case .temporary, .busy: return SunpaperSky.day
        case .attention: return Color(red: 1, green: 0.47, blue: 0.40)
        }
    }
}

extension SunpaperController {
    var statusTone: SunpaperStatusTone {
        if scheduler.isDownloading || scheduler.isApplying { return .busy }
        if scheduler.lastError != nil { return .attention }
        switch scheduler.playbackMode {
        case .paused: return .paused
        case .temporary: return .temporary
        case .following: return .following
        }
    }
}

/// A status capsule for ambient (always dark) surfaces.
struct StatusPill: View {
    let title: String
    let tone: SunpaperStatusTone
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.color).frame(width: 6, height: 6)
                .shadow(color: tone.color.opacity(0.8), radius: 3)
            Text(title).font(font.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.white.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

// MARK: - Ambient surfaces

/// A blurred, darkened wash of the wallpaper. Thumbnails are small, so the blur is deliberate.
struct AmbientBackdrop: View {
    let source: WallpaperSource?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [SunpaperSky.twilight, SunpaperSky.night], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .saturation(1.15)
            }
            LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.52)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .task(id: source) {
            let loaded = await AmbientImage.blurred(for: source)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}

/// Pre-blurred wallpaper images, so the wash looks the same in windows and offscreen renders.
@MainActor
private enum AmbientImage {
    private static var cache: [String: NSImage] = [:]

    static func blurred(for source: WallpaperSource?) async -> NSImage? {
        let key: String
        let original: CGImage?
        switch source {
        case .builtIn(let id):
            key = id
            guard let url = AerialCatalog.shared.asset(for: id)?.thumbnailURL,
                  let image = await ThumbnailCache.shared.thumbnail(for: url) else { return nil }
            original = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .custom(let path):
            key = path
            guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            original = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320
            ] as CFDictionary)
        case Optional.none, .some(.none):
            return nil
        }
        if let cached = cache[key] { return cached }
        guard let original else { return nil }
        let input = CIImage(cgImage: original)
        let scale = min(1, 240 / max(input.extent.width, 1))
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 7).cropped(to: small.extent)
        guard let output = CIContext().createCGImage(blurred, from: small.extent) else { return nil }
        if cache.count > 24 { cache.removeAll() }
        let image = NSImage(cgImage: output, size: small.extent.size)
        cache[key] = image
        return image
    }
}

extension View {
    /// Dark content over an ambient wallpaper wash, clipped to a card.
    func ambientCard(_ source: WallpaperSource?, cornerRadius: CGFloat = 14) -> some View {
        environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .background(AmbientBackdrop(source: source))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

// MARK: - Day ribbon

/// Today's schedule as a strip of wallpapers over a sky that follows sunrise and sunset.
struct DayRibbon: View {
    @ObservedObject var controller: SunpaperController
    var stripHeight: CGFloat = 40
    var showsLabels = true
    private let gap: CGFloat = 2
    private let labelHeight: CGFloat = 14

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let model = DayRibbonModel(controller: controller)
            VStack(spacing: 6) {
                if showsLabels {
                    track(labelHeight) { width in
                        ZStack {
                            if let rise = model.sunrise { sunMarker("sunrise.fill", model.sunriseText, at: rise, width: width) }
                            if let set = model.sunset { sunMarker("sunset.fill", model.sunsetText, at: set, width: width) }
                        }.frame(width: width, height: labelHeight)
                    }
                }
                track(stripHeight) { width in strip(model, width: width) }
                Capsule().fill(SunpaperSky.gradient(sunrise: model.sunrise, sunset: model.sunset))
                    .frame(height: 4)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                if showsLabels {
                    track(labelHeight) { width in
                        Text("Now · \(model.nowText)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(SunpaperSky.gold)
                            .fixedSize()
                            .position(x: clamped(model.now * width, width: width, inset: 40), y: labelHeight / 2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today’s wallpapers")
            .accessibilityValue(model.summary)
        }
    }

    private func track<Content: View>(_ height: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { proxy in content(proxy.size.width) }.frame(height: height)
    }

    @ViewBuilder
    private func strip(_ model: DayRibbonModel, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if model.segments.isEmpty {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08))
                    .overlay(Text("Changes with times appear here").font(.caption).foregroundStyle(.secondary))
            }
            ForEach(model.segments) { segment in
                WallpaperThumbnail(source: segment.source,
                                   size: CGSize(width: max(segment.length * width - gap, 2), height: stripHeight),
                                   cornerRadius: 5)
                    .offset(x: segment.start * width + gap / 2)
            }
            ZStack(alignment: .top) {
                Capsule().fill(.white).frame(width: 3, height: stripHeight + 8)
                Circle().fill(SunpaperSky.gold).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(y: -3)
            }
            .shadow(color: .black.opacity(0.45), radius: 2)
            .position(x: model.now * width, y: stripHeight / 2)
        }
        .frame(width: width, height: stripHeight)
    }

    private func sunMarker(_ symbol: String, _ text: String, at fraction: Double, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
            Text(text)
        }
        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        .fixedSize()
        .position(x: clamped(fraction * width, width: width, inset: 36), y: labelHeight / 2)
    }

    private func clamped(_ x: CGFloat, width: CGFloat, inset: CGFloat) -> CGFloat {
        min(max(x, inset), max(width - inset, inset))
    }
}

@MainActor
struct DayRibbonModel {
    struct Segment: Identifiable {
        let id: String
        let source: WallpaperSource
        let start: Double
        let length: Double
    }

    let segments: [Segment]
    let now: Double
    let sunrise: Double?
    let sunset: Double?
    let nowText: String
    let sunriseText: String
    let sunsetText: String
    let summary: String

    init(controller: SunpaperController) {
        let date = controller.currentDate
        let day = Calendar.current.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        func fraction(_ time: Date) -> Double { min(max(time.timeIntervalSince(day.start) / day.duration, 0), 1) }
        func text(_ time: Date?) -> String { time?.formatted(date: .omitted, time: .shortened) ?? "" }

        // Solar offsets can move a change into an adjacent calendar day. Resolve
        // those anchor days too, and use the actual preceding change at midnight.
        let marks = [-1, 0, 1].flatMap { offset -> [(slot: TimeSlot, time: Date)] in
            guard let anchorDay = Calendar.current.date(byAdding: .day, value: offset, to: date) else { return [] }
            return controller.slots.filter { $0.isEnabled && $0.source != .none }
                .compactMap { slot in controller.resolvedTime(for: slot.trigger, on: anchorDay).map { (slot: slot, time: $0) } }
        }
            .sorted { $0.time < $1.time }
        let todayMarks = marks.filter { $0.time >= day.start && $0.time < day.end }
        var segments: [Segment] = []
        if let previous = marks.last(where: { $0.time <= day.start }) {
            let end = todayMarks.first.map { fraction($0.time) } ?? 1
            segments.append(Segment(id: "overnight", source: previous.slot.source, start: 0, length: end))
        }
        for (index, mark) in todayMarks.enumerated() {
            let start = fraction(mark.time)
            let end = index + 1 < todayMarks.count ? fraction(todayMarks[index + 1].time) : 1
            segments.append(Segment(id: "\(mark.slot.id)-\(mark.time.timeIntervalSince1970)", source: mark.slot.source, start: start, length: end - start))
        }
        self.segments = segments.filter { $0.length > 0 }

        let sunriseTime = controller.resolvedTime(for: .sunrise(), on: date)
        let sunsetTime = controller.resolvedTime(for: .sunset(), on: date)
        now = fraction(date)
        sunrise = sunriseTime.map(fraction)
        sunset = sunsetTime.map(fraction)
        nowText = text(date)
        sunriseText = text(sunriseTime)
        sunsetText = text(sunsetTime)
        summary = todayMarks.isEmpty
            ? "No timed changes today"
            : todayMarks.map { "\($0.slot.name) at \(text($0.time))" }.joined(separator: ", ")
    }
}

// MARK: - Controls

/// A full-width action. Prominent actions use the accent fill.
struct SunpaperActionButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity).frame(height: height)
            .foregroundStyle(prominent ? SunpaperColor.onAccent : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(SunpaperColor.accent) : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(prominent ? 0 : 0.06)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// A list row that highlights on hover, like a menu item.
struct SunpaperRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverRow: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.06 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}

/// A small tinted symbol tile, as in System Settings.
struct SymbolTile: View {
    let systemName: String
    var color: Color = SunpaperColor.accent
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct InlineNotice: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill").font(.title3).foregroundStyle(SunpaperColor.accent)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action { Button(actionTitle, action: action) }
        }
        .padding(12)
        .background(SunpaperColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SunpaperColor.accent.opacity(0.2)))
        .accessibilityElement(children: .contain)
    }
}

struct ManualWallpaperSheet: View {
    @ObservedObject var controller: SunpaperController
    @State private var draft: WallpaperSource
    @State private var displayUUID: String?
    @State private var title: String
    init(controller: SunpaperController) {
        self.controller = controller
        _draft = State(initialValue: controller.shownSource ?? .none)
        _displayUUID = State(initialValue: controller.scope)
        _title = State(initialValue: controller.scope == nil ? "Use another wallpaper" : "Wallpaper for \(controller.scopeName)")
    }
    var body: some View {
        WallpaperGridPicker(
            selectedSource: $draft,
            title: title,
            confirmationTitle: controller.config.isFollowingSchedule ? "Use until next change" : "Use wallpaper"
        ) { source in controller.apply(source, displayUUID: displayUUID) }
    }
}

/// A quiet capsule for toolbar controls.
struct ToolbarPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.toolbarPill(pressed: configuration.isPressed)
    }
}

extension View {
    func toolbarPill(pressed: Bool = false) -> some View {
        padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(pressed ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
    }
}
