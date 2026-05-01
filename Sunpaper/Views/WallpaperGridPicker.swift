import SwiftUI
import UniformTypeIdentifiers

private enum AerialDownloadState: Equatable {
    case downloaded
    case downloadable
    case unavailable

    var title: String {
        switch self {
        case .downloaded:
            return "Downloaded"
        case .downloadable:
            return "Will download"
        case .unavailable:
            return "No download URL"
        }
    }

    var systemImage: String {
        switch self {
        case .downloaded:
            return "checkmark.circle"
        case .downloadable:
            return "arrow.down.circle"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .downloaded, .downloadable:
            return .secondary
        case .unavailable:
            return .orange
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .downloaded:
            return "The aerial video is downloaded."
        case .downloadable:
            return "The aerial video is not downloaded yet, but Sunpaper has a download URL."
        case .unavailable:
            return "The aerial video is not downloaded and the catalog does not provide a download URL."
        }
    }
}

// MARK: - Wallpaper Grid Picker

struct WallpaperGridPicker: View {
    @Binding var selectedSource: WallpaperSource
    let onSelect: (WallpaperSource) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var catalog = AerialCatalog.shared
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var customFileError: String?

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
            Picker("Wallpaper source", selection: $selectedTab) {
                Text("Aerials").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Wallpaper source")
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

    @ViewBuilder
    private var aerialGrid: some View {
        switch catalog.loadState {
        case .loading:
            ProgressView("Loading aerials...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading Apple aerial wallpapers")

        case .loaded:
            if filteredAssets.isEmpty {
                emptyState(
                    title: "No Aerials Found",
                    systemImage: "magnifyingglass",
                    message: "No Apple aerial wallpapers match \"\(searchText)\".",
                    actionTitle: "Clear Search",
                    actionHint: "Clears the search field."
                ) {
                    searchText = ""
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredAssets) { asset in
                            WallpaperThumbnailCell(
                                asset: asset,
                                isSelected: selectedAssetID == asset.id,
                                downloadState: downloadState(for: asset),
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
                .accessibilityIdentifier("aerialWallpaperGrid")
            }

        case .missingManifest, .malformedManifest, .noTopLevelAssets:
            emptyState(
                title: catalog.loadState.title,
                systemImage: catalog.loadState.systemImage,
                message: catalog.loadState.message ?? "Apple aerial wallpapers are not available.",
                actionTitle: "Reload Catalog",
                actionHint: "Attempts to update the aerial wallpaper list."
            ) {
                catalog.loadCatalog()
            }
        }
    }

    private func emptyState(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        actionHint: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .accessibilityHint(actionHint ?? "")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func downloadState(for asset: AerialAsset) -> AerialDownloadState {
        if WallpaperService.shared.isAerialDownloaded(assetID: asset.id) {
            return .downloaded
        }

        return asset.downloadURL == nil ? .unavailable : .downloadable
    }

    private var customWallpaperSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Custom Wallpapers")
                .font(.headline)

            Text("Choose a static image file. Custom video wallpapers are not supported yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                chooseCustomFile()
            } label: {
                Label("Choose File...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens a file picker for a custom static wallpaper image.")

            Text("Static images apply directly. MOV and MP4 files are not supported.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let customFileError {
                Label(customFileError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .accessibilityLabel("Custom wallpaper error. \(customFileError)")
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseCustomFile() {
        customFileError = nil

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .heic, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a wallpaper image. Custom videos are not supported yet."

        if panel.runModal() == .OK, let url = panel.url {
            guard !isMovieFile(url) else {
                customFileError = "Custom video wallpapers are not supported yet. Choose a static image instead."
                return
            }

            // Copy to app support directory for persistence
            do {
                let destURL = try copyToAppSupport(url)
                let source = WallpaperSource.custom(path: destURL.path)
                selectedSource = source
                onSelect(source)
                dismiss()
            } catch {
                customFileError = "Could not copy \(url.lastPathComponent): \(error.localizedDescription)"
                #if DEBUG
                print("[WallpaperGridPicker] Failed to copy file: \(error)")
                #endif
            }
        }
    }

    private func isMovieFile(_ url: URL) -> Bool {
        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            return contentType.conforms(to: .movie)
        }

        if let contentType = UTType(filenameExtension: url.pathExtension) {
            return contentType.conforms(to: .movie)
        }

        return ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
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
                    .accessibilityHidden(true)
                TextField("Search Aerials", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search aerial wallpapers")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Shows all aerial wallpapers.")
                }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 180)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
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

private struct WallpaperThumbnailCell: View {
    let asset: AerialAsset
    let isSelected: Bool
    let downloadState: AerialDownloadState
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
                                .accessibilityHidden(true)
                        }
                    }

                // Name
                Text(asset.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(height: 32)

                Label(downloadState.title, systemImage: downloadState.systemImage)
                    .font(.caption2)
                    .foregroundStyle(downloadState.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 14)
                    .accessibilityLabel(downloadState.accessibilityDescription)
            }
            .frame(maxWidth: .infinity, minHeight: 138)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) :
                          isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects \(asset.displayName). \(downloadState.accessibilityDescription)")
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
                        .accessibilityHidden(true)
                }

                // Name
                Text(displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose wallpaper. Current selection: \(displayName)")
        .accessibilityHint("Opens the wallpaper picker.")
    }

    private var displayName: String {
        switch source {
        case .none:
            return "None"
        case .builtIn(let assetID):
            return catalog.asset(for: assetID)?.displayName
                ?? BuiltInWallpapers.name(for: assetID)
                ?? "Unknown Aerial"
        case .custom(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

// MARK: - Preview

#Preview {
    WallpaperGridPicker(selectedSource: .constant(.none)) { _ in }
}
