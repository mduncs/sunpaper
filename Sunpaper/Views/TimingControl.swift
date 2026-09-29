import SwiftUI

/// Chooses when a change happens: relative to the sun, or at the same time daily.
/// It edits only the bound draft; callers decide when to save.
struct TimingControl: View {
    @ObservedObject var controller: SunpaperController
    @Binding var trigger: Trigger
    var excluding: UUID?

    static let anchors: [SolarEvent] = [.civilDawn, .sunrise, .solarNoon, .sunset, .civilDusk]
    /// Matches the scheduler's supported offset range, in minutes.
    static let offsetLimit = 360

    private var isSolar: Bool { if case .solar = trigger { return true }; return false }
    private var event: SolarEvent { if case .solar(let event, _) = trigger { return event }; return .sunrise }
    private var offsetMinutes: Int { if case .solar(_, let offset) = trigger { return Int((offset / 60).rounded()) }; return 0 }
    private var resolved: Date? { controller.resolvedTime(for: trigger) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modePicker
            readout
            DayTrack(controller: controller, trigger: trigger, excluding: excluding, onDrag: setMinuteOfDay, onStep: step)
            if isSolar {
                anchorChips
                offsetRow
            } else {
                fixedRow
            }
        }
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 3) {
            modeButton("Follow the sun", symbol: "sun.horizon.fill", selected: isSolar, action: useSolar)
            modeButton("Same time daily", symbol: "clock.fill", selected: !isSolar, action: useFixed)
        }
        .padding(3)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func modeButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(selected ? SunpaperColor.accent : Color.secondary)
                Text(title)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.1))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Switching modes keeps today's time where possible, anchored to the nearest sun event.
    private func useSolar() {
        guard !isSolar else { return }
        guard let time = resolved, let nearest = nearestSolar(to: minuteOfDay(time)) else {
            trigger = .solar(event: .sunrise, offset: 0); return
        }
        trigger = .solar(event: nearest.event, offset: Double(nearest.offset * 60))
    }

    private func useFixed() {
        guard isSolar else { return }
        let minute = resolved.map { roundedToFive(minuteOfDay($0)) % 1440 } ?? 12 * 60
        trigger = .fixed(hour: minute / 60, minute: minute % 60)
    }

    private func nearestSolar(to minute: Int) -> (event: SolarEvent, offset: Int)? {
        [SolarEvent.sunrise, .solarNoon, .sunset]
            .compactMap { event in eventMinute(event).map { (event: event, offset: roundedToFive(wrapped(minute - $0))) } }
            .filter { abs($0.offset) <= Self.offsetLimit }
            .min { abs($0.offset) < abs($1.offset) }
    }

    // MARK: Readout

    private var readout: some View {
        HStack(spacing: 12) {
            Image(systemName: trigger.symbolName).font(.title).foregroundStyle(SunpaperColor.accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                if let resolved {
                    Text(resolved.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Text(trigger.readableName).font(.title3.weight(.semibold))
                }
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        guard isSolar else { return "Every day" }
        return resolved == nil
            ? "Choose a location in Your day to see today’s time."
            : "\(trigger.readableName) · shifts with the seasons"
    }

    // MARK: Solar

    private var anchorChips: some View {
        HStack(spacing: 6) {
            ForEach(Self.anchors, id: \.self) { anchor in
                let selected = anchor == event
                Button { trigger = .solar(event: anchor, offset: Double(offsetMinutes * 60)) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: anchor.chipSymbol).font(.callout)
                        Text(anchor.shortName).font(.caption.weight(.medium))
                        Text(controller.resolvedTime(for: .solar(event: anchor, offset: 0))?.formatted(date: .omitted, time: .shortened) ?? "—")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .foregroundStyle(selected ? SunpaperColor.accent : Color.primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? SunpaperColor.accent.opacity(0.15) : Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? SunpaperColor.accent.opacity(0.6) : Color.primary.opacity(0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(anchor.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var offsetRow: some View {
        HStack(spacing: 8) {
            Text("Offset").foregroundStyle(.secondary)
            Spacer()
            stepButton("minus", by: -5, label: "Five minutes earlier").disabled(offsetMinutes <= -Self.offsetLimit)
            Text(offsetText).monospacedDigit().frame(minWidth: 132)
            stepButton("plus", by: 5, label: "Five minutes later").disabled(offsetMinutes >= Self.offsetLimit)
        }
        .font(.callout)
    }

    private var offsetText: String {
        guard offsetMinutes != 0 else { return "At \(event.shortName.lowercased())" }
        let minutes = abs(offsetMinutes)
        let parts = [minutes / 60 > 0 ? "\(minutes / 60) hr" : nil, minutes % 60 > 0 ? "\(minutes % 60) min" : nil]
        return "\(parts.compactMap { $0 }.joined(separator: " ")) \(offsetMinutes < 0 ? "before" : "after")"
    }

    // MARK: Fixed

    private var fixedRow: some View {
        HStack(spacing: 8) {
            Text("Exact time").foregroundStyle(.secondary)
            Spacer()
            stepButton("minus", by: -5, label: "Five minutes earlier")
            DatePicker("Exact time", selection: Binding(get: { resolved ?? Date() }, set: {
                let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                trigger = .fixed(hour: components.hour ?? 12, minute: components.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden().datePickerStyle(.field).fixedSize()
            stepButton("plus", by: 5, label: "Five minutes later")
        }
        .font(.callout)
    }

    // MARK: Editing

    private func stepButton(_ symbol: String, by minutes: Int, label: String) -> some View {
        Button { step(minutes) } label: {
            Image(systemName: symbol).font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func step(_ minutes: Int) {
        switch trigger {
        case .solar(let event, _):
            let value = min(max(offsetMinutes + minutes, -Self.offsetLimit), Self.offsetLimit)
            trigger = .solar(event: event, offset: Double(value * 60))
        case .fixed(let hour, let minute):
            let value = ((hour * 60 + minute + minutes) % 1440 + 1440) % 1440
            trigger = .fixed(hour: value / 60, minute: value % 60)
        }
    }

    /// Drags snap to five minutes: the offset for solar times, the clock for fixed times.
    /// A dragged solar time keeps its anchor; the offset is limited to the supported range.
    private func setMinuteOfDay(_ minute: Int) {
        if isSolar {
            guard let anchor = eventMinute(event) else { return }
            let offset = min(max(roundedToFive(wrapped(minute - anchor)), -Self.offsetLimit), Self.offsetLimit)
            trigger = .solar(event: event, offset: Double(offset * 60))
        } else {
            let snapped = min(roundedToFive(minute), 1435)
            trigger = .fixed(hour: snapped / 60, minute: snapped % 60)
        }
    }

    private func eventMinute(_ event: SolarEvent) -> Int? {
        controller.resolvedTime(for: .solar(event: event, offset: 0)).map(minuteOfDay)
    }
}

private func minuteOfDay(_ date: Date) -> Int {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
}

private func roundedToFive(_ minutes: Int) -> Int { Int((Double(minutes) / 5).rounded()) * 5 }

/// The same clock difference expressed within half a day either way.
private func wrapped(_ minutes: Int) -> Int {
    var value = minutes % 1440
    if value > 720 { value -= 1440 }
    if value < -720 { value += 1440 }
    return value
}

private extension SolarEvent {
    var shortName: String {
        switch self {
        case .civilDawn: return "Dawn"
        case .sunrise: return "Sunrise"
        case .solarNoon: return "Noon"
        case .sunset: return "Sunset"
        case .civilDusk: return "Dusk"
        }
    }

    var chipSymbol: String {
        switch self {
        case .civilDawn: return "sun.haze.fill"
        case .civilDusk: return "moon.haze.fill"
        default: return icon
        }
    }
}

// MARK: - Day track

/// A draggable 24-hour sky. Solar times can only reach six hours around their anchor,
/// so the rest of the sky is dimmed. Other enabled changes appear as dots.
private struct DayTrack: View {
    @ObservedObject var controller: SunpaperController
    let trigger: Trigger
    let excluding: UUID?
    let onDrag: (Int) -> Void
    let onStep: (Int) -> Void

    private let height: CGFloat = 42
    private let trackY: CGFloat = 28
    private let trackHeight: CGFloat = 12
    private let knob: CGFloat = 20

    var body: some View {
        let model = Model(controller: controller, trigger: trigger, excluding: excluding)
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    let sky = SunpaperSky.gradient(sunrise: model.sunrise, sunset: model.sunset)
                    Capsule().fill(sky).opacity(model.windows == nil ? 1 : 0.3)
                        .frame(width: width, height: trackHeight)
                        .position(x: width / 2, y: trackY)
                    if let windows = model.windows {
                        Capsule().fill(sky)
                            .frame(width: width, height: trackHeight)
                            .mask(alignment: .leading) {
                                ZStack(alignment: .leading) {
                                    ForEach(windows.indices, id: \.self) { index in
                                        Rectangle()
                                            .frame(width: (windows[index].upperBound - windows[index].lowerBound) * width)
                                            .offset(x: windows[index].lowerBound * width)
                                    }
                                }
                                .frame(width: width, alignment: .leading)
                            }
                            .position(x: width / 2, y: trackY)
                    }
                    ForEach(model.others.indices, id: \.self) { index in
                        Circle().fill(.white.opacity(0.9)).frame(width: 5, height: 5)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .position(x: model.others[index] * width, y: trackY)
                    }
                    if let anchor = model.anchor {
                        Image(systemName: anchor.symbol).font(.caption).foregroundStyle(.secondary)
                            .position(x: clamp(anchor.fraction * width, width), y: 8)
                    }
                    if let position = model.knob {
                        Circle().fill(SunpaperSky.gold)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .position(x: position * width, y: trackY)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard model.canDrag, width > 0 else { return }
                    let fraction = min(max(value.location.x / width, 0), 1)
                    onDrag(min(Int(fraction * 1440), 1439))
                })
            }
            .frame(height: height)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(Self.hourLabel(hour)).font(.caption2).foregroundStyle(.tertiary).fixedSize()
                            .position(x: clamp(Double(hour) / 24 * proxy.size.width, proxy.size.width, inset: 14), y: 6)
                    }
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time of day")
        .accessibilityValue(controller.resolvedTime(for: trigger)?.formatted(date: .omitted, time: .shortened) ?? "Needs a location")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(5)
            case .decrement: onStep(-5)
            @unknown default: break
            }
        }
    }

    private func clamp(_ x: CGFloat, _ width: CGFloat, inset: CGFloat = 8) -> CGFloat {
        min(max(x, inset), max(width - inset, inset))
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    @MainActor
    private struct Model {
        let sunrise: Double?
        let sunset: Double?
        let knob: Double?
        let anchor: (symbol: String, fraction: Double)?
        let windows: [ClosedRange<Double>]?
        let others: [Double]
        let canDrag: Bool

        init(controller: SunpaperController, trigger: Trigger, excluding: UUID?) {
            func fraction(_ date: Date) -> Double { Double(minuteOfDay(date)) / 1440 }
            sunrise = controller.resolvedTime(for: .sunrise()).map(fraction)
            sunset = controller.resolvedTime(for: .sunset()).map(fraction)
            knob = controller.resolvedTime(for: trigger).map(fraction)
            others = controller.slots.filter { $0.id != excluding && $0.isEnabled }
                .compactMap { controller.resolvedTime(for: $0.trigger).map(fraction) }
            switch trigger {
            case .fixed:
                anchor = nil; windows = nil; canDrag = true
            case .solar(let event, _):
                let center = controller.resolvedTime(for: .solar(event: event, offset: 0)).map(fraction)
                anchor = center.map { (symbol: event.chipSymbol, fraction: $0) }
                canDrag = center != nil
                if let center {
                    let reach = Double(TimingControl.offsetLimit) / 1440
                    let low = center - reach, high = center + reach
                    var ranges = [max(low, 0)...min(high, 1)]
                    if low < 0 { ranges.append((low + 1)...1) }
                    if high > 1 { ranges.append(0...(high - 1)) }
                    windows = ranges
                } else {
                    windows = nil
                }
            }
        }
    }
}

// MARK: - Editors

struct TimingEditor: View {
    @ObservedObject var controller: SunpaperController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Trigger
    let excluding: UUID?
    let onSave: (Trigger) -> Void

    init(controller: SunpaperController, trigger: Trigger, excluding: UUID? = nil, onSave: @escaping (Trigger) -> Void) {
        self.controller = controller; _draft = State(initialValue: trigger); self.excluding = excluding; self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When should it change?").font(.headline)
            TimingControl(controller: controller, trigger: $draft, excluding: excluding)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { onSave(draft); dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 400).tint(SunpaperColor.accent)
    }
}

/// Adding a change asks for its name and time together; its wallpaper is chosen from the row.
struct AddChangeSheet: View {
    @ObservedObject var controller: SunpaperController
    let onAdd: (String, Trigger) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var trigger: Trigger
    @FocusState private var nameFocused: Bool

    init(controller: SunpaperController, onAdd: @escaping (String, Trigger) -> Void) {
        self.controller = controller
        self.onAdd = onAdd
        let noon = Trigger.solar(event: .solarNoon, offset: 0)
        _trigger = State(initialValue: controller.resolvedTime(for: noon) == nil ? .fixed(hour: 12, minute: 0) : noon)
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? trigger.readableName : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a change").font(.title3.weight(.semibold))
                Text("Choose when it happens. You’ll pick its wallpaper in Your day.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Name", text: $name, prompt: Text(trigger.readableName))
                .textFieldStyle(.roundedBorder).focused($nameFocused)
            TimingControl(controller: controller, trigger: $trigger)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add change") { onAdd(resolvedName, trigger); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 440).tint(SunpaperColor.accent)
        .onAppear { nameFocused = true }
    }
}
