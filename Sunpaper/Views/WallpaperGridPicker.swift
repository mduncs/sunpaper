import SwiftUI
import UniformTypeIdentifiers
import ImageIO

private enum AerialDownloadState: Equatable {
    case downloaded, downloadable, unavailable

    var title: String {
        switch self {
        case .downloaded: return "Downloaded"
        case .downloadable: return "Downloadable"
        case .unavailable: return "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .downloaded: return "checkmark.circle"
        case .downloadable: return "arrow.down.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    var detail: String {
        switch self {
        case .downloaded: return "Ready to use."
        case .downloadable: return "The video downloads when this wallpaper is applied. An internet connection is required."
        case .unavailable: return "This video is not downloaded and its download URL is missing from the catalog."
        }
    }
}

private enum WallpaperPickerTab: Hashable {
    case aerials, custom
}

private extension AerialAsset {
    var pickerDisplayName: String {
        BuiltInWallpapers.name(for: id) ?? displayName
    }
}

/// Browsing changes only the local draft. The caller receives one selection on confirmation.
struct WallpaperGridPicker: View {
    @Binding var selectedSource: WallpaperSource
    let title: String
    let confirmationTitle: String
    let onSelect: (WallpaperSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = AerialCatalog.shared
    @State private var draftSource: WallpaperSource
    @State private var selectedTab: WallpaperPickerTab
    @State private var searchText = ""
    @State private var downloadedOnly = false
    @State private var customFileError: String?
    @State private var customPreview: NSImage?
    @State private var pendingCustomURL: URL?
    @State private var didConfirm = false
    @FocusState private var isSearchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(150), spacing: 16), count: 3)
    private let previewSize = CGSize(width: 232, height: 145)

    init(
        selectedSource: Binding<WallpaperSource>,
        title: String = "Choose wallpaper",
        confirmationTitle: String = "Use wallpaper",
        onSelect: @escaping (WallpaperSource) -> Void
    ) {
        self._selectedSource = selectedSource
        self.title = title
        self.confirmationTitle = confirmationTitle
        self.onSelect = onSelect
        self._draftSource = State(initialValue: selectedSource.wrappedValue)
        if case .custom = selectedSource.wrappedValue {
            self._selectedTab = State(initialValue: .custom)
        } else {
            self._selectedTab = State(initialValue: .aerials)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("Preview here. Your wallpaper stays unchanged until you confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("Wallpaper source", selection: $selectedTab) {
                        Text("Aerials").tag(WallpaperPickerTab.aerials)
                        Text("Custom image").tag(WallpaperPickerTab.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                    if selectedTab == .aerials {
                        Picker("Show aerials", selection: $downloadedOnly) {
                            Text("All").tag(false)
                            Text("Downloaded").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
                if selectedTab == .aerials {
                    HStack(spacing: 8) {
                        TextField("Search aerials", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isSearchFocused)
                            .accessibilityLabel("Search aerial wallpapers")
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                isSearchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear search")
                        }
                    }
                }
            }
            .padding(22)

            Divider()
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if selectedTab == .aerials {
                        aerialGrid
                    } else {
                        customWallpaperSection
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                previewDetail
                    .frame(width: previewSize.width)
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 820, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if case .custom(let path) = draftSource {
                loadCustomPreview(at: URL(fileURLWithPath: path))
            }
        }
    }

    @ViewBuilder
    private var aerialGrid: some View {
        switch catalog.loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading aerials…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .loaded:
            if filteredAssets.isEmpty {
                emptyState(
                    title: "No matching aerials",
                    message: downloadedOnly
                        ? "No downloaded aerials match these filters. Try All or clear your search."
                        : "Try another name or clear your search.",
                    actionTitle: "Reset filters"
                ) {
                    searchText = ""
                    downloadedOnly = false
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(filteredAssets) { asset in
                                WallpaperThumbnailCell(
                                    asset: asset,
                                    isSelected: draftSource.assetID == asset.id,
                                    downloadState: downloadState(for: asset)
                                ) {
                                    draftSource = .builtIn(assetID: asset.id)
                                }
                                .id(asset.id)
                            }
                        }
                        .padding(20)
                    }
                    .accessibilityIdentifier("aerialWallpaperGrid")
                    .onAppear {
                        if let id = draftSource.assetID,
                           let index = filteredAssets.firstIndex(where: { $0.id == id }), index >= 6 {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
            }
        case .missingManifest, .malformedManifest, .noTopLevelAssets:
            emptyState(
                title: catalog.loadState.title,
                message: catalog.loadState.message ?? "The aerial catalog is unavailable.",
                actionTitle: "Reload catalog"
            ) {
                catalog.loadCatalog()
            }
        }
    }

    private func emptyState(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customWallpaperSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("An image from your Mac")
                .font(.headline)
            Text("Choose a still image such as JPEG, PNG, or HEIC. Videos and animated images are not supported.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose image…", action: chooseCustomFile)
                .accessibilityHint("Choose an image to preview. This does not change your wallpaper.")
            Text("The image is saved to Sunpaper when you confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if selectedTab == .aerials, let asset = draftAsset {
                    AsyncThumbnail(url: asset.thumbnailURL, size: previewSize)
                        .id(asset.id)
                        .accessibilityLabel("Still preview of \(asset.pickerDisplayName)")
                    Text(asset.pickerDisplayName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(downloadState(for: asset).title, systemImage: downloadState(for: asset).systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(downloadState(for: asset).detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Still preview · Apple aerial")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedTab == .custom, case .custom(let path) = draftSource {
                    if let customPreview {
                        Image(nsImage: customPreview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: previewSize.width, height: previewSize.height)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("Preview of selected custom image")
                    } else {
                        previewPlaceholder
                    }
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.headline)
                        .lineLimit(3)
                        .truncationMode(.middle)
                    Text("Still image")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    previewPlaceholder
                    Text("Choose a wallpaper to preview")
                        .font(.headline)
                    Text("Selecting a photo here does not change your desktop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selectedTab == .custom, let customFileError {
                    Label(customFileError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Image error: \(customFileError)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }

    private var previewPlaceholder: some View {
        Rectangle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .frame(width: previewSize.width, height: previewSize.height)
            .overlay {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if selectedTab == .aerials {
                Text(catalogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wallpaperPickerStatus")
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(confirmationTitle, action: confirmSelection)
                .buttonStyle(.borderedProminent)
                .tint(SunpaperColor.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm || didConfirm)
                .accessibilityHint("Confirms the previewed wallpaper and closes the picker.")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var draftAsset: AerialAsset? {
        guard let id = draftSource.assetID else { return nil }
        return catalog.asset(for: id)
    }

    private var catalogStatus: String {
        switch catalog.loadState {
        case .loading: return "Loading aerials…"
        case .loaded: return "\(filteredAssets.count) aerials"
        case .missingManifest, .malformedManifest, .noTopLevelAssets:
            return "Catalog unavailable"
        }
    }

    private var canConfirm: Bool {
        switch (selectedTab, draftSource) {
        case (.aerials, .builtIn):
            guard let asset = draftAsset else { return false }
            return downloadState(for: asset) != .unavailable
        case (.custom, .custom(let path)):
            return customPreview != nil && FileManager.default.isReadableFile(atPath: path)
        default:
            return false
        }
    }

    private var filteredAssets: [AerialAsset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.assets.filter { asset in
            (query.isEmpty || asset.pickerDisplayName.localizedCaseInsensitiveContains(query)
                || asset.displayName.localizedCaseInsensitiveContains(query))
                && (!downloadedOnly || downloadState(for: asset) == .downloaded)
        }
    }

    private func downloadState(for asset: AerialAsset) -> AerialDownloadState {
        if WallpaperService.shared.isAerialDownloaded(assetID: asset.id) { return .downloaded }
        guard let url = asset.downloadURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return .unavailable }
        return .downloadable
    }

    private func chooseCustomFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose wallpaper image"
        panel.prompt = "Preview"
        panel.message = "Choose a still image to preview before confirming."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Validate and preview now; no persistent copy or binding mutation until confirmation.
        guard let image = validatedImage(at: url) else {
            customFileError = "This file could not be read as a still image. Choose a JPEG, PNG, or HEIC image."
            return
        }
        customFileError = nil
        customPreview = image
        pendingCustomURL = url
        draftSource = .custom(path: url.path)
    }

    private func validatedImage(at url: URL) -> NSImage? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) == 1 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private func loadCustomPreview(at url: URL) {
        customPreview = validatedImage(at: url)
        if customPreview == nil {
            customFileError = "This image is unavailable. Choose another image to continue."
        }
    }

    private func confirmSelection() {
        guard canConfirm, !didConfirm else { return }
        var confirmedSource = draftSource
        if let url = pendingCustomURL, selectedTab == .custom {
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Sunpaper/CustomWallpapers", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                try FileManager.default.copyItem(at: url, to: destination)
                confirmedSource = .custom(path: destination.path)
            } catch {
                customFileError = "Could not save this image: \(error.localizedDescription)"
                return
            }
        }
        didConfirm = true
        selectedSource = confirmedSource
        onSelect(confirmedSource)
        dismiss()
    }
}

private struct WallpaperThumbnailCell: View {
    let asset: AerialAsset
    let isSelected: Bool
    let downloadState: AerialDownloadState
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 150, height: 88))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, SunpaperColor.accent)
                                .padding(6)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? SunpaperColor.accent : .clear, lineWidth: 2)
                    }
                    .accessibilityHidden(true)
                Text(asset.pickerDisplayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
                Label(downloadState.title, systemImage: downloadState.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.pickerDisplayName)
        .accessibilityValue("\(isSelected ? "Selected for preview" : "Not selected"), \(downloadState.title)")
        .accessibilityHint("Previews this aerial without changing your desktop. \(downloadState.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            return BuiltInWallpapers.name(for: assetID)
                ?? catalog.asset(for: assetID)?.displayName
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
