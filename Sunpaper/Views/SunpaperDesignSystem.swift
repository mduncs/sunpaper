import SwiftUI
import AppKit

enum SunpaperSize {
    static let popoverWidth: CGFloat = 328
    static let popoverHeight: CGFloat = 384
    static let scheduleWidth: CGFloat = 780
    static let scheduleHeight: CGFloat = 640
    static let settingsMinWidth: CGFloat = 540
    static let settingsMinHeight: CGFloat = 560
    static let settingsIdealWidth: CGFloat = 580
    static let settingsIdealHeight: CGFloat = 620
}

enum SunpaperColor {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.92, green: 0.70, blue: 0.35, alpha: 1)
            : NSColor(red: 0.56, green: 0.34, blue: 0.08, alpha: 1)
    })
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let separator = Color.primary.opacity(0.1)
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
        .clipShape(RoundedRectangle(cornerRadius: 7))
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

struct InlineNotice: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(SunpaperColor.accent)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action { Button(actionTitle, action: action) }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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
            confirmationTitle: controller.config.enableSolarTracking ? "Use until next change" : "Use wallpaper"
        ) { source in controller.apply(source, displayUUID: displayUUID) }
    }
}
