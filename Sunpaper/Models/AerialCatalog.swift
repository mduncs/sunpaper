import Foundation
import SwiftUI

// MARK: - Aerial Asset Model

struct AerialAsset: Identifiable, Codable, Hashable {
    let id: String
    let accessibilityLabel: String
    let previewImage: String?
    let categories: [String]
    let subcategories: [String]?
    let showInTopLevel: Bool
    let includeInShuffle: Bool
    let preferredOrder: Int?
    let localizedNameKey: String?
    let shotID: String?

    // Video URL - uses custom key
    let videoURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accessibilityLabel
        case previewImage
        case categories
        case subcategories
        case showInTopLevel
        case includeInShuffle
        case preferredOrder
        case localizedNameKey
        case shotID
        case videoURL = "url-4K-SDR-240FPS"
    }

    var displayName: String {
        accessibilityLabel
    }

    var thumbnailURL: URL? {
        guard let urlString = previewImage, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var downloadURL: URL? {
        guard let urlString = videoURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}

struct AerialSubcategory: Identifiable, Codable, Hashable {
    let id: String
    let localizedNameKey: String
    let localizedDescriptionKey: String?
    let preferredOrder: Int?
    let previewImage: String?
    let representativeAssetID: String?

    var displayName: String {
        // Extract readable name from key like "AerialSubcategoryTahoe" -> "Tahoe"
        let name = localizedNameKey
            .replacingOccurrences(of: "AerialSubcategory", with: "")
            .replacingOccurrences(of: "Cities", with: "")
        return name.isEmpty ? localizedNameKey : name
    }
}

struct AerialCategory: Identifiable, Codable, Hashable {
    let id: String
    let localizedNameKey: String
    let localizedDescriptionKey: String?
    let preferredOrder: Int?
    let previewImage: String?
    let representativeAssetID: String?
    let subcategories: [AerialSubcategory]?

    var displayName: String {
        // Map known category keys to display names
        switch localizedNameKey {
        case "AerialCategorySpace": return "Space"
        case "AerialCategoryLandscapes": return "Landscape"
        case "AerialCategoryCities": return "Cityscape"
        case "AerialCategoryUnderwater": return "Underwater"
        default:
            // Extract from key like "AerialCategoryLandscapes" -> "Landscapes"
            let name = localizedNameKey.replacingOccurrences(of: "AerialCategory", with: "")
            return name.isEmpty ? localizedNameKey : name
        }
    }

    // Hashable conformance (exclude subcategories for simpler hashing)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AerialCategory, rhs: AerialCategory) -> Bool {
        lhs.id == rhs.id
    }
}

struct EntriesFile: Codable {
    let version: Int
    let localizationVersion: String?
    let initialAssetCount: Int?
    let assets: [AerialAsset]
    let categories: [AerialCategory]?
}

enum AerialCatalogLoadState: Equatable {
    case loading
    case loaded(assetCount: Int, categoryCount: Int)
    case missingManifest(URL)
    case malformedManifest(URL, reason: String)
    case noTopLevelAssets(URL)

    var title: String {
        switch self {
        case .loading:
            return "Loading Aerials"
        case .loaded:
            return "Aerials Loaded"
        case .missingManifest:
            return "Aerial Catalog Not Found"
        case .malformedManifest:
            return "Aerial Catalog Cannot Be Read"
        case .noTopLevelAssets:
            return "No Aerials Available"
        }
    }

    var message: String? {
        switch self {
        case .loading, .loaded:
            return nil
        case .missingManifest:
            return "Sunpaper reads the local aerial catalog that macOS creates after aerial wallpapers are downloaded. Open System Settings > Wallpaper, download an aerial wallpaper, then return here and reload the catalog."
        case .malformedManifest(_, let reason):
            return "Sunpaper found the local aerial catalog, but could not read it. \(reason) Reload after macOS refreshes the Wallpaper catalog."
        case .noTopLevelAssets:
            return "Sunpaper found the local aerial catalog, but it does not list any aerial wallpapers that can be shown here. Download an aerial wallpaper in System Settings > Wallpaper, then reload."
        }
    }

    var systemImage: String {
        switch self {
        case .loading:
            return "hourglass"
        case .loaded:
            return "photo.on.rectangle"
        case .missingManifest:
            return "folder.badge.questionmark"
        case .malformedManifest:
            return "doc.badge.exclamationmark"
        case .noTopLevelAssets:
            return "photo.stack"
        }
    }
}

// MARK: - Aerial Catalog Service

@MainActor
class AerialCatalog: ObservableObject {
    static let shared = AerialCatalog()

    @Published private(set) var assets: [AerialAsset] = []
    @Published private(set) var categories: [AerialCategory] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var error: String?
    @Published private(set) var loadState: AerialCatalogLoadState = .loading

    private var entriesURL: URL {
        // macOS stores aerial wallpaper manifest in user's Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.apple.wallpaper")
            .appendingPathComponent("aerials")
            .appendingPathComponent("manifest")
            .appendingPathComponent("entries.json")
    }

    private init() {
        loadCatalog()
    }

    func loadCatalog() {
        let path = entriesURL.path
        assets = []
        categories = []
        isLoaded = false
        error = nil
        loadState = .loading

        guard FileManager.default.fileExists(atPath: path) else {
            loadState = .missingManifest(entriesURL)
            error = loadState.message
            #if DEBUG
            print("[AerialCatalog] entries.json not found at: \(path)")
            #endif
            return
        }

        do {
            let data = try Data(contentsOf: entriesURL)
            let entries = try JSONDecoder().decode(EntriesFile.self, from: data)

            // Filter to showInTopLevel assets and sort by preferredOrder
            assets = entries.assets
                .filter { $0.showInTopLevel }
                .sorted { ($0.preferredOrder ?? 999) < ($1.preferredOrder ?? 999) }

            categories = (entries.categories ?? []).sorted { ($0.preferredOrder ?? 999) < ($1.preferredOrder ?? 999) }
            isLoaded = true
            loadState = assets.isEmpty
                ? .noTopLevelAssets(entriesURL)
                : .loaded(assetCount: assets.count, categoryCount: categories.count)

            #if DEBUG
            print("[AerialCatalog] Loaded \(assets.count) assets, \(categories.count) categories")
            #endif
        } catch {
            loadState = .malformedManifest(entriesURL, reason: Self.catalogReadFailureMessage(for: error))
            self.error = loadState.message
            #if DEBUG
            print("[AerialCatalog] Error: \(error)")
            #endif
        }
    }

    private static func catalogReadFailureMessage(for error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context):
            return "The manifest data is corrupted at \(codingPathDescription(context.codingPath))."
        case DecodingError.keyNotFound(let key, let context):
            return "The manifest is missing '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case DecodingError.typeMismatch(_, let context):
            return "The manifest contains an unexpected value at \(codingPathDescription(context.codingPath))."
        case DecodingError.valueNotFound(_, let context):
            return "The manifest is missing a value at \(codingPathDescription(context.codingPath))."
        default:
            return error.localizedDescription
        }
    }

    private static func codingPathDescription(_ path: [CodingKey]) -> String {
        let joinedPath = path.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
        return joinedPath.isEmpty ? "the top level" : joinedPath
    }

    func asset(for id: String) -> AerialAsset? {
        assets.first { $0.id == id }
    }

    func assets(in category: String) -> [AerialAsset] {
        assets.filter { $0.categories.contains(category) }
    }

    // Group assets by their primary category
    var assetsByCategory: [(category: AerialCategory, assets: [AerialAsset])] {
        var grouped: [String: [AerialAsset]] = [:]

        for asset in assets {
            let categoryID = asset.categories.first ?? "other"
            grouped[categoryID, default: []].append(asset)
        }

        // Map to actual category objects and sort by preferredOrder
        return categories.compactMap { category in
            guard let assets = grouped[category.id], !assets.isEmpty else { return nil }
            return (category: category, assets: assets)
        }
    }

    /// Get display name for category ID (for backward compatibility)
    func categoryName(for id: String) -> String {
        categories.first { $0.id == id }?.displayName ?? "Other"
    }
}

// MARK: - Thumbnail Cache

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [URL: NSImage] = [:]
    private var accessOrder: [URL] = []
    private let maximumMemoryEntries = 96
    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("Sunpaper/Thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func thumbnail(for url: URL) async -> NSImage? {
        // Check memory cache
        if let cached = cache[url] {
            markAccessed(url)
            return cached
        }

        // Check disk cache
        let diskPath = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        if let diskImage = NSImage(contentsOf: diskPath) {
            store(diskImage, for: url)
            return diskImage
        }

        // Download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }

            // Save to disk cache
            try? data.write(to: diskPath)

            // Keep disk cache in the system cache directory and bound the in-memory cache.
            store(image, for: url)

            return image
        } catch {
            #if DEBUG
            print("[ThumbnailCache] Failed to load \(url): \(error)")
            #endif
            return nil
        }
    }

    private func store(_ image: NSImage, for url: URL) {
        cache[url] = image
        markAccessed(url)
        trimMemoryCacheIfNeeded()
    }

    private func markAccessed(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func trimMemoryCacheIfNeeded() {
        while cache.count > maximumMemoryEntries, let oldestURL = accessOrder.first {
            accessOrder.removeFirst()
            cache[oldestURL] = nil
        }
    }
}

// MARK: - Async Thumbnail View

enum ThumbnailUnavailableReason: Equatable {
    case missingURL
    case loadFailed

    var title: String {
        switch self {
        case .missingURL:
            return "No Preview"
        case .loadFailed:
            return "Preview Unavailable"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .missingURL:
            return "No preview thumbnail is available."
        case .loadFailed:
            return "The preview thumbnail could not be loaded."
        }
    }
}

private enum ThumbnailLoadState {
    case idle
    case loading
    case loaded(NSImage)
    case unavailable(ThumbnailUnavailableReason)
}

struct AsyncThumbnail: View {
    let url: URL?
    let size: CGSize

    @State private var loadState: ThumbnailLoadState = .idle

    var body: some View {
        Group {
            switch loadState {
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityLabel("Preview thumbnail")
            case .loading:
                placeholder {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                .accessibilityLabel("Loading preview thumbnail")
            case .idle:
                placeholder {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Preview thumbnail")
            case .unavailable(let reason):
                placeholder {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                        if size.width >= 80 {
                            Text(reason.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .accessibilityLabel(reason.accessibilityLabel)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            await loadImage(from: url)
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay(content: content)
    }

    private func loadImage(from url: URL?) async {
        guard let url else {
            loadState = .unavailable(.missingURL)
            return
        }

        loadState = .loading
        if let image = await ThumbnailCache.shared.thumbnail(for: url) {
            loadState = .loaded(image)
        } else {
            loadState = .unavailable(.loadFailed)
        }
    }
}
