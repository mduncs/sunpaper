import SwiftUI

struct MenuBarView: View {
    let currentSlot: TimeSlot?
    let nextTransition: (slot: TimeSlot, date: Date)?
    let todaySchedule: [(slot: TimeSlot, time: Date)]
    let lastError: String?
    let onApplySlot: (TimeSlot) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusSummary

            if let error = lastError {
                ErrorStatusView(error: error)
            }

            Divider()
                .padding(.vertical, 2)

            Text("Today")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            if !todaySchedule.isEmpty {
                scheduleList
                    .accessibilityLabel("Today's schedule")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("No schedule available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No schedule available")
                .accessibilityHint("Open settings to configure scheduled wallpaper changes.")
            }

            Divider()
                .padding(.vertical, 2)

            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Text("Settings...")
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuButtonStyle())
            .accessibilityLabel("Open Settings")
            .accessibilityHint("Opens Sunpaper settings.")

            Divider()
                .padding(.vertical, 2)

            Button(action: onQuit) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Text("Quit Sunpaper")
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuButtonStyle())
            .accessibilityLabel("Quit Sunpaper")
            .accessibilityHint("Exits Sunpaper.")
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Label("Sunpaper", systemImage: "sun.horizon.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 8)

                StatusBadge(
                    text: statusText,
                    systemImage: statusIcon,
                    color: statusColor
                )
            }

            HStack(spacing: 6) {
                Image(systemName: currentSlot.map(slotIcon) ?? "clock")
                    .font(.subheadline)
                    .foregroundStyle(currentSlot.map(slotColor) ?? .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(currentSlot?.name ?? "No active slot")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(nextTransitionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sunpaper status")
        .accessibilityValue(statusAccessibilityValue)
    }

    @ViewBuilder
    private var scheduleList: some View {
        if todaySchedule.count > 5 {
            ScrollView {
                scheduleRows
            }
            .frame(maxHeight: 142)
        } else {
            scheduleRows
        }
    }

    private var scheduleRows: some View {
        VStack(spacing: 3) {
            ForEach(todaySchedule, id: \.slot.id) { item in
                ScheduleSlotButton(
                    slot: item.slot,
                    time: item.time,
                    isCurrent: item.slot.id == currentSlot?.id,
                    onTap: { onApplySlot(item.slot) }
                )
            }
        }
    }

    private var statusText: String {
        if lastError != nil {
            return "Needs attention"
        }

        if currentSlot == nil || todaySchedule.isEmpty {
            return "Waiting"
        }

        return "Ready"
    }

    private var statusIcon: String {
        if lastError != nil {
            return "exclamationmark.triangle.fill"
        }

        if currentSlot == nil || todaySchedule.isEmpty {
            return "clock.fill"
        }

        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if lastError != nil {
            return .orange
        }

        if currentSlot == nil || todaySchedule.isEmpty {
            return .secondary
        }

        return .green
    }

    private var nextTransitionText: String {
        guard let nextTransition else {
            return "Next: no more transitions today"
        }

        return "Next: \(nextTransition.slot.name) at \(formatScheduleTime(nextTransition.date))"
    }

    private var statusAccessibilityValue: String {
        var parts = [
            currentSlot.map { "Current slot: \($0.name)" } ?? "No active slot",
            nextTransition.map { "Next transition: \($0.slot.name) at \(formatScheduleTime($0.date))" } ?? "No more transitions today",
            "Status: \(statusText)"
        ]

        if let lastError {
            parts.append("Last issue: \(lastError)")
        }

        return parts.joined(separator: ". ")
    }
}

private struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .fontWeight(.medium)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct ErrorStatusView: View {
    let error: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Last issue")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last issue")
        .accessibilityValue(error)
    }
}

// MARK: - Schedule Slot Button

struct ScheduleSlotButton: View {
    let slot: TimeSlot
    let time: Date
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(formatScheduleTime(time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .frame(width: 52, alignment: .leading)

                Image(systemName: slotIcon(slot))
                    .font(.caption)
                    .foregroundStyle(slotColor(slot))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(slot.name)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                if isCurrent {
                    Text("Now")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor.opacity(0.1) :
                          isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var accessibilityLabel: String {
        "\(slot.name), \(formatScheduleTime(time))"
    }

    private var accessibilityValue: String {
        let currentState = isCurrent ? "Current slot" : "Scheduled slot"
        return "\(currentState). \(wallpaperDescription)."
    }

    private var accessibilityHint: String {
        isCurrent ? "Reapplies this slot now." : "Applies this slot now."
    }

    private var wallpaperDescription: String {
        switch slot.source {
        case .none:
            return "No wallpaper assigned"
        default:
            return "Wallpaper: \(slot.source.displayName)"
        }
    }
}

private func slotIcon(_ slot: TimeSlot) -> String {
    let name = slot.name.lowercased()
    if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
        return "sunrise.fill"
    } else if name.contains("day") || name.contains("noon") {
        return "sun.max.fill"
    } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
        return "sunset.fill"
    } else if name.contains("night") {
        return "moon.stars.fill"
    }

    switch slot.trigger {
    case .solar(let event, _):
        return event.icon
    case .fixed:
        return "clock.fill"
    }
}

private func slotColor(_ slot: TimeSlot) -> Color {
    let name = slot.name.lowercased()
    if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
        return .orange
    } else if name.contains("day") || name.contains("noon") {
        return .yellow
    } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
        return .orange
    } else if name.contains("night") {
        return .indigo
    }

    return .secondary
}

private func formatScheduleTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// Native-feeling menu button style
struct MenuButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.15) :
                          isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .foregroundStyle(.primary)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
