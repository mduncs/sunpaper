import SwiftUI
import CoreLocation
import ServiceManagement

private enum SettingsDesign {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let smallCard: CGFloat = 12
        static let card: CGFloat = 18
        static let largeCard: CGFloat = 24
    }

    enum Sizing {
        static let iconTile: CGFloat = 42
        static let smallIconTile: CGFloat = 34
        static let rowMinHeight: CGFloat = 62
        static let settingsMaxWidth: CGFloat = 820
        static let settingsIdealWidth: CGFloat = 860
        static let settingsMinWidth: CGFloat = 720
        static let settingsIdealHeight: CGFloat = 640
        static let settingsMinHeight: CGFloat = 540
    }

    enum Color {
        static let sunrise = SwiftUI.Color(red: 1.00, green: 0.40, blue: 0.30)
        static let sunset = SwiftUI.Color(red: 1.00, green: 0.54, blue: 0.22)
        static let day = SwiftUI.Color(red: 1.00, green: 0.78, blue: 0.10)
        static let sky = SwiftUI.Color(red: 0.30, green: 0.55, blue: 1.00)
        static let twilight = SwiftUI.Color(red: 0.48, green: 0.38, blue: 1.00)
        static let night = SwiftUI.Color(red: 0.28, green: 0.25, blue: 0.78)
        static let success = SwiftUI.Color(red: 0.35, green: 0.75, blue: 0.35)
        static let warning = SwiftUI.Color(red: 1.00, green: 0.68, blue: 0.15)
        static let danger = SwiftUI.Color.red
    }
}

private enum SettingsPhase {
    case morning
    case day
    case evening
    case night
    case fixed

    var symbolName: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        case .fixed: return "clock.fill"
        }
    }

    var colors: (SwiftUI.Color, SwiftUI.Color) {
        switch self {
        case .morning: return (SettingsDesign.Color.sunrise, .pink)
        case .day: return (SettingsDesign.Color.day, SettingsDesign.Color.sunset)
        case .evening: return (SettingsDesign.Color.sunset, SettingsDesign.Color.twilight)
        case .night: return (SettingsDesign.Color.twilight, SettingsDesign.Color.night)
        case .fixed: return (SettingsDesign.Color.sky, .cyan)
        }
    }

    static func infer(slotName: String, trigger: Trigger) -> SettingsPhase {
        let name = slotName.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return .morning
        }
        if name.contains("day") || name.contains("noon") || name.contains("afternoon") {
            return .day
        }
        if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return .evening
        }
        if name.contains("night") || name.contains("dark") {
            return .night
        }

        switch trigger {
        case .solar(let event, _):
            switch event {
            case .sunrise, .civilDawn: return .morning
            case .solarNoon: return .day
            case .sunset, .civilDusk: return .evening
            }
        case .fixed:
            return .fixed
        }
    }
}

struct SettingsView: View {
    fileprivate enum SettingsPane: Hashable {
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

        var systemImage: String {
            switch self {
            case .schedule:
                return "sun.max.fill"
            case .wallpapers:
                return "photo.on.rectangle.angled"
            case .general:
                return "gearshape"
            }
        }
    }

    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingLocationPicker = false
    @State private var showingResetConfirmation = false
    @State private var selectedPane: SettingsPane = .schedule

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(selectedPane: $selectedPane)

            Divider()
                .opacity(0.45)

            Group {
                switch selectedPane {
                case .schedule:
                    schedulePane
                        .accessibilityIdentifier("scheduleSettingsPane")
                case .wallpapers:
                    wallpapersPane
                        .accessibilityIdentifier("wallpapersSettingsPane")
                case .general:
                    generalPane
                        .accessibilityIdentifier("generalSettingsPane")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: SettingsDesign.Sizing.settingsMinWidth,
            idealWidth: SettingsDesign.Sizing.settingsIdealWidth,
            minHeight: SettingsDesign.Sizing.settingsMinHeight,
            idealHeight: SettingsDesign.Sizing.settingsIdealHeight
        )
        .background(SettingsWindowBackground())
        .navigationTitle("Sunpaper Settings")
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
            SettingsCard(
                title: "Sun Position",
                subtitle: "Location and tracking determine when wallpaper slots run.",
                systemImage: "sun.and.horizon.fill",
                tint: SettingsDesign.Color.sunset
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: SettingsDesign.Spacing.xl) {
                        locationSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        Divider()
                        solarTrackingSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.lg) {
                        locationSection
                        Divider()
                        solarTrackingSection
                    }
                }
            }

            SettingsCard(
                title: "Today's Schedule",
                subtitle: scheduleCardSubtitle,
                systemImage: "calendar.badge.clock",
                tint: scheduleCardTint,
                trailing: {
                    SettingsStatusChip(
                        title: scheduleStatusTitle,
                        systemImage: scheduleStatusIcon,
                        tint: scheduleCardTint
                    )
                }
            ) {
                scheduleSection
            }
        }
    }

    private var wallpapersPane: some View {
        SettingsPaneContainer {
            if !viewModel.config.enableSolarTracking {
                SettingsCard(
                    title: "Solar Tracking Is Off",
                    subtitle: "Wallpaper slots are inactive until tracking is turned on.",
                    systemImage: "pause.circle.fill",
                    tint: SettingsDesign.Color.warning
                ) {
                    HStack(alignment: .center, spacing: SettingsDesign.Spacing.md) {
                        Text("Turn on solar tracking to edit and run wallpaper slots.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: SettingsDesign.Spacing.md)

                        Button("Turn On") {
                            viewModel.config.enableSolarTracking = true
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("turnOnSolarTrackingButton")
                    }
                }
                .accessibilityIdentifier("solarTrackingOffState")
            }

            SettingsCard(
                title: "Display Assignment",
                subtitle: displayModeDescription,
                systemImage: "display.2",
                tint: SettingsDesign.Color.sky
            ) {
                displayModeSection
            }
            .disabled(!viewModel.config.enableSolarTracking)
            .opacity(viewModel.config.enableSolarTracking ? 1 : 0.58)

            SettingsCard(
                title: "Time Slots",
                subtitle: timeSlotCardSubtitle,
                systemImage: "photo.stack",
                tint: SettingsDesign.Color.twilight
            ) {
                timeSlotsSection
            }
            .disabled(!viewModel.config.enableSolarTracking)
            .opacity(viewModel.config.enableSolarTracking ? 1 : 0.58)
        }
    }

    private var generalPane: some View {
        SettingsPaneContainer {
            SettingsCard(
                title: "Startup",
                subtitle: "Choose how Sunpaper starts with macOS.",
                systemImage: "paperplane.fill",
                tint: SettingsDesign.Color.sky
            ) {
                launchAtLoginSection
            }

            SettingsCard(
                title: "About",
                subtitle: "App version and build details.",
                systemImage: "sun.horizon.fill",
                tint: SettingsDesign.Color.sunset
            ) {
                aboutSection
            }

            SettingsCard(
                title: "Reset",
                subtitle: "Restore default scheduling settings.",
                systemImage: "arrow.counterclockwise",
                tint: SettingsDesign.Color.danger
            ) {
                resetSection
            }
        }
    }

    // MARK: - Sections

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            HStack(alignment: .center, spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(
                    systemImage: hasLocation ? "location.fill" : "location",
                    tint: hasLocation ? SettingsDesign.Color.sky : .secondary,
                    size: SettingsDesign.Sizing.smallIconTile
                )

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xxs) {
                    Text("Current Location")
                        .font(.system(size: 13, weight: .semibold))
                    Text(locationDisplayName)
                        .font(.system(size: 13))
                        .foregroundColor(hasLocation ? .primary : .secondary)
                        .lineLimit(1)
                        .accessibilityLabel("Current location")
                        .accessibilityValue(locationDisplayName)
                    Text("Used to calculate sunrise, sunset, and solar noon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: SettingsDesign.Spacing.md)

                Button(hasLocation ? "Change..." : "Set Location...") {
                    showingLocationPicker = true
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(hasLocation ? "Change location" : "Set location")
                .accessibilityHint("Opens location search.")
                .accessibilityIdentifier("changeLocationButton")
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            HStack(alignment: .top, spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(
                    systemImage: viewModel.config.enableSolarTracking ? "sun.max.fill" : "sun.max",
                    tint: viewModel.config.enableSolarTracking ? SettingsDesign.Color.day : .secondary,
                    size: SettingsDesign.Sizing.smallIconTile
                )

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xs) {
                    Toggle("Solar Tracking", isOn: $viewModel.config.enableSolarTracking)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityLabel("Solar tracking")
                        .accessibilityValue(viewModel.config.enableSolarTracking ? "On" : "Off")
                        .accessibilityHint("Turns automatic wallpaper changes based on sun position on or off.")
                        .accessibilityIdentifier("solarTrackingToggle")

                    Text("Switch wallpapers at sunrise, sunset, solar noon, or a fixed time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.lg) {
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            if viewModel.config.displayMode == .allDisplays {
                allDisplaysSlotsView
            } else {
                perDisplaySlotsView
            }
        }
    }

    private var allDisplaysSlotsView: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
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

        return VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Label(display.displayName, systemImage: display.isPrimary ? "desktopcomputer" : "display")
                    .font(.system(size: 13, weight: .semibold))
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
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
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.sm) {
                    if let context = viewModel.scheduleContextDescription {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(scheduleItems, id: \.slot.id) { item in
                        TodayScheduleRow(
                            slot: item.slot,
                            timeText: formatTime(item.time),
                            isCurrent: item.slot.id == visibleCurrentSlot?.id
                        )
                        .accessibilityLabel(scheduleAccessibilityLabel(for: item, currentSlot: visibleCurrentSlot))
                    }
                }
                .accessibilityIdentifier("todayScheduleList")
            }
        }
        .accessibilityIdentifier("scheduleSection")
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.sm) {
            Toggle("Open at Login", isOn: $viewModel.launchAtLogin)
                .font(.system(size: 13, weight: .semibold))
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            Text("Restore the default slots and clear custom schedule settings. Your selected location is reset as part of the default configuration.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Settings...", systemImage: "arrow.counterclockwise")
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.sm) {
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

    private var scheduleCardSubtitle: String {
        if !viewModel.config.enableSolarTracking {
            return "Tracking is paused."
        }
        if !hasLocation {
            return "Set a location to calculate today's solar events."
        }
        if let context = viewModel.scheduleContextDescription {
            return context
        }
        return "Resolved from your enabled wallpaper slots."
    }

    private var scheduleStatusTitle: String {
        if !viewModel.config.enableSolarTracking { return "Paused" }
        if !hasLocation { return "Location Needed" }
        if viewModel.visibleTodaySchedule.isEmpty { return "No Slots" }
        return "Ready"
    }

    private var scheduleStatusIcon: String {
        if !viewModel.config.enableSolarTracking { return "pause.circle.fill" }
        if !hasLocation { return "location.slash.fill" }
        if viewModel.visibleTodaySchedule.isEmpty { return "clock.badge.exclamationmark" }
        return "checkmark.circle.fill"
    }

    private var scheduleCardTint: Color {
        if !viewModel.config.enableSolarTracking || viewModel.visibleTodaySchedule.isEmpty {
            return SettingsDesign.Color.warning
        }
        if !hasLocation {
            return .secondary
        }
        return SettingsDesign.Color.success
    }

    private var timeSlotCardSubtitle: String {
        switch viewModel.config.displayMode {
        case .allDisplays:
            return "A shared schedule applies to every connected display."
        case .perDisplay:
            return "Edit the schedule for one display at a time."
        }
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

private struct SettingsWindowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SettingsDesign.Color.sky.opacity(0.14),
                    SettingsDesign.Color.sunrise.opacity(0.10),
                    SettingsDesign.Color.twilight.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsHeader: View {
    @Binding var selectedPane: SettingsView.SettingsPane

    private let panes: [SettingsView.SettingsPane] = [.schedule, .wallpapers, .general]

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.xl) {
            HStack(spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(
                    systemImage: "sun.horizon.fill",
                    tint: SettingsDesign.Color.sunset,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sunpaper")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 190, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sunpaper Settings")

            Spacer(minLength: SettingsDesign.Spacing.lg)

            HStack(spacing: SettingsDesign.Spacing.xs) {
                ForEach(panes, id: \.self) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                            .font(.system(size: 13, weight: selectedPane == pane ? .semibold : .regular))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, SettingsDesign.Spacing.md)
                            .frame(height: 32)
                            .frame(minWidth: 108)
                            .foregroundStyle(selectedPane == pane ? SettingsDesign.Color.sunset : .primary)
                            .background {
                                if selectedPane == pane {
                                    Capsule(style: .continuous)
                                        .fill(.regularMaterial)
                                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule(style: .continuous))
                    .accessibilityLabel(pane.title)
                    .accessibilityValue(selectedPane == pane ? "Selected" : "Not selected")
                    .accessibilityHint("Shows the \(pane.title.lowercased()) settings pane.")
                }
            }
            .padding(4)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
        }
        .padding(.leading, 94)
        .padding(.trailing, SettingsDesign.Spacing.xxl)
        .frame(height: 64)
    }
}

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
            .padding(SettingsDesign.Spacing.xxl)
            .frame(maxWidth: SettingsDesign.Sizing.settingsMaxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct SettingsCard<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.lg) {
            HStack(alignment: .top, spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xxs) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: SettingsDesign.Spacing.md)

                trailing
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SettingsDesign.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunpaperSettingsGlassCard()
    }
}

private extension SettingsCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            trailing: { EmptyView() },
            content: content
        )
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                label
                    .frame(width: 150, alignment: .leading)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.sm) {
                label

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = SettingsDesign.Sizing.iconTile

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                }

            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, tint.opacity(0.55))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SettingsStatusChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, SettingsDesign.Spacing.sm)
            .padding(.vertical, SettingsDesign.Spacing.xs)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

private struct TodayScheduleRow: View {
    let slot: TimeSlot
    let timeText: String
    let isCurrent: Bool

    private var phase: SettingsPhase {
        SettingsPhase.infer(slotName: slot.name, trigger: slot.trigger)
    }

    var body: some View {
        HStack(alignment: .center, spacing: SettingsDesign.Spacing.md) {
            SettingsIconTile(
                systemImage: phase.symbolName,
                tint: phase.colors.0,
                size: SettingsDesign.Sizing.smallIconTile
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(slot.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Label(slot.trigger.displayName, systemImage: slot.trigger.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: SettingsDesign.Spacing.md)

            VStack(alignment: .trailing, spacing: SettingsDesign.Spacing.xs) {
                Text(timeText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                if isCurrent {
                    SettingsStatusChip(title: "Current", systemImage: "checkmark.circle.fill", tint: SettingsDesign.Color.success)
                }
            }
        }
        .padding(.horizontal, SettingsDesign.Spacing.md)
        .padding(.vertical, SettingsDesign.Spacing.sm)
        .frame(minHeight: SettingsDesign.Sizing.rowMinHeight)
        .background(isCurrent ? SettingsDesign.Color.success.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.smallCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.Radius.smallCard, style: .continuous)
                .strokeBorder(isCurrent ? SettingsDesign.Color.success.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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
        VStack(spacing: SettingsDesign.Spacing.sm) {
            SettingsIconTile(systemImage: systemImage, tint: .secondary, size: 38)

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            actions
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SettingsDesign.Spacing.xl)
        .padding(.horizontal, SettingsDesign.Spacing.xl)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
        }
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
        HStack(alignment: .top, spacing: SettingsDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsDesign.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.control, style: .continuous))
    }
}

private struct DisplaySummaryRow: View {
    let display: DisplayManager.Display

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.sm) {
            SettingsIconTile(
                systemImage: display.isPrimary ? "desktopcomputer" : "display",
                tint: display.isPrimary ? SettingsDesign.Color.sky : .secondary,
                size: 28
            )

            Text(display.displayName)
                .font(.caption)
                .lineLimit(1)

            if display.isPrimary {
                SettingsStatusChip(title: "Primary", systemImage: "checkmark.circle.fill", tint: SettingsDesign.Color.sky)
                    .scaleEffect(0.88)
            }

            if !display.hasStableIdentity {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.secondary)
                    .help("macOS reported this display using a temporary identifier.")
                    .accessibilityLabel("Temporary display identifier")
            }

            Spacer()
        }
        .padding(.vertical, SettingsDesign.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.displayName)
        .accessibilityValue(display.isPrimary ? "Primary display" : "Connected display")
    }
}

private struct SettingsGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let borderOpacity = colorScheme == .dark ? 0.18 : 0.45
        let shadowOpacity = colorScheme == .dark ? 0.28 : 0.08

        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.largeCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.largeCard, style: .continuous)
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 8)
    }
}

private extension View {
    func sunpaperSettingsGlassCard() -> some View {
        modifier(SettingsGlassCardModifier())
    }
}

// MARK: - Time Slot Row

struct TimeSlotRow: View {
    @Binding var slot: TimeSlot
    let onDelete: () -> Void
    let onPreview: () -> Void
    @State private var showingTriggerEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
            HStack(alignment: .center, spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(
                    systemImage: phase.symbolName,
                    tint: phase.colors.0,
                    size: SettingsDesign.Sizing.iconTile
                )

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xs) {
                    TextField("Slot name", text: $slot.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityLabel("Slot name")
                        .accessibilityValue(slot.name)
                        .accessibilityIdentifier("timeSlotName.\(slot.id.uuidString)")

                    Label(slot.isEnabled ? "Enabled" : "Disabled", systemImage: slot.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(slot.isEnabled ? SettingsDesign.Color.success : .secondary)
                }

                Spacer(minLength: SettingsDesign.Spacing.md)

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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SettingsDesign.Spacing.lg) {
                    slotTriggerControl
                        .frame(maxWidth: .infinity, alignment: .leading)
                    slotWallpaperControl
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
                    slotTriggerControl
                    slotWallpaperControl
                }
            }
            .opacity(slot.isEnabled ? 1 : 0.62)
        }
        .padding(SettingsDesign.Spacing.lg)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.Radius.card, style: .continuous)
                .strokeBorder(slot.isEnabled ? phase.colors.0.opacity(0.26) : Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeSlotRow.\(slot.id.uuidString)")
    }

    private var slotTriggerControl: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xs) {
            Text("Trigger")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showingTriggerEditor = true
            } label: {
                HStack(spacing: SettingsDesign.Spacing.sm) {
                    Label(slot.trigger.displayName, systemImage: slot.trigger.icon)
                        .lineLimit(1)

                    Spacer(minLength: SettingsDesign.Spacing.sm)

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: 280, alignment: .leading)
            .accessibilityLabel("Trigger")
            .accessibilityValue(slot.trigger.displayName)
            .accessibilityHint("Opens trigger editing.")
            .accessibilityIdentifier("editTrigger.\(slot.id.uuidString)")
            .popover(isPresented: $showingTriggerEditor) {
                TriggerEditorPopover(trigger: $slot.trigger)
            }
        }
    }

    private var slotWallpaperControl: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xs) {
            Text("Wallpaper")
                .font(.caption)
                .foregroundStyle(.secondary)

            WallpaperPicker(source: $slot.source, onPreview: onPreview)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var phase: SettingsPhase {
        SettingsPhase.infer(slotName: slot.name, trigger: slot.trigger)
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
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.lg) {
            HStack(spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(systemImage: trigger.icon, tint: triggerTint, size: SettingsDesign.Sizing.smallIconTile)

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xxs) {
                    Text("Edit Trigger")
                        .font(.system(size: 15, weight: .semibold))
                    Text(trigger.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Picker("Trigger type", selection: modeBinding) {
                Text("Solar").tag(TriggerMode.solar)
                Text("Fixed").tag(TriggerMode.fixed)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("triggerTypePicker")

            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
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
        .padding(SettingsDesign.Spacing.lg)
        .frame(width: 340)
        .background(.regularMaterial)
        .accessibilityIdentifier("triggerEditorPopover")
    }

    private func labeledRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 58, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var triggerTint: Color {
        switch trigger {
        case .solar(let event, _):
            switch event {
            case .sunrise, .civilDawn: return SettingsDesign.Color.sunrise
            case .solarNoon: return SettingsDesign.Color.day
            case .sunset, .civilDusk: return SettingsDesign.Color.sunset
            }
        case .fixed:
            return SettingsDesign.Color.sky
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
            HStack(spacing: SettingsDesign.Spacing.sm) {
                if case .builtIn(let assetID) = source,
                   let asset = catalog.asset(for: assetID) {
                    AsyncThumbnail(url: asset.thumbnailURL, size: CGSize(width: 44, height: 28))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(sourcePlaceholderTint.opacity(0.14))
                        .frame(width: 44, height: 28)
                        .overlay {
                            Image(systemName: sourcePlaceholderIcon)
                                .font(.caption2)
                                .foregroundStyle(sourcePlaceholderTint)
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(sourceKind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 210, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 1)
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

    private var sourceKind: String {
        switch source {
        case .none:
            return "No wallpaper selected"
        case .builtIn:
            return "Apple aerial"
        case .custom:
            return "Custom image"
        }
    }

    private var sourcePlaceholderIcon: String {
        switch source {
        case .none:
            return "photo"
        case .builtIn:
            return "sparkles.rectangle.stack"
        case .custom:
            return "photo.fill"
        }
    }

    private var sourcePlaceholderTint: Color {
        switch source {
        case .none:
            return .secondary
        case .builtIn:
            return SettingsDesign.Color.twilight
        case .custom:
            return SettingsDesign.Color.sky
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
            todaySchedule = []
            currentSlot = nil
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
            HStack(spacing: SettingsDesign.Spacing.md) {
                SettingsIconTile(systemImage: "location.fill", tint: SettingsDesign.Color.sky)

                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.xxs) {
                    Text("Set Location")
                        .font(.system(size: 17, weight: .semibold))

                    Text("Current: \(currentLocation ?? "Not set")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("currentLocationSummary")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsDesign.Spacing.xl)

            Divider()

            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.md) {
                HStack(spacing: SettingsDesign.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

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
            .padding(SettingsDesign.Spacing.xl)

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
            .padding(SettingsDesign.Spacing.lg)
        }
        .frame(width: 460, height: 520)
        .background(SettingsWindowBackground())
        .onAppear {
            searchFieldFocused = true
        }
        .accessibilityIdentifier("locationPicker")
    }

    private var locationResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SettingsDesign.Spacing.xs) {
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
            .padding(.top, SettingsDesign.Spacing.xs)
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
            HStack(spacing: SettingsDesign.Spacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(SettingsDesign.Color.sunset)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(lat.formatted(.number.precision(.fractionLength(3)))), \(lon.formatted(.number.precision(.fractionLength(3))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(SettingsDesign.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.Radius.control, style: .continuous))
        .background(isHovered ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.28), in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.control, style: .continuous))
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
