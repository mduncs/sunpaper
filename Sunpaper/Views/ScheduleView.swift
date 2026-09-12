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
            HStack {
                Image(systemName: "sun.horizon.fill").foregroundStyle(SunpaperColor.accent)
                Text("Sunpaper").font(.headline)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            HStack(spacing: 18) {
                Button { showLocation = true } label: {
                    Label(controller.config.locationName ?? "Choose location", systemImage: "location")
                }
                .buttonStyle(.plain).help("Location for sunrise and sunset")
                displayChooser
                Spacer()
                Toggle("Follow schedule", isOn: Binding(
                    get: { controller.scheduler.playbackMode == .following }, set: { controller.setFollowing($0) }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            .font(.callout).padding(.horizontal, 24).padding(.vertical, 16)

            HStack(spacing: 14) {
                WallpaperThumbnail(source: controller.shownSource, size: CGSize(width: 96, height: 60))
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaperName(controller.shownSource)).font(.headline)
                    Text(controller.stateTitle).font(.callout).foregroundStyle(.secondary)
                    Text(controller.stateDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if case .temporary = controller.scheduler.playbackMode {
                    Button("Resume schedule") { controller.setFollowing(true) }
                } else {
                    Button("Use another…") { controller.isChoosingWallpaper = true }
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = controller.scheduler.lastError {
                        InlineNotice(text: error, actionTitle: "Retry") { controller.scheduler.retryLastApplication() }
                    } else if controller.needsLocation {
                        InlineNotice(text: "Choose a location for sunrise and sunset. You can also use fixed times.", actionTitle: "Choose…") { showLocation = true }
                    }
                    HStack {
                        Text("Your day").font(.title2.weight(.semibold))
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
                    if controller.slots.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sun.horizon").font(.largeTitle).foregroundStyle(.secondary)
                            Text("A day of your own").font(.headline)
                            Text("Choose a collection, or add your first wallpaper change.")
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(controller.slots) { slot in
                                ScheduleRow(controller: controller, slot: slot, rename: { renameSlot = SlotEditTarget(slot: slot, displayUUID: controller.scope) })
                                if slot.id != controller.slots.last?.id { Divider().padding(.leading, 112) }
                            }
                        }
                    }
                    HStack {
                        Button { addingScope = controller.scope; showAdd = true } label: { Label("Add change", systemImage: "plus") }
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
                    }.padding(.vertical, 4)
                }.padding(24)
            }
        }
        .background(SunpaperColor.surface)
        .tint(SunpaperColor.accent)
        .frame(minWidth: 720, minHeight: 600)
        .sheet(isPresented: $showLocation) { LocationChooser(controller: controller) }
        .sheet(isPresented: $controller.isChoosingWallpaper) { ManualWallpaperSheet(controller: controller) }
        .sheet(isPresented: $showAdd) {
            ChangeNameSheet(title: "Add a change", initialName: "", confirmationTitle: "Add change") { name in
                controller.editSlots("Add change", displayUUID: addingScope) { $0.append(TimeSlot(name: name, trigger: .fixed(hour: 12, minute: 0), isEnabled: true)) }
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
            .fixedSize()
        } else {
            Button(action: openSettings) { Label("All displays", systemImage: "display") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
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

    private var isCurrent: Bool {
        controller.scheduler.playbackMode == .following && controller.expectedSlot?.id == slot.id && controller.shownSource == slot.source && slot.source != .none
    }

    var body: some View {
        HStack(spacing: 14) {
            Button { editingScope = controller.scope; editingSlot = slot; source = slot.source; showWallpaper = true } label: {
                WallpaperThumbnail(source: slot.source)
            }
            .buttonStyle(.plain).accessibilityLabel("Choose wallpaper for \(slot.name)")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(slot.name).font(.headline)
                    if isCurrent { Text("Current").font(.caption).foregroundStyle(SunpaperColor.accent) }
                    if !slot.isEnabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
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
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(slot.trigger.readableName)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    if let time = controller.resolvedTime(for: slot.trigger) {
                        Text("Today, \(time.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Needs a location").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain).accessibilityLabel("Time for \(slot.name): \(slot.trigger.readableName)")
            .popover(isPresented: $showTime) {
                TimingEditor(controller: controller, trigger: (editingSlot ?? slot).trigger) { trigger in
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
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("More options for \(slot.name)")
        }
        .font(.callout)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(isCurrent ? SunpaperColor.accent.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showWallpaper) {
            WallpaperGridPicker(selectedSource: $source, title: "Wallpaper for \((editingSlot ?? slot).name)", confirmationTitle: "Use for \((editingSlot ?? slot).name)") { selection in
                var updated = editingSlot ?? slot; updated.source = selection; controller.updateSlot(updated, displayUUID: editingScope)
            }
        }
        .onAppear { source = slot.source }
    }
}

struct TimingEditor: View {
    @ObservedObject var controller: SunpaperController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Trigger
    let onSave: (Trigger) -> Void

    init(controller: SunpaperController, trigger: Trigger, onSave: @escaping (Trigger) -> Void) {
        self.controller = controller; _draft = State(initialValue: trigger); self.onSave = onSave
    }
    private var isSolar: Bool { if case .solar = draft { return true }; return false }
    private var event: SolarEvent { if case .solar(let event, _) = draft { return event }; return .sunrise }
    private var offset: Double { if case .solar(_, let offset) = draft { return offset / 60 }; return 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When should it change?").font(.headline)
            Picker("Timing", selection: Binding(get: { isSolar }, set: { draft = $0 ? .solar(event: .sunrise, offset: 0) : .fixed(hour: 12, minute: 0) })) {
                Text("Sunrise & sunset").tag(true)
                Text("Fixed time").tag(false)
            }.pickerStyle(.segmented).labelsHidden()
            if isSolar {
                Picker("Sun event", selection: Binding(get: { event }, set: { draft = .solar(event: $0, offset: offset * 60) })) {
                    ForEach(SolarEvent.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Text("Offset")
                    Spacer()
                    Stepper(value: Binding(get: { Int(offset) }, set: { draft = .solar(event: event, offset: Double($0) * 60) }), in: -360...360, step: 15) {
                        Text(offset == 0 ? "At the event" : "\(Int(abs(offset))) min \(offset < 0 ? "before" : "after")").monospacedDigit()
                    }.fixedSize()
                }
            } else {
                DatePicker("Time", selection: Binding(get: { controller.resolvedTime(for: draft) ?? Date() }, set: {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    draft = .fixed(hour: components.hour ?? 12, minute: components.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
            }
            if let date = controller.resolvedTime(for: draft) {
                Text("Today, \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
            } else {
                Text("Choose a location in Your day to calculate this time.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { onSave(draft); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 340).tint(SunpaperColor.accent)
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
