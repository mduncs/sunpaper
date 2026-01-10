import SwiftUI
import UniformTypeIdentifiers

// MARK: - Wallpaper Grid Picker

struct WallpaperGridPicker: View {
    @Binding var selectedSource: WallpaperSource
    let onSelect: (WallpaperSource) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var catalog = AerialCatalog.shared
    @State private var searchText = ""
    @State private var selectedTab = 0

    private var selectedAssetID: String? {
        if case .builtIn(let id) = selectedSource { return id }
        return nil
    }

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Aerials").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
            if selectedTab == 0 {
                aerialGrid
            } else {
                customWallpaperSection
            }
        }
        .frame(width: 560, height: 520)
    }

    private var aerialGrid: some View {
        Group {
            if catalog.isLoaded {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredAssets) { asset in
                            WallpaperThumbnailCell(
                                asset: asset,
                                isSelected: selectedAssetID == asset.id,
                                onSelect: {
                                    let source = WallpaperSource.builtIn(assetID: asset.id)
                                    selectedSource = source
                                    onSelect(source)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding()
                }
            } else if let error = catalog.error {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("Loading aerials...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var customWallpaperSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Custom Wallpapers")
                .font(.headline)

            Text("Choose your own image or video file")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                chooseCustomFile()
            } label: {
                Label("Choose File...", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Text("Supported: HEIC, JPG, PNG, MOV, MP4")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseCustomFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .heic, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a wallpaper image or video"

        if panel.runModal() == .OK, let url = panel.url {
            // Copy to app support directory for persistence
            do {
                let destURL = try copyToAppSupport(url)
                let source = WallpaperSource.custom(path: destURL.path)
                selectedSource = source
                onSelect(source)
                dismiss()
            } catch {
                #if DEBUG
                print("[WallpaperGridPicker] Failed to copy file: \(error)")
                #endif
            }
        }
    }

    private func copyToAppSupport(_ sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let wallpapersDir = appSupport.appendingPathComponent("Sunpaper/CustomWallpapers", isDirectory: true)

        // Create directory if needed
        try fm.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)

        // Use UUID prefix to avoid collisions
        let destName = "\(UUID().uuidString.prefix(8))_\(sourceURL.lastPathComponent)"
        let destURL = wallpapersDir.appendingPathComponent(destName)

        // Copy file
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)

        #if DEBUG
        print("[WallpaperGridPicker] Copied custom wallpaper to: \(destURL.path)")
        #endif
        return destURL
    }

    private var header: some View {
        HStack {
            Text("Choose Wallpaper")
                .font(.headline)

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 180)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var filteredAssets: [AerialAsset] {
        if searchText.isEmpty {
            return catalog.assets
        }
        return catalog.assets.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Thumbnail Cell

struct WallpaperThumbnailCell: View {
    let asset: AerialAsset
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // Thumbnail
                AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 140, height: 80))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 3)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }

                // Name
                Text(asset.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) :
                          isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Compact Wallpaper Button (for inline use)

struct WallpaperButton: View {
    let source: WallpaperSource
    let onTap: () -> Void

    @StateObject private var catalog = AerialCatalog.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Mini thumbnail
                if case .builtIn(let assetID) = source,
                   let asset = catalog.asset(for: assetID) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 32, height: 20))
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(width: 32, height: 20)
                }

                // Name
                Text(displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        switch source {
        case .none:
            return "None"
        case .builtIn(let assetID):
            return catalog.asset(for: assetID)?.displayName ?? "Unknown"
        case .custom(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

// MARK: - Preview

#Preview {
    WallpaperGridPicker(selectedSource: .constant(.none)) { _ in }
}
