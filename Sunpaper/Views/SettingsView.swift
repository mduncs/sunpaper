import SwiftUI
import ServiceManagement
import CoreLocation

struct SettingsView: View {
    @ObservedObject var controller: SunpaperController
    @ObservedObject private var transition = WallpaperTransition.shared
    @State private var showLocation = false
    @State private var launchAtLogin = false
    @State private var loginNeedsApproval = false
    @State private var loginError: String?
    @State private var captureAllowed = false
    @State private var capturePermissionRequested = false
    @State private var showReset = false
    @State private var clearScope: String?
    @State private var clearScopeName = "All displays"

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .padding(-6)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sunpaper").font(.title3.weight(.semibold))
                        Text([Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, "Follows your day."]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusDot(title: controller.stateTitle, tone: controller.statusTone)
                }
                .padding(.vertical, 4)
            }
            Section("General") {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) {
                    Label { Text("Open Sunpaper at login") } icon: { SymbolTile(systemName: "power", color: .gray) }
                }
                if loginNeedsApproval {
                    Text("Approve Sunpaper in Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if !isInApplications {
                    Text("Login will open this copy. Move Sunpaper to Applications first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent {
                    HStack(spacing: 10) {
                        Text(controller.config.locationName ?? "Not set")
                        Button(controller.config.locationName == nil ? "Choose…" : "Change…") { showLocation = true }
                    }
                } label: {
                    Label { Text("Location") } icon: { SymbolTile(systemName: "location.fill", color: .blue) }
                }
                Text(sunTimesSummary).font(.caption).foregroundStyle(.secondary)
            } header: { Text("Sunrise & sunset") }
            Section {
                Picker(selection: Binding(get: { controller.config.displayMode }, set: { controller.setDisplayMode($0) })) {
                    Text("Same on all displays").tag(DisplayMode.allDisplays)
                    Text("Different for each display").tag(DisplayMode.perDisplay)
                } label: {
                    Label { Text("Wallpaper schedule") } icon: { SymbolTile(systemName: "display.2", color: .indigo) }
                }
                Text(controller.config.displayMode == .allDisplays
                     ? "One schedule follows you across your displays."
                     : "Choose a display in Your day to edit its schedule. Saved schedules are kept when a display is disconnected.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Displays") }
            Section {
                Toggle(isOn: Binding(
                    get: { controller.config.smoothWallpaperChanges },
                    set: { controller.setSmoothWallpaperChanges($0) })) {
                    Label { Text("Smooth wallpaper changes") } icon: { SymbolTile(systemName: "sparkles", color: .orange) }
                }
                Text(controller.config.smoothWallpaperChanges
                     ? "Keep the previous wallpaper visible while the next one loads."
                     : "Your schedule still works. Changes may briefly flash gray.")
                    .font(.caption).foregroundStyle(.secondary)
                if controller.config.smoothWallpaperChanges {
                    LabeledContent {
                        Label(captureAllowed ? "Allowed" : "Not allowed", systemImage: captureAllowed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(captureAllowed ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    } label: {
                        Label { Text("Screen capture access") } icon: { SymbolTile(systemName: "rectangle.dashed", color: .purple) }
                    }
                    Text("Only the wallpaper is captured—not your apps or audio. Nothing is recorded or saved.")
                        .font(.caption).foregroundStyle(.secondary)
                    if controller.scheduler.smoothingUnavailableBecauseOfPermission || !captureAllowed {
                        Text("Changes happen instantly until screen capture is allowed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Why is this needed?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple’s native aerial switching uses a private permission—an entitlement—that Sunpaper doesn’t have.")
                        Text("Sunpaper schedules your wallpapers and switches them by reloading macOS’s wallpaper. That reload can briefly show gray. Smoothing keeps the previous wallpaper visible during the change.")
                        Text("Smoothing is optional. With it off, your schedule still works and no screen capture access is needed.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if controller.config.smoothWallpaperChanges && !captureAllowed {
                    Button("Allow screen capture…") {
                        WallpaperTransition.requestCapturePermission()
                        capturePermissionRequested = true
                        captureAllowed = WallpaperTransition.hasCapturePermission
                    }
                    if capturePermissionRequested {
                        Button("Quit & Reopen") { WallpaperTransition.relaunchApp() }
                    }
                }
                if transition.needsRecovery {
                    InlineNotice(text: transition.recoveryError ?? "Your previous wallpaper is still being kept visible.", actionTitle: transition.isRecovering ? "Restoring…" : "Restore desktop") {
                        Task { await transition.retryRecovery() }
                    }.disabled(transition.isRecovering)
                }
                DisclosureGroup("Troubleshooting") {
                    Text("If macOS asked you to quit and reopen Sunpaper after allowing access, do that before trying another change. Reduce Motion in macOS Accessibility settings is respected.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry wallpaper change") { Task { await controller.retryWallpaperChange() } }
                    Button("Open macOS Wallpaper settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
            } header: { Text("Smooth changes") }
            Section {
                HStack {
                    Label { Text("Clear this schedule") } icon: { SymbolTile(systemName: "trash.fill", color: .red) }
                    Spacer()
                    Button("Clear…", role: .destructive) {
                        clearScope = controller.scope; clearScopeName = controller.scopeName; showReset = true
                    }
                }
                Text("Removes changes for \(controller.scopeName.lowercased()). Location and other settings are kept. You can undo this.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Schedule") }
        }
        .formStyle(.grouped)
        .tint(SunpaperColor.accent)
        .frame(minWidth: SunpaperSize.settingsMinWidth, minHeight: SunpaperSize.settingsMinHeight)
        .onAppear(perform: refreshAccess)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshAccess() }
        .sheet(isPresented: $showLocation) { LocationChooser(controller: controller) }
        .confirmationDialog("Clear the schedule for \(clearScopeName)?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Clear schedule", role: .destructive) { controller.editSlots("Clear schedule", displayUUID: clearScope) { $0.removeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The current wallpaper stays in place. Your location and other settings are kept.") }
    }

    private var sunTimesSummary: String {
        switch controller.polarCondition {
        case .polarDay:
            return "Today the sun doesn’t set here (midnight sun). Solar changes use estimated times."
        case .polarNight:
            return "Today the sun doesn’t rise here (polar night). Solar changes use estimated times."
        case .normal, nil:
            break
        }
        let time = { (event: SolarEvent) in
            controller.resolvedTime(for: .solar(event: event, offset: 0))?.formatted(date: .omitted, time: .shortened)
        }
        guard let sunrise = time(.sunrise), let sunset = time(.sunset) else {
            return "Needed for changes that follow the sun. Fixed times work without one."
        }
        return "Today: sunrise \(sunrise) · sunset \(sunset). Fixed times don’t need a location."
    }

    /// Where login will launch from; the screenshot renderer points this at /Applications.
    static var appBundleURL = Bundle.main.bundleURL

    private var isInApplications: Bool {
        let path = Self.appBundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return !path.contains("/AppTranslocation/") &&
            (path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/"))
    }

    private func refreshAccess() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
        captureAllowed = WallpaperTransition.hasCapturePermission
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let message = error.localizedDescription
            loginError = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if loginError == message { loginError = nil }
            }
        }
        refreshAccess()
    }
}

/// A status dot and title for ordinary (non-ambient) surfaces.
private struct StatusDot: View {
    let title: String
    let tone: SunpaperStatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone == .following ? SunpaperColor.accent : tone == .paused ? Color.secondary : tone.color)
                .frame(width: 7, height: 7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LocationChoice: Identifiable {
    var id: String { "\(latitude),\(longitude)" }
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double
}

struct LocationChooser: View {
    @ObservedObject var controller: SunpaperController
    @StateObject private var search = LocationSearchModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LocationChoice?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Location for your day").font(.title2.weight(.semibold))
            Text("Choose a city for sunrise and sunset. Times follow your Mac’s time zone.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Search city or place", text: $search.query).textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            HStack {
                Button { selected = nil; search.findCurrentLocation() } label: { Label("Use current location", systemImage: "location") }
                .disabled(search.locating)
                Spacer()
                if search.searching || search.locating { ProgressView().controlSize(.small) }
            }
            if let error = search.error {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(search.results) { choice in
                        Button { selected = choice } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(choice.name).font(.headline)
                                    Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == choice.id { Image(systemName: "checkmark").foregroundStyle(SunpaperColor.accent) }
                            }.padding(10).contentShape(Rectangle())
                                .background(selected?.id == choice.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityAddTraits(selected?.id == choice.id ? .isSelected : [])
                    }
                    if search.results.isEmpty && !search.searching && search.error == nil {
                        Text("No places found. Try a nearby city.").foregroundStyle(.secondary).padding(20)
                    }
                }
            }.frame(height: 224)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use location") {
                    if let selected { controller.setLocation(name: selected.name, latitude: selected.latitude, longitude: selected.longitude) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(selected == nil)
            }
        }.padding(24).frame(width: 430).tint(SunpaperColor.accent)
        .onAppear { searchFocused = true }
        .onDisappear { search.cancel() }
        .onChange(of: search.query) { _, _ in selected = nil; search.search() }
        .onChange(of: search.results.map(\.id)) { _, _ in selected = nil }
    }
}

@MainActor
final class LocationSearchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = ""
    @Published private(set) var results: [LocationChoice] = [
        LocationChoice(name: "Chicago", detail: "Illinois, United States", latitude: 41.8781, longitude: -87.6298),
        LocationChoice(name: "New York", detail: "New York, United States", latitude: 40.7128, longitude: -74.0060),
        LocationChoice(name: "London", detail: "United Kingdom", latitude: 51.5074, longitude: -0.1278),
        LocationChoice(name: "Tokyo", detail: "Japan", latitude: 35.6762, longitude: 139.6503)
    ]
    @Published private(set) var searching = false
    @Published private(set) var locating = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var geocoder = CLGeocoder()
    private var manager: CLLocationManager?
    private let makeManager: () -> CLLocationManager

    init(makeManager: @escaping () -> CLLocationManager = CLLocationManager.init) {
        self.makeManager = makeManager
        super.init()
    }

    func search() {
        task?.cancel(); geocoder.cancelGeocode()
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil; locating = false
        error = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searching = false; return }
        searching = true
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                let places = try await self.geocoder.geocodeAddressString(query)
                guard !Task.isCancelled else { return }
                self.results = places.compactMap(Self.choice)
                self.searching = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searching = false
                self.results = []
                self.error = "Couldn’t find that place. Check your connection or try a nearby city."
            }
        }
    }

    func findCurrentLocation() {
        cancel(); error = nil; locating = true
        let manager = makeManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { handleAuthorization(manager.authorizationStatus) }
    }

    func cancel() {
        task?.cancel(); task = nil; geocoder.cancelGeocode()
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        searching = false; locating = false
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard locating else { return }
        switch status {
        case .authorized, .authorizedAlways: manager?.requestLocation()
        case .denied, .restricted:
            error = "Location access is off. You can search for a city instead."
            locating = false
        case .notDetermined: break
        @unknown default: locating = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.manager === manager else { return }
            self.handleAuthorization(status)
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self, self.locating, self.manager === manager else { return }
            self.locating = false
            self.manager?.stopUpdatingLocation()
            self.results = [LocationChoice(name: "Current location", detail: "\(location.coordinate.latitude.formatted(.number.precision(.fractionLength(2)))), \(location.coordinate.longitude.formatted(.number.precision(.fractionLength(2))))", latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)]
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.locating, self.manager === manager else { return }
            self.locating = false
            self.error = "Couldn’t get your location. You can search for a city instead."
        }
    }
    private static func choice(_ place: CLPlacemark) -> LocationChoice? {
        guard let location = place.location else { return nil }
        return LocationChoice(name: place.locality ?? place.name ?? "Place", detail: [place.administrativeArea, place.country].compactMap { $0 }.joined(separator: ", "), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
