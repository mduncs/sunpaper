import SwiftUI
import CoreLocation
import ServiceManagement

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingLocationPicker = false
    @State private var showingResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Location
                locationSection

                Divider()

                // Solar tracking toggle
                solarTrackingSection

                if viewModel.config.enableSolarTracking {
                    Divider()

                    // Display mode
                    displayModeSection

                    Divider()

                    // Time slots
                    timeSlotsSection

                    Divider()

                    // Today's schedule
                    scheduleSection
                }

                Divider()

                // General settings
                generalSection

                Spacer(minLength: 20)
            }
            .padding()
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 500)
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                currentLocation: viewModel.config.locationName,
                onSelect: { name, lat, lon in
                    viewModel.setLocation(name: name, latitude: lat, longitude: lon)
                }
            )
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Image(systemName: "sun.horizon.fill")
                .font(.largeTitle)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading) {
                Text("Sunpaper")
                    .font(.title2.bold())
                Text("Wallpapers that follow the sun")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)

                if let name = viewModel.config.locationName {
                    Text(name)
                } else {
                    Text("Not set")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Change") {
                    showingLocationPicker = true
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Polar region warning
            if let warning = viewModel.polarWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private var solarTrackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $viewModel.config.enableSolarTracking) {
                VStack(alignment: .leading) {
                    Text("Change wallpaper by sun position")
                        .font(.headline)
                    Text("Automatically switch wallpapers at sunrise, sunset, and custom times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Configuration")
                .font(.headline)

            Picker("", selection: $viewModel.config.displayMode) {
                Text("Same on all displays").tag(DisplayMode.allDisplays)
                Text("Per-display wallpapers").tag(DisplayMode.perDisplay)
            }
            .pickerStyle(.radioGroup)

            if viewModel.config.displayMode == .perDisplay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Displays")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(viewModel.displays) { display in
                        HStack {
                            Image(systemName: display.isPrimary ? "desktopcomputer" : "display")
                                .foregroundColor(display.isPrimary ? .blue : .secondary)
                            Text(display.displayName)
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var timeSlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.config.displayMode == .allDisplays {
                // All displays mode - show single slot list
                allDisplaysSlotsView
            } else {
                // Per-display mode - show tabbed interface
                perDisplaySlotsView
            }
        }
    }

    private var allDisplaysSlotsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Slots")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addSlot()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.config.slots.isEmpty {
                emptySlotState
            } else {
                ForEach($viewModel.config.slots) { $slot in
                    TimeSlotRow(
                        slot: $slot,
                        onDelete: { viewModel.removeSlot(id: slot.id) },
                        onPreview: { viewModel.previewWallpaper(slot.source) }
                    )
                }
            }
        }
    }

    private var perDisplaySlotsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Slots")
                    .font(.headline)
                Spacer()
            }

            if viewModel.displays.isEmpty {
                Text("No displays detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                TabView(selection: $viewModel.selectedDisplayUUID) {
                    ForEach(viewModel.displays) { display in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: display.isPrimary ? "desktopcomputer" : "display")
                                    .foregroundColor(display.isPrimary ? .blue : .secondary)
                                Text(display.displayName)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    viewModel.addSlot(for: display.uuid)
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            let displaySlots = viewModel.getDisplaySlots(for: display.uuid)
                            if displaySlots.isEmpty {
                                emptySlotState
                            } else {
                                ForEach(displaySlots.indices, id: \.self) { index in
                                    TimeSlotRow(
                                        slot: viewModel.displaySlotBinding(for: display.uuid, at: index),
                                        onDelete: { viewModel.removeSlot(for: display.uuid, at: index) },
                                        onPreview: { viewModel.previewWallpaper(displaySlots[index].source, displayUUID: display.uuid) }
                                    )
                                }
                            }
                        }
                        .padding(.top, 8)
                        .tabItem {
                            Text(display.displayName)
                        }
                        .tag(display.uuid)
                    }
                }
                .frame(minHeight: 300)
            }
        }
    }

    private var emptySlotState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("No time slots configured")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Add at least one slot to enable wallpaper changes")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                viewModel.addSlot()
            } label: {
                Label("Add Slot", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Schedule")
                .font(.headline)

            if viewModel.todaySchedule.isEmpty {
                Text("No transitions scheduled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.todaySchedule, id: \.slot.id) { item in
                        HStack {
                            Text(formatTime(item.time))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 70, alignment: .leading)

                            Text(item.slot.name)

                            if item.slot.id == viewModel.currentSlot?.id {
                                Text("(now)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.secondary)
            }

            Button("Reset to Defaults") {
                showingResetConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    viewModel.resetToDefaults()
                }
            } message: {
                Text("This will delete your custom time slots and restore the default configuration.")
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Time Slot Row

struct TimeSlotRow: View {
    @Binding var slot: TimeSlot
    let onDelete: () -> Void
    let onPreview: () -> Void
    @State private var showingTriggerEditor = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon based on slot name
            Image(systemName: slotIcon)
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColors.0, iconColors.1)
                .frame(width: 32)

            // Main content
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: Name and delete
                HStack {
                    TextField("Name", text: $slot.name)
                        .textFieldStyle(.plain)
                        .font(.headline)

                    Spacer()

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Row 2: Trigger and wallpaper
                HStack(spacing: 12) {
                    // Trigger button - shows current setting
                    Button {
                        showingTriggerEditor.toggle()
                    } label: {
                        Text(slot.trigger.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingTriggerEditor) {
                        TriggerEditorPopover(trigger: $slot.trigger)
                    }

                    Spacer()

                    // Wallpaper picker
                    WallpaperPicker(source: $slot.source, onPreview: onPreview)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // Icon based on slot name keywords
    private var slotIcon: String {
        let name = slot.name.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return "sunrise.fill"
        } else if name.contains("day") || name.contains("noon") || name.contains("afternoon") {
            return "sun.max.fill"
        } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return "sunset.fill"
        } else if name.contains("night") || name.contains("dark") {
            return "moon.stars.fill"
        }
        // Fallback to trigger-based icon
        return slot.trigger.icon
    }

    private var iconColors: (Color, Color) {
        let name = slot.name.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return (.pink, .orange)
        } else if name.contains("day") || name.contains("noon") || name.contains("afternoon") {
            return (.yellow, .orange)
        } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return (.orange, .red)
        } else if name.contains("night") || name.contains("dark") {
            return (.indigo, .purple)
        }
        // Fallback to trigger-based colors
        switch slot.trigger {
        case .solar(let event, _):
            switch event {
            case .sunrise, .civilDawn: return (.pink, .orange)
            case .sunset, .civilDusk: return (.orange, .red)
            case .solarNoon: return (.yellow, .orange)
            }
        case .fixed:
            return (.blue, .cyan)
        }
    }
}

// MARK: - Trigger Editor Popover

struct TriggerEditorPopover: View {
    @Binding var trigger: Trigger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trigger Time")
                .font(.headline)

            // Event picker
            Picker("Event", selection: eventBinding) {
                ForEach(SolarEvent.allCases, id: \.self) { event in
                    Text(event.displayName).tag(Optional(event))
                }
                Divider()
                Text("Fixed Time").tag(Optional<SolarEvent>.none)
            }
            .pickerStyle(.radioGroup)

            Divider()

            // Offset or time picker
            if case .solar(_, let offset) = trigger {
                HStack {
                    Text("Offset")
                    Spacer()
                    Stepper(value: offsetBinding, in: -180...180, step: 15) {
                        Text(formatOffset(offset))
                            .monospacedDigit()
                    }
                }
            } else if case .fixed = trigger {
                HStack {
                    Text("Time")
                    Spacer()
                    DatePicker("", selection: fixedTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func formatOffset(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes == 0 { return "±0" }
        let sign = minutes > 0 ? "+" : ""
        if abs(minutes) >= 60 {
            let hours = minutes / 60
            let mins = abs(minutes) % 60
            if mins == 0 {
                return "\(sign)\(hours)h"
            }
            return "\(sign)\(hours)h \(mins)m"
        }
        return "\(sign)\(minutes)m"
    }

    private var eventBinding: Binding<SolarEvent?> {
        Binding(
            get: {
                if case .solar(let event, _) = trigger { return event }
                return nil
            },
            set: { newEvent in
                if let event = newEvent {
                    let currentOffset: TimeInterval
                    if case .solar(_, let offset) = trigger {
                        currentOffset = offset
                    } else {
                        currentOffset = 0
                    }
                    trigger = .solar(event: event, offset: currentOffset)
                } else {
                    trigger = .fixed(hour: 12, minute: 0)
                }
            }
        )
    }

    private var offsetBinding: Binding<TimeInterval> {
        Binding(
            get: {
                if case .solar(_, let offset) = trigger {
                    return offset / 60 // Convert to minutes for stepper
                }
                return 0
            },
            set: { newMinutes in
                if case .solar(let event, _) = trigger {
                    trigger = .solar(event: event, offset: newMinutes * 60)
                }
            }
        )
    }

    private var fixedTimeBinding: Binding<Date> {
        Binding(
            get: {
                if case .fixed(let hour, let minute) = trigger {
                    var components = DateComponents()
                    components.hour = hour
                    components.minute = minute
                    return Calendar.current.date(from: components) ?? Date()
                }
                return Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                trigger = .fixed(hour: components.hour ?? 12, minute: components.minute ?? 0)
            }
        )
    }
}

// MARK: - Trigger Picker

struct TriggerPicker: View {
    @Binding var trigger: Trigger

    var body: some View {
        HStack(spacing: 4) {
            // Event picker
            Picker("", selection: eventBinding) {
                ForEach(SolarEvent.allCases, id: \.self) { event in
                    Text(event.displayName).tag(event)
                }
                Divider()
                Text("Fixed Time").tag(Optional<SolarEvent>.none)
            }
            .labelsHidden()
            .frame(width: 100)

            // Offset stepper (for solar events)
            if case .solar(_, let offset) = trigger {
                OffsetStepper(offset: offsetBinding)
            }

            // Time picker (for fixed)
            if case .fixed(let hour, let minute) = trigger {
                DatePicker("", selection: fixedTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 80)
            }
        }
    }

    private var eventBinding: Binding<SolarEvent?> {
        Binding(
            get: {
                if case .solar(let event, _) = trigger { return event }
                return nil
            },
            set: { newEvent in
                if let event = newEvent {
                    // Preserve offset when switching events
                    let currentOffset: TimeInterval
                    if case .solar(_, let offset) = trigger {
                        currentOffset = offset
                    } else {
                        currentOffset = 0
                    }
                    trigger = .solar(event: event, offset: currentOffset)
                } else {
                    trigger = .fixed(hour: 12, minute: 0)
                }
            }
        )
    }

    private var offsetBinding: Binding<TimeInterval> {
        Binding(
            get: {
                if case .solar(_, let offset) = trigger { return offset }
                return 0
            },
            set: { newOffset in
                if case .solar(let event, _) = trigger {
                    trigger = .solar(event: event, offset: newOffset)
                }
            }
        )
    }

    private var fixedTimeBinding: Binding<Date> {
        Binding(
            get: {
                if case .fixed(let hour, let minute) = trigger {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                    components.hour = hour
                    components.minute = minute
                    return Calendar.current.date(from: components) ?? Date()
                }
                return Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                trigger = .fixed(hour: components.hour ?? 12, minute: components.minute ?? 0)
            }
        )
    }
}

// MARK: - Offset Stepper

struct OffsetStepper: View {
    @Binding var offset: TimeInterval

    private var hours: Int { Int(offset / 3600) }
    private var displayText: String {
        if offset == 0 { return "±0" }
        let sign = offset > 0 ? "+" : ""
        return "\(sign)\(hours)h"
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                offset -= 3600
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 40)

            Button {
                offset += 3600
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Wallpaper Picker

struct WallpaperPicker: View {
    @Binding var source: WallpaperSource
    let onPreview: () -> Void

    @State private var showingGridPicker = false
    @StateObject private var catalog = AerialCatalog.shared

    var body: some View {
        Button {
            showingGridPicker = true
        } label: {
            HStack(spacing: 8) {
                // Mini thumbnail
                if case .builtIn(let assetID) = source,
                   let asset = catalog.asset(for: assetID) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 36, height: 22))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 36, height: 22)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }

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
        .sheet(isPresented: $showingGridPicker) {
            WallpaperGridPicker(selectedSource: $source) { newSource in
                source = newSource
                onPreview()
            }
        }
    }

    private var displayName: String {
        switch source {
        case .none:
            return "None"
        case .builtIn(let assetID):
            return catalog.asset(for: assetID)?.displayName ?? "Select..."
        case .custom(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

// MARK: - View Model

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var config: WallpaperConfig {
        didSet {
            saveConfig()
            notifyAppDelegate()
            updateSchedule()
        }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            toggleLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var todaySchedule: [(slot: TimeSlot, time: Date)] = []
    @Published var currentSlot: TimeSlot?
    @Published var polarWarning: String?
    @Published var displays: [DisplayManager.Display] = []
    @Published var selectedDisplayUUID: String = ""

    init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "wallpaperConfig"),
           let loaded = try? JSONDecoder().decode(WallpaperConfig.self, from: data) {
            config = loaded
        } else {
            config = .default
        }

        // Load displays
        displays = DisplayManager.shared.getDisplays()
        if let primary = displays.first {
            selectedDisplayUUID = primary.uuid
        }

        // Initial schedule update
        updateSchedule()

        // Load launch at login state from SMAppService
        loadLaunchAtLoginState()
    }

    private func notifyAppDelegate() {
        // Sync config to AppDelegate's scheduler
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateConfig(config)
        }
    }

    func setLocation(name: String, latitude: Double, longitude: Double) {
        config.locationName = name
        config.latitude = latitude
        config.longitude = longitude
        updateSchedule()
    }

    func addSlot() {
        let newSlot = TimeSlot(
            name: "New",
            trigger: .solar(event: .solarNoon, offset: 0),
            source: .none
        )
        config.slots.append(newSlot)
    }

    func removeSlot(id: UUID) {
        config.slots.removeAll { $0.id == id }
    }

    func previewWallpaper(_ source: WallpaperSource, displayUUID: String? = nil) {
        switch source {
        case .builtIn(let assetID):
            try? WallpaperService.shared.setWallpaper(assetID: assetID, displayUUID: displayUUID)
        case .custom(let path):
            try? WallpaperService.shared.setCustomWallpaper(path: path)
        case .none:
            break
        }
    }

    func resetToDefaults() {
        config = .default
    }

    // MARK: - Per-Display Management

    func addSlot(for displayUUID: String) {
        let newSlot = TimeSlot(
            name: "New",
            trigger: .solar(event: .solarNoon, offset: 0),
            source: .none
        )
        var displaySlots = config.slots(for: displayUUID)
        displaySlots.append(newSlot)
        config.setSlots(displaySlots, for: displayUUID)
    }

    func removeSlot(for displayUUID: String, at index: Int) {
        var displaySlots = config.slots(for: displayUUID)
        guard index < displaySlots.count else { return }
        displaySlots.remove(at: index)
        config.setSlots(displaySlots, for: displayUUID)
    }

    func getDisplaySlots(for displayUUID: String) -> [TimeSlot] {
        return config.slots(for: displayUUID)
    }

    func displaySlotBinding(for displayUUID: String, at index: Int) -> Binding<TimeSlot> {
        Binding(
            get: {
                let slots = self.config.slots(for: displayUUID)
                guard index < slots.count else {
                    return TimeSlot(name: "", trigger: .solar(event: .solarNoon, offset: 0), source: .none)
                }
                return slots[index]
            },
            set: { newValue in
                var slots = self.config.slots(for: displayUUID)
                guard index < slots.count else { return }
                slots[index] = newValue
                self.config.setSlots(slots, for: displayUUID)
            }
        )
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "wallpaperConfig")
        }
    }

    private func updateSchedule() {
        guard let lat = config.latitude, let lon = config.longitude else {
            polarWarning = nil
            return
        }

        let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let sunTimes = SunCalculator.calculate(for: location)

        todaySchedule = config.sortedSlots(sunTimes: sunTimes).map { slot in
            (slot: slot, time: slot.resolvedTime(sunTimes: sunTimes))
        }
        currentSlot = config.currentSlot(sunTimes: sunTimes)

        // Check for polar conditions
        polarWarning = SunCalculator.polarDescription(for: sunTimes.polarCondition)
    }

    // MARK: - Launch at Login

    private func loadLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    // Already enabled, nothing to do
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    // Already disabled, nothing to do
                    return
                }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            #if DEBUG
            print("[Launch at Login] Error toggling: \(error)")
            #endif
            // Revert the UI state on error
            DispatchQueue.main.async {
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - Location Picker

struct LocationPickerView: View {
    let currentLocation: String?
    let onSelect: (String, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchViewModel = LocationSearchViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("Set Location")
                .font(.headline)

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search city...", text: $searchViewModel.searchText)
                    .textFieldStyle(.plain)
                if searchViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Search results or quick picks
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !searchViewModel.searchResults.isEmpty {
                        ForEach(searchViewModel.searchResults) { result in
                            LocationButton(
                                name: result.displayName,
                                lat: result.latitude,
                                lon: result.longitude,
                                onSelect: selectAndDismiss
                            )
                        }
                    } else if searchViewModel.searchText.isEmpty {
                        Text("Quick picks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(LocationSearchViewModel.quickPicks) { pick in
                            LocationButton(
                                name: pick.displayName,
                                lat: pick.latitude,
                                lon: pick.longitude,
                                onSelect: selectAndDismiss
                            )
                        }
                    } else if !searchViewModel.isSearching {
                        Text("No results found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
            }

            Divider()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 320, height: 400)
    }

    private func selectAndDismiss(name: String, lat: Double, lon: Double) {
        onSelect(name, lat, lon)
        dismiss()
    }
}

struct LocationButton: View {
    let name: String
    let lat: Double
    let lon: Double
    let onSelect: (String, Double, Double) -> Void

    var body: some View {
        Button {
            onSelect(name, lat, lon)
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.red)
                Text(name)
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Location Search ViewModel

struct LocationResult: Identifiable {
    let id = UUID()
    let displayName: String
    let latitude: Double
    let longitude: Double
}

@MainActor
class LocationSearchViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            searchDebounced()
        }
    }
    @Published var searchResults: [LocationResult] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?
    private let geocoder = CLGeocoder()

    static let quickPicks: [LocationResult] = [
        LocationResult(displayName: "Chicago, IL, USA", latitude: 41.8781, longitude: -87.6298),
        LocationResult(displayName: "New York, NY, USA", latitude: 40.7128, longitude: -74.0060),
        LocationResult(displayName: "San Francisco, CA, USA", latitude: 37.7749, longitude: -122.4194),
        LocationResult(displayName: "Los Angeles, CA, USA", latitude: 34.0522, longitude: -118.2437),
        LocationResult(displayName: "London, UK", latitude: 51.5074, longitude: -0.1278),
        LocationResult(displayName: "Paris, France", latitude: 48.8566, longitude: 2.3522),
        LocationResult(displayName: "Tokyo, Japan", latitude: 35.6762, longitude: 139.6503),
        LocationResult(displayName: "Sydney, Australia", latitude: -33.8688, longitude: 151.2093),
    ]

    private func searchDebounced() {
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            await search(query: searchText)
        }
    }

    private func search(query: String) async {
        isSearching = true

        do {
            let placemarks = try await geocoder.geocodeAddressString(query)

            guard !Task.isCancelled else { return }

            searchResults = placemarks.compactMap { placemark in
                guard let location = placemark.location else { return nil }

                let name = [
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ]
                .compactMap { $0 }
                .joined(separator: ", ")

                return LocationResult(
                    displayName: name.isEmpty ? query : name,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
        } catch {
            #if DEBUG
            print("[Location Search] Error: \(error)")
            #endif
            searchResults = []
        }

        isSearching = false
    }
}

#Preview {
    SettingsView()
}
