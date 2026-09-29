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
        case .downloadable: return "icloud.and.arrow.down"
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

    var summary: String {
        switch self {
        case .downloaded: return "Downloaded · ready to use"
        case .downloadable: return "Downloads when applied · needs internet"
        case .unavailable: return "Unavailable · missing from the catalog"
        }
    }
}

private extension AerialAsset {
    var pickerDisplayName: String {
        BuiltInWallpapers.name(for: id) ?? displayName
    }
}

private struct AerialSection: Identifiable {
    let id: String
    let title: String
    let assets: [AerialAsset]
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
    @State private var searchText = ""
    @State private var downloadedOnly = false
    @State private var customFileError: String?
    @State private var customPreview: NSImage?
    @State private var pendingCustomURL: URL?
    @State private var customPath: String?
    /// A section the grid should scroll to; cleared once handled so a chip can be used again.
    @State private var jumpTarget: String?
    @State private var didConfirm = false
    @FocusState private var isSearchFocused: Bool

    private static let customSectionID = "your-images"

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
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            Divider()
            footer
        }
        .onAppear {
            if case .custom(let path) = draftSource {
                loadCustomPreview(at: URL(fileURLWithPath: path))
                jumpTarget = Self.customSectionID
            } else if let id = draftSource.assetID,
                      let section = sections.first(where: { $0.assets.contains { $0.id == id } }),
                      section.id != sections.first?.id {
                jumpTarget = section.id
            }
        }
        .frame(width: 760, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(catalogStatus).accessibilityIdentifier("wallpaperPickerStatus")
                        Text("·")
                        Text("Nothing changes until you confirm.")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                searchField.frame(width: 200)
                Toggle(isOn: $downloadedOnly) {
                    Label("Downloaded", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .help("Show only aerials that are already on this Mac")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sections) { section in
                        jumpChip(section.title) { jumpTarget = section.id }
                    }
                    jumpChip("Your images", symbol: "photo") { jumpTarget = Self.customSectionID }
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search aerials", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel("Search aerial wallpapers")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isSearchFocused ? SunpaperColor.accent.opacity(0.6) : Color.primary.opacity(0.08)))
    }

    private func jumpChip(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Scrolls to this group")
    }

    // MARK: Grid

    /// Sections live in a plain stack so every header exists as a scroll target for the jump chips.
    /// Thumbnails are small and cached, so realizing the whole catalog is cheap.
    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                catalogNotice.padding(.horizontal, 22).padding(.top, 16)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionHeader(section.title, detail: section.assets.count == 1 ? "1 aerial" : "\(section.assets.count) aerials")
                            .id(section.id)
                        TileRows(items: section.assets) { asset in
                            WallpaperThumbnailCell(
                                asset: asset,
                                isSelected: draftSource.assetID == asset.id,
                                downloadState: downloadState(for: asset),
                                onSelect: { draftSource = .builtIn(assetID: asset.id) },
                                onConfirm: { draftSource = .builtIn(assetID: asset.id); confirmSelection() }
                            )
                        }
                        .padding(.bottom, 10)
                    }
                    sectionHeader("Your images", detail: "Still images such as JPEG, PNG, or HEIC")
                        .id(Self.customSectionID)
                    HStack(alignment: .top, spacing: 16) {
                        ChooseImageTile(action: chooseCustomFile)
                        if let customPath, let customPreview {
                            let source = WallpaperSource.custom(path: customPath)
                            CustomImageCell(image: customPreview, name: URL(fileURLWithPath: customPath).lastPathComponent,
                                            isSelected: draftSource == source,
                                            onSelect: { draftSource = source },
                                            onConfirm: { draftSource = source; confirmSelection() })
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 22)
            }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                jumpTarget = nil
            }
        }
        .accessibilityIdentifier("aerialWallpaperGrid")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var catalogNotice: some View {
        switch catalog.loadState {
        case .loading:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Loading aerials…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        case .loaded:
            if sections.isEmpty {
                notice(title: "No matching aerials",
                       message: downloadedOnly ? "No downloaded aerials match. Try showing all, or clear your search." : "Try another name or clear your search.",
                       actionTitle: "Reset filters") { searchText = ""; downloadedOnly = false }
            }
        case .missingManifest, .malformedManifest, .noTopLevelAssets:
            notice(title: catalog.loadState.title,
                   message: catalog.loadState.message ?? "The aerial catalog is unavailable.",
                   actionTitle: "Reload catalog") { catalog.loadCatalog() }
        }
    }

    private func sectionHeader(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(.top, 16).padding(.bottom, 10)
    }

    private func notice(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            selectionThumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(selectionName).font(.headline).lineLimit(1).truncationMode(.middle)
                if let customFileError {
                    Label(customFileError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                        .accessibilityLabel("Image error: \(customFileError)")
                } else if let asset = draftAsset {
                    Label(downloadState(for: asset).summary, systemImage: downloadState(for: asset).systemImage)
                        .font(.caption).foregroundStyle(.secondary)
                        .help(downloadState(for: asset).detail)
                } else if case .custom = draftSource {
                    Label("Still image · saved to Sunpaper when you confirm", systemImage: "photo")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Choose a wallpaper. Double-click to use it right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        .padding(.vertical, 14)
    }

    @ViewBuilder private var selectionThumbnail: some View {
        Group {
            if let asset = draftAsset {
                AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 72, height: 44)).id(asset.id)
            } else if case .custom = draftSource, let customPreview {
                Image(nsImage: customPreview).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.primary.opacity(0.06).overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .frame(width: 72, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityHidden(true)
    }

    private var selectionName: String {
        if let asset = draftAsset { return asset.pickerDisplayName }
        if case .custom(let path) = draftSource { return URL(fileURLWithPath: path).lastPathComponent }
        return "Nothing selected"
    }

    // MARK: Model

    private var draftAsset: AerialAsset? {
        guard let id = draftSource.assetID else { return nil }
        return catalog.asset(for: id)
    }

    private var catalogStatus: String {
        switch catalog.loadState {
        case .loading: return "Loading aerials…"
        case .loaded:
            let count = sections.reduce(0) { $0 + $1.assets.count }
            return count == 1 ? "1 aerial" : "\(count) aerials"
        case .missingManifest, .malformedManifest, .noTopLevelAssets:
            return "Catalog unavailable"
        }
    }

    private var canConfirm: Bool {
        switch draftSource {
        case .builtIn:
            guard let asset = draftAsset else { return false }
            return downloadState(for: asset) != .unavailable
        case .custom(let path):
            return customPreview != nil && FileManager.default.isReadableFile(atPath: path)
        case .none:
            return false
        }
    }

    /// Day collections first, then Apple's categories, each filtered by search and download state.
    private var sections: [AerialSection] {
        guard case .loaded = catalog.loadState else { return [] }
        var seen = Set<String>()
        let collections = BuiltInWallpapers.allSets
            .flatMap { set in BuiltInWallpapers.Phase.allCases.map { set.assetID(for: $0) } }
            .filter { seen.insert($0).inserted }
            .compactMap { catalog.asset(for: $0) }
        let categories = catalog.assetsByCategory.map { AerialSection(id: $0.category.id, title: $0.category.displayName, assets: $0.assets) }
        return ([AerialSection(id: "day-collections", title: "Day collections", assets: collections)] + categories)
            .map { AerialSection(id: $0.id, title: $0.title, assets: $0.assets.filter(matchesFilters)) }
            .filter { !$0.assets.isEmpty }
    }

    private func matchesFilters(_ asset: AerialAsset) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (query.isEmpty || asset.pickerDisplayName.localizedCaseInsensitiveContains(query)
            || asset.displayName.localizedCaseInsensitiveContains(query))
            && (!downloadedOnly || downloadState(for: asset) == .downloaded)
    }

    private func downloadState(for asset: AerialAsset) -> AerialDownloadState {
        if WallpaperService.shared.isAerialDownloaded(assetID: asset.id) { return .downloaded }
        guard let url = asset.downloadURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return .unavailable }
        return .downloadable
    }

    // MARK: Custom images

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
        customPath = url.path
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
        customPath = customPreview == nil ? nil : url.path
        if customPreview == nil {
            customFileError = "This image is unavailable. Choose another image to continue."
        }
    }

    private func confirmSelection() {
        guard canConfirm, !didConfirm else { return }
        var confirmedSource = draftSource
        if case .custom(let path) = draftSource, let url = pendingCustomURL, url.path == path {
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

// MARK: - Cells

/// Fixed rows of four tiles. Unlike lazy grids, row heights never change as tiles are
/// realized, so selecting a tile or jumping to a section cannot shift the scroll position.
private struct TileRows<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell
    private let perRow = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { start in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items[start..<min(start + perRow, items.count)]) { item in cell(item) }
                }
            }
        }
    }
}

private struct TileArtwork<Content: View>: View {
    let isSelected: Bool
    let hovering: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: 162, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SunpaperColor.onAccent, SunpaperColor.accent)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? SunpaperColor.accent : Color.primary.opacity(hovering ? 0.25 : 0.08),
                                  lineWidth: isSelected ? 2.5 : 1)
            }
            .shadow(color: .black.opacity(hovering || isSelected ? 0.25 : 0), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

private struct WallpaperThumbnailCell: View {
    let asset: AerialAsset
    let isSelected: Bool
    let downloadState: AerialDownloadState
    let onSelect: () -> Void
    let onConfirm: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                TileArtwork(isSelected: isSelected, hovering: hovering) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 162, height: 96))
                }
                .overlay(alignment: .bottomLeading) {
                    if downloadState != .downloaded {
                        Image(systemName: downloadState == .downloadable ? "icloud.and.arrow.down" : "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                Text(asset.pickerDisplayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 162, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onConfirm))
        .help(downloadState == .downloaded ? asset.pickerDisplayName : "\(asset.pickerDisplayName) · \(downloadState.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.pickerDisplayName)
        .accessibilityValue("\(isSelected ? "Selected for preview" : "Not selected"), \(downloadState.title)")
        .accessibilityHint("Previews this aerial without changing your desktop. \(downloadState.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CustomImageCell: View {
    let image: NSImage
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onConfirm: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                TileArtwork(isSelected: isSelected, hovering: hovering) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
                Text(name).font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 162, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onConfirm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Custom image \(name)")
        .accessibilityValue(isSelected ? "Selected for preview" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChooseImageTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(hovering ? SunpaperColor.accent : Color.secondary.opacity(0.5))
                    .background(Color.primary.opacity(hovering ? 0.05 : 0.02), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        Image(systemName: "plus").font(.title2.weight(.medium))
                            .foregroundStyle(hovering ? SunpaperColor.accent : Color.secondary)
                    }
                    .frame(width: 162, height: 96)
                Text("Choose image…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 162, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose image")
        .accessibilityHint("Choose an image to preview. This does not change your wallpaper.")
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
