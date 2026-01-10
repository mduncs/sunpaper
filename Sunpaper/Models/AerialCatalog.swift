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

// MARK: - Aerial Catalog Service

@MainActor
class AerialCatalog: ObservableObject {
    static let shared = AerialCatalog()

    @Published private(set) var assets: [AerialAsset] = []
    @Published private(set) var categories: [AerialCategory] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var error: String?

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

        guard FileManager.default.fileExists(atPath: path) else {
            error = "Aerial entries.json not found. Make sure you have aerial wallpapers downloaded in System Settings."
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

            #if DEBUG
            print("[AerialCatalog] Loaded \(assets.count) assets, \(categories.count) categories")
            #endif
        } catch {
            self.error = "Failed to parse entries.json: \(error.localizedDescription)"
            #if DEBUG
            print("[AerialCatalog] Error: \(error)")
            #endif
        }
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
    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("Sunpaper/Thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func thumbnail(for url: URL) async -> NSImage? {
        // Check memory cache
        if let cached = cache[url] {
            return cached
        }

        // Check disk cache
        let diskPath = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        if let diskImage = NSImage(contentsOf: diskPath) {
            cache[url] = diskImage
            return diskImage
        }

        // Download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }

            // Save to disk cache
            try? data.write(to: diskPath)

            // Save to memory cache
            cache[url] = image

            return image
        } catch {
            #if DEBUG
            print("[ThumbnailCache] Failed to load \(url): \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Async Thumbnail View

struct AsyncThumbnail: View {
    let url: URL?
    let size: CGSize

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url, image == nil else { return }
        isLoading = true
        image = await ThumbnailCache.shared.thumbnail(for: url)
        isLoading = false
    }
}
