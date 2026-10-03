import SwiftUI

struct ScheduleView: View {
    @ObservedObject var controller: SunpaperController
    var openSettings: () -> Void = {}
    @State private var showLocation = false
    @State private var showAdd = false
    @State private var renameSlot: SlotEditTarget?
    @State private var addingScope: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showLocation = true } label: {
                    Label(controller.config.locationName ?? "Choose location", systemImage: "location.fill")
                }
                .buttonStyle(ToolbarPillStyle()).help("Location for sunrise and sunset")
                displayChooser
                Spacer()
                Toggle("Follow schedule", isOn: Binding(
                    get: { controller.scheduler.playbackMode == .following }, set: { controller.setFollowing($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(ToolbarPillStyle()).help("Settings").accessibilityLabel("Open Settings")
                    .padding(.leading, 6)
            }
            .font(.callout).padding(.horizontal, 24).padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    todayCard
                    if let error = controller.scheduler.lastError {
                        InlineNotice(text: error, actionTitle: "Retry") { Task { await controller.retryWallpaperChange() } }
                    } else if controller.needsLocation {
                        InlineNotice(text: "Choose a location for sunrise and sunset. You can also use fixed times.", actionTitle: "Choose…") { showLocation = true }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your day").font(.title2.weight(.semibold))
                        Text(changeCount).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(BuiltInWallpapers.allSets, id: \.name) { set in
                                Button(set.name) { controller.useCollection(set) }
                            }
                        } label: {
                            Text("Collection: \(controller.collectionName)")
                        }
                        .fixedSize().help("Replace this schedule with four matching wallpapers. You can undo this.")
                    }
                    .padding(.top, 4)
                    if controller.slots.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sun.horizon.fill").symbolRenderingMode(.multicolor).font(.system(size: 34))
                            Text("A day of your own").font(.headline)
                            Text("Choose a collection, or add your first wallpaper change.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        VStack(spacing: 4) {
                            ForEach(slotsInDayOrder) { slot in
                                ScheduleRow(controller: controller, slot: slot, rename: { renameSlot = SlotEditTarget(slot: slot, displayUUID: controller.scope) })
                            }
                        }
                    }
                    HStack {
                        Button { addingScope = controller.scope; showAdd = true } label: {
                            Label("Add change", systemImage: "plus.circle.fill").fontWeight(.medium)
                        }
                        .buttonStyle(.plain).foregroundStyle(SunpaperColor.accent)
                        Spacer()
                        if !controller.slots.isEmpty && !controller.slots.contains(where: \.isEnabled) {
                            Button("Enable these changes") {
                                controller.editSlots("Enable changes") { slots in
                                    for index in slots.indices { slots[index].isEnabled = true }
                                }
                            }
                            .controlSize(.small)
                        }
                    }.padding(.horizontal, 10)
                }
                .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 2)
            }
        }
        .background(SunpaperColor.surface)
        .tint(SunpaperColor.accent)
        .frame(minWidth: SunpaperSize.scheduleMinWidth, minHeight: SunpaperSize.scheduleMinHeight)
        .sheet(isPresented: $showLocation) { LocationChooser(controller: controller) }
        .sheet(isPresented: $controller.isChoosingWallpaper) { ManualWallpaperSheet(controller: controller) }
        .sheet(isPresented: $showAdd) {
            AddChangeSheet(controller: controller) { name, trigger in
                controller.editSlots("Add change", displayUUID: addingScope) { $0.append(TimeSlot(name: name, trigger: trigger, isEnabled: true)) }
            }
        }
        .sheet(item: $renameSlot) { target in
            ChangeNameSheet(title: "Rename change", initialName: target.slot.name, confirmationTitle: "Save") { name in
                var updated = target.slot; updated.name = name; controller.updateSlot(updated, displayUUID: target.displayUUID)
            }
        }
        .alert("Sunpaper", isPresented: Binding(get: { controller.message != nil }, set: { if !$0 { controller.message = nil } })) {
            Button("OK") { controller.message = nil }
        } message: { Text(controller.message ?? "") }
    }

    /// Rows read like the day: earliest change first, unresolved ones last.
    private var slotsInDayOrder: [TimeSlot] {
        let calendar = Calendar.current
        func minute(_ slot: TimeSlot) -> Int {
            guard let date = controller.resolvedTime(for: slot.trigger) else { return .max }
            return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        return controller.slots.enumerated()
            .sorted { (minute($0.element), $0.offset) < (minute($1.element), $1.offset) }
            .map(\.element)
    }

    private var changeCount: String {
        let active = controller.slots.filter(\.isEnabled).count
        return active == 1 ? "1 change" : "\(active) changes"
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                WallpaperThumbnail(source: controller.shownSource, size: CGSize(width: 124, height: 76), cornerRadius: 9)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(title: controller.stateTitle, tone: controller.statusTone)
                    Text(wallpaperName(controller.shownSource)).font(.title2.weight(.semibold)).lineLimit(1)
                    Text(controller.stateDetail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if case .temporary = controller.scheduler.playbackMode {
                    Button("Resume schedule") { controller.setFollowing(true) }
                } else {
                    Button("Use another…") { controller.isChoosingWallpaper = true }
                }
            }
            DayRibbon(controller: controller)
        }
        .padding(18)
        .ambientCard(controller.shownSource, cornerRadius: 16)
    }

    @ViewBuilder private var displayChooser: some View {
        if controller.config.displayMode == .perDisplay {
            Menu {
                ForEach(controller.displays, id: \.uuid) { display in
                    Button(display.name) { controller.selectedDisplayUUID = display.uuid }
                }
                ForEach(controller.config.perDisplayConfigs.filter { config in !controller.displays.contains(where: { $0.uuid == config.displayUUID }) }, id: \.displayUUID) { config in
                    Button("Disconnected display") { controller.selectedDisplayUUID = config.displayUUID }
                }
                Divider()
                Button("Display settings…", action: openSettings)
            } label: { Label(controller.scopeName, systemImage: "display") }
            .menuStyle(.borderlessButton).fixedSize().toolbarPill()
        } else {
            Button(action: openSettings) { Label("All displays", systemImage: "display") }
                .buttonStyle(ToolbarPillStyle()).foregroundStyle(.secondary)
        }
    }
}

private struct SlotEditTarget: Identifiable {
    let slot: TimeSlot
    let displayUUID: String?
    var id: UUID { slot.id }
}

private struct ScheduleRow: View {
    @ObservedObject var controller: SunpaperController
    let slot: TimeSlot
    let rename: () -> Void
    @State private var showWallpaper = false
    @State private var showTime = false
    @State private var source: WallpaperSource = .none
    @State private var editingScope: String?
    @State private var editingSlot: TimeSlot?
    @State private var hovering = false

    private var isCurrent: Bool {
        controller.scheduler.playbackMode == .following && controller.expectedSlot?.id == slot.id && controller.shownSource == slot.source && slot.source != .none
    }

    private var resolvedTime: Date? { controller.resolvedTime(for: slot.trigger) }

    private var triggerCaption: String {
        if case .fixed = slot.trigger { return "Every day" }
        return slot.trigger.readableName
    }

    var body: some View {
        HStack(spacing: 14) {
            Button { editingScope = controller.scope; editingSlot = slot; source = slot.source; showWallpaper = true } label: {
                WallpaperThumbnail(source: slot.source, size: CGSize(width: 92, height: 56), cornerRadius: 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent ? SunpaperColor.accent : Color.primary.opacity(0.08), lineWidth: isCurrent ? 2 : 1))
                    .saturation(slot.isEnabled ? 1 : 0).opacity(slot.isEnabled ? 1 : 0.55)
            }
            .buttonStyle(.plain).accessibilityLabel("Choose wallpaper for \(slot.name)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(slot.name).font(.headline)
                    if isCurrent { badge("Now", color: SunpaperColor.accent) }
                    if !slot.isEnabled { badge("Off", color: .secondary) }
                }
                Button { editingScope = controller.scope; editingSlot = slot; source = slot.source; showWallpaper = true } label: {
                    HStack(spacing: 5) {
                        Text(wallpaperName(slot.source)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Wallpaper for \(slot.name): \(wallpaperName(slot.source))")
            }
            Spacer(minLength: 8)
            Button { editingScope = controller.scope; editingSlot = slot; showTime = true } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(resolvedTime?.formatted(date: .omitted, time: .shortened) ?? "Needs a location")
                        .font(resolvedTime == nil ? .callout : .title3.weight(.semibold))
                        .foregroundStyle(resolvedTime == nil ? .secondary : .primary)
                        .monospacedDigit()
                    HStack(spacing: 5) {
                        Image(systemName: slot.trigger.symbolName).foregroundStyle(SunpaperColor.accent)
                        Text(triggerCaption)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
            }
            .buttonStyle(SunpaperRowButtonStyle())
            .opacity(slot.isEnabled ? 1 : 0.6)
            .accessibilityLabel("Time for \(slot.name): \(slot.trigger.readableName)")
            .popover(isPresented: $showTime) {
                TimingEditor(controller: controller, trigger: (editingSlot ?? slot).trigger, excluding: slot.id) { trigger in
                    var updated = editingSlot ?? slot; updated.trigger = trigger; controller.updateSlot(updated, displayUUID: editingScope)
                }
            }
            Menu {
                Button("Rename…", action: rename)
                Button(slot.isEnabled ? "Turn off change" : "Turn on change") {
                    var updated = slot; updated.isEnabled.toggle(); controller.updateSlot(updated)
                }
                Button("Duplicate") {
                    controller.editSlots("Duplicate change") { $0.append(TimeSlot(name: "\(slot.name) copy", trigger: slot.trigger, source: slot.source, isEnabled: slot.isEnabled)) }
                }
                if let assetID = slot.source.assetID {
                    Button(controller.redownloadingAssets.contains(assetID) ? "Downloading…" : "Download again") {
                        controller.downloadAgain(assetID: assetID)
                    }
                    .disabled(controller.redownloadingAssets.contains(assetID) || AerialCatalog.shared.asset(for: assetID)?.downloadURL == nil)
                }
                Divider()
                Button("Remove change", role: .destructive) {
                    controller.editSlots("Remove change") { $0.removeAll { $0.id == slot.id } }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
            .foregroundStyle(.secondary)
            .accessibilityLabel("More options for \(slot.name)")
        }
        .font(.callout)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? SunpaperColor.accent.opacity(0.09) : Color.primary.opacity(hovering ? 0.045 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrent ? SunpaperColor.accent.opacity(0.3) : Color.primary.opacity(0.05))
        )
        .onHover { hovering = $0 }
        .sheet(isPresented: $showWallpaper) {
            WallpaperGridPicker(selectedSource: $source, title: "Wallpaper for \((editingSlot ?? slot).name)", confirmationTitle: "Use for \((editingSlot ?? slot).name)") { selection in
                var updated = editingSlot ?? slot; updated.source = selection; controller.updateSlot(updated, displayUUID: editingScope)
            }
        }
        .onAppear { source = slot.source }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title).font(.caption2.weight(.semibold)).textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct ChangeNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirmationTitle: String
    let onSave: (String) -> Void
    @State private var name: String
    @FocusState private var focused: Bool
    init(title: String, initialName: String, confirmationTitle: String, onSave: @escaping (String) -> Void) {
        self.title = title; self.confirmationTitle = confirmationTitle; self.onSave = onSave
        _name = State(initialValue: initialName)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.headline)
            TextField("Name, e.g. Evening", text: $name).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmationTitle) { onSave(name.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 340).onAppear { focused = true }
    }
}
