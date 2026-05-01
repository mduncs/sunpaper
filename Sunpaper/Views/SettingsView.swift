import SwiftUI
import CoreLocation
import ServiceManagement

struct SettingsView: View {
    private enum SettingsPane: Hashable {
        case schedule
        case wallpapers
        case general

        var title: String {
            switch self {
            case .schedule:
                return "Schedule"
            case .wallpapers:
                return "Wallpapers"
            case .general:
                return "General"
            }
        }
    }

    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingLocationPicker = false
    @State private var showingResetConfirmation = false
    @State private var selectedPane: SettingsPane = .schedule

    var body: some View {
        TabView(selection: $selectedPane) {
            schedulePane
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(SettingsPane.schedule)
                .accessibilityIdentifier("scheduleSettingsPane")

            wallpapersPane
                .tabItem {
                    Label("Wallpapers", systemImage: "photo.on.rectangle")
                }
                .tag(SettingsPane.wallpapers)
                .accessibilityIdentifier("wallpapersSettingsPane")

            generalPane
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsPane.general)
                .accessibilityIdentifier("generalSettingsPane")
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 600)
        .navigationTitle(selectedPane.title)
        .accessibilityIdentifier("settingsView")
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView(
                currentLocation: viewModel.config.locationName,
                onSelect: { name, lat, lon in
                    viewModel.setLocation(name: name, latitude: lat, longitude: lon)
                }
            )
        }
    }

    // MARK: - Panes

    private var schedulePane: some View {
        SettingsPaneContainer {
            SettingsSection("Location") {
                locationSection
            }

            SettingsSection("Tracking") {
                solarTrackingSection
            }

            SettingsSection("Today's Schedule") {
                scheduleSection
            }
        }
    }

    private var wallpapersPane: some View {
        SettingsPaneContainer {
            if !viewModel.config.enableSolarTracking {
                EmptySettingsState(
                    title: "Solar Tracking Is Off",
                    systemImage: "sun.horizon",
                    message: "Wallpaper slots are inactive until solar tracking is turned on."
                ) {
                    Button("Turn On") {
                        viewModel.config.enableSolarTracking = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("turnOnSolarTrackingButton")
                }
                .accessibilityIdentifier("solarTrackingOffState")
            }

            SettingsSection("Display Assignment") {
                displayModeSection
            }
            .disabled(!viewModel.config.enableSolarTracking)

            SettingsSection("Time Slots") {
                timeSlotsSection
            }
            .disabled(!viewModel.config.enableSolarTracking)
        }
    }

    private var generalPane: some View {
        SettingsPaneContainer {
            SettingsSection("Startup") {
                launchAtLoginSection
            }

            SettingsSection("About") {
                aboutSection
            }

            SettingsSection("Reset") {
                resetSection
            }
        }
    }

    // MARK: - Sections

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(
                title: "Current Location",
                help: "Used to calculate sunrise, sunset, and solar noon."
            ) {
                HStack(spacing: 8) {
                    Image(systemName: hasLocation ? "location.fill" : "location")
                        .foregroundColor(hasLocation ? .blue : .secondary)
                        .accessibilityHidden(true)

                    Text(locationDisplayName)
                        .lineLimit(1)
                        .foregroundColor(hasLocation ? .primary : .secondary)
                        .accessibilityLabel("Current location")
                        .accessibilityValue(locationDisplayName)

                    Spacer(minLength: 8)

                    Button(hasLocation ? "Change..." : "Set Location...") {
                        showingLocationPicker = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(hasLocation ? "Change location" : "Set location")
                    .accessibilityHint("Opens location search.")
                    .accessibilityIdentifier("changeLocationButton")
                }
            }
            .accessibilityIdentifier("currentLocationRow")

            if let warning = viewModel.polarWarning {
                StatusMessage(
                    warning,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Location warning")
                .accessibilityValue(warning)
                .accessibilityIdentifier("polarWarning")
            }
        }
        .accessibilityIdentifier("locationSection")
    }

    private var solarTrackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Solar Tracking", isOn: $viewModel.config.enableSolarTracking)
                .accessibilityLabel("Solar tracking")
                .accessibilityValue(viewModel.config.enableSolarTracking ? "On" : "Off")
                .accessibilityHint("Turns automatic wallpaper changes based on sun position on or off.")
                .accessibilityIdentifier("solarTrackingToggle")

            Text("Switch wallpapers at sunrise, sunset, solar noon, or a fixed time.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !hasLocation {
                StatusMessage(
                    "Set a location before Sunpaper can calculate today's transitions.",
                    systemImage: "location.slash",
                    tint: .secondary
                )
            }
        }
    }

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsControlRow(
                title: "Mode",
                help: displayModeDescription
            ) {
                Picker("Display mode", selection: $viewModel.config.displayMode) {
                    Text("All Displays").tag(DisplayMode.allDisplays)
                    Text("By Display").tag(DisplayMode.perDisplay)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Display mode")
                .accessibilityHint("Choose whether all displays use the same slots or each display has its own slots.")
                .accessibilityIdentifier("displayModePicker")
            }

            if viewModel.config.displayMode == .perDisplay {
                connectedDisplaysList
            }
        }
        .accessibilityIdentifier("displaySection")
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
            HStack(alignment: .firstTextBaseline) {
                Text("\(viewModel.config.slots.count) \(viewModel.config.slots.count == 1 ? "slot" : "slots")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button {
                    viewModel.addSlot()
                } label: {
                    Label("Add Slot", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add time slot")
                .accessibilityHint("Adds a wallpaper time slot for all displays.")
                .accessibilityIdentifier("addAllDisplaysSlotButton")
            }

            if viewModel.config.slots.isEmpty {
                emptySlotState(message: "Add a slot to create the schedule used on every display.") {
                    viewModel.addSlot()
                }
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
            if viewModel.displays.isEmpty {
                EmptySettingsState(
                    title: "No Displays Detected",
                    systemImage: "display",
                    message: "Sunpaper will show per-display slots after macOS reports a connected display."
                )
                .accessibilityIdentifier("noDisplaysState")
            } else {
                SettingsControlRow(
                    title: "Display",
                    help: "Choose the display whose schedule you want to edit."
                ) {
                    Picker("Display", selection: $viewModel.selectedDisplayUUID) {
                        ForEach(viewModel.displays) { display in
                            Text(display.displayName).tag(display.uuid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                    .accessibilityLabel("Display")
                    .accessibilityIdentifier("displaySlotsPicker")
                }

                if let display = viewModel.selectedDisplay {
                    displaySlotsEditor(for: display)
                }
            }
        }
    }

    private func displaySlotsEditor(for display: DisplayManager.Display) -> some View {
        let displaySlots = viewModel.getDisplaySlots(for: display.uuid)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(display.displayName, systemImage: display.isPrimary ? "desktopcomputer" : "display")
                    .font(.subheadline)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                Button {
                    viewModel.addSlot(for: display.uuid)
                } label: {
                    Label("Add Slot", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add time slot for \(display.displayName)")
                .accessibilityHint("Adds a wallpaper time slot for this display.")
                .accessibilityIdentifier("addDisplaySlotButton.\(display.uuid)")
            }

            if displaySlots.isEmpty {
                emptySlotState(message: "Add a slot to create the schedule for \(display.displayName).") {
                    viewModel.addSlot(for: display.uuid)
                }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("displaySlotsEditor.\(display.uuid)")
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let scheduleItems = viewModel.visibleTodaySchedule
            let visibleCurrentSlot = viewModel.visibleCurrentSlot

            if !viewModel.config.enableSolarTracking {
                EmptySettingsState(
                    title: "Tracking Is Off",
                    systemImage: "pause.circle",
                    message: "Turn on solar tracking to run today's wallpaper schedule."
                )
                .accessibilityIdentifier("emptyScheduleState")
            } else if !hasLocation {
                EmptySettingsState(
                    title: "No Location Set",
                    systemImage: "location",
                    message: "Set a location to calculate today's solar events."
                ) {
                    Button("Set Location...") {
                        showingLocationPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityIdentifier("emptyScheduleState")
            } else if scheduleItems.isEmpty {
                EmptySettingsState(
                    title: "No Transitions",
                    systemImage: "clock",
                    message: "Add at least one enabled time slot to create today's schedule."
                )
                .accessibilityIdentifier("emptyScheduleState")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let context = viewModel.scheduleContextDescription {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(scheduleItems, id: \.slot.id) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(formatTime(item.time))
                                .font(.system(.body, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 74, alignment: .leading)

                            Text(item.slot.name)
                                .lineLimit(1)

                            if item.slot.id == visibleCurrentSlot?.id {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(scheduleAccessibilityLabel(for: item, currentSlot: visibleCurrentSlot))
                    }
                }
                .accessibilityIdentifier("todayScheduleList")
            }
        }
        .accessibilityIdentifier("scheduleSection")
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open at Login", isOn: $viewModel.launchAtLogin)
                .accessibilityLabel("Launch at login")
                .accessibilityValue(viewModel.launchAtLogin ? "Enabled" : "Disabled")
                .accessibilityHint("Opens Sunpaper automatically when you sign in.")
                .accessibilityIdentifier("launchAtLoginToggle")

            Text("Uses the macOS login item service for this app.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutSection: some View {
        SettingsControlRow(title: "Version") {
            Text(appVersion)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel("Version")
                .accessibilityValue(appVersion)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("versionRow")
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Restore the default slots and clear custom schedule settings. Your selected location is reset as part of the default configuration.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Text("Reset Settings...")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Reset settings")
                .accessibilityHint("Opens a confirmation before removing custom time slots and restoring defaults.")
                .accessibilityIdentifier("resetDefaultsButton")

                Spacer()
            }
            .alert("Reset Settings?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    viewModel.resetToDefaults()
                }
            } message: {
                Text("This removes your custom time slots and restores the default configuration.")
            }
        }
    }

    private var connectedDisplaysList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.displays.isEmpty {
                Text("No displays detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("noConnectedDisplaysText")
            } else {
                ForEach(viewModel.displays) { display in
                    DisplaySummaryRow(display: display)
                }
            }
        }
        .accessibilityIdentifier("connectedDisplaysList")
    }

    private func emptySlotState(message: String, addAction: @escaping () -> Void) -> some View {
        EmptySettingsState(
            title: "No Time Slots",
            systemImage: "clock",
            message: message
        ) {
            Button {
                addAction()
            } label: {
                Label("Add Slot", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Add time slot")
            .accessibilityHint("Adds a wallpaper time slot.")
            .accessibilityIdentifier("emptyStateAddSlotButton")
        }
        .accessibilityIdentifier("emptyTimeSlotsState")
    }

    private var displayModeDescription: String {
        switch viewModel.config.displayMode {
        case .allDisplays:
            return "Use one shared schedule for every connected display."
        case .perDisplay:
            return "Configure a separate schedule for each connected display."
        }
    }

    private var locationDisplayName: String {
        if let name = viewModel.config.locationName, !name.isEmpty {
            return name
        }

        if hasLocation {
            return "Coordinates Set"
        }

        return "Not Set"
    }

    private var hasLocation: Bool {
        viewModel.config.latitude != nil && viewModel.config.longitude != nil
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func scheduleAccessibilityLabel(for item: (slot: TimeSlot, time: Date), currentSlot: TimeSlot?) -> String {
        let currentText = item.slot.id == currentSlot?.id ? ", current slot" : ""
        return "\(item.slot.name), \(formatTime(item.time))\(currentText)"
    }
}

// MARK: - Settings Layout

private struct SettingsPaneContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsControlRow<Content: View>: View {
    let title: String
    let help: String?
    let content: Content

    init(
        title: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                if let help {
                    Text(help)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 150, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptySettingsState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let actions: Actions

    init(
        title: String,
        systemImage: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            actions
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private extension EmptySettingsState where Actions == EmptyView {
    init(title: String, systemImage: String, message: String) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = EmptyView()
    }
}

private struct StatusMessage: View {
    let message: String
    let systemImage: String
    let tint: Color

    init(_ message: String, systemImage: String, tint: Color) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DisplaySummaryRow: View {
    let display: DisplayManager.Display

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: display.isPrimary ? "desktopcomputer" : "display")
                .foregroundColor(display.isPrimary ? .blue : .secondary)
                .accessibilityHidden(true)

            Text(display.displayName)
                .lineLimit(1)

            if !display.hasStableIdentity {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.secondary)
                    .help("macOS reported this display using a temporary identifier.")
                    .accessibilityLabel("Temporary display identifier")
            }

            Spacer()
        }
        .font(.caption)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.displayName)
        .accessibilityValue(display.isPrimary ? "Primary display" : "Connected display")
    }
}

// MARK: - Time Slot Row

struct TimeSlotRow: View {
    @Binding var slot: TimeSlot
    let onDelete: () -> Void
    let onPreview: () -> Void
    @State private var showingTriggerEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: slotIcon)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColors.0, iconColors.1)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                TextField("Slot name", text: $slot.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Slot name")
                    .accessibilityValue(slot.name)
                    .accessibilityIdentifier("timeSlotName.\(slot.id.uuidString)")

                Toggle("Enabled", isOn: $slot.isEnabled)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .accessibilityLabel("\(slot.name) enabled")
                    .accessibilityValue(slot.isEnabled ? "Enabled" : "Disabled")
                    .accessibilityIdentifier("timeSlotEnabled.\(slot.id.uuidString)")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete slot", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete Slot")
                .accessibilityLabel("Delete \(slot.name)")
                .accessibilityHint("Removes this time slot.")
                .accessibilityIdentifier("deleteTimeSlot.\(slot.id.uuidString)")
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Trigger")
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)

                    Button {
                        showingTriggerEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Label(slot.trigger.displayName, systemImage: slot.trigger.icon)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: 260, alignment: .leading)
                    .accessibilityLabel("Trigger")
                    .accessibilityValue(slot.trigger.displayName)
                    .accessibilityHint("Opens trigger editing.")
                    .accessibilityIdentifier("editTrigger.\(slot.id.uuidString)")
                    .popover(isPresented: $showingTriggerEditor) {
                        TriggerEditorPopover(trigger: $slot.trigger)
                    }
                }

                GridRow {
                    Text("Wallpaper")
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)

                    WallpaperPicker(source: $slot.source, onPreview: onPreview)
                        .frame(maxWidth: 300, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeSlotRow.\(slot.id.uuidString)")
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
    private enum TriggerMode: Hashable {
        case solar
        case fixed
    }

    @Binding var trigger: Trigger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Trigger")
                .font(.headline)

            Picker("Trigger type", selection: modeBinding) {
                Text("Solar").tag(TriggerMode.solar)
                Text("Fixed").tag(TriggerMode.fixed)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("triggerTypePicker")

            VStack(alignment: .leading, spacing: 10) {
                if case .solar = trigger {
                    labeledRow("Event") {
                        Picker("Event", selection: solarEventBinding) {
                            ForEach(SolarEvent.allCases, id: \.self) { event in
                                Text(event.displayName).tag(event)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 190, alignment: .leading)
                        .accessibilityLabel("Solar event")
                        .accessibilityHint("Choose the solar event that starts this slot.")
                        .accessibilityIdentifier("triggerEventPicker")
                    }

                    labeledRow("Offset") {
                        Stepper(value: offsetMinutesBinding, in: -180...180, step: 15) {
                            Text(formatOffset(currentSolarOffset))
                                .monospacedDigit()
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                        .accessibilityLabel("Solar offset")
                        .accessibilityValue(formatOffset(currentSolarOffset))
                        .accessibilityHint("Adjusts the trigger in 15 minute steps before or after the selected solar event.")
                        .accessibilityIdentifier("triggerOffsetStepper")
                    }
                } else {
                    labeledRow("Time") {
                        DatePicker("Fixed time", selection: fixedTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel("Fixed time")
                            .accessibilityHint("Sets the time of day for this trigger.")
                            .accessibilityIdentifier("triggerFixedTimePicker")
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("doneEditingTriggerButton")
            }
        }
        .padding()
        .frame(width: 310)
        .accessibilityIdentifier("triggerEditorPopover")
    }

    private func labeledRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private var modeBinding: Binding<TriggerMode> {
        Binding(
            get: {
                if case .solar = trigger { return .solar }
                return .fixed
            },
            set: { mode in
                switch mode {
                case .solar:
                    if case .solar = trigger { return }
                    trigger = .solar(event: .solarNoon, offset: 0)
                case .fixed:
                    if case .fixed = trigger { return }
                    trigger = .fixed(hour: 12, minute: 0)
                }
            }
        )
    }

    private var solarEventBinding: Binding<SolarEvent> {
        Binding(
            get: {
                if case .solar(let event, _) = trigger {
                    return event
                }
                return .solarNoon
            },
            set: { event in
                let offset = currentSolarOffset
                trigger = .solar(event: event, offset: offset)
            }
        )
    }

    private var offsetMinutesBinding: Binding<TimeInterval> {
        Binding(
            get: {
                if case .solar(_, let offset) = trigger {
                    return offset / 60
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

    private var currentSolarOffset: TimeInterval {
        if case .solar(_, let offset) = trigger {
            return offset
        }
        return 0
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
            Picker("Trigger event", selection: eventBinding) {
                ForEach(SolarEvent.allCases, id: \.self) { event in
                    Text(event.displayName).tag(Optional(event))
                }
                Divider()
                Text("Fixed Time").tag(Optional<SolarEvent>.none)
            }
            .labelsHidden()
            .frame(width: 100)
            .accessibilityLabel("Trigger event")
            .accessibilityIdentifier("inlineTriggerEventPicker")

            // Offset stepper (for solar events)
            if case .solar = trigger {
                OffsetStepper(offset: offsetBinding)
            }

            // Time picker (for fixed)
            if case .fixed = trigger {
                DatePicker("Fixed time", selection: fixedTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 80)
                    .accessibilityLabel("Fixed time")
                    .accessibilityIdentifier("inlineTriggerFixedTimePicker")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inlineTriggerPicker")
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
                Label("Decrease offset", systemImage: "minus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Moves the trigger one hour earlier.")
            .accessibilityIdentifier("decreaseOffsetButton")

            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 40)
                .accessibilityLabel("Offset")
                .accessibilityValue(displayText)

            Button {
                offset += 3600
            } label: {
                Label("Increase offset", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Moves the trigger one hour later.")
            .accessibilityIdentifier("increaseOffsetButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offsetStepper")
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
                if case .builtIn(let assetID) = source,
                   let asset = catalog.asset(for: assetID) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 38, height: 24))
                        .accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 38, height: 24)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityHidden(true)
                }

                Text(displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Wallpaper")
        .accessibilityValue(displayName)
        .accessibilityHint("Opens wallpaper selection. Selecting a wallpaper applies a preview.")
        .accessibilityIdentifier("wallpaperPickerButton")
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
            return catalog.asset(for: assetID)?.displayName
                ?? BuiltInWallpapers.name(for: assetID)
                ?? "Unknown Aerial"
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

    var selectedDisplay: DisplayManager.Display? {
        displays.first(where: { $0.uuid == selectedDisplayUUID }) ?? displays.first
    }

    var visibleTodaySchedule: [(slot: TimeSlot, time: Date)] {
        guard let sunTimes = currentSunTimes else { return [] }
        let date = Date()
        return visibleScheduleSlots
            .filter { $0.isEnabled }
            .sorted { $0.resolvedTime(sunTimes: sunTimes, on: date) < $1.resolvedTime(sunTimes: sunTimes, on: date) }
            .map { slot in
                (slot: slot, time: slot.resolvedTime(sunTimes: sunTimes, on: date))
            }
    }

    var visibleCurrentSlot: TimeSlot? {
        guard let sunTimes = currentSunTimes else { return nil }
        return WallpaperConfig.currentSlot(slots: visibleScheduleSlots, sunTimes: sunTimes)
    }

    var scheduleContextDescription: String? {
        guard config.displayMode == .perDisplay, let selectedDisplay else { return nil }
        return "Showing schedule for \(selectedDisplay.displayName)."
    }

    init() {
        // Load from UserDefaults
        let data = UserDefaults.standard.data(forKey: WallpaperConfig.userDefaultsKey)
        config = WallpaperConfig.decodeCompatibleOrDefault(from: data)

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

    private var visibleScheduleSlots: [TimeSlot] {
        if config.displayMode == .perDisplay, let selectedDisplay {
            return config.slots(for: selectedDisplay.uuid)
        }

        return config.slots
    }

    private var currentSunTimes: SunCalculator.SunTimes? {
        guard let lat = config.latitude, let lon = config.longitude else { return nil }
        let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return SunCalculator.calculate(for: location)
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: WallpaperConfig.userDefaultsKey)
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
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Location")
                    .font(.headline)

                Text("Current: \(currentLocation ?? "Not set")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("currentLocationSummary")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Search city or address", text: $searchViewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFieldFocused)
                        .accessibilityLabel("Search locations")
                        .accessibilityHint("Type a city or address to search.")
                        .accessibilityIdentifier("locationSearchField")

                    if searchViewModel.isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Searching locations")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("locationSearchRow")

                locationResults
            }
            .padding()

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("cancelLocationPickerButton")
            }
            .padding()
        }
        .frame(width: 380, height: 440)
        .onAppear {
            searchFieldFocused = true
        }
        .accessibilityIdentifier("locationPicker")
    }

    private var locationResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if !searchViewModel.searchResults.isEmpty {
                    resultHeader("Search Results")

                    ForEach(searchViewModel.searchResults) { result in
                        LocationButton(
                            name: result.displayName,
                            lat: result.latitude,
                            lon: result.longitude,
                            onSelect: selectAndDismiss
                        )
                    }
                } else if searchViewModel.searchText.isEmpty {
                    resultHeader("Quick Picks")

                    ForEach(LocationSearchViewModel.quickPicks) { pick in
                        LocationButton(
                            name: pick.displayName,
                            lat: pick.latitude,
                            lon: pick.longitude,
                            onSelect: selectAndDismiss
                        )
                    }
                } else if searchViewModel.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityIdentifier("searchingLocationsState")
                } else {
                    EmptySettingsState(
                        title: "No Locations Found",
                        systemImage: "magnifyingglass",
                        message: "Try a city, region, or street address."
                    )
                    .frame(minHeight: 180)
                    .accessibilityIdentifier("noLocationResults")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(searchViewModel.searchText.isEmpty ? "Quick location picks" : "Location search results")
        .accessibilityIdentifier("locationResultsList")
    }

    private func resultHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
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
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(name, lat, lon)
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.red)
                    .accessibilityHidden(true)
                Text(name)
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(name)
        .accessibilityHint("Sets this as the wallpaper schedule location.")
        .accessibilityIdentifier("locationResult.\(name)")
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
