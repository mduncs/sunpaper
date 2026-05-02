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
            return "Downloadable"
        case .unavailable:
            return "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .downloaded:
            return "checkmark.circle.fill"
        case .downloadable:
            return "arrow.down.circle"
        case .unavailable:
            return "exclamationmark.triangle.fill"
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

private enum WallpaperPickerTab: Hashable {
    case aerials
    case custom
}

// MARK: - Wallpaper Grid Picker

struct WallpaperGridPicker: View {
    @Binding var selectedSource: WallpaperSource
    let onSelect: (WallpaperSource) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var catalog = AerialCatalog.shared
    @State private var searchText = ""
    @State private var selectedTab: WallpaperPickerTab = .aerials
    @State private var customFileError: String?
    @FocusState private var isSearchFocused: Bool

    private let sheetSize = CGSize(width: 680, height: 620)

    private var selectedAssetID: String? {
        if case .builtIn(let id) = selectedSource { return id }
        return nil
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 172), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            sourceControls

            ZStack {
                if selectedTab == .aerials {
                    aerialGrid
                } else {
                    customWallpaperSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.36))

            footer
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            if case .custom = selectedSource {
                selectedTab = .custom
            }
        }
    }

    @ViewBuilder
    private var aerialGrid: some View {
        switch catalog.loadState {
        case .loading:
            loadingState

        case .loaded:
            if filteredAssets.isEmpty {
                emptyState(
                    title: "No Aerials Found",
                    systemImage: "magnifyingglass",
                    message: "No aerial wallpapers match \"\(searchQuery)\".",
                    actionTitle: "Clear Search",
                    actionHint: "Clears the search field."
                ) {
                    searchText = ""
                    isSearchFocused = true
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredAssets) { asset in
                                WallpaperThumbnailCell(
                                    asset: asset,
                                    isSelected: selectedAssetID == asset.id,
                                    downloadState: downloadState(for: asset),
                                    onSelect: {
                                        selectAerial(asset)
                                    }
                                )
                                .id(asset.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("aerialWallpaperGrid")
                    .onAppear {
                        scrollSelectedAssetIntoView(with: proxy)
                    }
                }
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
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            if let actionTitle, let action {
                Button {
                    action()
                } label: {
                    Label(actionTitle, systemImage: actionTitle == "Clear Search" ? "xmark.circle" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityHint(actionHint ?? "")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    private func downloadState(for asset: AerialAsset) -> AerialDownloadState {
        if WallpaperService.shared.isAerialDownloaded(assetID: asset.id) {
            return .downloaded
        }

        return asset.downloadURL == nil ? .unavailable : .downloadable
    }

    private var customWallpaperSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [7, 5]))

                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(spacing: 6) {
                            Text("Choose a Custom Image")
                                .font(.title3.weight(.semibold))

                            Text("Use a static image file for this wallpaper. Custom video wallpapers are not supported yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 430)
                        }

                        Button {
                            chooseCustomFile()
                        } label: {
                            Label("Choose Image...", systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Opens a file picker for a custom static wallpaper image.")
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 30)
                }
                .frame(maxWidth: 500, minHeight: 220)
                .accessibilityElement(children: .contain)

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedCustomFileName {
                        infoRow(
                            title: "Current image",
                            value: selectedCustomFileName,
                            systemImage: "photo"
                        )
                        .accessibilityLabel("Current custom image")
                        .accessibilityValue(selectedCustomFileName)
                    } else {
                        infoRow(
                            title: "Current image",
                            value: "No custom image selected",
                            systemImage: "photo"
                        )
                    }

                    infoRow(
                        title: "Allowed files",
                        value: "Static images such as JPEG, PNG, and HEIC. MOV and MP4 files are rejected.",
                        systemImage: "checkmark.seal"
                    )
                }
                .frame(maxWidth: 500, alignment: .leading)

                if let customFileError {
                    inlineError(customFileError)
                        .frame(maxWidth: 500, alignment: .leading)
                }
            }

            Text("Files are copied into Sunpaper's application support folder so the wallpaper remains available later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseCustomFile() {
        customFileError = nil

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .heic, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Wallpaper Image"
        panel.prompt = "Choose"
        panel.message = "Choose a static image. Videos are not supported as custom wallpapers."

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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Wallpaper")
                    .font(.title3.weight(.semibold))

                Text("Select an aerial wallpaper or use a static image from your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Wallpaper source", selection: $selectedTab) {
                Text("Aerials").tag(WallpaperPickerTab.aerials)
                Text("Custom Image").tag(WallpaperPickerTab.custom)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .accessibilityLabel("Wallpaper source")

            if selectedTab == .aerials {
                aerialSearchRow
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var aerialSearchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search Aerials", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .frame(maxWidth: 360)
                .accessibilityLabel("Search aerial wallpapers")
                .accessibilityHint("Filters the aerial wallpaper grid.")

            Button {
                searchText = ""
                isSearchFocused = true
            } label: {
                Label("Clear Search", systemImage: "xmark.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(searchText.isEmpty)
            .accessibilityLabel("Clear search")
            .accessibilityHint("Shows all aerial wallpapers.")

            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wallpaperPickerStatus")

            Spacer()

            if showsFooterReloadButton {
                Button {
                    catalog.loadCatalog()
                } label: {
                    Label("Reload Catalog", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityHint("Refreshes the aerial wallpaper catalog.")
            }

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var showsFooterReloadButton: Bool {
        guard selectedTab == .aerials else { return false }
        if case .loaded = catalog.loadState {
            return true
        }
        return false
    }

    private var filteredAssets: [AerialAsset] {
        if searchQuery.isEmpty {
            return catalog.assets
        }
        return catalog.assets.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCustomFileName: String? {
        guard case .custom(let path) = selectedSource else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var footerStatus: String {
        switch selectedTab {
        case .aerials:
            switch catalog.loadState {
            case .loading:
                return "Loading aerial catalog..."
            case .loaded(let assetCount, _):
                if searchQuery.isEmpty {
                    return "\(assetCount) aerial wallpapers"
                }
                return "\(filteredAssets.count) of \(assetCount) aerial wallpapers match the search"
            case .missingManifest:
                return "Download an aerial wallpaper in System Settings, then reload the catalog."
            case .malformedManifest:
                return "The local aerial catalog could not be read. Reload after the catalog refreshes."
            case .noTopLevelAssets:
                return "No aerial wallpapers are available in the local catalog."
            }
        case .custom:
            if let selectedCustomFileName {
                return "Current custom image: \(selectedCustomFileName)"
            }
            return "Choose a static image from your Mac."
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Loading Aerials")
                .font(.headline)

            Text("Reading the local aerial catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading aerial wallpapers")
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inlineError(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .multilineTextAlignment(.leading)
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.24))
        }
        .accessibilityLabel("Custom wallpaper error. \(message)")
    }

    private func selectAerial(_ asset: AerialAsset) {
        let source = WallpaperSource.builtIn(assetID: asset.id)
        selectedSource = source
        onSelect(source)
        dismiss()
    }

    private func scrollSelectedAssetIntoView(with proxy: ScrollViewProxy) {
        guard let selectedAssetID, filteredAssets.contains(where: { $0.id == selectedAssetID }) else {
            return
        }

        DispatchQueue.main.async {
            proxy.scrollTo(selectedAssetID, anchor: .center)
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
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 132, height: 76))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.18)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.black.opacity(0.08))
                        }
                        .accessibilityHidden(true)

                    downloadBadge

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 132, height: 76)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(asset.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .topLeading)

                HStack(spacing: 6) {
                    selectionIndicator
                    downloadStatus
                }
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 154, maxHeight: 154, alignment: .top)
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(cellFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(cellStroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Selects this aerial wallpaper. \(downloadState.accessibilityDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var selectionIndicator: some View {
        Group {
            if isSelected {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Not selected")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .frame(maxWidth: isSelected ? 70 : 0, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private var downloadStatus: some View {
        Label(downloadState.title, systemImage: downloadState.systemImage)
            .font(.caption2)
            .foregroundStyle(downloadState.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var downloadBadge: some View {
        if downloadState != .downloaded || isHovered {
            Image(systemName: downloadState.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(downloadState == .unavailable ? .orange : .white)
                .padding(5)
                .background(.black.opacity(downloadState == .unavailable ? 0.48 : 0.42), in: Circle())
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    private var cellFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }

        if isHovered {
            return AnyShapeStyle(.regularMaterial)
        }

        return AnyShapeStyle(Color.primary.opacity(0.035))
    }

    private var cellStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }

        if isHovered {
            return Color.primary.opacity(0.16)
        }

        return Color.primary.opacity(0.08)
    }

    private var accessibilityValue: String {
        let selection = isSelected ? "Selected" : "Not selected"
        return "\(selection), \(downloadState.title)"
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
